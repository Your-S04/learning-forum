<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { authState, signOut } from './composables/useAuth'
import { useTheme } from './composables/useTheme'
import { supabase } from './lib/supabase'
import NoticeBanner from './components/NoticeBanner.vue'

const route = useRoute()
const router = useRouter()
const { isDark, toggleTheme } = useTheme()
const username = computed(() => authState.profile?.username ?? '')
const isAdmin = computed(() => authState.profile?.role === 'admin')

// 今日访客：记录"我今天来过"（同一人当天只记一次），再统计今天的去重人数
const todayVisitors = ref(0)

// 站内通知：未读数 + 列表
const unreadCount = ref(0)
const notifications = ref([])

async function fetchUnread() {
  if (!authState.session) return
  const { count } = await supabase
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', authState.session.user.id)
    .eq('is_read', false)
  unreadCount.value = count ?? 0
}

async function loadNotifList() {
  if (!authState.session) return
  const { data } = await supabase
    .from('notifications')
    .select('*')
    .eq('user_id', authState.session.user.id)
    .order('created_at', { ascending: false })
    .limit(10)
  notifications.value = data ?? []
}

async function markRead(n) {
  if (!n.is_read) {
    await supabase.from('notifications').update({ is_read: true }).eq('id', n.id)
    fetchUnread()
  }
  if (n.link_problem_id) {
    router.push({ name: 'problem-detail', params: { id: n.link_problem_id } })
  }
}

async function markAllRead() {
  await supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('user_id', authState.session.user.id)
    .eq('is_read', false)
  unreadCount.value = 0
  loadNotifList()
}

async function recordAndCount() {
  if (!authState.session) return
  const today = new Date().toLocaleDateString('en-CA') // 本地时区的 YYYY-MM-DD
  await supabase
    .from('daily_visits')
    .upsert(
      { user_id: authState.session.user.id, visited_on: today },
      { onConflict: 'user_id,visited_on', ignoreDuplicates: true }
    )
  // 登录即打卡：每天自动记一次（重复打卡会撞联合主键，静默忽略）
  const { error: ckErr } = await supabase
    .from('checkins')
    .insert({ user_id: authState.session.user.id })
  if (ckErr && ckErr.code !== '23505') console.warn('打卡失败', ckErr.message)

  const { count } = await supabase
    .from('daily_visits')
    .select('*', { count: 'exact', head: true })
    .eq('visited_on', today)
  todayVisitors.value = count ?? 0
  fetchUnread()
}

onMounted(() => {
  recordAndCount()
  // 每 60 秒刷新未读红点
  setInterval(fetchUnread, 60000)
})
watch(() => authState.session?.user.id, recordAndCount)

async function handleSignOut() {
  await signOut()
  router.push({ name: 'login' })
}
</script>

<template>
  <el-container v-if="route.name !== 'login'" style="min-height: 100vh">
    <el-header
      style="
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-bottom: 1px solid var(--el-border-color);
      "
    >
      <el-menu :default-active="route.path" mode="horizontal" router :ellipsis="false">
        <el-menu-item index="/problems">题目</el-menu-item>
        <el-menu-item index="/board">看板</el-menu-item>
        <el-menu-item index="/leaderboard">排行榜</el-menu-item>
        <el-menu-item v-if="isAdmin" index="/dashboard">管理面板</el-menu-item>
      </el-menu>
      <div style="display: flex; align-items: center; gap: 16px">
        <span class="hide-sm" style="color: var(--el-text-color-secondary); font-size: 13px">
          今日访问 {{ todayVisitors }} 人
        </span>
        <el-popover placement="bottom-end" :width="330" trigger="click" @show="loadNotifList">
          <template #reference>
            <el-badge :value="unreadCount" :hidden="!unreadCount" :max="99">
              <el-button link>
                <el-icon :size="18"><Bell /></el-icon>
              </el-button>
            </el-badge>
          </template>
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px">
            <strong>通知</strong>
            <el-button link size="small" :disabled="!unreadCount" @click="markAllRead">全部已读</el-button>
          </div>
          <div style="max-height: 320px; overflow-y: auto">
            <div
              v-for="n in notifications"
              :key="n.id"
              style="padding: 8px 4px; border-bottom: 1px solid var(--el-border-color-lighter); cursor: pointer"
              @click="markRead(n)"
            >
              <div :style="{ fontSize: '13px', fontWeight: n.is_read ? 400 : 600 }">{{ n.title }}</div>
              <div style="font-size: 11px; color: var(--el-text-color-secondary); margin-top: 2px">
                {{ new Date(n.created_at).toLocaleString('zh-CN') }}
              </div>
            </div>
            <el-empty v-if="!notifications.length" :image-size="60" description="暂无通知" />
          </div>
        </el-popover>
        <el-button link @click="toggleTheme">
          <el-icon><Moon v-if="!isDark" /><Sunny v-else /></el-icon>
        </el-button>
        <el-dropdown>
          <span style="cursor: pointer">
            <el-icon style="vertical-align: -2px"><User /></el-icon>
            {{ username }}
          </span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="router.push({ name: 'profile' })">个人中心</el-dropdown-item>
              <el-dropdown-item divided @click="handleSignOut">退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </el-header>
    <el-main>
      <NoticeBanner />
      <router-view />
    </el-main>
  </el-container>
  <router-view v-else />
</template>
