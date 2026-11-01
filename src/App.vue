<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { authState, signOut } from './composables/useAuth'
import { supabase } from './lib/supabase'

const route = useRoute()
const router = useRouter()
const username = computed(() => authState.profile?.username ?? '')
const isAdmin = computed(() => authState.profile?.role === 'admin')

// 今日访客：记录"我今天来过"（同一人当天只记一次），再统计今天的去重人数
const todayVisitors = ref(0)

async function recordAndCount() {
  if (!authState.session) return
  const today = new Date().toLocaleDateString('en-CA') // 本地时区的 YYYY-MM-DD
  await supabase
    .from('daily_visits')
    .upsert(
      { user_id: authState.session.user.id, visited_on: today },
      { onConflict: 'user_id,visited_on', ignoreDuplicates: true }
    )
  const { count } = await supabase
    .from('daily_visits')
    .select('*', { count: 'exact', head: true })
    .eq('visited_on', today)
  todayVisitors.value = count ?? 0
}

onMounted(recordAndCount)
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
        <span style="color: var(--el-text-color-secondary); font-size: 13px">
          今日访问 {{ todayVisitors }} 人
        </span>
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
      <router-view />
    </el-main>
  </el-container>
  <router-view v-else />
</template>
