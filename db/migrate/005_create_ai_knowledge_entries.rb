class CreateAiKnowledgeEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_knowledge_entries do |t|
      t.string  :category, null: false, default: 'rule'
      t.text    :content, null: false
      t.text    :reason
      t.string  :source, null: false, default: 'manual'
      t.integer :project_id
      t.integer :issue_id
      t.integer :user_id
      t.boolean :active, null: false, default: true
      t.boolean :reviewed, null: false, default: false
      t.integer :hit_count, null: false, default: 0
      t.timestamps
    end

    add_index :ai_knowledge_entries, :project_id
    add_index :ai_knowledge_entries, [:active, :category]
    add_index :ai_knowledge_entries, :source
  end
end
