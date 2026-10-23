class AddLearningFieldsToAiTextVersions < ActiveRecord::Migration[6.1]
  def change
    # Unveränderte KI-Ausgabe (improved_text wird durch Nutzer-Edits überschrieben)
    add_column :ai_text_versions, :ai_output_text, :text
    add_column :ai_text_versions, :request_type, :string
    add_column :ai_text_versions, :model_used, :string
    add_column :ai_text_versions, :learned_at, :datetime
  end
end
