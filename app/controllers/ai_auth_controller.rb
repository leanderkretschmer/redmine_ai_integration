# Anmeldung mit einem Claude-Konto (OAuth) – nur für Administratoren.
class AiAuthController < ApplicationController
  before_action :require_admin
  skip_before_action :verify_authenticity_token, only: [:claude_start, :claude_exchange, :claude_logout, :claude_status]

  # Schritt 1: Autorisierungs-URL erzeugen (PKCE in der Session merken)
  def claude_start
    pkce = RedmineAiIntegration::ClaudeOauth.generate_pkce
    session[:claude_oauth_pkce] = pkce
    url = RedmineAiIntegration::ClaudeOauth.authorize_url(pkce, callback_url)

    render json: {
      success: true,
      authorize_url: url,
      redirect_mode: RedmineAiIntegration::ClaudeOauth.callback_mode? ? 'callback' : 'manual',
      callback_url: callback_url
    }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # Schritt 2a (manuell): Code "code#state" einlösen
  def claude_exchange
    pkce = session_pkce
    return render json: { success: false, error: 'Anmeldung nicht gestartet oder Session abgelaufen – bitte erneut starten' }, status: 400 unless pkce

    RedmineAiIntegration::ClaudeOauth.exchange_code!(params[:code], pkce, callback_url)
    session.delete(:claude_oauth_pkce)
    render json: { success: true, status: RedmineAiIntegration::ClaudeOauth.status }
  rescue RedmineAiIntegration::ClaudeOauth::Error => e
    render json: { success: false, error: e.message }, status: 400
  rescue => e
    Rails.logger.error "Claude OAuth Exchange Fehler: #{e.class} #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end

  # Schritt 2b (Redirect-Modus): Anthropic leitet mit ?code=&state= hierher zurück
  def claude_callback
    pkce = session_pkce
    if pkce.nil?
      flash[:error] = 'Claude-Anmeldung: Session abgelaufen – bitte erneut starten.'
      return redirect_to plugin_settings_path('redmine_ai_integration')
    end

    code = params[:code].to_s
    code = "#{code}##{params[:state]}" if params[:state].present? && !code.include?('#')
    RedmineAiIntegration::ClaudeOauth.exchange_code!(code, pkce, callback_url)
    session.delete(:claude_oauth_pkce)
    flash[:notice] = 'Claude-Konto erfolgreich verbunden.'
    redirect_to plugin_settings_path('redmine_ai_integration')
  rescue RedmineAiIntegration::ClaudeOauth::Error => e
    flash[:error] = "Claude-Anmeldung fehlgeschlagen: #{e.message}"
    redirect_to plugin_settings_path('redmine_ai_integration')
  end

  def claude_logout
    RedmineAiIntegration::ClaudeOauth.logout!
    render json: { success: true, status: RedmineAiIntegration::ClaudeOauth.status }
  end

  def claude_status
    render json: { success: true, status: RedmineAiIntegration::ClaudeOauth.status }
  end

  private

  def session_pkce
    raw = session[:claude_oauth_pkce]
    return nil if raw.blank?

    raw.to_h.transform_keys(&:to_sym)
  end

  def callback_url
    "#{request.base_url}/ai_auth/claude/callback"
  end
end
