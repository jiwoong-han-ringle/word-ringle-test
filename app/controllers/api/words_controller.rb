class Api::WordsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_user_id

  def create
    sentence = params[:sentence]

    if sentence.length == 0
      return render json: { error: 'No sentence to process' }, status: :bad_request
    end

    begin
      # 단어를 받고 WordProcessor로 전달
      processor = WordProcessor.new(@user_id)
      result = processor.process_user_words(sentence)
      
      render json: result
    rescue => e
      Rails.logger.error "Word processing error: #{e.message}"
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