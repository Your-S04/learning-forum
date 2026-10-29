import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  console.error(
    '[you-forum] 缺少 Supabase 配置：请复制 .env.example 为 .env.local，' +
      '并填入 VITE_SUPABASE_URL 和 VITE_SUPABASE_ANON_KEY 后重启开发服务器。'
  )
}

// 占位配置让项目在无密钥时也能启动（页面会报错，但方便先把界面搭起来）
export const supabase = createClient(
  url || 'https://placeholder.supabase.co',
  anonKey || 'placeholder-anon-key'
)
