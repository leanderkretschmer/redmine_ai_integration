# frozen_string_literal: true

require 'json'

module RedmineAiIntegration
  # Baut den Wissensbasis-Abschnitt für System-Prompts und extrahiert neue
  # Erkenntnisse aus Nutzer-Korrekturen ("Lernen aus Fehlern").
  class KnowledgeBase
    DEFAULT_MAX_ENTRIES = 40
    DEFAULT_MAX_CHARS   = 6000

    LEARNING_SYSTEM_PROMPT = <<~PROMPT
      Rolle: Du bist ein Qualitätsanalyst für ein KI-Lektoratssystem.

      Du bekommst drei Texte:
      1. ORIGINAL – der Ausgangstext des Nutzers
      2. KI-VORSCHLAG – die Korrektur, die das Lektoratssystem geliefert hat
      3. FINAL – die Fassung, die der Nutzer anschließend tatsächlich gespeichert hat

      Aufgabe: Vergleiche KI-VORSCHLAG und FINAL. Leite daraus bis zu drei kurze, allgemeingültige
      Erkenntnisse ab, die das Lektoratssystem künftig berücksichtigen soll, damit es den Nutzer
      nicht erneut korrigieren muss. Typische Erkenntnisse:
      - Terminologie: Fachbegriffe, Produktnamen, Eigennamen oder Schreibweisen, die beibehalten werden sollen
      - Regel: eine Korrektur, die der Nutzer rückgängig gemacht hat (die KI lag falsch) oder die der Nutzer zusätzlich vorgenommen hat (die KI hat etwas übersehen)
      - Stil: Formulierungs-, Anrede- oder Formatierungspräferenzen

      Ignoriere inhaltliche Ergänzungen oder Kürzungen, die nichts mit Korrekturqualität zu tun haben.
      Wenn es keine verallgemeinerbare Erkenntnis gibt, gib eine leere Liste zurück.

      Ausgabe (STRENG): Nur ein JSON-Array, keine Erklärungen, kein Markdown:
      [{"category":"terminology|rule|style|fact","content":"<kurze Anweisung in Imperativform, max. 200 Zeichen>","reason":"<kurze Begründung>"}]
    PROMPT

    def self.settings
      Setting.plugin_redmine_ai_integration
    end

    def self.enabled?
      settings['knowledge_base_enabled'] != '0'
    end

    def self.auto_learn?
      settings['knowledge_auto_learn'] == '1'
    end

    def self.max_entries
      (settings['knowledge_max_entries'].presence || DEFAULT_MAX_ENTRIES).to_i
    end

    # Liefert den Prompt-Abschnitt mit relevanten Einträgen (oder leeren String)
    def self.prompt_section(project_id: nil, categories: nil)
      return '' unless enabled?

      scope = AiKnowledgeEntry.active.for_project(project_id)
      scope = scope.where(category: categories) if categories.present?
      entries = scope.order(Arel.sql('project_id IS NULL, hit_count DESC, updated_at DESC')).limit(max_entries).to_a
      return '' if entries.empty?

      lines = []
      used = 0
      entries.each do |entry|
        line = "- [#{entry.category_label}] #{entry.content}"
        break if used + line.length > DEFAULT_MAX_CHARS

        lines << line
        used += line.length
      end

      <<~SECTION

        --- Wissensbasis (verbindlich berücksichtigen) ---
        Die folgenden Regeln, Begriffe und Hinweise stammen aus früheren Korrekturen dieser Redmine-Instanz
        und aus manueller Pflege. Wende sie an, sofern sie auf den vorliegenden Text zutreffen. Sie haben Vorrang
        vor allgemeinen Stilregeln, widersprechen aber nie korrekter Rechtschreibung und Grammatik:
        #{lines.join("\n")}
        --- Ende Wissensbasis ---
      SECTION
    end

    # Hängt den Wissensbasis-Abschnitt an einen System-Prompt an
    def self.augment_prompt(system_prompt, project_id: nil, categories: nil)
      section = prompt_section(project_id: project_id, categories: categories)
      section.blank? ? system_prompt : "#{system_prompt}\n#{section}"
    end

    # Lernt aus einer Korrektur-Version: vergleicht KI-Ausgabe mit finaler Nutzerfassung
    # und legt neue Wissenseinträge an. Liefert die angelegten/aktualisierten Einträge.
    def self.learn_from_version!(version, final_text, user: User.current, client: nil)
      ai_text = version.ai_output_text.presence || version.improved_text
      final_text = final_text.to_s

      return [] if ai_text.blank? || final_text.blank?
      return [] if AiKnowledgeEntry.normalize(ai_text) == AiKnowledgeEntry.normalize(final_text)

      client ||= AiClient.new
      user_message = <<~MSG
        ORIGINAL:
        #{version.original_text.to_s.strip}

        KI-VORSCHLAG:
        #{ai_text.strip}

        FINAL:
        #{final_text.strip}
      MSG

      result = client.complete(LEARNING_SYSTEM_PROMPT, user_message, task: :learning)
      lessons = parse_lessons(result[:text])

      project_id = version.issue&.project_id
      entries = lessons.first(3).map do |lesson|
        AiKnowledgeEntry.learn!(
          category:   lesson['category'],
          content:    lesson['content'],
          reason:     lesson['reason'],
          project_id: project_id,
          issue_id:   version.issue_id,
          user_id:    user&.id
        )
      end.compact

      version.update_columns(learned_at: Time.current)
      Rails.logger.info "AI Knowledge - #{entries.size} Einträge aus Version #{version.version_id} gelernt (Tokens: #{result.dig(:tokens, :total)})"

      { entries: entries, tokens: result[:tokens], model: result[:model] }
    end

    # Toleranter JSON-Parser: extrahiert das erste Array aus der Antwort
    def self.parse_lessons(text)
      raw = text.to_s.strip
      raw = raw.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '')
      start = raw.index('[')
      finish = raw.rindex(']')
      return [] if start.nil? || finish.nil? || finish < start

      data = JSON.parse(raw[start..finish])
      return [] unless data.is_a?(Array)

      data.select { |l| l.is_a?(Hash) && l['content'].present? }.map do |l|
        category = l['category'].to_s.downcase
        category = 'rule' unless AiKnowledgeEntry::CATEGORIES.include?(category)
        { 'category' => category, 'content' => l['content'].to_s[0, 500], 'reason' => l['reason'].to_s[0, 1000] }
      end
    rescue JSON::ParserError => e
      Rails.logger.warn "AI Knowledge - Antwort nicht als JSON lesbar: #{e.message} / #{raw[0, 200]}"
      []
    end
  end
end
