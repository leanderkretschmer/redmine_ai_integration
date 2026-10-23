class AiRewriteController < ApplicationController
  before_action :require_login, except: [:settings]
  before_action :check_settings, except: [:test_connection, :rewrite_stream, :requests, :check_versions, :list_versions, :settings, :pull_ollama_model]
  before_action :require_admin, only: [:test_connection, :pull_ollama_model, :requests]
  skip_before_action :verify_authenticity_token, only: [:rewrite, :rewrite_stream, :save_version, :get_version, :clear_versions, :test_connection, :check_versions, :list_versions, :settings]

  # Settings, die ans Frontend gehen dürfen (keine Schlüssel/Tokens!)
  PUBLIC_SETTING_KEYS = %w[
    ai_provider embedded_system_prompt slim_response
    knowledge_base_enabled knowledge_auto_learn
  ].freeze

  def rewrite
    original_text = params[:original_text]
    system_prompt = params[:system_prompt]

    Rails.logger.info "AI Rewrite Request - Text length: #{original_text&.length}, Prompt length: #{system_prompt&.length}"

    session_id = params[:session_id] || generate_session_id
    field_type = params[:field_type] || 'description'
    issue_id = params[:issue_id].presence
    provider = params[:provider].presence || Setting.plugin_redmine_ai_integration['ai_provider']
    request_type = params[:request_type].presence || 'rewrite'

    return render json: { error: 'Original-Text fehlt' }, status: 400 if original_text.blank?
    return render json: { error: 'System-Prompt fehlt' }, status: 400 if system_prompt.blank?

    begin
      client = RedmineAiIntegration::AiClient.new(nil, provider: provider)
      task = task_for_request_type(request_type)

      # Wissensbasis in den Prompt einbinden
      project_id = Issue.where(id: issue_id).pick(:project_id) if issue_id
      full_prompt = RedmineAiIntegration::KnowledgeBase.augment_prompt(system_prompt, project_id: project_id)

      result = client.complete(full_prompt, original_text, task: task)

      improved_text = result[:text]
      token_info = result[:tokens] || {}

      if improved_text.blank?
        Rails.logger.error 'AI Rewrite Error - Provider returned empty text'
        raise 'Die KI hat keine Antwort geliefert. Bitte versuchen Sie es erneut.'
      end

      version_id = save_text_version(original_text, improved_text, session_id, field_type, issue_id, provider, token_info,
                                     request_type: request_type, model_used: result[:model])

      Rails.logger.info "AI Rewrite Success - Model: #{result[:model]}, Improved Text Length: #{improved_text&.length}"

      render json: {
        improved_text: improved_text,
        version_id: version_id,
        session_id: session_id,
        model: result[:model],
        knowledge_enabled: RedmineAiIntegration::KnowledgeBase.enabled?,
        auto_learn: RedmineAiIntegration::KnowledgeBase.auto_learn?
      }
    rescue => e
      Rails.logger.error "AI Rewrite Fehler: #{e.class} #{e.message}"
      render json: { error: "Fehler bei der KI-Verarbeitung: #{e.message}" }, status: 500
    end
  end

  def rewrite_stream
    # Streaming-Implementierung für zukünftige Erweiterungen
    render json: { error: 'Streaming noch nicht implementiert' }, status: 501
  end

  def save_version
    text = params[:text]
    version_id = params[:version_id]

    if version_id.present?
      version = AiTextVersion.find_by_version_id(version_id)
      if version
        version.update!(improved_text: text, last_changed_on: Time.current)
        render json: { success: true }
      else
        render json: { error: 'Version nicht gefunden' }, status: 404
      end
    else
      original_text = params[:original_text]
      session_id = params[:session_id]
      field_type = params[:field_type] || 'description'
      issue_id = params[:issue_id].presence

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

  # Nur unkritische Einstellungen ans Frontend geben
  def settings
    all = Setting.plugin_redmine_ai_integration
    public_settings = all.to_h.slice(*PUBLIC_SETTING_KEYS)
    public_settings['provider_configured'] = RedmineAiIntegration::AiClient.new(all).configuration_error.nil?
    render json: { settings: public_settings }
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
    provider = params[:provider].presence || Setting.plugin_redmine_ai_integration['ai_provider']
    client = RedmineAiIntegration::AiClient.new(nil, provider: provider)
    render json: client.test_connection
  end

  def pull_ollama_model
    model_name = params[:model_name]
    return render json: { success: false, error: 'Modellname fehlt' }, status: 400 if model_name.blank?

    settings = Setting.plugin_redmine_ai_integration
    url = settings['ollama_url']
    return render json: { success: false, error: 'Ollama URL nicht konfiguriert' }, status: 400 if url.blank?

    require 'net/http'
    require 'json'

    url = url.chomp('/')
    uri = URI("#{url}/api/pull")

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = url.start_with?('https://')
      http.read_timeout = 300

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = { name: model_name, stream: false }.to_json

      response = http.request(request)

      if response.code == '200'
        render json: { success: true, message: "Modell #{model_name} wurde erfolgreich geladen." }
      else
        render json: { success: false, error: "Fehler beim Laden: #{response.code} - #{response.body}" }
      end
    rescue => e
      render json: { success: false, error: "Verbindungsfehler: #{e.message}" }
    end
  end

  def requests
    @versions = AiTextVersion.recent.limit(50)
  end

  private

  def check_settings
    error = RedmineAiIntegration::AiClient.new.configuration_error
    if error
      render json: { error: error }, status: 400
      return false
    end
    true
  end

  def task_for_request_type(request_type)
    case request_type.to_s
    when 'complex' then :complex
    else :correction
    end
  end

  def ensure_original_version_saved(original_text, session_id, field_type = nil, issue_id = nil)
    existing = AiTextVersion.where(session_id: session_id).order(:created_at).first
    return if existing && existing.version_id == "#{session_id}_original"

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

    Rails.logger.info "Ensure Original Version - Session ID: #{session_id}, Version ID: #{version.version_id}"
  end

  def save_text_version(original_text, improved_text, session_id = nil, field_type = nil, issue_id = nil, provider = nil, token_info = {}, request_type: nil, model_used: nil)
    session_id ||= params[:session_id] || generate_session_id
    field_type ||= params[:field_type] || detect_field_type
    issue_id ||= params[:issue_id].presence || extract_issue_id

    ensure_original_version_saved(original_text, session_id, field_type, issue_id) unless AiTextVersion.where(session_id: session_id).exists?

    version_id = "#{session_id}_#{Time.now.to_i}"
    version_number = AiTextVersion.next_version_number_for(session_id, field_type)

    version = AiTextVersion.create!(
      session_id: session_id,
      version_id: version_id,
      version_number: version_number,
      original_text: original_text,
      improved_text: improved_text,
      ai_output_text: provider.present? ? improved_text : nil,
      request_type: request_type,
      model_used: model_used,
      user_id: User.current.id,
      issue_id: issue_id,
      field_type: field_type,
      last_changed_on: Time.current,
      journal_id: params[:journal_id],
      fixed_version_id: fetch_fixed_version_id(issue_id),
      provider: provider,
      prompt_tokens: token_info[:prompt] || 0,
      completion_tokens: token_info[:completion] || 0,
      total_tokens: token_info[:total] || 0
    )

    Rails.logger.info "Save Text Version - Session ID: #{session_id}, Version ID: #{version_id}, Issue ID: #{issue_id}, Tokens: #{version.total_tokens}"
    version_id
  end

  def get_text_version(version_id, direction)
    current_version = AiTextVersion.find_by_version_id(version_id)
    return nil unless current_version

    new_version = case direction
                  when 'prev' then current_version.get_prev_version
                  when 'next' then current_version.get_next_version
                  when 'exact' then current_version
                  end

    return nil unless new_version

    {
      id: new_version.version_id,
      text: new_version.improved_text,
      can_go_prev: new_version.can_go_prev?,
      can_go_next: new_version.can_go_next?
    }
  end

  def detect_field_type
    if request.referer
      return 'notes' if request.referer.include?('notes')
      return 'description' if request.referer.include?('description')
    end

    params[:field_type] || 'description'
  end

  def extract_issue_id
    if request.referer && request.referer =~ /\/issues\/(\d+)/
      return $1
    end
    params[:issue_id].presence
  end

  def generate_session_id
    user_id = User.current&.id || 'anonymous'
    "#{user_id}_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  end

  def fetch_fixed_version_id(issue_id)
    return nil unless issue_id
    Issue.find_by(id: issue_id)&.fixed_version_id
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
