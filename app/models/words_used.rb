class WordsUsed < ApplicationRecord
  self.table_name = 'words_used'
  
  validates :user_id, presence: true
  
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  
  def add_word_usage(lemma, count = 1)
    self.history ||= {}
    self.history[lemma] = (self.history[lemma] || 0) + count
    save
  end
  
  def get_word_count(lemma)
    (self.history || {})[lemma] || 0
  end
  
  def total_words
    (self.history || {}).values.sum
  end
  
  def unique_words_count
    (self.history || {}).keys.length
  end
end