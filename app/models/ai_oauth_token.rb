# OAuth-Zugangsdaten pro Provider (derzeit nur 'claude').
# Getrennt von den Plugin-Settings gespeichert, damit das Speichern des Settings-Formulars
# die Tokens nicht überschreibt.
class AiOauthToken < ActiveRecord::Base
  self.table_name = 'ai_oauth_tokens'

  validates :provider, presence: true, uniqueness: true

  def self.for(provider)
    find_or_initialize_by(provider: provider.to_s)
  end

  def present_token?
    access_token.present? || refresh_token.present?
  end
end
