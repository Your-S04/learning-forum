<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { authState, signOut } from './composables/useAuth'

const route = useRoute()
const router = useRouter()
const username = computed(() => authState.profile?.username ?? '')

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
      </el-menu>
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
    </el-header>
    <el-main>
      <router-view />
    </el-main>
  </el-container>
  <router-view v-else />
</template>
