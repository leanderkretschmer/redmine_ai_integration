# Eintrag in der Wissensbasis des KI-Plugins.
#
# Einträge stammen entweder aus manueller Pflege (source = 'manual') oder wurden aus
# Nutzer-Korrekturen gelernt (source = 'learned'). Sie werden bei Korrektur-, Erweiterungs-
# und Chat-Anfragen als zusätzlicher Kontext an das Modell übergeben.
class AiKnowledgeEntry < ActiveRecord::Base
  self.table_name = 'ai_knowledge_entries'

  CATEGORIES = %w[rule terminology style fact].freeze
  SOURCES    = %w[manual learned].freeze

  CATEGORY_LABELS = {
    'rule'        => 'Regel',
    'terminology' => 'Terminologie',
    'style'       => 'Stil',
    'fact'        => 'Fakt'
  }.freeze

  belongs_to :project, optional: true
  belongs_to :issue, optional: true
  belongs_to :user, optional: true

  validates :content, presence: true, length: { maximum: 2000 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :source, inclusion: { in: SOURCES }

  scope :active, -> { where(active: true) }
  scope :learned, -> { where(source: 'learned') }
  scope :manual, -> { where(source: 'manual') }
  scope :unreviewed, -> { where(reviewed: false) }
  scope :recent, -> { order(updated_at: :desc) }

  # Globale Einträge + Einträge des angegebenen Projekts
  scope :for_project, lambda { |project_id|
    if project_id.present?
      where('project_id IS NULL OR project_id = ?', project_id)
    else
      where(project_id: nil)
    end
  }

  before_validation :normalize_content

  def category_label
    CATEGORY_LABELS[category] || category
  end

  def learned?
    source == 'learned'
  end

  def self.normalize(text)
    text.to_s.strip.gsub(/\s+/, ' ')
  end

  # Legt einen gelernten Eintrag an oder erhöht den Zähler eines identischen Eintrags
  def self.learn!(attrs)
    normalized = normalize(attrs[:content])
    return nil if normalized.blank?

    existing = where(content: normalized).first
    if existing
      existing.increment!(:hit_count)
      existing.update_columns(active: true, updated_at: Time.current) unless existing.active?
      return existing
    end

    create!(attrs.merge(content: normalized, source: 'learned', reviewed: false, active: true, hit_count: 1))
  end

  def self.stats
    {
      total: count,
      active: active.count,
      learned: learned.count,
      unreviewed: unreviewed.count
    }
  end

  private

  def normalize_content
    self.content = self.class.normalize(content)
  end
end
