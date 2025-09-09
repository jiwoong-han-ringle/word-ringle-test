class WordProcessor
  def initialize(user_id)
    @user_id = user_id
    @python_service = PythonWordService.new
    @ruby_service = RubyWordProcessor.new(user_id)
    @storage_service = WordStorageService.new(user_id)
  end

  def process_user_words(sentence)
    start_time = Time.current
    used_fallback = false

    # 1. Python 모듈로 문장 처리, 실패 시 Ruby fallback
    processed_words, used_fallback = process_sentence_with_fallback(sentence)

    # 2. 단어들을 DB/Redis에 저장
    storage_result = @storage_service.store_words(processed_words)

    # 3. 원형별 카운트 계산
    lemma_counts = @storage_service.count_lemmas(processed_words)

    # 4. 사용자 기록 및 통계 업데이트
    @storage_service.update_user_history(lemma_counts)

    processed_word_count = processed_words.count { |word_data| word_data["root"] }
    @storage_service.update_daily_stats(processed_word_count, lemma_counts.keys.length)

    # 5. 결과 응답 생성
    build_response(sentence, lemma_counts, storage_result, used_fallback, start_time)
  end

  private

  def process_sentence_with_fallback(sentence)
    begin
      processed_words = @python_service.process_sentence(sentence)
      [processed_words, false]
    rescue PythonServiceError => e
      Rails.logger.warn "Python service failed: #{e.message}, falling back to Ruby lemmatizer"
      processed_words = @ruby_service.process_sentence_words(sentence)
      [processed_words, true]
    end
  end

  def build_response(sentence, lemma_counts, storage_result, used_fallback, start_time)
    user_stats = @storage_service.get_user_statistics

    response = {
      success: true,
      processing_time: ((Time.current - start_time) * 1000).round(2),
      processed: {
        total_words: sentence.split.length,
        unique_words_count: lemma_counts.keys.length,
        unique_words: lemma_counts.keys,
        newly_learned_words: storage_result[:newly_learned_words],
        newly_learned_count: storage_result[:new_words_count]
      },
      user: user_stats
    }

    # Ruby fallback 사용 시 표시
    if used_fallback
      response[:fallback_used] = true
      response[:processor] = "Ruby Lemmatizer (Python service unavailable)"
    else
      response[:processor] = "Python spaCy"
    end

    response
  end
end
