class Word < ApplicationRecord
  self.table_name = 'words'
  self.primary_key = 'word_id'
  
  has_many :relation_words, foreign_key: :word_id
  
  validates :lemma, presence: true, length: { maximum: 50 }, uniqueness: true
  validates :word_type, presence: true, inclusion: { 
    in: %w[noun verb adj adv] 
  }
  
  scope :by_lemma, ->(lemma) { where(lemma: lemma) }
end