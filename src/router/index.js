import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/problems' },
    { path: '/login', name: 'login', component: () => import('../views/LoginView.vue') },
    { path: '/problems', name: 'problems', component: () => import('../views/ProblemListView.vue') },
    { path: '/problems/new', name: 'problem-new', component: () => import('../views/ProblemEditView.vue') },
    { path: '/problems/:id(\\d+)', name: 'problem-detail', component: () => import('../views/ProblemDetailView.vue') },
    { path: '/problems/:id(\\d+)/edit', name: 'problem-edit', component: () => import('../views/ProblemEditView.vue') },
    { path: '/board', name: 'board', component: () => import('../views/BoardView.vue') },
    { path: '/leaderboard', name: 'leaderboard', component: () => import('../views/LeaderboardView.vue') },
    { path: '/profile', name: 'profile', component: () => import('../views/ProfileView.vue') },
  ],
})

// 登录守卫：未登录只能看登录页，已登录访问登录页则跳回题目列表
router.beforeEach(async (to) => {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  if (!session && to.name !== 'login') return { name: 'login' }
  if (session && to.name === 'login') return { name: 'problems' }
})

export default router
