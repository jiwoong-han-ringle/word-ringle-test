class UserCount < ApplicationRecord
  self.table_name = 'user_counts'
  
  validates :user_id, presence: true
  validates :date, presence: true
  validates :total_words, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :unique_words, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :date }
  
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :recent_days, ->(days) { where('date >= ?', days.days.ago.to_date) }
  scope :by_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  
  def self.update_daily_stats(user_id, date, total_words, unique_words)
    find_or_initialize_by(user_id: user_id, date: date).tap do |record|
      record.total_words = (record.total_words || 0) + total_words
      record.unique_words = unique_words
      record.save!
    end
  end
end