class CreateAiChatMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_chat_messages do |t|
      t.integer :issue_id, null: false, index: true
      t.integer :user_id, null: false, index: true
      t.text :question, null: false
      t.text :answer
      t.text :context_used
      t.string :model_used
      t.integer :journal_id_referenced # optional
      t.timestamps
    end
    
    add_index :ai_chat_messages, [:issue_id, :created_at]
  end
end