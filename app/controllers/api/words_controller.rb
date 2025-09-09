class Api::WordsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_user_id

  def create
    sentence = params[:sentence]
    method = params[:method] || 'python'  # 'python' or 'ruby'

    if sentence.length == 0
      return render json: { error: 'No sentence to process' }, status: :bad_request
    end

    begin
      # 처리 방법에 따라 다른 processor 사용
      processor = case method.downcase
                  when 'ruby'
                    RubyWordProcessor.new(@user_id)
                  when 'python'
                    WordProcessor.new(@user_id)
                  else
                    return render json: { error: 'Invalid method. Use "python" or "ruby"' }, status: :bad_request
                  end

      result = processor.process_user_words(sentence)
      
      render json: result
    rescue => e
      Rails.logger.error "Word processing error (#{method}): #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: { 
        error: 'Internal server error', 
        message: e.message,
        method: method
      }, status: :internal_server_error
    end
  end

  # 성능 비교를 위한 새로운 엔드포인트
  def compare
    sentence = params[:sentence]

    if sentence.length == 0
      return render json: { error: 'No sentence to process' }, status: :bad_request
    end

    begin
      results = {}
      
      # Python 방식 테스트
      start_time = Time.current
      python_processor = WordProcessor.new(@user_id)
      python_result = python_processor.process_user_words(sentence)
      python_time = ((Time.current - start_time) * 1000).round(2)
      
      # Ruby 방식 테스트
      start_time = Time.current
      ruby_processor = RubyWordProcessor.new(@user_id + 1000)  # 다른 user_id로 테스트
      ruby_result = ruby_processor.process_user_words(sentence)
      ruby_time = ((Time.current - start_time) * 1000).round(2)
      
      # 비교 결과
      render json: {
        success: true,
        sentence: sentence,
        comparison: {
          python: {
            processing_time: python_time,
            processed: python_result[:processed],
            method: 'Python Container + spaCy'
          },
          ruby: {
            processing_time: ruby_time,
            processed: ruby_result[:processed],
            method: 'Ruby Lemmatizer'
          },
          performance_improvement: {
            time_saved: python_time - ruby_time,
            percentage_faster: ((python_time - ruby_time) / python_time * 100).round(1)
          }
        }
      }
    rescue => e
      Rails.logger.error "Comparison error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: { 
        error: 'Internal server error', 
        message: e.message 
      }, status: :internal_server_error
    end
  end

  private

  def set_user_id
    @user_id = params[:user_id] || 1 # Default user for testing
  end
end