post 'ai_rewrite/rewrite', to: 'ai_rewrite#rewrite'
post 'ai_rewrite/rewrite_stream', to: 'ai_rewrite#rewrite_stream'
post 'ai_rewrite/save_version', to: 'ai_rewrite#save_version'
get 'ai_rewrite/get_version', to: 'ai_rewrite#get_version'
delete 'ai_rewrite/clear_versions', to: 'ai_rewrite#clear_versions'
post 'ai_rewrite/test_connection', to: 'ai_rewrite#test_connection'
get 'ai_rewrite/requests', to: 'ai_rewrite#requests'
get 'ai_rewrite/check_versions', to: 'ai_rewrite#check_versions'

