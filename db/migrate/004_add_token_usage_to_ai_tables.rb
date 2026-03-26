class AddTokenUsageToAiTables < ActiveRecord::Migration[6.1]
  def change
    add_column :ai_chat_messages, :prompt_tokens, :integer, default: 0
    add_column :ai_chat_messages, :completion_tokens, :integer, default: 0
    add_column :ai_chat_messages, :total_tokens, :integer, default: 0
    add_column :ai_chat_messages, :provider, :string
    
    add_column :ai_text_versions, :prompt_tokens, :integer, default: 0
    add_column :ai_text_versions, :completion_tokens, :integer, default: 0
    add_column :ai_text_versions, :total_tokens, :integer, default: 0
    add_column :ai_text_versions, :provider, :string
  end
end
