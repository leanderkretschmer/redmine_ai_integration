class AddVersioningFields < ActiveRecord::Migration[6.1]
  def change
    add_column :ai_text_versions, :version_number, :integer, null: false, default: 0
    add_column :ai_text_versions, :journal_id, :integer
    add_column :ai_text_versions, :fixed_version_id, :integer

    add_index :ai_text_versions, :journal_id
    add_index :ai_text_versions, :fixed_version_id
    add_index :ai_text_versions, [:session_id, :version_number, :field_type], unique: true, name: 'idx_ai_versions_session_version_field'
    add_index :ai_text_versions, [:issue_id, :field_type, :last_changed_on], name: 'idx_ai_versions_issue_field_changed_on'
  end
end
