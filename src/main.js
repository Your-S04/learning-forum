import { createApp } from 'vue'
import 'element-plus/theme-chalk/dark/css-vars.css'

import './style.css'
import App from './App.vue'
import router from './router'
import { initAuth } from './composables/useAuth'

const app = createApp(App)

app.use(router)

// 启动时恢复登录状态（Supabase 会自动从 localStorage 读取会话）
initAuth()

app.mount('#app')
