import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import 'element-plus/dist/index.css'
import * as ElementPlusIconsVue from '@element-plus/icons-vue'

import App from './App.vue'
import router from './router'
import { initAuth } from './composables/useAuth'

const app = createApp(App)

app.use(ElementPlus, { locale: zhCn })
for (const [name, component] of Object.entries(ElementPlusIconsVue)) {
  app.component(name, component)
}
app.use(router)

// 启动时恢复登录状态（Supabase 会自动从 localStorage 读取会话）
initAuth()

app.mount('#app')
