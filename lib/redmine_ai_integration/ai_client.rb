# frozen_string_literal: true

require 'net/http'
require 'json'

module RedmineAiIntegration
  # Zentraler Zugriff auf alle KI-Provider (OpenAI, Gemini, Claude, Ollama).
  #
  # - wählt das Modell pro Aufgabe (:correction, :complex, :chat, :learning)
  # - unterstützt für Claude sowohl API-Key als auch die Anmeldung mit einem Claude-Konto (OAuth)
  # - liefert immer { text:, tokens: { prompt:, completion:, total: }, model: }
  class AiClient
    class Error < StandardError; end

    TASKS = %w[correction complex chat learning].freeze

    # Standard-Effort pro Aufgabe (nur Claude-Modelle ab 4.6 / 5.x)
    CLAUDE_EFFORT = {
      'correction' => 'low',
      'complex'    => 'low',
      'chat'       => 'medium',
      'learning'   => 'medium'
    }.freeze

    CLAUDE_MAX_TOKENS = 8000
    DEFAULT_MAX_TOKENS = 2000

    attr_reader :settings, :provider

    def initialize(settings = nil, provider: nil)
      @settings = settings || Setting.plugin_redmine_ai_integration
      @provider = (provider.presence || @settings['ai_provider']).to_s
    end

    # Modell für eine Aufgabe: zuerst aufgabenspezifisch, sonst Provider-Standard
    def model_for(task)
      task = task.to_s
      specific = settings["model_#{task}"].to_s.strip
      return specific if specific.present?

      default_model
    end

    def default_model
      case provider
      when 'openai' then settings['openai_model'].presence || 'gpt-3.5-turbo'
      when 'gemini' then settings['gemini_model'].presence || 'gemini-1.5-pro'
      when 'claude' then settings['claude_model'].presence || 'claude-opus-5-5'
      when 'ollama' then settings['ollama_model'].presence || 'llama2'
      else ''
      end
    end

    # Prüft, ob der Provider konfiguriert ist; liefert nil oder eine Fehlermeldung
    def configuration_error
      case provider
      when 'openai'
        'OpenAI API Key nicht konfiguriert' if settings['openai_api_key'].blank?
      when 'gemini'
        'Gemini API Key nicht konfiguriert' if settings['gemini_api_key'].blank?
      when 'claude'
        if claude_oauth?
          'Claude-Konto nicht verbunden – bitte in den Plugin-Einstellungen anmelden' unless ClaudeOauth.logged_in?
        elsif settings['claude_api_key'].blank?
          'Claude API Key nicht konfiguriert'
        end
      when 'ollama'
        'Ollama URL nicht konfiguriert' if settings['ollama_url'].blank?
      else
        'KI-Provider nicht konfiguriert'
      end
    end

    def claude_oauth?
      settings['claude_auth_mode'] == 'oauth'
    end

    # Hauptaufruf: System-Prompt + Nutzertext -> Antwort
    def complete(system_prompt, user_text, task: :correction)
      model = model_for(task)
      result = case provider
               when 'openai' then call_openai(system_prompt, user_text, model)
               when 'gemini' then call_gemini(system_prompt, user_text, model)
               when 'claude' then call_claude(system_prompt, user_text, model, task)
               when 'ollama' then call_ollama(system_prompt, user_text, model)
               else raise Error, "Unbekannter Provider: #{provider}"
               end
      result[:model] = model
      result
    end

    # Verbindungstest + Modell-Liste
    def test_connection
      case provider
      when 'openai' then test_openai
      when 'gemini' then test_gemini
      when 'claude' then test_claude
      when 'ollama' then test_ollama
      else { success: false, error: 'Unbekannter Provider' }
      end
    rescue Error, ClaudeOauth::Error => e
      { success: false, error: e.message }
    rescue StandardError => e
      { success: false, error: "Verbindungsfehler: #{e.message}" }
    end

    private

    # ---------------------------------------------------------------- OpenAI

    def call_openai(system_prompt, user_text, model)
      uri = URI('https://api.openai.com/v1/chat/completions')
      body = {
        model: model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_text }
        ],
        temperature: 0.7,
        max_tokens: DEFAULT_MAX_TOKENS
      }
      result = post_json(uri, body, { 'Authorization' => "Bearer #{settings['openai_api_key']}" }, 'OpenAI')
      {
        text: result.dig('choices', 0, 'message', 'content').to_s.strip,
        tokens: {
          prompt: result.dig('usage', 'prompt_tokens'),
          completion: result.dig('usage', 'completion_tokens'),
          total: result.dig('usage', 'total_tokens')
        }
      }
    end

    def test_openai
      return { success: false, error: 'OpenAI API Key nicht konfiguriert' } if settings['openai_api_key'].blank?

      data = get_json(URI('https://api.openai.com/v1/models'), { 'Authorization' => "Bearer #{settings['openai_api_key']}" }, 'OpenAI')
      models = (data['data'] || []).map { |m| m['id'] }.sort
      { success: true, message: 'Verbindung erfolgreich', models: models }
    end

    # ---------------------------------------------------------------- Gemini

    def call_gemini(system_prompt, user_text, model)
      model = model.to_s.split('/').last
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{settings['gemini_api_key']}")
      body = {
        systemInstruction: { parts: [{ text: system_prompt }] },
        contents: [{ parts: [{ text: user_text }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: DEFAULT_MAX_TOKENS }
      }
      result = post_json(uri, body, {}, 'Gemini')
      {
        text: result.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.strip,
        tokens: {
          prompt: result.dig('usageMetadata', 'promptTokenCount'),
          completion: result.dig('usageMetadata', 'candidatesTokenCount'),
          total: result.dig('usageMetadata', 'totalTokenCount')
        }
      }
    end

    def test_gemini
      return { success: false, error: 'Gemini API Key nicht konfiguriert' } if settings['gemini_api_key'].blank?

      data = get_json(URI("https://generativelanguage.googleapis.com/v1beta/models?key=#{settings['gemini_api_key']}"), {}, 'Gemini')
      models = (data['models'] || []).map { |m| m['name'].to_s.split('/').last }
      { success: true, message: 'Verbindung erfolgreich', models: models }
    end

    # ---------------------------------------------------------------- Claude

    def claude_headers
      headers = { 'anthropic-version' => '2023-06-01' }
      if claude_oauth?
        headers.merge!(ClaudeOauth.auth_headers)
      else
        headers['x-api-key'] = settings['claude_api_key']
      end
      headers
    end

    # Ältere Modelle kennen output_config.effort nicht
    def claude_supports_effort?(model)
      m = model.to_s
      return false if m.match?(/claude-(3|2|instant)/)
      return false if m.match?(/claude-(opus|sonnet)-4-[0-5]/)
      return false if m.match?(/claude-haiku-4-5/)

      true
    end

    def call_claude(system_prompt, user_text, model, task)
      uri = URI('https://api.anthropic.com/v1/messages')
      body = {
        model: model,
        max_tokens: CLAUDE_MAX_TOKENS,
        system: system_prompt,
        messages: [{ role: 'user', content: user_text }]
      }
      if claude_supports_effort?(model)
        effort = settings["effort_#{task}"].presence || CLAUDE_EFFORT[task.to_s] || 'medium'
        body[:output_config] = { effort: effort }
      end

      result = post_json(uri, body, claude_headers, 'Claude')

      if result['stop_reason'] == 'refusal'
        reason = result.dig('stop_details', 'explanation') || result.dig('stop_details', 'category') || 'unbekannt'
        raise Error, "Claude hat die Anfrage abgelehnt (#{reason})"
      end

      text_block = (result['content'] || []).find { |b| b['type'] == 'text' }
      {
        text: text_block ? text_block['text'].to_s.strip : '',
        tokens: {
          prompt: result.dig('usage', 'input_tokens'),
          completion: result.dig('usage', 'output_tokens'),
          total: result.dig('usage', 'input_tokens').to_i + result.dig('usage', 'output_tokens').to_i
        }
      }
    end

    def test_claude
      if claude_oauth?
        return { success: false, error: 'Claude-Konto nicht verbunden' } unless ClaudeOauth.logged_in?
      elsif settings['claude_api_key'].blank?
        return { success: false, error: 'Claude API Key nicht konfiguriert' }
      end

      data = get_json(URI('https://api.anthropic.com/v1/models?limit=100'), claude_headers, 'Claude')
      models = (data['data'] || []).map { |m| m['id'] }
      message = claude_oauth? ? "Verbindung erfolgreich (Claude-Konto: #{ClaudeOauth.token_record.account.presence || 'angemeldet'})" : 'Verbindung erfolgreich'
      { success: true, message: message, models: models }
    end

    # ---------------------------------------------------------------- Ollama

    def ollama_base
      (settings['ollama_url'].presence || 'http://localhost:11434').chomp('/')
    end

    def call_ollama(system_prompt, user_text, model)
      uri = URI("#{ollama_base}/api/generate")
      body = {
        model: model,
        system: system_prompt,
        prompt: user_text,
        stream: false,
        options: { temperature: 0.7, num_predict: DEFAULT_MAX_TOKENS }
      }
      result = post_json(uri, body, {}, 'Ollama', read_timeout: 180)
      {
        text: result['response'].to_s.strip,
        tokens: {
          prompt: result['prompt_eval_count'],
          completion: result['eval_count'],
          total: result['prompt_eval_count'].to_i + result['eval_count'].to_i
        }
      }
    end

    def test_ollama
      return { success: false, error: 'Ollama URL nicht konfiguriert' } if settings['ollama_url'].blank?

      data = get_json(URI("#{ollama_base}/api/tags"), {}, 'Ollama', timeout: 10)
      models = (data['models'] || []).map { |m| m['name'] }
      { success: true, message: 'Verbindung erfolgreich', models: models }
    end

    # ---------------------------------------------------------------- HTTP

    def build_http(uri, open_timeout: 30, read_timeout: 120)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http
    end

    def post_json(uri, body, headers, label, read_timeout: 120)
      http = build_http(uri, read_timeout: read_timeout)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json

      response = http.request(request)
      unless response.code == '200'
        Rails.logger.error "#{label} API Fehler - Code: #{response.code}, Body: #{response.body.to_s[0, 1000]}"
        raise Error, "#{label} API Fehler: #{response.code} - #{response.body.to_s[0, 500]}#{oauth_block_hint(label, response)}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "#{label} lieferte ungültiges JSON: #{e.message}"
    end

    # Anthropic beantwortet Inferenz-Anfragen mit Abo-Tokens (claude.ai Pro/Max) außerhalb von
    # Claude Code mit einem generischen 429 "rate_limit_error" / "Error". Das ist kein echtes Limit.
    def oauth_block_hint(label, response)
      return '' unless label == 'Claude' && claude_oauth?
      return '' unless response.code == '429' || response.code == '401' || response.code == '403'

      body = response.body.to_s
      generic = body.include?('"message":"Error"') || body =~ /OAuth authentication is currently not supported/i
      return '' unless generic || response.code != '429'

      ' – Hinweis: Anthropic lässt Inferenz mit Tokens von Claude-Abo-Konten (claude.ai Pro/Max) derzeit nur in ' \
      'Claude Code zu. Bitte in den Plugin-Einstellungen auf „API-Key“ umstellen (Schlüssel unter ' \
      'platform.claude.com/settings/keys) oder ein Console-/Entwicklerkonto verwenden.'
    end

    def get_json(uri, headers, label, timeout: 30)
      http = build_http(uri, open_timeout: timeout, read_timeout: timeout)
      request = Net::HTTP::Get.new(uri)
      headers.each { |k, v| request[k] = v }

      response = http.request(request)
      unless response.code == '200'
        raise Error, "#{label}: HTTP #{response.code}: #{response.body.to_s[0, 500]}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "#{label} lieferte ungültiges JSON: #{e.message}"
    end
  end
end
