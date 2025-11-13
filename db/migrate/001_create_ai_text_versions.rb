class CreateAiTextVersions < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_text_versions do |t|
      t.string :session_id, null: false, index: true
      t.string :version_id, null: false, index: true
      t.text :original_text, null: false
      t.text :improved_text, null: false
      t.integer :user_id, null: false, index: true
      t.integer :issue_id, index: true
      t.string :field_type, null: false # 'description', 'notes', etc.
      t.datetime :last_changed_on, null: false, index: true
      t.timestamps
    end
    
    add_index :ai_text_versions, [:session_id, :version_id], unique: true
    add_index :ai_text_versions, [:issue_id, :last_changed_on]
  end
end

