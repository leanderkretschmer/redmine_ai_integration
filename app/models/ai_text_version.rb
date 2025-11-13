class AiTextVersion < ActiveRecord::Base
  self.table_name = 'ai_text_versions'
  
  belongs_to :user
  belongs_to :issue, optional: true
  
  validates :session_id, presence: true
  validates :version_id, presence: true
  validates :original_text, presence: true
  validates :improved_text, presence: true
  validates :user_id, presence: true
  validates :field_type, presence: true
  
  scope :for_session, ->(session_id) { where(session_id: session_id).order(:created_at) }
  scope :for_issue, ->(issue_id) { where(issue_id: issue_id).order(last_changed_on: :desc) }
  scope :recent, -> { order(last_changed_on: :desc) }
  
  def self.find_by_version_id(version_id)
    where(version_id: version_id).first
  end
  
  def self.get_versions_for_session(session_id)
    for_session(session_id).to_a
  end
  
  def self.get_original_for_session(session_id)
    for_session(session_id).order(:created_at).first
  end
  
  def can_go_prev?
    self.class.for_session(session_id).where('created_at < ?', created_at).exists?
  end
  
  def can_go_next?
    self.class.for_session(session_id).where('created_at > ?', created_at).exists?
  end
  
  def get_prev_version
    self.class.for_session(session_id).where('created_at < ?', created_at).order(created_at: :desc).first
  end
  
  def get_next_version
    self.class.for_session(session_id).where('created_at > ?', created_at).order(:created_at).first
  end
end

