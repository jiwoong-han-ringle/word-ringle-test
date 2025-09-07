class WordForm < ApplicationRecord
  self.primary_key = :word_form_id
  
  belongs_to :base_word, foreign_key: :base_word_id
  
  validates :form, presence: true, uniqueness: true, length: { maximum: 50 }
  validates :form_type, presence: true, inclusion: { 
    in: %w[
      base_form present_tense past_tense past_participle present_participle
      plural singular comparative superlative
      infinitive gerund
    ] 
  }
  
  # 원형 찾기
  def base_form
    base_word.base_form
  end
  
  # 같은 원형의 다른 변형들
  def sibling_forms
    base_word.word_forms.where.not(word_form_id: word_form_id)
  end
  
  # 특정 단어 형태로 원형 찾기
  def self.find_base_by_form(word_form)
    form_record = find_by(form: word_form.downcase)
    form_record&.base_word
  end
end