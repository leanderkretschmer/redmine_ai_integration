module RedmineAiIntegration
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, partial: 'hooks/ai_integration_assets'
    render_on :view_issues_show_sidebar_bottom, partial: 'hooks/ai_chat_sidebar'
  end
end