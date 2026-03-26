class AiChatMessage < ActiveRecord::Base
  self.table_name = 'ai_chat_messages'
  
  belongs_to :issue
  belongs_to :user
  belongs_to :journal_referenced, class_name: 'Journal', optional: true
  
  validates :issue_id, presence: true
  validates :user_id, presence: true
  validates :question, presence: true
  
  scope :for_issue, ->(issue_id) { where(issue_id: issue_id).order(:created_at) }
  scope :recent, -> { order(created_at: :desc) }
  
  def self.token_stats(period = nil)
    query = self.all
    case period
    when :daily
      query = query.where('created_at >= ?', Time.current.beginning_of_day)
    when :weekly
      query = query.where('created_at >= ?', Time.current.beginning_of_week)
    when :monthly
      query = query.where('created_at >= ?', Time.current.beginning_of_month)
    end
    
    {
      prompt: query.sum(:prompt_tokens),
      completion: query.sum(:completion_tokens),
      total: query.sum(:total_tokens)
    }
  end
  
  def self.build_context_for_issue(issue)
    journals = issue.journals.includes(:user, :details).order(:created_on)
    context_parts = []
    
    # Basis-Informationen
    context_parts << "Ticket ##{issue.id}: #{issue.subject}"
    context_parts << "Status: #{issue.status.name}" if issue.status
    context_parts << "Priorität: #{issue.priority.name}" if issue.priority
    context_parts << "Autor: #{issue.author.name}" if issue.author
    context_parts << "Erstellt: #{issue.created_on}"
    
    # Beschreibung
    if issue.description.present?
      context_parts << "\nBeschreibung:\n#{issue.description}"
    end
    
    # Kommentare/Journals
    journals.each_with_index do |journal, index|
      next if journal.notes.blank?
      
      context_parts << "\nKommentar ##{index + 1} (#{journal.created_on} von #{journal.user.name}):"
      context_parts << journal.notes
      
      # Detail-Änderungen hinzufügen
      if journal.details.any?
        changes = journal.details.map do |detail|
          "- #{detail.prop_key}: #{detail.old_value} → #{detail.value}"
        end.join("\n")
        context_parts << "Änderungen:\n#{changes}"
      end
    end
    
    context_parts.join("\n")
  end
  
  def extract_journal_references(text)
    # Finde alle Vorkommen von #Zahl oder "Kommentar #Zahl"
    references = []
    text.scan(/(?:Kommentar\s+)?#(\d+)/i).each do |match|
      journal_index = match[0].to_i
      # Konvertiere Journal-Index zur tatsächlichen Journal-ID
      journal = issue.journals.where.not(notes: [nil, '']).order(:created_on).offset(journal_index - 1).first
      references << journal if journal
    end
    references.uniq
  end
end