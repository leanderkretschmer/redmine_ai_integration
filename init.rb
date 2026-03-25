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
    'embedded_system_prompt' => 'Du bist ein professioneller Textkorrektor. Korrigiere Rechtschreibung, Grammatik und Satzstellung. Verbessere die Struktur und mache den Text professioneller.',
    'system_prompt' => 'Analysiere den bereitgestellten Text. Falls der Text am Anfang eine klare Anweisung enthält, führe diese Anweisung für den restlichen Teil des Textes aus. Falls keine Anweisung vorhanden ist, korrigiere den Text professionell. Antworte immer ausschließlich mit dem bearbeiteten Text, ohne jegliche Erklärungen, Begrüßungen oder einleitende Sätze.'
  }, partial: 'settings/settings'
end