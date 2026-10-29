<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const problems = ref([])
const loading = ref(true)

onMounted(async () => {
  const { data } = await supabase
    .from('problems')
    .select('id, title, created_at, profiles(username)')
    .order('created_at', { ascending: false })
  problems.value = data ?? []
  loading.value = false
})
</script>

<template>
  <el-card>
    <div style="display: flex; justify-content: space-between; align-items: center">
      <h2 style="margin: 0">题目</h2>
      <el-button type="primary" @click="router.push({ name: 'problem-new' })">
        发布题目
      </el-button>
    </div>
    <el-table
      :data="problems"
      v-loading="loading"
      style="margin-top: 16px; cursor: pointer"
      @row-click="(row) => router.push({ name: 'problem-detail', params: { id: row.id } })"
    >
      <el-table-column prop="title" label="标题" />
      <el-table-column label="作者" width="140">
        <template #default="{ row }">{{ row.profiles?.username }}</template>
      </el-table-column>
      <el-table-column label="发布时间" width="200">
        <template #default="{ row }">
          {{ new Date(row.created_at).toLocaleString('zh-CN') }}
        </template>
      </el-table-column>
      <template #empty>还没有题目，点击右上角发布第一道题吧</template>
    </el-table>
  </el-card>
</template>
