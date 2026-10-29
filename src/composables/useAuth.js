import { reactive } from 'vue'
import { supabase } from '../lib/supabase'

// 全局唯一的登录状态：任何地方 useAuth() 拿到的是同一个对象
export const authState = reactive({
  session: null,
  profile: null,
  ready: false,
})

async function loadProfile(session) {
  if (!session) return null
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', session.user.id)
    .single()
  return data
}

export async function initAuth() {
  const {
    data: { subscription },
  } = await supabase.auth.onAuthStateChange((_event, session) => {
    // 用 setTimeout 避免在回调里同步调用 supabase 查询造成死锁
    setTimeout(async () => {
      authState.session = session
      authState.profile = await loadProfile(session)
    }, 0)
  })

  const {
    data: { session },
  } = await supabase.auth.getSession()
  authState.session = session
  authState.profile = await loadProfile(session)
  authState.ready = true

  return subscription
}

// 用户名（学号）登录：Supabase 的账号是邮箱，这里自动补全域名
export async function signIn(username, password) {
  const email = username.includes('@')
    ? username
    : `${username}@youforum.local`
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
}

export async function signOut() {
  await supabase.auth.signOut()
}

export async function changePassword(newPassword) {
  const { error } = await supabase.auth.updateUser({ password: newPassword })
  if (error) throw error
}
