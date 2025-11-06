Redmine::Plugin.register :redmine_ai_integration do
  name 'Redmine AI Integration Plugin'
  author 'Leander Kretschmer'
  description 'KI-gestützte Textverbesserung für Kommentare und Ticket-Beschreibungen'
  version '0.0.5'
  url 'https://github.com/leanderkretschmer/redmine_ai_integration.git'
  author_url 'https://github.com/leanderkretschmer'

  settings default: {
    'ai_provider' => 'openai',
    'openai_api_key' => '',
    'openai_model' => 'gpt-3.5-turbo',
    'ollama_url' => 'http://localhost:11434',
    'ollama_model' => 'llama2',
    'gemini_api_key' => '',
    'gemini_model' => 'gemini-pro',
    'claude_api_key' => '',
    'claude_model' => 'claude-3-sonnet-20240229',
    'system_prompt' => 'Du bist ein professioneller Textkorrektor. Verbessere den folgenden Text, korrigiere Rechtschreib- und Grammatikfehler, verbessere die Struktur und mache ihn professioneller, während der ursprüngliche Sinn und Inhalt erhalten bleibt. Antworte nur mit dem verbesserten Text, ohne zusätzliche Erklärungen.'
  }, partial: 'settings/settings'
end

# Assets laden
Rails.application.config.to_prepare do
  Redmine::Plugin.find(:redmine_ai_integration).assets.each do |asset|
    Rails.application.config.assets.precompile << asset
  end
end

# Routes registrieren
Rails.application.config.to_prepare do
  RedmineApp::Application.routes.append do
    post 'ai_rewrite/rewrite', to: 'ai_rewrite#rewrite'
    post 'ai_rewrite/save_version', to: 'ai_rewrite#save_version'
    get 'ai_rewrite/get_version', to: 'ai_rewrite#get_version'
    delete 'ai_rewrite/clear_versions', to: 'ai_rewrite#clear_versions'
    post 'ai_rewrite/test_connection', to: 'ai_rewrite#test_connection'
  end
end

