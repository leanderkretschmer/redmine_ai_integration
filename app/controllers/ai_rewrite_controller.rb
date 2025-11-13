class AiRewriteController < ApplicationController
  include ActionController::Live

  before_action :require_login
  before_action :check_settings, except: [:test_connection, :rewrite_stream, :requests]
  skip_before_action :verify_authenticity_token, only: [:rewrite, :rewrite_stream, :save_version, :get_version, :clear_versions, :test_connection]

  def rewrite_stream
    text = params[:text]
    return render json: { error: 'Kein Text angegeben' }, status: 400 if text.blank?

    provider = Setting.plugin_redmine_ai_integration['ai_provider']
    
    # Nur Ollama unterstützt Streaming aktuell
    unless provider == 'ollama'
      return render json: { error: 'Streaming wird nur für Ollama unterstützt' }, status: 400
    end

    # SSE-Response vorbereiten
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    
    begin
      settings = Setting.plugin_redmine_ai_integration
      system_prompt = settings['system_prompt'] || 'Verbessere den folgenden Text professionell.'
      session_id = params[:session_id] || generate_session_id
      
      # Custom Prompt verwenden, falls vorhanden
      custom_prompt = params[:custom_prompt].presence
      system_prompt = custom_prompt || system_prompt
      
      # Originaltext SOFORT speichern, bevor Streaming startet
      field_type = params[:field_type] || detect_field_type
      issue_id = params[:issue_id] || extract_issue_id
      Rails.logger.info "Rewrite Stream - Speichere Originaltext für Session: #{session_id}"
      ensure_original_version_saved(text, session_id, field_type, issue_id)
      
      accumulated_text = ''
      
      call_ollama_stream(text, system_prompt, settings, session_id) do |chunk|
        accumulated_text += chunk
        # Jeden Chunk als SSE-Event senden und sofort flushen
        response.stream.write("data: #{JSON.generate({ text: chunk })}\n\n")
        response.stream.flush
      end
      
      # Finales Event mit Version-ID
      version_id = save_text_version(text, accumulated_text, session_id, field_type, issue_id)
      response.stream.write("data: #{JSON.generate({ done: true, version_id: version_id })}\n\n")
      response.stream.flush
      
    rescue => e
      Rails.logger.error "AI Rewrite Stream Fehler: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      response.stream.write("data: #{JSON.generate({ error: e.message })}\n\n")
      response.stream.flush
    ensure
      response.stream.close
    end
  end

  def rewrite
    text = params[:text]
    return render json: { error: 'Kein Text angegeben' }, status: 400 if text.blank?

    begin
      provider = Setting.plugin_redmine_ai_integration['ai_provider']
      # Custom Prompt verwenden, falls vorhanden, sonst Standard-Prompt
      custom_prompt = params[:custom_prompt].presence
      improved_text = call_ai_api(text, provider, custom_prompt)
      
      # Session-ID für Version-Speicherung
      session_id = params[:session_id] || generate_session_id
      field_type = params[:field_type] || detect_field_type
      issue_id = params[:issue_id] || extract_issue_id
      
      # Originaltext SOFORT speichern
      ensure_original_version_saved(text, session_id, field_type, issue_id)
      
      # Version speichern
      version_id = save_text_version(text, improved_text, session_id, field_type, issue_id)
      
      render json: { 
        improved_text: improved_text,
        version_id: version_id
      }
    rescue => e
      Rails.logger.error "AI Rewrite Fehler: #{e.message}"
      render json: { error: "Fehler beim Verbessern des Textes: #{e.message}" }, status: 500
    end
  end

  def save_version
    text = params[:text]
    version_id = params[:version_id]
    
    if version_id.present?
      update_version(version_id, text)
      render json: { success: true }
    else
      render json: { error: 'Keine Version-ID angegeben' }, status: 400
    end
  end

  def get_version
    version_id = params[:version_id]
    direction = params[:direction] # 'prev', 'next', or 'original'
    session_id = params[:session_id]
    
    Rails.logger.info "Get Version - Version ID: #{version_id}, Direction: #{direction}, Session ID: #{session_id}"
    
    # Session-ID aus Version-ID extrahieren falls nicht vorhanden
    if session_id.blank? && version_id.present?
      # Session-ID ist der Teil vor dem letzten Timestamp
      parts = version_id.split('_')
      if parts.length >= 3
        # Format: user_id_timestamp_random -> user_id_timestamp
        session_id = parts[0..-2].join('_')
      else
        session_id = parts.first
      end
    end
    
    if direction == 'original'
      version = get_original_version(session_id || version_id)
    else
      version = get_text_version(version_id, direction)
    end
    
    if version
      Rails.logger.info "Get Version - Found version, Text length: #{version[:text].to_s.length}"
      render json: { 
        text: version[:text],
        version_id: version[:id],
        can_go_prev: version[:can_go_prev],
        can_go_next: version[:can_go_next]
      }
    else
      Rails.logger.error "Get Version - Version not found for version_id: #{version_id}, direction: #{direction}, session_id: #{session_id}"
      render json: { error: 'Version nicht gefunden' }, status: 404
    end
  end

  def clear_versions
    session_id = params[:session_id]
    clear_text_versions(session_id)
    render json: { success: true }
  end

  def requests
    # Hole alle eindeutigen Issue-IDs mit dem neuesten last_changed_on
    @requests = AiTextVersion.where.not(issue_id: nil)
                             .select('issue_id, MAX(last_changed_on) as max_last_changed_on')
                             .group(:issue_id)
                             .order('MAX(last_changed_on) DESC')
                             .limit(100)
                             .map do |r|
                               issue = Issue.find_by(id: r.issue_id)
                               next unless issue
                               
                               {
                                 issue_id: r.issue_id,
                                 last_changed_on: r.max_last_changed_on,
                                 issue: issue
                               }
                             end
                             .compact # Entferne nil-Einträge
    
    render 'requests'
  end

  def test_connection
    Rails.logger.info "=== AI Rewrite Test Connection Start ==="
    Rails.logger.info "Provider: #{params[:provider]}"
    Rails.logger.info "Settings: #{Setting.plugin_redmine_ai_integration.inspect}"
    
    begin
      settings = Setting.plugin_redmine_ai_integration
      provider = params[:provider] || settings['ai_provider']
      
      Rails.logger.info "Using provider: #{provider}"
      
      case provider
      when 'openai'
        Rails.logger.info "Testing OpenAI connection..."
        result = test_openai_connection(settings)
      when 'ollama'
        Rails.logger.info "Testing Ollama connection..."
        result = test_ollama_connection(settings)
      when 'gemini'
        Rails.logger.info "Testing Gemini connection..."
        result = test_gemini_connection(settings)
      when 'claude'
        Rails.logger.info "Testing Claude connection..."
        result = test_claude_connection(settings)
      else
        Rails.logger.error "Unbekannter Provider: #{provider}"
        render json: { success: false, error: "Unbekannter Provider: #{provider}" }, status: 400
        return
      end
      
      Rails.logger.info "Test result: #{result.inspect}"
      Rails.logger.info "=== AI Rewrite Test Connection End ==="
      render json: result
    rescue => e
      Rails.logger.error "Test Connection Fehler: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { success: false, error: e.message, backtrace: e.backtrace.first(5) }, status: 500
    end
  end

  private

  def check_settings
    settings = Setting.plugin_redmine_ai_integration
    provider = settings['ai_provider']
    
    case provider
    when 'openai'
      if settings['openai_api_key'].blank?
        render json: { error: 'OpenAI API Key nicht konfiguriert' }, status: 400
        return false
      end
    when 'ollama'
      # Ollama benötigt keine API-Key, nur URL
    when 'gemini'
      if settings['gemini_api_key'].blank?
        render json: { error: 'Gemini API Key nicht konfiguriert' }, status: 400
        return false
      end
    when 'claude'
      if settings['claude_api_key'].blank?
        render json: { error: 'Claude API Key nicht konfiguriert' }, status: 400
        return false
      end
    end
    true
  end

  def call_ai_api(text, provider, custom_prompt = nil)
    settings = Setting.plugin_redmine_ai_integration
    # Custom Prompt verwenden, falls vorhanden, sonst Standard-Prompt
    system_prompt = custom_prompt || settings['system_prompt'] || 'Verbessere den folgenden Text professionell.'

    case provider
    when 'openai'
      call_openai(text, system_prompt, settings)
    when 'ollama'
      call_ollama(text, system_prompt, settings)
    when 'gemini'
      call_gemini(text, system_prompt, settings)
    when 'claude'
      call_claude(text, system_prompt, settings)
    else
      raise "Unbekannter AI-Provider: #{provider}"
    end
  end

  def call_openai(text, system_prompt, settings)
    require 'net/http'
    require 'json'

    uri = URI('https://api.openai.com/v1/chat/completions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{settings['openai_api_key']}"

    body = {
      model: settings['openai_model'] || 'gpt-3.5-turbo',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: text }
      ],
      temperature: 0.7
    }

    request.body = body.to_json
    response = http.request(request)

    if response.code == '200'
      result = JSON.parse(response.body)
      result['choices'][0]['message']['content'].strip
    else
      raise "OpenAI API Fehler: #{response.code} - #{response.body}"
    end
  end

  def call_ollama_stream(text, system_prompt, settings, session_id, &block)
    require 'net/http'
    require 'json'

    # Direkte Ollama API verwenden (Streaming)
    url = settings['ollama_url'] || 'http://localhost:11434'
    Rails.logger.info "Ollama Stream Call - URL: #{url}, Model: #{settings['ollama_model']}"
    
    url = url.chomp('/')
    use_ssl = url.start_with?('https://')
    
    uri = URI("#{url}/api/generate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = use_ssl
    http.open_timeout = 30
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'

    body = {
      model: settings['ollama_model'] || 'llama2',
      prompt: "#{system_prompt}\n\nText:\n#{text}",
      stream: true
    }

    request.body = body.to_json
    
    begin
      http.request(request) do |response|
        if response.code == '200'
          buffer = ''
          response.read_body do |chunk|
            buffer += chunk.to_s
            # Verarbeite alle vollständigen Zeilen
            lines = buffer.split("\n")
            buffer = lines.pop || '' # Letzte unvollständige Zeile bleibt im Buffer
            
            lines.each do |line|
              next if line.empty?
              begin
                parsed = JSON.parse(line)
                content = parsed['response']
                block.call(content) if content
              rescue JSON::ParserError
                # Ignoriere ungültige JSON-Zeilen
              end
            end
          end
          # Verarbeite verbleibenden Buffer
          if buffer.present?
            buffer.split("\n").each do |line|
              next if line.empty?
              begin
                parsed = JSON.parse(line)
                content = parsed['response']
                block.call(content) if content
              rescue JSON::ParserError
              end
            end
          end
        else
          raise "Ollama API Fehler: #{response.code} - #{response.body[0..500]}"
        end
      end
    rescue Timeout::Error => e
      Rails.logger.error "Ollama Stream Call - Timeout: #{e.message}"
      raise "Verbindung zu Ollama fehlgeschlagen: Timeout nach 120 Sekunden"
    rescue => e
      Rails.logger.error "Ollama Stream Call - Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise "Ollama Verbindungsfehler: #{e.message}"
    end
  end

  def call_ollama(text, system_prompt, settings)
    require 'net/http'
    require 'json'

    # Direkte Ollama API verwenden
    url = settings['ollama_url'] || 'http://localhost:11434'
    Rails.logger.info "Ollama Call - URL: #{url}, Model: #{settings['ollama_model']}"
    
    # URL normalisieren (ohne trailing slash)
    url = url.chomp('/')
    
    # SSL automatisch erkennen
    use_ssl = url.start_with?('https://')
    
    uri = URI("#{url}/api/generate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = use_ssl
    http.open_timeout = 30
    http.read_timeout = 120

    Rails.logger.info "Ollama Call - Full URI: #{uri}, Host: #{uri.host}, Port: #{uri.port}, SSL: #{use_ssl}"

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'

    body = {
      model: settings['ollama_model'] || 'llama2',
      prompt: "#{system_prompt}\n\nText:\n#{text}",
      stream: false
    }

    Rails.logger.info "Ollama Call - Sending request with model: #{body[:model]}"
    request.body = body.to_json
    
    begin
      response = http.request(request)
      Rails.logger.info "Ollama Call - Response Code: #{response.code}"

      if response.code == '200'
        result = JSON.parse(response.body)
        result['response'].strip
      else
        raise "Ollama API Fehler: #{response.code} - #{response.body[0..500]}"
      end
    rescue Timeout::Error => e
      Rails.logger.error "Ollama Call - Timeout: #{e.message}"
      raise "Verbindung zu Ollama fehlgeschlagen: Timeout nach 120 Sekunden"
    rescue => e
      Rails.logger.error "Ollama Call - Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise "Ollama Verbindungsfehler: #{e.message}"
    end
  end

  def call_gemini(text, system_prompt, settings)
    require 'net/http'
    require 'json'

    api_key = settings['gemini_api_key']
    model = settings['gemini_model'] || 'gemini-pro'
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'

    body = {
      contents: [{
        parts: [{
          text: "#{system_prompt}\n\nText:\n#{text}"
        }]
      }]
    }

    request.body = body.to_json
    response = http.request(request)

    if response.code == '200'
      result = JSON.parse(response.body)
      result.dig('candidates', 0, 'content', 'parts', 0, 'text').strip
    else
      raise "Gemini API Fehler: #{response.code} - #{response.body}"
    end
  end

  def call_claude(text, system_prompt, settings)
    require 'net/http'
    require 'json'

    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = settings['claude_api_key']
    request['anthropic-version'] = '2023-06-01'

    body = {
      model: settings['claude_model'] || 'claude-3-sonnet-20240229',
      max_tokens: 4096,
      system: system_prompt,
      messages: [{
        role: 'user',
        content: text
      }]
    }

    request.body = body.to_json
    response = http.request(request)

    if response.code == '200'
      result = JSON.parse(response.body)
      result.dig('content', 0, 'text').strip
    else
      raise "Claude API Fehler: #{response.code} - #{response.body}"
    end
  end

  def ensure_original_version_saved(original_text, session_id, field_type = nil, issue_id = nil)
    # Prüfen ob bereits eine Original-Version existiert
    existing = AiTextVersion.where(session_id: session_id).order(:created_at).first
    
    return if existing && existing.version_id == "#{session_id}_original"
    
    # Original-Version erstellen
    version = AiTextVersion.create!(
      session_id: session_id,
      version_id: "#{session_id}_original",
      original_text: original_text,
      improved_text: original_text,
      user_id: User.current.id,
      issue_id: issue_id,
      field_type: field_type || detect_field_type,
      last_changed_on: Time.current
    )
    
    Rails.logger.info "Ensure Original Version - Session ID: #{session_id}, Saved original text, Version ID: #{version.version_id}"
  end

  def save_text_version(original_text, improved_text, session_id = nil, field_type = nil, issue_id = nil)
    session_id ||= params[:session_id] || generate_session_id
    field_type ||= params[:field_type] || detect_field_type
    issue_id ||= params[:issue_id] || extract_issue_id
    
    # Sicherstellen, dass Original-Version existiert
    ensure_original_version_saved(original_text, session_id, field_type, issue_id) unless AiTextVersion.where(session_id: session_id).exists?
    
    version_id = "#{session_id}_#{Time.now.to_i}"
    
    version = AiTextVersion.create!(
      session_id: session_id,
      version_id: version_id,
      original_text: original_text,
      improved_text: improved_text,
      user_id: User.current.id,
      issue_id: issue_id,
      field_type: field_type,
      last_changed_on: Time.current
    )
    
    Rails.logger.info "Save Text Version - Session ID: #{session_id}, Version ID: #{version_id}, Issue ID: #{issue_id}"
    version_id
  end

  def update_version(version_id, text)
    version = AiTextVersion.find_by_version_id(version_id)
    
    if version
      version.update!(
        improved_text: text,
        last_changed_on: Time.current
      )
    end
  end

  def get_text_version(version_id, direction)
    current_version = AiTextVersion.find_by_version_id(version_id)
    return nil unless current_version
    
    new_version = case direction
    when 'prev'
      current_version.get_prev_version
    when 'next'
      current_version.get_next_version
    else
      nil
    end
    
    return nil unless new_version
    
    {
      id: new_version.version_id,
      text: new_version.improved_text,
      can_go_prev: new_version.can_go_prev?,
      can_go_next: new_version.can_go_next?
    }
  end

  def get_original_version(version_id_or_session_id)
    # Wenn es eine Version-ID ist, extrahiere die Session-ID
    # Format: user_id_timestamp_random -> user_id_timestamp
    session_id = if version_id_or_session_id.to_s.include?('_')
      parts = version_id_or_session_id.to_s.split('_')
      if parts.length >= 3
        # Entferne den letzten Teil (random oder timestamp für version)
        parts[0..-2].join('_')
      else
        version_id_or_session_id
      end
    else
      version_id_or_session_id
    end
    
    Rails.logger.info "Get Original Version - Input: #{version_id_or_session_id}, Session ID: #{session_id}"
    
    original_version = AiTextVersion.get_original_for_session(session_id)
    
    return nil unless original_version
    
    versions_count = AiTextVersion.for_session(session_id).count
    
    Rails.logger.info "Get Original Version - Found original version, ID: #{original_version.version_id}, Total versions: #{versions_count}"
    
    {
      id: original_version.version_id,
      text: original_version.original_text,
      can_go_prev: false,
      can_go_next: versions_count > 1
    }
  end

  def clear_text_versions(session_id)
    AiTextVersion.where(session_id: session_id).delete_all
  end
  
  def extract_issue_id
    # Versuche Issue-ID aus der URL zu extrahieren
    if request.referer
      match = request.referer.match(/\/issues\/(\d+)/)
      return match[1].to_i if match
    end
    
    # Versuche aus params
    params[:issue_id]&.to_i
  end
  
  def detect_field_type
    # Versuche Field-Type aus der URL oder params zu bestimmen
    if request.referer
      return 'notes' if request.referer.include?('notes')
      return 'description' if request.referer.include?('description')
    end
    
    params[:field_type] || 'description'
  end

  def generate_session_id
    user_id = User.current&.id || 'anonymous'
    "#{user_id}_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  end

  def test_openai_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "OpenAI Test - API Key vorhanden: #{!settings['openai_api_key'].blank?}"
    
    if settings['openai_api_key'].blank?
      return { success: false, error: 'OpenAI API Key nicht konfiguriert' }
    end

    uri = URI('https://api.openai.com/v1/models')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{settings['openai_api_key']}"

    Rails.logger.info "OpenAI Test - Sende Request an: #{uri}"
    response = http.request(request)
    Rails.logger.info "OpenAI Test - Response Code: #{response.code}"

    if response.code == '200'
      models = JSON.parse(response.body)['data'].map { |m| m['id'] }.select { |id| id.start_with?('gpt') }
      Rails.logger.info "OpenAI Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      error_msg = "API Fehler: #{response.code} - #{response.body[0..200]}"
      Rails.logger.error "OpenAI Test - #{error_msg}"
      { success: false, error: error_msg }
    end
  end

  def test_ollama_connection(settings)
    require 'net/http'
    require 'json'

    # Direkte Ollama API testen
    url = settings['ollama_url'] || 'http://localhost:11434'
    Rails.logger.info "Ollama Test - URL: #{url}"
    
    # URL normalisieren (ohne trailing slash)
    url = url.chomp('/')
    
    # SSL automatisch erkennen
    use_ssl = url.start_with?('https://')
    
    begin
      # Zuerst einen einfachen Health-Check versuchen
      health_uri = URI(url)
      health_http = Net::HTTP.new(health_uri.host, health_uri.port)
      health_http.use_ssl = use_ssl
      health_http.open_timeout = 10
      health_http.read_timeout = 10
      
      Rails.logger.info "Ollama Test - Health Check an: #{health_uri}, SSL: #{use_ssl}"
      health_request = Net::HTTP::Get.new(health_uri)
      health_response = health_http.request(health_request)
      Rails.logger.info "Ollama Test - Health Check Response: #{health_response.code}"
      
      # Dann die Models-API testen
      uri = URI("#{url}/api/tags")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = use_ssl
      http.open_timeout = 15
      http.read_timeout = 15

      Rails.logger.info "Ollama Test - Sende Request an: #{uri}, Host: #{uri.host}, Port: #{uri.port}, SSL: #{use_ssl}"
      request = Net::HTTP::Get.new(uri)
      response = http.request(request)
      Rails.logger.info "Ollama Test - Response Code: #{response.code}, Body length: #{response.body.length}"

      if response.code == '200'
        models_data = JSON.parse(response.body)
        models = models_data['models'] ? models_data['models'].map { |m| m['name'] } : []
        Rails.logger.info "Ollama Test - Gefundene Modelle: #{models.count} (#{models.join(', ')})"
        { success: true, message: "Verbindung erfolgreich zu #{url}", models: models }
      else
        error_msg = "API Fehler: #{response.code} - #{response.body[0..200]}"
        Rails.logger.error "Ollama Test - #{error_msg}"
        { success: false, error: error_msg }
      end
    rescue Timeout::Error => e
      error_msg = "Verbindung zu #{url} fehlgeschlagen: Timeout (Server erreichbar, aber Antwort dauert zu lange)"
      Rails.logger.error "Ollama Test - #{error_msg}"
      Rails.logger.error "Ollama Test - Host: #{uri.host rescue 'unknown'}, Port: #{uri.port rescue 'unknown'}"
      { success: false, error: error_msg }
    rescue SocketError => e
      error_msg = "Verbindung zu #{url} fehlgeschlagen: Netzwerkfehler - #{e.message}"
      Rails.logger.error "Ollama Test - #{error_msg}"
      { success: false, error: error_msg }
    rescue => e
      error_msg = "Verbindung fehlgeschlagen: #{e.class} - #{e.message}"
      Rails.logger.error "Ollama Test - #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: error_msg }
    end
  end

  def test_gemini_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "Gemini Test - API Key vorhanden: #{!settings['gemini_api_key'].blank?}"
    
    if settings['gemini_api_key'].blank?
      return { success: false, error: 'Gemini API Key nicht konfiguriert' }
    end

    api_key = settings['gemini_api_key']
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    Rails.logger.info "Gemini Test - Sende Request an: #{uri.host}#{uri.path}"
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
    Rails.logger.info "Gemini Test - Response Code: #{response.code}"

    if response.code == '200'
      models_data = JSON.parse(response.body)
      models = models_data['models'] ? models_data['models'].map { |m| m['name'] } : []
      Rails.logger.info "Gemini Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      error_msg = "API Fehler: #{response.code} - #{response.body[0..200]}"
      Rails.logger.error "Gemini Test - #{error_msg}"
      { success: false, error: error_msg }
    end
  end

  def test_claude_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "Claude Test - API Key vorhanden: #{!settings['claude_api_key'].blank?}"
    
    if settings['claude_api_key'].blank?
      return { success: false, error: 'Claude API Key nicht konfiguriert' }
    end

    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = settings['claude_api_key']
    request['anthropic-version'] = '2023-06-01'

    body = {
      model: settings['claude_model'] || 'claude-3-sonnet-20240229',
      max_tokens: 10,
      messages: [{
        role: 'user',
        content: 'test'
      }]
    }

    Rails.logger.info "Claude Test - Sende Request an: #{uri}"
    request.body = body.to_json
    response = http.request(request)
    Rails.logger.info "Claude Test - Response Code: #{response.code}"

    if response.code == '200'
      Rails.logger.info "Claude Test - Verbindung erfolgreich"
      { success: true, message: 'Verbindung erfolgreich' }
    else
      error_body = response.body[0..500]
      error_msg = "API Fehler: #{response.code} - #{error_body}"
      Rails.logger.error "Claude Test - #{error_msg}"
      { success: false, error: error_msg }
    end
  end
end

