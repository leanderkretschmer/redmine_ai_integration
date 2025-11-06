# Redmine AI Rewrite Plugin

Ein Redmine 6 Plugin, das KI-gestützte Textverbesserung für Kommentare und Ticket-Beschreibungen bietet.

## Funktionen

- **Rewrite-Button**: Fügt einen Button zu Textfeldern hinzu, der den Text mit KI verbessert
- **Mehrere KI-Provider**: Unterstützt OpenAI, Ollama (selbstgehostet), Google Gemini und Anthropic Claude
- **Versionsverwaltung**: Mehrere Rewrites ohne Speichern - Schritt für Schritt vor/zurück navigieren
- **Rückgängig-Funktion**: Originaltext wiederherstellen
- **Lade-Animation**: Visuelles Feedback während der Verarbeitung
- **Anpassbarer System-Prompt**: Definiere, wie der Text verbessert werden soll

## Installation

1. Kopiere das Plugin-Verzeichnis nach `redmine/plugins/redmine_ai_rewrite`
2. Starte Redmine neu oder führe `bundle exec rake redmine:plugins:migrate RAILS_ENV=production` aus
3. Gehe zu Administration → Plugins → AI Rewrite Einstellungen
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
- API Key von https://console.anthropic.com/
- Standard-Modell: claude-3-sonnet-20240229

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
5. Nutze die Navigations-Buttons (◀ ▶) um zwischen Versionen zu wechseln
6. Nutze "Rückgängig" um zum Originaltext zurückzukehren
7. Speichere den Kommentar oder das Ticket

## Versionsverwaltung

- Jeder Rewrite erstellt eine neue Version
- Alle Versionen bleiben erhalten, bis der Kommentar/Ticket gespeichert wird
- Navigation zwischen Versionen mit ◀ (vorherige) und ▶ (nächste)
- Originaltext kann jederzeit wiederhergestellt werden

## Technische Details

- Versionsdaten werden temporär in `tmp/redmine_ai_rewrite/` gespeichert
- Session-basierte Versionsverwaltung pro Textfeld
- Automatische Bereinigung beim Speichern

## Lizenz

Dieses Plugin ist unter der MIT-Lizenz lizenziert.

