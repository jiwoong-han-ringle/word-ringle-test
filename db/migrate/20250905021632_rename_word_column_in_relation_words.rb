class RenameWordColumnInRelationWords < ActiveRecord::Migration[8.0]
  def change
    rename_column :relation_words, :word, :word_text
  end
end
