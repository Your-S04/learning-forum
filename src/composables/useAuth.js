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
    .select('username, role')
    .eq('id', session.user.id)
    .single()
  return data
}

export function initAuth() {
  let requestId = 0
  const {
    data: { subscription },
  } = supabase.auth.onAuthStateChange((_event, session) => {
    // 用 setTimeout 避免在回调里同步调用 supabase 查询造成死锁
    setTimeout(async () => {
      const previousUserId = authState.session?.user.id
      authState.session = session
      if (session?.user.id === previousUserId && requestId !== 0) return

      const id = ++requestId
      authState.profile = null
      const profile = await loadProfile(session)
      if (id !== requestId) return
      authState.profile = profile
      authState.ready = true
    }, 0)
  })

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
