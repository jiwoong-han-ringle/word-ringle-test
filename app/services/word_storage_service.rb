class WordStorageService
  def initialize(user_id)
    @user_id = user_id
    @redis = Redis.new(host: 'localhost', port: 6379, db: 0)
  end

  def store_words(processed_words)
    return { new_words_count: 0, newly_learned_words: [] } if processed_words.empty?
    
    new_words_count = 0
    newly_learned_words = []
    user_history = get_user_history
    
    processed_words.each do |word_data|
      original_word = word_data['word']
      lemma = word_data['root']
      pos = word_data['pos']
      
      next unless lemma
      
      Rails.logger.debug "Processing word: '#{original_word}' -> '#{lemma}' (POS: #{pos})"
      
      # 사용자가 이전에 학습한 적 없는 단어인지 확인
      is_newly_learned = !user_history.key?(lemma)
      
      word_id = find_or_create_lemma(lemma, pos)
      next unless word_id
      
      create_relation_if_needed(original_word, lemma, word_id)
      cache_word(original_word, lemma, word_id, map_pos_to_type(pos))
      
      if is_newly_learned
        newly_learned_words << lemma
      end
    end
    
    { new_words_count: newly_learned_words.length, newly_learned_words: newly_learned_words.uniq }
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
    Rails.logger.info "Updated user history for user #{@user_id}: #{words_used.history.keys.length} unique words"
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
    Rails.logger.info "Updated daily stats for user #{@user_id}: total=#{user_count.total_words}, unique=#{user_count.unique_words}"
  end

  def get_user_history
    words_used = WordsUsed.find_by(user_id: @user_id)
    words_used&.history || {}
  end

  def get_user_statistics
    user_history = get_user_history
    today = Date.current
    today_stats = UserCount.find_by(user_id: @user_id, date: today)
    
    {
      user_id: @user_id,
      total_unique_words_learned: user_history.keys.length,
      today_words_processed: today_stats&.total_words || 0,
      today_unique_words: today_stats&.unique_words || 0
    }
  end

  private

  def find_or_create_lemma(lemma, pos)
    word_key = "lemma:#{lemma}"
    word_data_cached = @redis.get(word_key)
    
    if word_data_cached
      word_info = JSON.parse(word_data_cached)
      Rails.logger.debug "Found lemma in Redis: '#{lemma}' (ID: #{word_info['word_id']})"
      return word_info['word_id']
    end
    
    word_record = Word.find_by(lemma: lemma)
    
    unless word_record
      word_type = map_pos_to_type(pos)
      word_type = 'noun' if word_type.blank? || !%w[noun verb adj adv].include?(word_type)
      
      begin
        word_record = Word.create!(lemma: lemma, word_type: word_type)
        Rails.logger.info "Created new lemma: '#{lemma}' (ID: #{word_record.word_id})"
      rescue ActiveRecord::RecordInvalid => e
        word_record = Word.find_by(lemma: lemma)
        Rails.logger.info "Found existing lemma after conflict: '#{lemma}'"
      end
    end
    
    return nil unless word_record
    
    # Cache to Redis
    word_info = {
      word_id: word_record.word_id,
      lemma: word_record.lemma,
      word_type: word_record.word_type
    }
    @redis.setex(word_key, 86400, word_info.to_json)
    
    word_record.word_id
  end

  def create_relation_if_needed(original_word, lemma, word_id)
    return if original_word.downcase == lemma.downcase
    return if RelationWord.exists?(word_text: original_word)
    
    begin
      RelationWord.create!(word_id: word_id, word_text: original_word)
      Rails.logger.info "Created relation: '#{original_word}' -> '#{lemma}'"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.debug "Relation already exists: '#{original_word}'"
    end
  end

  def cache_word(original_word, lemma, word_id, word_type)
    word_cache_key = "word:#{original_word}"
    return if @redis.exists(word_cache_key)
    
    word_cache_data = {
      word_id: word_id,
      word: original_word,
      lemma: lemma,
      word_type: word_type
    }
    @redis.setex(word_cache_key, 86400, word_cache_data.to_json)
  end

  def word_created?(lemma)
    # Simple check - in real implementation, track this properly
    true
  end

  def map_pos_to_type(pos_tag)
    return 'noun' if pos_tag.nil? || pos_tag.empty?
    
    case pos_tag.upcase.strip
    when 'VERB', 'AUX' then 'verb'
    when 'NOUN', 'PROPN' then 'noun'
    when 'ADJ' then 'adj'
    when 'ADV' then 'adv'
    when 'PRON', 'DET', 'ADP', 'CONJ', 'CCONJ', 'SCONJ', 'NUM', 'PART', 'INTJ', 'PUNCT', 'SYM', 'X' then 'noun'
    else 'noun'
    end
  end
end