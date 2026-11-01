<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const problems = ref([])
const loading = ref(true)

// 筛选与排序
const tags = ref([])
const tagFilter = ref(null) // 选中分类的 id
const sortBy = ref('time') // time 最新发布 | difficulty 难度高→低

async function load() {
  loading.value = true
  let query = supabase
    .from('problems')
    .select('id, title, created_at, difficulty, profiles!problems_user_id_fkey(username), problem_likes(count), tags(name)')
  if (tagFilter.value) query = query.eq('tag_id', tagFilter.value)
  query =
    sortBy.value === 'time'
      ? query.order('created_at', { ascending: false })
      : // 难度排序：星多的在前，未设置难度的排在最后
        query.order('difficulty', { ascending: false, nullsFirst: false })
  const { data } = await query
  problems.value = data ?? []
  loading.value = false
}

onMounted(async () => {
  const { data: tagData } = await supabase.from('tags').select('id, name').order('name')
  tags.value = tagData ?? []
  load()
})

watch([tagFilter, sortBy], load)
</script>

<template>
  <el-card v-loading="loading">
    <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px">
      <h2 style="margin: 0">题目</h2>
      <div style="display: flex; gap: 8px; align-items: center">
        <el-select v-model="tagFilter" placeholder="全部分类" clearable style="width: 150px">
          <el-option v-for="t in tags" :key="t.id" :label="t.name" :value="t.id" />
        </el-select>
        <el-radio-group v-model="sortBy" size="default">
          <el-radio-button value="time">时间</el-radio-button>
          <el-radio-button value="difficulty">难度</el-radio-button>
        </el-radio-group>
        <el-button type="primary" @click="router.push({ name: 'problem-new' })">
          发布题目
        </el-button>
      </div>
    </div>
    <el-table
      :data="problems"
      style="margin-top: 16px; cursor: pointer"
      @row-click="(row) => router.push({ name: 'problem-detail', params: { id: row.id } })"
    >
      <el-table-column prop="title" label="标题" />
      <el-table-column label="分类" width="110">
        <template #default="{ row }">
          <el-tag v-if="row.tags?.name" size="small" type="info">{{ row.tags.name }}</el-tag>
          <span v-else style="color: var(--el-text-color-secondary)">-</span>
        </template>
      </el-table-column>
      <el-table-column label="难度" width="140">
        <template #default="{ row }">
          <el-rate v-if="row.difficulty" :model-value="row.difficulty" disabled size="small" />
          <span v-else style="color: var(--el-text-color-secondary)">-</span>
        </template>
      </el-table-column>
      <el-table-column label="Like" width="80" align="center">
        <template #default="{ row }">{{ row.problem_likes?.[0]?.count ?? 0 }}</template>
      </el-table-column>
      <el-table-column label="作者" width="140" class-name="hide-sm" label-class-name="hide-sm">
        <template #default="{ row }">{{ row.profiles?.username }}</template>
      </el-table-column>
      <el-table-column label="发布时间" width="200" class-name="hide-sm" label-class-name="hide-sm">
        <template #default="{ row }">
          {{ new Date(row.created_at).toLocaleString('zh-CN') }}
        </template>
      </el-table-column>
      <template #empty>没有符合条件的题目</template>
    </el-table>
  </el-card>
</template>
