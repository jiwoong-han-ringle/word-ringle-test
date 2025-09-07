class CreateSimpleSchema < ActiveRecord::Migration[8.0]
  def change
    # 1. words 테이블 - 원형(lemma)만 저장
    create_table :words, primary_key: :word_id do |t|
      t.string :lemma, limit: 50, null: false
      t.string :word_type, null: false  # noun, verb, adj, adv
      t.timestamp :created_at, default: -> { "CURRENT_TIMESTAMP" }
    end
    
    add_index :words, :lemma, unique: true
    
    # 2. relation_words 테이블 - 변형 단어들
    create_table :relation_words do |t|
      t.references :word, null: false, foreign_key: { to_table: :words, primary_key: :word_id }
      t.string :word, limit: 50, null: false  # working, cats, running 등
      t.timestamps
    end
    
    add_index :relation_words, :word, unique: true
    
    # 3. user_counts 테이블 - 일별 통계
    create_table :user_counts do |t|
      t.bigint :user_id, null: false
      t.date :date, null: false
      t.integer :total_words, default: 0
      t.integer :unique_words, default: 0
      t.timestamps
    end
    
    add_index :user_counts, [:user_id, :date], unique: true
    
    # 4. words_used 테이블 - 사용자별 단어 히스토리
    create_table :words_used do |t|
      t.bigint :user_id, null: false
      t.json :history  # {lemma: count} 형태
      t.timestamps
    end
    
    add_index :words_used, :user_id
  end
end