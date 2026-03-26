Redmine::Plugin.register :redmine_ai_integration do
  name 'Redmine AI Integration Plugin'
  author 'Leander Kretschmer'
  description 'KI-gestützte Textverbesserung für Kommentare und Ticket-Beschreibungen mit Chat-Assistent'
  version '0.0.28'
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
    'claude_model' => 'claude-3-sonnet-20240229',
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
    'chat_system_prompt' => 'Du bist ein hilfreicher Assistent für Redmine-Tickets. Analysiere das Ticket und beantworte Fragen basierend auf den vorhandenen Informationen. Fasse dich immer kurz und nenne nur die wichtigsten Eckpunkte, es sei denn, der Benutzer bittet ausdrücklich um mehr Details.'
  }, partial: 'settings/settings'
end