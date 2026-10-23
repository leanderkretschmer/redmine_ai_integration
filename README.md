# Redmine AI Integration Plugin

Ein Redmine 6 Plugin, das KI-gestützte Textverbesserung für Kommentare und Ticket-Beschreibungen bietet.

## Funktionen

- **Rewrite-Button**: Fügt einen Button zu Textfeldern hinzu, der den Text mit KI verbessert
- **Mehrere KI-Provider**: Unterstützt OpenAI, Ollama (selbstgehostet), Google Gemini und Anthropic Claude
- **Versionsverwaltung**: Mehrere Rewrites ohne Speichern - Schritt für Schritt vor/zurück navigieren
- **Rückgängig-Funktion**: Originaltext wiederherstellen
- **Lade-Animation**: Visuelles Feedback während der Verarbeitung
- **Anpassbarer System-Prompt**: Definiere, wie der Text verbessert werden soll
- **Claude-Konto-Anmeldung**: Claude wahlweise per API-Key oder per OAuth-Login mit einem Claude-Konto nutzen (ohne eigenen Schlüssel)
- **Modell pro Aufgabe**: Eigenes Modell für Korrektur, Erweitern, Chat und Wissens-Extraktion
- **Lernende Wissensbasis**: Regeln, Terminologie und Stilvorgaben, die bei jeder Anfrage mitgegeben werden; lernt automatisch, wenn Nutzer eine KI-Korrektur nachbessern

## Installation

1. Kopiere das Plugin-Verzeichnis nach `redmine/plugins/redmine_ai_integration`
2. Starte Redmine neu oder führe `bundle exec rake redmine:plugins:migrate RAILS_ENV=production` aus
3. Gehe zu Administration → Plugins → Redmine AI Integration Plugin → Configuration
4. Konfiguriere deinen bevorzugten KI-Provider und API-Keys

## Konfiguration

### OpenAI
- API Key von https://platform.openai.com/
- Standard-Modell: gpt-3.5-turbo

### Ollama (selbstgehostet)
- Standard-URL: http://localhost:11434
- Verfügbare Modelle: llama2, mistral, codellama, etc.

### Google Gemini
- API Key von https://makersuite.google.com/app/apikey
- Standard-Modell: gemini-pro

### Anthropic Claude
- **API-Key**: von https://platform.claude.com/settings/keys
- **Claude-Konto (OAuth)**: In den Plugin-Einstellungen „Mit Claude-Konto anmelden“ wählen → „Mit Claude anmelden“ → im Anmeldefenster bestätigen → angezeigten Code (`code#state`) einfügen → „Code einlösen“. Tokens liegen in der Tabelle `ai_oauth_tokens` und werden automatisch erneuert. Die Anmeldung mit einem Abo-Konto unterliegt den Nutzungsbedingungen von Anthropic.
- Standard-Modell: claude-opus-5-5 (Alternativen: claude-sonnet-5-5, claude-haiku-5-5)
- Für Claude-Modelle ab 4.6 wird `output_config.effort` gesetzt (Korrektur/Erweitern: low, Chat/Lernen: medium)

## Modell pro Aufgabe

Unter „Modell pro Aufgabe“ kann je Aufgabe (Korrektur, Erweitern, Chat, Wissens-Extraktion) ein Modell des gewählten Providers hinterlegt werden. Leer = Standardmodell des Providers. „Modelle laden“ holt die Modellliste vom Provider.

## Wissensbasis

- Verwaltung: Administration → KI-Wissensbasis (`/ai_knowledge`)
- Einträge haben Kategorie (Regel, Terminologie, Stil, Fakt), optional ein Projekt (sonst global), Quelle (manuell/gelernt) und einen Treffer-Zähler.
- Aktive Einträge werden als Abschnitt „Wissensbasis“ an den System-Prompt von Korrektur, Erweitern und Chat angehängt (Limit über „Max. Einträge im Prompt“).
- **Lernen aus Fehlern**: Nach einer KI-Korrektur wird die unveränderte KI-Ausgabe in `ai_text_versions.ai_output_text` gespeichert. Ändert der Nutzer den Text, erscheint „Aus Änderung lernen“; bei aktiviertem Auto-Lernen passiert das beim Absenden des Formulars automatisch. Das Modell (Aufgabe „Wissens-Extraktion“) vergleicht Original, KI-Vorschlag und finale Fassung und legt bis zu drei verallgemeinerbare Erkenntnisse als „gelernt/ungeprüft“ ab. Identische Erkenntnisse erhöhen nur den Treffer-Zähler.
- Gelernte Einträge sind sofort aktiv und sollten in der Verwaltung geprüft werden (Prüfen, Deaktivieren, Löschen; „Ungeprüfte gelernte Einträge löschen“).

## System-Prompt

Der System-Prompt definiert, wie der Text verbessert werden soll. Standard:

```
Du bist ein professioneller Textkorrektor. Verbessere den folgenden Text, korrigiere Rechtschreib- und Grammatikfehler, verbessere die Struktur und mache ihn professioneller, während der ursprüngliche Sinn und Inhalt erhalten bleibt. Antworte nur mit dem verbesserten Text, ohne zusätzliche Erklärungen.
```

## Verwendung

1. Öffne ein Ticket oder Kommentarfeld
2. Schreibe oder füge Text ein
3. Klicke auf den "Rewrite"-Button
4. Warte auf die Verbesserung
5. Nutze die Navigations-Buttons (< >) um zwischen Versionen zu wechseln
6. Nutze "Rückgängig" um zum Originaltext zurückzukehren
7. Speichere den Kommentar oder das Ticket

## Versionsverwaltung

- Jeder Rewrite erstellt eine neue Version
- Alle Versionen bleiben erhalten, bis der Kommentar/Ticket gespeichert wird
- Navigation zwischen Versionen mit < (vorherige) und > (nächste)
- Originaltext kann jederzeit wiederhergestellt werden

## Technische Details

- Versionen liegen in `ai_text_versions`, Chat-Verlauf in `ai_chat_messages`, Wissensbasis in `ai_knowledge_entries`, OAuth-Tokens in `ai_oauth_tokens`
- Session-basierte Versionsverwaltung pro Textfeld
- Alle Provider-Aufrufe laufen über `RedmineAiIntegration::AiClient` (`lib/redmine_ai_integration/ai_client.rb`); OAuth in `claude_oauth.rb`, Wissensbasis in `knowledge_base.rb`
- Der Endpunkt `/ai_rewrite/settings` liefert nur unkritische Einstellungen (keine Schlüssel/Tokens)
- Nach dem Update: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production` (Migrationen 005–007)

## Lizenz

Dieses Plugin ist unter der MIT-Lizenz lizenziert.

