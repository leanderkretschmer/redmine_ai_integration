class AiRewriteController < ApplicationController
  before_action :check_settings, except: [:test_connection, :rewrite_stream, :requests, :check_versions, :list_versions, :settings]
  skip_before_action :verify_authenticity_token, only: [:rewrite, :rewrite_stream, :save_version, :get_version, :clear_versions, :test_connection, :check_versions, :list_versions, :settings]
  
  def rewrite
    original_text = params[:original_text]
    system_prompt = params[:system_prompt]
    session_id = params[:session_id] || generate_session_id
    field_type = params[:field_type] || 'description'
    issue_id = params[:issue_id]
    provider = params[:provider] || Setting.plugin_redmine_ai_integration['ai_provider']
    request_type = params[:request_type] || 'rewrite'
    
    return render json: { error: 'Original-Text fehlt' }, status: 400 if original_text.blank?
    return render json: { error: 'System-Prompt fehlt' }, status: 400 if system_prompt.blank?
    
    settings = Setting.plugin_redmine_ai_integration
    
    begin
      improved_text = case provider
      when 'openai'
        call_openai(original_text, system_prompt, settings)
      when 'gemini'
        call_gemini(original_text, system_prompt, settings)
      when 'claude'
        call_claude(original_text, system_prompt, settings)
      when 'ollama'
        call_ollama(original_text, system_prompt, settings)
      else
        raise "Unbekannter Provider: #{provider}"
      end
      
      version_id = save_text_version(original_text, improved_text, session_id, field_type, issue_id)
      
      render json: {
        improved_text: improved_text,
        version_id: version_id,
        session_id: session_id
      }
      
    rescue => e
      Rails.logger.error "AI Rewrite Fehler: #{e.message}"
      render json: { error: "Fehler bei der KI-Verarbeitung: #{e.message}" }, status: 500
    end
  end
  
  def rewrite_stream
    original_text = params[:original_text]
    system_prompt = params[:system_prompt]
    provider = params[:provider] || Setting.plugin_redmine_ai_integration['ai_provider']
    
    return render json: { error: 'Original-Text fehlt' }, status: 400 if original_text.blank?
    
    settings = Setting.plugin_redmine_ai_integration
    
    if provider == 'ollama'
      url = settings['ollama_url'] || 'http://localhost:11434'
      url = url.chomp('/')
      model = settings['ollama_model'] || 'llama2'
      
      uri = URI("#{url}/api/generate")
      
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Last-Modified'] = Time.now.httpdate
      
      begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request.body = {
            model: model,
            prompt: "#{system_prompt}\n\nText: #{original_text}",
            stream: true,
            options: {
              temperature: 0.7,
              num_predict: 2000
            }
          }.to_json
          
          http.request(request) do |res|
            res.read_body do |chunk|
              # Ollama sendet JSON-Chunks
              begin
                json_chunk = JSON.parse(chunk)
                response.stream.write "data: #{json_chunk['response']}\n\n"
                break if json_chunk['done']
              rescue JSON::ParserError
                # Falls ein Chunk kein vollständiges JSON ist
                next
              end
            end
          end
        end
      rescue => e
        response.stream.write "data: [ERROR: #{e.message}]\n\n"
      ensure
        response.stream.close
      end
    else
      render json: { error: 'Streaming nur für Ollama implementiert' }, status: 501
    end
  end
  
  def save_version
    text = params[:text]
    version_id = params[:version_id]
    
    if version_id.present?
      # Aktualisiere bestehende Version
      version = AiTextVersion.find_by_version_id(version_id)
      if version
        version.update!(improved_text: text, last_changed_on: Time.current)
        render json: { success: true }
      else
        render json: { error: 'Version nicht gefunden' }, status: 404
      end
    else
      # Neue Version erstellen
      original_text = params[:original_text]
      session_id = params[:session_id]
      field_type = params[:field_type] || 'description'
      issue_id = params[:issue_id]
      
      new_version_id = save_text_version(original_text, text, session_id, field_type, issue_id)
      render json: { version_id: new_version_id }
    end
  end
  
  def get_version
    version_id = params[:version_id]
    direction = params[:direction] || 'exact'
    
    result = get_text_version(version_id, direction)
    
    if result
      render json: result
    else
      render json: { error: 'Version nicht gefunden' }, status: 404
    end
  end
  
  def list_versions
    session_id = params[:session_id]
    issue_id = params[:issue_id]&.to_i
    field_type = params[:field_type]
    journal_id = params[:journal_id]

    if session_id.blank? && issue_id.present?
      query = AiTextVersion.where(issue_id: issue_id, field_type: field_type)
      query = query.where(journal_id: journal_id) if journal_id.present?
      latest = query.order(last_changed_on: :desc).first
      session_id = latest&.session_id
    end

    return render json: { versions: [] } if session_id.blank?

    versions = list_versions_for_session(session_id, field_type)
    render json: { session_id: session_id, versions: versions }
  end
  
  def settings
    settings = Setting.plugin_redmine_ai_integration
    render json: { settings: settings }
  end
  
  def check_versions
    issue_id = params[:issue_id]
    field_type = params[:field_type] || 'description'
    journal_id = params[:journal_id]
    
    return render json: { has_versions: false } if issue_id.blank?
    
    query = AiTextVersion.where(issue_id: issue_id, field_type: field_type)
    query = query.where(journal_id: journal_id) if journal_id.present?
    
    latest = query.order(last_changed_on: :desc).first
    
    if latest
      original = AiTextVersion.where(session_id: latest.session_id).order(:created_at).first
      
      render json: {
        has_versions: true,
        session_id: latest.session_id,
        version_id: latest.version_id,
        can_go_prev: original && original != latest,
        can_go_next: false
      }
    else
      render json: { has_versions: false }
    end
  end
  
  def clear_versions
    session_id = params[:session_id]
    
    if session_id.present?
      AiTextVersion.where(session_id: session_id).destroy_all
      render json: { success: true, message: 'Versionen gelöscht' }
    else
      render json: { error: 'Session-ID fehlt' }, status: 400
    end
  end
  
  def test_connection
    provider = params[:provider] || Setting.plugin_redmine_ai_integration['ai_provider']
    settings = Setting.plugin_redmine_ai_integration
    
    result = case provider
    when 'openai'
      test_openai_connection(settings)
    when 'gemini'
      test_gemini_connection(settings)
    when 'claude'
      test_claude_connection(settings)
    when 'ollama'
      test_ollama_connection(settings)
    else
      { success: false, error: 'Unbekannter Provider' }
    end
    
    render json: result
  end
  
  def requests
    @versions = AiTextVersion.recent.limit(50)
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
    when 'ollama'
      if settings['ollama_url'].blank?
        render json: { error: 'Ollama URL nicht konfiguriert' }, status: 400
        return false
      end
    else
      render json: { error: 'KI-Provider nicht konfiguriert' }, status: 400
      return false
    end
    
    true
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
      temperature: 0.7,
      max_tokens: 2000
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
  
  def call_gemini(text, system_prompt, settings)
    require 'net/http'
    require 'json'
    
    api_key = settings['gemini_api_key']
    model = settings['gemini_model'].presence || 'gemini-1.5-pro'
    model = model.to_s.split('/').last # Normalisiere Modellname
    
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    
    body = {
      contents: [{
        parts: [{
          text: "#{system_prompt}\n\nText: #{text}"
        }]
      }],
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 2000
      }
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
      max_tokens: 2000,
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
  
  def call_ollama(text, system_prompt, settings)
    require 'net/http'
    require 'json'
    
    url = settings['ollama_url'] || 'http://localhost:11434'
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
      prompt: "#{system_prompt}\n\nText: #{text}",
      stream: false,
      options: {
        temperature: 0.7,
        num_predict: 2000
      }
    }
    
    request.body = body.to_json
    response = http.request(request)
    
    if response.code == '200'
      result = JSON.parse(response.body)
      result['response'].strip
    else
      raise "Ollama API Fehler: #{response.code} - #{response.body}"
    end
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

    response = http.request(request)

    if response.code == '200'
      models_data = JSON.parse(response.body)
      models = models_data['data'] ? models_data['data'].map { |m| m['id'] } : []
      Rails.logger.info "OpenAI Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
    end
  end
  
  def test_gemini_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "Gemini Test - API Key vorhanden: #{!settings['gemini_api_key'].blank?}"
    
    if settings['gemini_api_key'].blank?
      return { success: false, error: 'Gemini API Key nicht konfiguriert' }
    end

    uri = URI("https://generativelanguage.googleapis.com/v1beta/models?key=#{settings['gemini_api_key']}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)

    response = http.request(request)

    if response.code == '200'
      models_data = JSON.parse(response.body)
      models = if models_data['models']
        models_data['models'].map { |m| m['name'].to_s.split('/').last }
      else
        []
      end
      Rails.logger.info "Gemini Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
    end
  end
  
  def test_claude_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "Claude Test - API Key vorhanden: #{!settings['claude_api_key'].blank?}"
    
    if settings['claude_api_key'].blank?
      return { success: false, error: 'Claude API Key nicht konfiguriert' }
    end

    uri = URI('https://api.anthropic.com/v1/models')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['x-api-key'] = settings['claude_api_key']
    request['anthropic-version'] = '2023-06-01'

    response = http.request(request)

    if response.code == '200'
      models_data = JSON.parse(response.body)
      models = models_data['models'] ? models_data['models'].map { |m| m['id'] } : []
      Rails.logger.info "Claude Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
    end
  end
  
  def test_ollama_connection(settings)
    require 'net/http'
    require 'json'

    Rails.logger.info "Ollama Test - URL: #{settings['ollama_url']}"
    
    if settings['ollama_url'].blank?
      return { success: false, error: 'Ollama URL nicht konfiguriert' }
    end

    url = settings['ollama_url']
    url = url.chomp('/')
    use_ssl = url.start_with?('https://')

    uri = URI("#{url}/api/tags")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = use_ssl
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)

    response = http.request(request)

    if response.code == '200'
      models_data = JSON.parse(response.body)
      models = models_data['models'] ? models_data['models'].map { |m| m['name'] } : []
      Rails.logger.info "Ollama Test - Gefundene Modelle: #{models.count}"
      { success: true, message: 'Verbindung erfolgreich', models: models }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
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
      version_number: 0,
      original_text: original_text,
      improved_text: original_text,
      user_id: User.current.id,
      issue_id: issue_id,
      field_type: field_type || detect_field_type,
      last_changed_on: Time.current,
      journal_id: params[:journal_id],
      fixed_version_id: fetch_fixed_version_id(issue_id)
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
    version_number = AiTextVersion.next_version_number_for(session_id, field_type)
    
    version = AiTextVersion.create!(
      session_id: session_id,
      version_id: version_id,
      version_number: version_number,
      original_text: original_text,
      improved_text: improved_text,
      user_id: User.current.id,
      issue_id: issue_id,
      field_type: field_type,
      last_changed_on: Time.current,
      journal_id: params[:journal_id],
      fixed_version_id: fetch_fixed_version_id(issue_id)
    )
    
    Rails.logger.info "Save Text Version - Session ID: #{session_id}, Version ID: #{version_id}, Issue ID: #{issue_id}"
    version_id
  end
  
  def get_text_version(version_id, direction)
    current_version = AiTextVersion.find_by_version_id(version_id)
    return nil unless current_version
    
    new_version = case direction
    when 'prev'
      current_version.get_prev_version
    when 'next'
      current_version.get_next_version
    when 'exact'
      current_version
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
  
  def get_original_version(session_id)
    original_version = AiTextVersion.where(session_id: session_id, version_id: "#{session_id}_original").first
    return nil unless original_version
    
    versions_count = AiTextVersion.where(session_id: session_id).count
    
    {
      id: original_version.version_id,
      text: original_version.original_text,
      can_go_prev: false,
      can_go_next: versions_count > 1
    }
  end
  
  def detect_field_type
    # Versuche Field-Type aus der URL oder params zu bestimmen
    if request.referer
      return 'notes' if request.referer.include?('notes')
      return 'description' if request.referer.include?('description')
    end
    
    params[:field_type] || 'description'
  end
  
  def extract_issue_id
    # Extrahiere Issue-ID aus der URL
    if request.referer && request.referer =~ /\/issues\/(\d+)/
      return $1
    end
    params[:issue_id]
  end
  
  def generate_session_id
    user_id = User.current&.id || 'anonymous'
    "#{user_id}_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  end
  
  def fetch_fixed_version_id(issue_id)
    return nil unless issue_id
    issue = Issue.find_by(id: issue_id)
    issue&.fixed_version_id
  end
  
  def list_versions_for_session(session_id, field_type = nil)
    relation = AiTextVersion.where(session_id: session_id)
    relation = relation.where(field_type: field_type) if field_type.present?
    relation.order(:version_number, :created_at).map do |v|
      {
        version_id: v.version_id,
        version_number: v.version_number,
        label: "v#{v.version_number}",
        created_at: v.created_at
      }
    end
  end
end