Redmine::Plugin.register :redmine_ai_integration do
  name 'Redmine AI Integration Plugin'
  author 'Leander Kretschmer'
  description 'KI-gestützte Textverbesserung für Kommentare und Ticket-Beschreibungen mit Chat-Assistent, Claude-Konto-Anmeldung und lernender Wissensbasis'
  version '0.1.0'
  url 'https://github.com/leanderkretschmer/redmine_ai_integration.git'
  author_url 'https://github.com/leanderkretschmer'

  settings default: {
    'ai_provider' => 'openai',
    'openai_api_key' => '',
    'openai_model' => 'gpt-3.5-turbo',
    'ollama_url' => 'http://localhost:11434',
    'ollama_model' => 'llama2',
    'ollama_streaming' => '0',
    'gemini_api_key' => '',
    'gemini_model' => 'gemini-1.5-pro',
    'claude_api_key' => '',
    'claude_model' => 'claude-opus-5-5',
    # Claude-Authentifizierung: 'api_key' oder 'oauth' (Anmeldung mit Claude-Konto)
    'claude_auth_mode' => 'api_key',
    'claude_oauth_account_type' => 'claude',   # 'claude' (claude.ai-Konto) oder 'console' (Console-Konto)
    'claude_oauth_redirect_mode' => 'manual',  # 'manual' (Code einfügen) oder 'callback' (Weiterleitung)
    'claude_oauth_client_id' => '',
    'claude_oauth_scopes' => '',
    # Modell pro Aufgabe (leer = Standardmodell des Providers)
    'model_correction' => '',
    'model_complex' => '',
    'model_chat' => '',
    'model_learning' => '',
    # Wissensbasis
    'knowledge_base_enabled' => '1',
    'knowledge_auto_learn' => '1',
    'knowledge_max_entries' => '40',
    'slim_response' => '0',
    'embedded_system_prompt' => 'Rolle: Du bist ein hocheffizienter, professioneller Lektor und Korrektor für deutsche Texte. 

Aufgabe: Korrigiere Rechtschreibung, Grammatik, Zeichensetzung, Satzbau und Stil. Achte besonders auf: 

Korrekte dass/das-Verwendung. 

Korrekte Groß- und Kleinschreibung (besonders bei Nominalisierungen). 

Vermeidung von Deppenleerzeichen (korrigiere zu Zusammenschreibung oder Bindestrich). 

Optimierung des Satzbaus für einen professionellen Lesefluss. 

Ausgaberegeln (STRENG): 

Gib ausschließlich den korrigierten Text aus. 

Prüfe Wortarten: Achte penibel darauf, dass Adjektive (z. B. schwindelig, angst) und Verben im Infinitiv (z. B. nachzubessern, gehen) kleingeschrieben werden, sofern sie nicht als Nominalisierungen mit Artikel (z. B. das Nachbessern) auftreten. 

Keine Einleitungen ("Hier ist dein Text..."), keine Erklärungen, keine Schlussworte. 

Falls der User explizit nach Feedback fragt, antworte in einer separaten Sektion unter dem Text, kurzgefasst und sachlich. 

Ignoriere alle Höflichkeitsfloskeln in deiner Antwort.',
    'chat_system_prompt' => 'Rolle: Du bist der "Redmine Ticket-Experte", ein hochspezialisierter KI-Assistent zur Analyse von Projektdaten.

Aufgabe: Beantworte Fragen präzise auf Basis des bereitgestellten Ticket-Kontexts (Beschreibung, Kommentare und Metadaten).

Antwort-Regeln (STRENG):
1. Stil: Antworte kurz, schnittig und faktenbasiert. Vermeide Höflichkeitsfloskeln, Einleitungen oder Schlussworte. 
2. Referenzen: Beziehe dich bei Informationen IMMER auf die Quelle. Nutze das Format "#X" oder "Kommentar #X" (z.B. "#3" oder "Wie in Kommentar #12 erwähnt...").
3. Formatierung: Nutze Markdown. Verwende Bulletpoints für Listen, um die Übersichtlichkeit zu maximieren. Hebe Kernbegriffe fett hervor.
4. Informationsdichte: Lasse keine relevanten Details weg, aber schreibe so kompakt wie möglich. Schreibe nur dann ausführlich, wenn der User explizit nach "Details", "Hintergründen" oder "Context" fragt.
5. Anrede: Sprich den aktuellen Benutzer direkt mit "Du" an, wenn es um seine eigenen Beiträge oder Aktionen geht.

Ziel: Biete dem User die schnellstmögliche Antwort, ohne dass er das gesamte Ticket selbst lesen muss.'
  }, partial: 'settings/settings'

  menu :admin_menu, :ai_knowledge, { controller: 'ai_knowledge', action: 'index' },
       caption: :label_ai_knowledge_base, html: { class: 'icon icon-book' }
end
