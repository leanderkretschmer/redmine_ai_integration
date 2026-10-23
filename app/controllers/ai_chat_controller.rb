class AiChatController < ApplicationController
  before_action :require_login
  skip_before_action :verify_authenticity_token, only: [:ask, :history]
  
  def ask
    issue_id = params[:issue_id]
    question = params[:question]
    
    return render json: { error: 'Issue-ID fehlt' }, status: 400 if issue_id.blank?
    return render json: { error: 'Frage fehlt' }, status: 400 if question.blank?
    
    issue = Issue.find_by(id: issue_id)
    return render json: { error: 'Ticket nicht gefunden' }, status: 404 unless issue
    
    # Bereite Kontext vor
    context = AiChatMessage.build_context_for_issue(issue)
    
    # Erstelle System-Prompt
    system_prompt = build_chat_system_prompt(issue, context)
    
    # Hole AI-Antwort
    settings = Setting.plugin_redmine_ai_integration
    provider = settings['ai_provider']
    client = RedmineAiIntegration::AiClient.new(settings)

    if (config_error = client.configuration_error)
      return render json: { error: config_error }, status: 400
    end

    begin
      # Wissensbasis (Fakten, Terminologie, Regeln des Projekts) einbinden
      system_prompt = RedmineAiIntegration::KnowledgeBase.augment_prompt(system_prompt, project_id: issue.project_id)

      result = client.complete(system_prompt, question, task: :chat)
      answer = result[:text]
      token_info = result[:tokens] || {}
      
      # Extrahiere Journal-Referenzen
      journal_references = extract_journal_references_from_answer(answer, issue)
      
      # Speichere Nachricht
      message = AiChatMessage.create!(
        issue_id: issue_id,
        user_id: User.current.id,
        question: question,
        answer: answer,
        context_used: context.truncate(1000), # Begrenze Kontext-Länge
        model_used: result[:model] || provider,
        journal_id_referenced: journal_references.first&.id,
        provider: provider,
        prompt_tokens: token_info[:prompt] || 0,
        completion_tokens: token_info[:completion] || 0,
        total_tokens: token_info[:total] || 0
      )
      
      # Formatiere Antwort mit Links
      formatted_answer = format_answer_with_links(answer, issue)
      
      render json: {
        answer: formatted_answer,
        message_id: message.id,
        journal_references: journal_references.map { |j| { id: j.id, index: find_journal_index(j, issue) } }
      }
      
    rescue => e
      Rails.logger.error "AI Chat Fehler: #{e.message}"
      render json: { error: "Fehler bei der KI-Anfrage: #{e.message}" }, status: 500
    end
  end
  
  def history
    issue_id = params[:issue_id]
    return render json: { messages: [] } if issue_id.blank?
    
    # Filtere nach Issue und aktuellem User für benutzerspezifischen Chat-Verlauf
    messages = AiChatMessage.for_issue(issue_id).where(user_id: User.current.id).includes(:user, :journal_referenced)
    
    render json: {
      messages: messages.map do |msg|
        {
          id: msg.id,
          question: msg.question,
          answer: format_answer_with_links(msg.answer, msg.issue),
          user_name: msg.user.name,
          created_at: msg.created_at.iso8601,
          journal_references: msg.journal_referenced ? [{ id: msg.journal_referenced.id, index: find_journal_index(msg.journal_referenced, msg.issue) }] : []
        }
      end
    }
  end
  
  def clear
    issue_id = params[:issue_id]
    return render json: { error: 'Issue-ID fehlt' }, status: 400 if issue_id.blank?
    
    begin
      AiChatMessage.where(issue_id: issue_id, user_id: User.current.id).destroy_all
      render json: { success: true }
    rescue => e
      render json: { error: e.message }, status: 500
    end
  end
  
  private
  
  def build_chat_system_prompt(issue, context)
    settings = Setting.plugin_redmine_ai_integration
    chat_prompt = settings['chat_system_prompt']
    
    user_name = User.current.name
    
    # Falls der Prompt Platzhalter für User-Info enthält oder wir sie erzwingen wollen:
    system_instruction = <<~PROMPT
      Du bist ein hilfreicher Assistent für Redmine-Tickets.
      Aktueller Benutzer: #{user_name}
      WICHTIG: Sprich den Benutzer "#{user_name}" direkt mit "Du" an, wenn es um seine eigenen Kommentare oder Aktionen geht.
      
      Ticket-Kontext:
      #{context}
      
      Anweisung:
      #{chat_prompt}
    PROMPT
    
    system_instruction
  end
  
  def extract_journal_references_from_answer(answer, issue)
    return [] unless answer.present?
    
    references = []
    answer.scan(/(?:Kommentar\s+)?#(\d+)/i).each do |match|
      journal_index = match[0].to_i
      journal = issue.journals.where.not(notes: [nil, '']).order(:created_on).offset(journal_index - 1).first
      references << journal if journal
    end
    references.uniq
  end
  
  def format_answer_with_links(answer, issue)
    return answer unless answer.present?
    
    # Ersetze "Kommentar #X" und "#X" mit Links
    formatted = answer.gsub(/(?:Kommentar\s+)?#(\d+)/i) do |match|
      journal_index = $1.to_i
      journal = issue.journals.where.not(notes: [nil, '']).order(:created_on).offset(journal_index - 1).first
      
      if journal
        "<a href='##{journal_index}' class='ai-journal-link' data-journal-id='#{journal.id}'>#{match}</a>"
      else
        match
      end
    end
    
    formatted
  end
  
  def find_journal_index(journal, issue)
    journals = issue.journals.where.not(notes: [nil, '']).order(:created_on)
    journals.index(journal) + 1
  end
end