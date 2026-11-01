<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabase'

const rows = ref([])
const loading = ref(true)

onMounted(async () => {
  // leaderboard 是数据库里的视图，当普通表查即可
  const { data } = await supabase.from('leaderboard').select('*')
  rows.value = data ?? []
  loading.value = false
})
</script>

<template>
  <el-card v-loading="loading">
    <h2 style="margin-top: 0">贡献排行榜</h2>
    <p style="color: var(--el-text-color-secondary); margin-top: 0">
      发布一道题目 +3 分，回复一次讨论 +1 分，收到一个点赞 +2 分，回答被置顶 +2 分
    </p>
    <el-table :data="rows">
      <el-table-column type="index" label="排名" width="80" />
      <el-table-column prop="username" label="用户名" />
      <el-table-column prop="score" label="贡献分" width="120" />
    </el-table>
  </el-card>
</template>
