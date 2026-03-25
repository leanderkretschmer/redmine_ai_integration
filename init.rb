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
    'embedded_system_prompt' => 'Du bist ein professioneller Textkorrektor.',
    'system_prompt' => 'Verbessere den folgenden Text, korrigiere Rechtschreib- und Grammatikfehler, verbessere die Struktur und mache ihn professioneller, während der ursprüngliche Sinn und Inhalt erhalten bleibt. Antworte nur mit dem verbesserten Text, ohne zusätzliche Erklärungen.'
  }, partial: 'settings/settings'
end