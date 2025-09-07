class RelationWord < ApplicationRecord
  belongs_to :word, foreign_key: :word_id, primary_key: :word_id, class_name: 'Word'
  
  validates :word_text, presence: true, length: { maximum: 50 }, uniqueness: true
end