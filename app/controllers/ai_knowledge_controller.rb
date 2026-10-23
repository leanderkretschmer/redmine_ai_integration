# Wissensbasis: Verwaltung (Admin) und Lernen aus Nutzer-Korrekturen (alle angemeldeten Nutzer).
class AiKnowledgeController < ApplicationController
  layout 'admin', only: [:index, :new, :edit]

  before_action :require_login
  before_action :require_admin, except: [:learn, :suggest]
  before_action :find_entry, only: [:edit, :update, :destroy, :toggle, :review]
  skip_before_action :verify_authenticity_token, only: [:learn, :suggest]

  helper :sort
  include SortHelper

  def index
    sort_init 'updated_at', 'desc'
    sort_update %w[category source active hit_count updated_at]

    @stats = AiKnowledgeEntry.stats
    scope = AiKnowledgeEntry.includes(:project, :user)
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where(source: params[:source]) if params[:source].present?
    scope = scope.where(active: params[:active] == '1') if params[:active].present?
    scope = scope.where('content LIKE ?', "%#{AiKnowledgeEntry.sanitize_sql_like(params[:q])}%") if params[:q].present?

    @entry_count = scope.count
    @entry_pages = Paginator.new @entry_count, per_page_option, params['page']
    @entries = scope.order(sort_clause).limit(@entry_pages.per_page).offset(@entry_pages.offset).to_a
  end

  def new
    @entry = AiKnowledgeEntry.new(category: 'rule', source: 'manual', active: true, reviewed: true)
  end

  def create
    @entry = AiKnowledgeEntry.new(entry_params)
    @entry.source = 'manual'
    @entry.reviewed = true
    @entry.user_id = User.current.id
    if @entry.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to ai_knowledge_path
    else
      render :new
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params.merge(reviewed: true))
      flash[:notice] = l(:notice_successful_update)
      redirect_to ai_knowledge_path
    else
      render :edit
    end
  end

  def destroy
    @entry.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to ai_knowledge_path
  end

  def toggle
    @entry.update(active: !@entry.active, reviewed: true)
    redirect_back_or_default ai_knowledge_path
  end

  def review
    @entry.update(reviewed: true)
    redirect_back_or_default ai_knowledge_path
  end

  def destroy_learned
    AiKnowledgeEntry.learned.unreviewed.destroy_all
    flash[:notice] = 'Ungeprüfte gelernte Einträge gelöscht.'
    redirect_to ai_knowledge_path
  end

  # Lernen aus einer Korrektur: KI-Ausgabe vs. finale Nutzerfassung
  def learn
    unless RedmineAiIntegration::KnowledgeBase.enabled?
      return render json: { success: false, error: 'Wissensbasis ist deaktiviert' }, status: 400
    end

    version = AiTextVersion.find_by_version_id(params[:version_id])
    return render json: { success: false, error: 'Version nicht gefunden' }, status: 404 unless version
    unless version.user_id == User.current.id || User.current.admin?
      return render json: { success: false, error: 'Keine Berechtigung' }, status: 403
    end
    if version.learned_at.present? && params[:force] != '1'
      return render json: { success: true, already_learned: true, entries: [] }
    end

    final_text = params[:final_text].presence || version.improved_text
    client = RedmineAiIntegration::AiClient.new
    if (error = client.configuration_error)
      return render json: { success: false, error: error }, status: 400
    end

    result = RedmineAiIntegration::KnowledgeBase.learn_from_version!(version, final_text, client: client)
    entries = result.is_a?(Hash) ? result[:entries] : []
    # Nutzer-Edit als finale Fassung festhalten
    version.update_columns(improved_text: final_text, last_changed_on: Time.current) if params[:final_text].present?

    render json: {
      success: true,
      entries: entries.map { |e| { id: e.id, category: e.category_label, content: e.content, reason: e.reason } },
      tokens: result.is_a?(Hash) ? result[:tokens] : nil
    }
  rescue RedmineAiIntegration::AiClient::Error, RedmineAiIntegration::ClaudeOauth::Error => e
    render json: { success: false, error: e.message }, status: 502
  rescue => e
    Rails.logger.error "AI Knowledge Learn Fehler: #{e.class} #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end

  # Manueller Wissensvorschlag aus dem Editor (z. B. "Produktname XY immer so schreiben")
  def suggest
    content = params[:content].to_s.strip
    return render json: { success: false, error: 'Inhalt fehlt' }, status: 400 if content.blank?

    issue = Issue.find_by(id: params[:issue_id]) if params[:issue_id].present?
    entry = AiKnowledgeEntry.create!(
      category:   AiKnowledgeEntry::CATEGORIES.include?(params[:category]) ? params[:category] : 'rule',
      content:    content,
      reason:     'Manuell aus dem Editor hinzugefügt',
      source:     'learned',
      project_id: issue&.project_id,
      issue_id:   issue&.id,
      user_id:    User.current.id,
      reviewed:   User.current.admin?,
      active:     true,
      hit_count:  1
    )
    render json: { success: true, entry: { id: entry.id, category: entry.category_label, content: entry.content } }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: 422
  end

  private

  def find_entry
    @entry = AiKnowledgeEntry.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def entry_params
    permitted = params.require(:ai_knowledge_entry).permit(:category, :content, :reason, :project_id, :active)
    permitted[:project_id] = nil if permitted[:project_id].blank?
    permitted
  end
end
