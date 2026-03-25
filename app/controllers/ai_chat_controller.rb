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
    
    begin
      answer = call_ai_for_chat(question, system_prompt, provider, settings)
      
      # Extrahiere Journal-Referenzen
      journal_references = extract_journal_references_from_answer(answer, issue)
      
      # Speichere Nachricht
      message = AiChatMessage.create!(
        issue_id: issue_id,
        user_id: User.current.id,
        question: question,
        answer: answer,
        context_used: context.truncate(1000), # Begrenze Kontext-Länge
        model_used: settings["#{provider}_model"] || provider,
        journal_id_referenced: journal_references.first&.id
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
    
    messages = AiChatMessage.for_issue(issue_id).includes(:user, :journal_referenced)
    
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
  
  private
  
  def build_chat_system_prompt(issue, context)
    settings = Setting.plugin_redmine_ai_integration
    custom_prompt = settings['system_prompt'] || ''
    
    base_prompt = <<~PROMPT
      Du bist ein hilfreicher Assistent für Redmine-Tickets. Analysiere das folgende Ticket und beantworte Fragen basierend auf den vorhandenen Informationen.
      
      WICHTIG:
      - Verwende für Verweise auf Kommentare das Format "Kommentar #X" oder "#X" (z.B. "#35")
      - Wenn du Informationen aus einem bestimmten Kommentar nennst, erwähne die Kommentar-Nummer
      - Beantworte nur basierend auf den vorhandenen Daten im Ticket
      - Wenn Informationen fehlen, sage das klar
      - Halte Antworten präzise und relevant
      
      Ticket-Kontext:
      #{context}
    PROMPT
    
    base_prompt + "\n\n#{custom_prompt}" if custom_prompt.present?
    base_prompt
  end
  
  def call_ai_for_chat(question, system_prompt, provider, settings)
    case provider
    when 'openai'
      call_openai_chat(question, system_prompt, settings)
    when 'gemini'
      call_gemini_chat(question, system_prompt, settings)
    when 'claude'
      call_claude_chat(question, system_prompt, settings)
    when 'ollama'
      call_ollama_chat(question, system_prompt, settings)
    else
      raise "Unbekannter Provider: #{provider}"
    end
  end
  
  def call_openai_chat(question, system_prompt, settings)
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
        { role: 'user', content: question }
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
  
  def call_gemini_chat(question, system_prompt, settings)
    require 'net/http'
    require 'json'
    
    api_key = settings['gemini_api_key']
    model = settings['gemini_model'] || 'gemini-1.5-pro'
    model = model.to_s.split('/').last # Normalisiere Modellname
    
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    
    body = {
      contents: [{
        parts: [{
          text: "#{system_prompt}\n\nFrage: #{question}"
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
  
  def call_claude_chat(question, system_prompt, settings)
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
        content: question
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
  
  def call_ollama_chat(question, system_prompt, settings)
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
      prompt: "#{system_prompt}\n\nFrage: #{question}",
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