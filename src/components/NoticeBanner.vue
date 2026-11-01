<script setup>
// 顶部公告横幅：管理员公告 + 48 小时内截止的作业/考试
// 收起状态存 localStorage（按内容 id 记），同一批收起后不再打扰
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../lib/supabase'

const notices = ref([]) // 管理员公告
const dueSoon = ref([]) // 即将截止的任务
const dismissed = ref(JSON.parse(localStorage.getItem('dismissed-notices') ?? '[]'))
const loading = ref(true)

const visible = computed(() => [
  ...notices.value.filter((n) => !dismissed.value.includes(`n${n.id}`)),
  ...dueSoon.value.filter((d) => !dismissed.value.includes(`d${d.id}`)),
])

function dismissAll() {
  dismissed.value = [
    ...new Set([...dismissed.value, ...visible.value.map((i) => i.key)]),
  ]
  localStorage.setItem('dismissed-notices', JSON.stringify(dismissed.value))
}

function dismissOne(key) {
  dismissed.value = [...new Set([...dismissed.value, key])]
  localStorage.setItem('dismissed-notices', JSON.stringify(dismissed.value))
}

function dueText(iso) {
  const hours = Math.max(0, (new Date(iso) - new Date()) / 3600000)
  if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} 分钟后截止`
  if (hours < 24) return `${Math.round(hours)} 小时后截止`
  return `${Math.round(hours / 24)} 天后截止`
}

onMounted(async () => {
  const now = new Date().toISOString()
  const in48h = new Date(Date.now() + 48 * 3600 * 1000).toISOString()
  const [noticeRes, dueRes] = await Promise.all([
    supabase
      .from('board_items')
      .select('id, title, note, created_at')
      .eq('type', 'notice')
      .order('created_at', { ascending: false })
      .limit(3),
    supabase
      .from('board_items')
      .select('id, type, title, course, end_at')
      .in('type', ['homework', 'exam'])
      .gte('end_at', now)
      .lte('end_at', in48h)
      .order('end_at'),
  ])
  notices.value = (noticeRes.data ?? []).map((n) => ({ ...n, key: `n${n.id}` }))
  dueSoon.value = (dueRes.data ?? []).map((d) => ({ ...d, key: `d${d.id}` }))
  loading.value = false
})
</script>

<template>
  <div v-if="visible.length" class="notice-banner">
    <el-alert type="warning" :closable="false">
      <template #title>
        <span style="display: flex; justify-content: space-between; width: 100%; align-items: center">
          <span>📢 有 {{ visible.length }} 条公告提醒</span>
          <el-button link size="small" @click="dismissAll">全部收起</el-button>
        </span>
      </template>
      <div v-for="i in visible" :key="i.key" style="display: flex; justify-content: space-between; gap: 8px; padding: 2px 0">
        <span v-if="i.end_at">
          <el-tag size="small" :type="i.type === 'exam' ? 'danger' : 'primary'" style="margin-right: 6px">
            {{ i.type === 'exam' ? '考试' : '作业' }}
          </el-tag>
          <strong>{{ i.title }}</strong>
          <span v-if="i.course">（{{ i.course }}）</span>
          —— {{ dueText(i.end_at) }}
        </span>
        <span v-else>
          <el-tag size="small" type="warning" style="margin-right: 6px">公告</el-tag>
          <strong>{{ i.title }}</strong>
          <span v-if="i.note" style="white-space: pre-wrap"> —— {{ i.note.slice(0, 120) }}{{ i.note.length > 120 ? '…' : '' }}</span>
        </span>
        <el-button link size="small" @click="dismissOne(i.key)">收起</el-button>
      </div>
    </el-alert>
  </div>
</template>
