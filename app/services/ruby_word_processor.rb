require 'lemmatizer'
require 'engtagger'

class RubyWordProcessor
  def initialize(user_id)
    @user_id = user_id
    @lemmatizer = Lemmatizer.new
    @tagger = EngTagger.new
    @redis = Redis.new(host: 'localhost', port: 6379, db: 0)
  end

  def process_user_words(sentence)
    start_time = Time.current

    # 1. 문장을 Ruby로 처리 (원형화)
    processed_words = analyze_sentence_with_ruby(sentence)
    
    # 2. 데이터베이스 구조에 맞춰 단어들 처리
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

  # WordProcessor fallback용 메서드 (Python 형태와 동일한 반환값)
  def process_sentence_words(sentence)
    analyze_sentence_with_ruby(sentence)
  end

  private

  def analyze_sentence_with_ruby(sentence)
    words = sentence.split
    processed_words = []
    
    words.each do |word|
      clean_word = word.gsub(/[^\w]/, '').downcase
      next if clean_word.empty?
      
      # Ruby lemmatization
      lemma = @lemmatizer.lemma(clean_word)
      
      # 간단한 품사 추정 (정확하지 않지만 기본적인 분류)
      pos = estimate_pos(clean_word, lemma)
      
      processed_words << {
        'word' => word,
        'root' => lemma == clean_word ? nil : lemma, # 원형과 같으면 nil
        'pos' => pos
      }
    end
    
    processed_words
  end

  def estimate_pos(word, lemma)
    # 간단한 품사 추정 로직
    case word
    when /ly$/
      'ADV'
    when /ing$/
      'VERB'
    when /ed$/
      'VERB' 
    when /s$/ && word != lemma
      'NOUN'
    else
      # lemmatizer가 변화를 준 경우의 추정
      if word != lemma
        case lemma
        when /^(be|have|do|go|come|see|get|make|know|think|take|give|find|tell|become|leave|feel|put|bring|begin|keep|hold|write|stand|hear|let|mean|set|meet|run|pay|sit|speak|lie|lead|read|grow|open|walk|win|offer|remember|love|consider|appear|buy|serve|die|send|expect|build|stay|fall|cut|reach|kill|remain)$/
          'VERB'
        else
          'NOUN'
        end
      else
        'NOUN'
      end
    end
  end

  # Python 방식과 동일한 로직들 복사
  def process_words_with_relations(processed_words)
    return 0 if processed_words.empty?
    
    new_words_count = 0
    
    processed_words.each do |word_data|
      original_word = word_data['word']
      lemma = word_data['root']
      pos = word_data['pos']
      
      # root가 null인 단어들은 스킵 (원형과 동일한 경우)
      unless lemma
        Rails.logger.debug "Skipping word '#{original_word}' - same as lemma"
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

  def count_lemmas(processed_words)
    lemma_counts = Hash.new(0)
    processed_words.each do |word_data|
      next unless word_data['root']
      lemma_counts[word_data['root']] += 1
    end
    lemma_counts
  end

  def update_user_history(lemma_counts)
    words_used = WordsUsed.find_or_initialize_by(user_id: @user_id)
    
    if words_used.persisted?
      existing_history = words_used.history || {}
      lemma_counts.each do |lemma, count|
        existing_history[lemma] = (existing_history[lemma] || 0) + count
      end
      words_used.history = existing_history
    else
      words_used.history = lemma_counts
    end
    
    words_used.save!
    Rails.logger.info "Updated user history (Ruby) for user #{@user_id}: total unique words = #{words_used.history.keys.length}"
  end

  def update_daily_stats(total_words, unique_words)
    today = Date.current
    
    user_count = UserCount.find_or_initialize_by(user_id: @user_id, date: today)
    
    if user_count.persisted?
      user_count.total_words += total_words
      user_count.unique_words += unique_words
    else
      user_count.total_words = total_words
      user_count.unique_words = unique_words
    end
    
    user_count.save!
    Rails.logger.info "Updated daily stats (Ruby) for user #{@user_id}: total=#{user_count.total_words}, unique=#{user_count.unique_words}"
  end

  def build_response(sentence, lemma_counts, new_words_count, start_time)
    words_used = WordsUsed.find_by(user_id: @user_id)
    user_history = words_used&.history || {}
    
    today = Date.current
    today_stats = UserCount.find_by(user_id: @user_id, date: today)
    
    {
      success: true,
      processing_time: ((Time.current - start_time) * 1000).round(2),
      method: 'Ruby Lemmatizer',
      processed: {
        total_words: sentence.split.length,
        unique_words_count: lemma_counts.keys.length,
        unique_words: lemma_counts.keys,
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
    
    case pos_tag.upcase.strip
    when 'VERB', 'AUX' then 'verb'
    when 'NOUN', 'PROPN' then 'noun'
    when 'ADJ' then 'adj'
    when 'ADV' then 'adv'
    else 'noun'
    end
  end
end