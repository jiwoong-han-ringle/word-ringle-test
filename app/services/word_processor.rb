require 'net/http'
require 'uri'
require 'json'

class WordProcessor
  @@http_client = nil
  
  def self.http_client
    @@http_client ||= begin
      uri = URI.parse("http://localhost:8000") # Python Module Container
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = false
      http.keep_alive_timeout = 30
      http.open_timeout = 5
      http.read_timeout = 30
      http.start
      Rails.logger.info "✅ HTTP connection pool initialized for Python service"
      http
    end
  end

  def initialize(user_id)
    @user_id = user_id
    @redis = Redis.new(host: 'localhost', port: 6379, db: 0)
  end

  def process_user_words(sentence)
    start_time = Time.current

    # 1. 문장을 Python 모듈로 처리 (원형화 및 품사 분석)
    processed_words = call_python_module(sentence)
    
    # 2. 새로운 데이터베이스 구조에 맞춰 단어들 처리
    new_words_count = process_words_with_relations(processed_words)
    
    # 3. 원형별 카운트 계산 
    lemma_counts = count_lemmas(processed_words)
    
    # 4. 사용자 기록 갱신
    update_user_history(lemma_counts)
    
    # 5. 일별 통계 업데이트
    processed_word_count = processed_words.count { |word_data| word_data['root'] }
    update_daily_stats(processed_word_count, lemma_counts.keys.length)

    # 6. 결과 응답 생성
    build_response(sentence, lemma_counts, new_words_count, start_time)
  end

  private

  def separate_cached_and_uncached_words(words_array)
    cached_words = []
    uncached_words = []

    # 각 단어들 확인
    words_array.each do |word|
      cached_data_json = @redis.get("word:#{word}")
      
      if cached_data_json
        # 캐시된 단어: JSON에서 파싱해서 사용
        cached_data = JSON.parse(cached_data_json)
        cached_words << {
          'word' => cached_data['word'],
          'root' => cached_data['lemma'], 
          'pos' => cached_data['word_type']&.upcase || 'NOUN'
        }
        Rails.logger.info "Found cached word: '#{word}' -> '#{cached_data['lemma']}'"
      else
        # 캐시에 없는 단어: Python 모듈로 처리 필요
        uncached_words << word
        Rails.logger.info "Uncached word: '#{word}'"
      end
    end
    
    [cached_words, uncached_words]
  end

  def combine_cached_and_processed_words(cached_words, newly_processed_words)
    # 캐시된 단어와 새로 처리된 단어를 합쳐서 반환
    cached_words + newly_processed_words
  end

  def process_words_with_relations(processed_words)
    return 0 if processed_words.empty?
    
    new_words_count = 0
    
    processed_words.each do |word_data|
      original_word = word_data['word']
      lemma = word_data['root']
      pos = word_data['pos']
      
      # root가 null인 단어들은 스킵
      unless lemma
        Rails.logger.debug "Skipping word '#{original_word}' with POS '#{pos}' - no lemma"
        next
      end
      
      Rails.logger.debug "Processing word: '#{original_word}' -> '#{lemma}' (POS: #{pos})"
      
      # 1. Redis에서 원형(lemma) 확인
      word_key = "lemma:#{lemma}"
      word_data_cached = @redis.get(word_key)
      
      if word_data_cached
        # Redis에 있으면 파싱
        word_info = JSON.parse(word_data_cached)
        word_id = word_info['word_id']
        Rails.logger.debug "Found lemma in Redis: '#{lemma}' (ID: #{word_id})"
      else
        # Redis에 없으면 DB에서 찾기
        word_record = Word.find_by(lemma: lemma)
        
        unless word_record
          # DB에도 없으면 새로 생성
          word_type = map_pos_to_type(pos)
          
          # Safety check
          if word_type.blank? || !%w[noun verb adj adv].include?(word_type)
            word_type = 'noun'
          end
          
          begin
            word_record = Word.create!(lemma: lemma, word_type: word_type)
            new_words_count += 1
            Rails.logger.info "Created new lemma: '#{lemma}' (ID: #{word_record.word_id})"
          rescue ActiveRecord::RecordInvalid => e
            # 동시성 문제로 인해 이미 생성된 경우
            word_record = Word.find_by(lemma: lemma)
            Rails.logger.info "Found existing lemma after conflict: '#{lemma}'"
          end
        end
        
        # Redis에 캐싱
        word_info = {
          word_id: word_record.word_id,
          lemma: word_record.lemma,
          word_type: word_record.word_type
        }
        @redis.setex(word_key, 86400, word_info.to_json)
        word_id = word_record.word_id
      end
      
      # 2. 원형과 다른 단어인 경우 relation_words에 추가
      if original_word.downcase != lemma.downcase
        unless RelationWord.exists?(word_text: original_word)
          begin
            RelationWord.create!(word_id: word_id, word_text: original_word)
            Rails.logger.info "Created relation: '#{original_word}' -> '#{lemma}'"
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.debug "Relation already exists: '#{original_word}'"
          end
        end
      end
      
      # 3. Redis에 개별 단어 캐싱 (검색용)
      word_cache_key = "word:#{original_word}"
      unless @redis.exists(word_cache_key)
        word_cache_data = {
          word_id: word_id,
          word: original_word,
          lemma: lemma,
          word_type: word_info['word_type']
        }
        @redis.setex(word_cache_key, 86400, word_cache_data.to_json)
      end
    end
    
    new_words_count
  end

  def process_new_words(newly_processed_words)
    return 0 if newly_processed_words.empty?
    
    new_words_count = 0
    
    newly_processed_words.each do |word_data|
      original_word = word_data['word']
      lemma = word_data['root']
      
      # root가 null인 단어들은 스킵
      next unless lemma
      
      # DB에서 확인
      existing_word = Word.find_by(word: original_word)
      
      unless existing_word
        # 새 단어를 DB에 저장
        word_type = map_pos_to_type(lemma)
        begin
          new_word = Word.create!(
            word: original_word,
            lemma: lemma,
            word_type: word_type
          )
          new_words_count += 1
          Rails.logger.info "Created new word in DB: '#{original_word}' -> '#{lemma}' (ID: #{new_word.id})"
          
          # Redis에 캐싱
          word_data = {
            word_id: new_word.id,
            word: new_word.word,
            lemma: new_word.lemma,
            word_type: new_word.word_type,
            created_at: new_word.created_at.to_s
          }
          @redis.setex("word:#{original_word}", 86400, word_data.to_json)
        rescue ActiveRecord::RecordInvalid => e
          if e.message.include?("Lemma has already been taken")
            existing_by_lemma = Word.find_by(lemma: lemma)
            Rails.logger.info "Found existing word with same lemma: '#{existing_by_lemma.word}' -> '#{lemma}' for new word '#{original_word}'"
            
            # 기존 단어 데이터를 Redis에 캐싱
            word_data = {
              word_id: existing_by_lemma.id,
              word: original_word,
              lemma: existing_by_lemma.lemma,
              word_type: existing_by_lemma.word_type,
              created_at: existing_by_lemma.created_at.to_s
            }
            @redis.setex("word:#{original_word}", 86400, word_data.to_json)
          else
            raise e
          end
        end
      else
        # 기존 단어면 Redis에 캐싱
        word_data = {
          word_id: existing_word.id,
          word: existing_word.word,
          lemma: existing_word.lemma,
          word_type: existing_word.word_type,
          created_at: existing_word.created_at.to_s
        }
        @redis.setex("word:#{original_word}", 86400, word_data.to_json)
        Rails.logger.info "Cached existing word: '#{original_word}' -> '#{existing_word.lemma}'"
      end
    end
    
    new_words_count
  end

  def call_python_module(sentence)
    words_array = sentence.split
    Rails.logger.info "call_python_module called with: #{words_array.inspect}"
    
    # Redis에서 캐시된 단어와 그렇지 않은 단어 분리
    cached_words, uncached_words = separate_cached_and_uncached_words(words_array)
    Rails.logger.info "Cached: #{cached_words.length}, Uncached: #{uncached_words.length}"
    
    # 캐시되지 않은 단어들만 Python으로 처리
    newly_processed_words = []
    if uncached_words.any?
      uncached_sentence = uncached_words.join(' ')
      Rails.logger.info "Processing #{uncached_words.length} uncached words with Python: #{uncached_words.join(', ')}"
      
      newly_processed_words = call_python_api(uncached_sentence)
      Rails.logger.info "Python processed #{newly_processed_words.length} words"
      
      # 새로 처리된 단어들을 Redis에 캐싱
      cache_processed_words(newly_processed_words)
    else
      Rails.logger.info "All words found in cache, skipping Python API call"
    end
    
    # 캐시된 단어와 새로 처리된 단어 합치기
    result = combine_cached_and_processed_words(cached_words, newly_processed_words)
    Rails.logger.info "Combined result: #{result.inspect}"
    result
  end

  def call_python_api(sentence)
    http_client = self.class.http_client
    request = Net::HTTP::Post.new('/analyze', { 'Content-Type' => 'application/json' })
    request.body = { sentence: sentence }.to_json
    response = http_client.request(request)
    
    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      Rails.logger.info "Python API response: #{result.inspect}"
      result
    else
      Rails.logger.error "Python API error: #{response.code} #{response.body}"
      # Fallback: 단어를 그대로 원형으로 처리
      sentence.split.map { |word| { 'word' => word, 'root' => word.downcase, 'pos' => 'NOUN' } }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "Python module parsing error: #{e.message}"
    Rails.logger.error "Python output: #{response&.body}"
    sentence.split.map { |word| { 'word' => word, 'root' => word.downcase, 'pos' => 'NOUN' } }
  rescue => e
    Rails.logger.error "Python API call failed: #{e.class} #{e.message}"
    sentence.split.map { |word| { 'word' => word, 'root' => word.downcase, 'pos' => 'NOUN' } }
  end

  def cache_processed_words(processed_words)
    processed_words.each do |word_data|
      word = word_data['word']
      next unless word_data['root'] # root가 없는 단어는 스킵
      
      word_cache_key = "word:#{word}"
      unless @redis.exists(word_cache_key)
        @redis.setex(word_cache_key, 86400, word_data.to_json)
        Rails.logger.debug "Cached word: #{word} -> #{word_data['root']}"
      end
    end
  end

  def count_lemmas(processed_words)
    lemma_counts = Hash.new(0)
    processed_words.each do |word_data|
      # root가 null인 단어들(PRON, PROPN, NUM, PUNCT 등)은 원형화가 불필요하므로 제외
      next unless word_data['root']
      lemma_counts[word_data['root']] += 1
    end
    lemma_counts
  end


  def update_user_history(lemma_counts)
    # WordsUsed 테이블의 JSON history에만 저장 (개인화된 데이터는 Redis 제외)
    words_used = WordsUsed.find_or_initialize_by(user_id: @user_id)
    
    if words_used.persisted?
      # 기존 히스토리 업데이트
      existing_history = words_used.history || {}
      lemma_counts.each do |lemma, count|
        existing_history[lemma] = (existing_history[lemma] || 0) + count
      end
      words_used.history = existing_history
    else
      # 새로운 히스토리 생성
      words_used.history = lemma_counts
    end
    
    words_used.save!
    Rails.logger.info "Updated user history in DB (JSON) for user #{@user_id}: total unique words = #{words_used.history.keys.length}"
  end

  def update_daily_stats(total_words, unique_words)
    today = Date.current
    
    # DB에서만 통계 저장 (개인화된 데이터는 Redis 제외)
    user_count = UserCount.find_or_initialize_by(user_id: @user_id, date: today)
    
    if user_count.persisted?
      # 기존 통계 업데이트
      user_count.total_words += total_words
      user_count.unique_words += unique_words
    else
      # 새로운 통계 생성
      user_count.total_words = total_words
      user_count.unique_words = unique_words
    end
    
    user_count.save!
    Rails.logger.info "Updated daily stats in DB for user #{@user_id}: total=#{user_count.total_words}, unique=#{user_count.unique_words}"
  end

  def build_response(sentence, lemma_counts, new_words_count, start_time)
    # DB에서 사용자 정보 조회
    words_used = WordsUsed.find_by(user_id: @user_id)
    user_history = words_used&.history || {}
    
    # 오늘 통계 조회
    today = Date.current
    today_stats = UserCount.find_by(user_id: @user_id, date: today)
    
    {
      success: true,
      processing_time: ((Time.current - start_time) * 1000).round(2),
      processed: {
        total_words: sentence.split.length,
        unique_words: lemma_counts.keys.length,
        new_words: new_words_count
      },
      user: {
        user_id: @user_id,
        total_unique_words_learned: user_history.keys.length,
        today_words_processed: today_stats&.total_words || 0,
        today_unique_words: today_stats&.unique_words || 0,
        most_used_words: user_history.sort_by { |_, count| -count }.first(5).map do |lemma, count|
          { word: lemma, count: count }
        end
      }
    }
  end

  def map_pos_to_type(pos_tag)
    return 'noun' if pos_tag.nil? || pos_tag.empty?
    
    # spaCy POS 태그를 기반으로 매핑 (모든 spaCy 태그 포함)
    case pos_tag.upcase.strip
    when 'VERB', 'AUX' then 'verb'
    when 'NOUN', 'PROPN' then 'noun'
    when 'ADJ' then 'adj'
    when 'ADV' then 'adv'
    when 'PRON' then 'noun'  # 대명사도 noun으로 처리
    when 'DET' then 'noun'   # 한정사도 noun으로 처리  
    when 'ADP' then 'noun'   # 전치사도 noun으로 처리
    when 'CONJ', 'CCONJ', 'SCONJ' then 'noun'  # 접속사도 noun으로 처리
    when 'NUM' then 'noun'   # 수사도 noun으로 처리
    when 'PART' then 'noun'  # 조사/불변화사도 noun으로 처리
    when 'INTJ' then 'noun'  # 감탄사도 noun으로 처리
    when 'PUNCT' then 'noun' # 구두점도 noun으로 처리
    when 'SYM' then 'noun'   # 기호도 noun으로 처리
    when 'X' then 'noun'     # 기타도 noun으로 처리
    else 'noun'
    end
  end

  def determine_form_type(original_word, lemma)
    return 'base' if original_word.downcase == lemma.downcase
    
    # 단어 형태 분석
    original_lower = original_word.downcase
    lemma_lower = lemma.downcase
    
    case original_lower
    when /#{Regexp.escape(lemma_lower)}ing$/
      'present_participle'
    when /#{Regexp.escape(lemma_lower)}ed$/
      'past_tense'
    when /#{Regexp.escape(lemma_lower)}s$/
      'plural'
    when /#{Regexp.escape(lemma_lower)}er$/
      'comparative'
    when /#{Regexp.escape(lemma_lower)}est$/
      'superlative'
    else
      'variant'
    end
  end
end

