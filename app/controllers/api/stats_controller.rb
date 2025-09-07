class Api::StatsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_user_id

  def show
    days = params[:days]&.to_i || 7
    
    if days <= 0 || days > 365
      return render json: { error: 'days must be between 1 and 365' }, status: :bad_request
    end

    begin
      # DB에서만 통계 조회 (개인화된 데이터는 Redis 제외)
      date_range = (Date.current - days.days + 1.day)..Date.current
      user_counts = UserCount.where(user_id: @user_id, date: date_range)
                            .order(:date)

      # 날짜별 데이터 구성
      unique_history = []
      total_history = []
      total_unique_words = 0
      total_words_processed = 0
      days_with_activity = 0

      days.times do |i|
        date = Date.current - i.days
        user_count = user_counts.find { |uc| uc.date == date }
        
        if user_count
          unique_history << {
            date: date.strftime('%Y-%m-%d'),
            unique_words: user_count.unique_words
          }
          total_history << {
            date: date.strftime('%Y-%m-%d'),
            total_words: user_count.total_words
          }
          
          total_unique_words += user_count.unique_words
          total_words_processed += user_count.total_words
          days_with_activity += 1
        else
          unique_history << { 
            date: date.strftime('%Y-%m-%d'), 
            unique_words: 0 
          }
          total_history << { 
            date: date.strftime('%Y-%m-%d'), 
            total_words: 0 
          }
        end
      end

      # WordsUsed 테이블에서 사용자의 전체 고유 단어 통계 조회
      words_used = WordsUsed.find_by(user_id: @user_id)
      all_time_unique_words = words_used&.history&.keys&.length || 0
      
      render json: {
        user_id: @user_id,
        period_days: days,
        unique_history: unique_history.reverse,
        total_history: total_history.reverse,
        summary: {
          total_unique_words: total_unique_words,
          total_words_processed: total_words_processed,
          days_with_activity: days_with_activity,
          all_time_unique_words: all_time_unique_words
        }
      }
    rescue => e
      Rails.logger.error "Stats retrieval error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: { 
        error: 'Internal server error', 
        message: e.message 
      }, status: :internal_server_error
    end
  end

  private

  def set_user_id
    @user_id = params[:id] || params[:user_id] || 1 # URL :id parameter or query user_id
  end
end