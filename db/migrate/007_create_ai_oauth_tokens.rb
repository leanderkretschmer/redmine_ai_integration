class CreateAiOauthTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :ai_oauth_tokens do |t|
      t.string   :provider, null: false
      t.text     :access_token
      t.text     :refresh_token
      t.datetime :expires_at
      t.string   :account
      t.string   :scope
      t.integer  :user_id
      t.timestamps
    end
    add_index :ai_oauth_tokens, :provider, unique: true
  end
end
