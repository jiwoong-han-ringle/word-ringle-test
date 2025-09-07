class BaseWord < ApplicationRecord
  self.primary_key = :base_word_id
  
  has_many :word_forms, foreign_key: :base_word_id, dependent: :destroy
  has_many :word_relations, foreign_key: :base_word_id, dependent: :destroy
  has_many :related_words, through: :word_relations, source: :related_word
  
  validates :base_form, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :word_type, presence: true, inclusion: { in: %w[noun verb adj adv] }
  
  # 특정 단어의 모든 변형 가져오기
  def all_forms
    word_forms.pluck(:form) + [base_form]
  end
  
  # 특정 변형 타입의 단어 찾기
  def form_of_type(form_type)
    word_forms.find_by(form_type: form_type)&.form
  end
  
  # 관련 단어들 (동의어, 반의어 등)
  def related_by_type(relation_type)
    BaseWord.joins(:word_relations)
            .where(word_relations: { base_word_id: base_word_id, relation_type: relation_type })
            .pluck(:base_form)
  end
end