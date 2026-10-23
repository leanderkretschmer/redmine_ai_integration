# frozen_string_literal: true

require 'net/http'
require 'json'
require 'securerandom'
require 'digest'
require 'base64'

module RedmineAiIntegration
  # OAuth-Anmeldung mit einem Claude-Konto (PKCE-Flow, wie bei "ant auth login --no-browser").
  #
  # Ablauf:
  #   1. authorize_url   -> Admin öffnet die URL im Browser, meldet sich mit seinem Claude-Konto an
  #   2. Anthropic zeigt einen Code im Format "code#state" an (manueller Modus) oder leitet
  #      auf unsere Callback-Route weiter (Callback-Modus, falls die Redirect-URI beim Client erlaubt ist)
  #   3. exchange_code!  -> Code gegen Access-/Refresh-Token tauschen und in ai_oauth_tokens speichern
  #   4. access_token    -> liefert ein gültiges Token und erneuert es bei Bedarf automatisch
  #
  # Die Tokens werden mit "Authorization: Bearer" + "anthropic-beta: oauth-2025-04-20" gegen
  # api.anthropic.com verwendet.
  class ClaudeOauth
    DEFAULT_CLIENT_ID     = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
    AUTHORIZE_URL_CLAUDE  = 'https://claude.ai/oauth/authorize'
    AUTHORIZE_URL_CONSOLE = 'https://console.anthropic.com/oauth/authorize'
    TOKEN_URL             = 'https://console.anthropic.com/v1/oauth/token'
    MANUAL_REDIRECT_URI   = 'https://console.anthropic.com/oauth/code/callback'
    DEFAULT_SCOPES        = 'org:create_api_key user:profile user:inference'
    OAUTH_BETA_HEADER     = 'oauth-2025-04-20'

    # Sicherheitspuffer: Token gilt als abgelaufen, wenn weniger als 2 Minuten übrig sind
    EXPIRY_MARGIN = 120

    class Error < StandardError; end

    def self.settings
      Setting.plugin_redmine_ai_integration
    end

    def self.client_id
      settings['claude_oauth_client_id'].presence || DEFAULT_CLIENT_ID
    end

    def self.scopes
      settings['claude_oauth_scopes'].presence || DEFAULT_SCOPES
    end

    def self.authorize_base_url
      settings['claude_oauth_account_type'] == 'console' ? AUTHORIZE_URL_CONSOLE : AUTHORIZE_URL_CLAUDE
    end

    def self.callback_mode?
      settings['claude_oauth_redirect_mode'] == 'callback'
    end

    def self.redirect_uri(callback_url = nil)
      callback_mode? && callback_url.present? ? callback_url : MANUAL_REDIRECT_URI
    end

    # PKCE: Verifier + Challenge erzeugen
    def self.generate_pkce
      verifier  = SecureRandom.urlsafe_base64(64).tr('=', '')
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier)).tr('=', '')
      { verifier: verifier, challenge: challenge, state: SecureRandom.urlsafe_base64(32).tr('=', '') }
    end

    def self.authorize_url(pkce, callback_url = nil)
      params = {
        'code'                  => 'true',
        'client_id'             => client_id,
        'response_type'         => 'code',
        'redirect_uri'          => redirect_uri(callback_url),
        'scope'                 => scopes,
        'code_challenge'        => pkce[:challenge],
        'code_challenge_method' => 'S256',
        'state'                 => pkce[:state]
      }
      "#{authorize_base_url}?#{URI.encode_www_form(params)}"
    end

    # Tauscht den Autorisierungscode gegen Tokens. `raw_code` darf "code#state" sein.
    def self.exchange_code!(raw_code, pkce, callback_url = nil)
      raise Error, 'Kein Code übergeben' if raw_code.blank?

      code, state_from_code = raw_code.to_s.strip.split('#', 2)
      state = state_from_code.presence || pkce[:state]

      if pkce[:state].present? && state.present? && state != pkce[:state]
        raise Error, 'State stimmt nicht überein – bitte Anmeldung erneut starten'
      end

      body = {
        grant_type:    'authorization_code',
        code:          code,
        state:         state,
        client_id:     client_id,
        redirect_uri:  redirect_uri(callback_url),
        code_verifier: pkce[:verifier]
      }

      tokens = post_token(body)
      persist_tokens!(tokens)
      tokens
    end

    def self.refresh!
      refresh_token = token_record.refresh_token
      raise Error, 'Kein Refresh-Token vorhanden – bitte erneut anmelden' if refresh_token.blank?

      tokens = post_token(
        grant_type:    'refresh_token',
        refresh_token: refresh_token,
        client_id:     client_id
      )
      persist_tokens!(tokens)
      tokens
    end

    def self.token_record
      AiOauthToken.for('claude')
    end

    def self.logged_in?
      token_record.present_token?
    end

    def self.expires_at
      token_record.expires_at
    end

    def self.expired?
      exp = expires_at
      exp.nil? || exp <= Time.now + EXPIRY_MARGIN
    end

    # Gültiges Access-Token (erneuert bei Bedarf)
    def self.access_token
      raise Error, 'Nicht mit Claude-Konto angemeldet' unless logged_in?

      if expired?
        Rails.logger.info 'Claude OAuth - Token abgelaufen, erneuere...'
        refresh!
      end
      token_record.access_token
    end

    def self.logout!
      AiOauthToken.where(provider: 'claude').destroy_all
    end

    def self.status
      record = token_record
      {
        logged_in:    logged_in?,
        account:      record.account,
        expires_at:   expires_at&.iso8601,
        expired:      logged_in? ? expired? : nil,
        scope:        record.scope,
        account_type: settings['claude_oauth_account_type'] || 'claude',
        client_id:    client_id
      }
    end

    # Header für API-Requests mit OAuth-Token
    def self.auth_headers
      {
        'Authorization'  => "Bearer #{access_token}",
        'anthropic-beta' => OAUTH_BETA_HEADER
      }
    end

    private_class_method def self.post_token(body)
      uri  = URI(TOKEN_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['Accept']       = 'application/json'
      request.body = body.to_json

      response = http.request(request)
      unless response.code.to_i == 200
        Rails.logger.error "Claude OAuth - Token-Request fehlgeschlagen: #{response.code} #{response.body.to_s[0, 500]}"
        raise Error, "Token-Anfrage fehlgeschlagen (HTTP #{response.code}): #{extract_error(response.body)}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Ungültige Antwort vom Token-Endpunkt: #{e.message}"
    end

    private_class_method def self.extract_error(body)
      data = JSON.parse(body.to_s)
      data['error_description'] || data.dig('error', 'message') || data['error'] || body.to_s[0, 200]
    rescue JSON::ParserError
      body.to_s[0, 200]
    end

    private_class_method def self.persist_tokens!(tokens)
      raise Error, 'Antwort enthält kein access_token' if tokens['access_token'].blank?

      record = token_record
      expires_in = tokens['expires_in'].to_i
      account = tokens.dig('account', 'email_address') ||
                tokens.dig('account', 'email') ||
                tokens.dig('organization', 'name') ||
                record.account

      record.access_token = tokens['access_token']
      record.expires_at   = Time.now + (expires_in > 0 ? expires_in : 3600)
      record.account      = account.to_s
      record.scope        = tokens['scope'].to_s
      record.user_id      = User.current&.id if defined?(User)
      # Refresh-Token nur überschreiben, wenn ein neues geliefert wurde
      record.refresh_token = tokens['refresh_token'] if tokens['refresh_token'].present?
      record.save!
    end
  end
end
