module RedmineAiIntegration
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, partial: 'hooks/ai_integration_assets'
  end
end

