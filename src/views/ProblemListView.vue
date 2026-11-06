<script setup>
import { ElAlert, ElButton, ElCard, ElOption, ElRadioButton, ElRadioGroup, ElRate, ElSelect, ElTable, ElTableColumn, ElTag, ElLoadingDirective as vLoading } from 'element-plus'
import 'element-plus/es/components/alert/style/css'
import 'element-plus/es/components/button/style/css'
import 'element-plus/es/components/card/style/css'
import 'element-plus/es/components/option/style/css'
import 'element-plus/es/components/radio-button/style/css'
import 'element-plus/es/components/radio-group/style/css'
import 'element-plus/es/components/rate/style/css'
import 'element-plus/es/components/select/style/css'
import 'element-plus/es/components/table/style/css'
import 'element-plus/es/components/table-column/style/css'
import 'element-plus/es/components/tag/style/css'
import 'element-plus/es/components/loading/style/css'
import { ref, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

const router = useRouter()
const problems = ref([])
const loading = ref(true)
const loadError = ref(false)
const pageSize = 30
const page = ref(1)
const hasNextPage = ref(false)
let requestId = 0

// 筛选与排序
const tags = ref([])
const tagFilter = ref(null) // 选中分类的 id
const sortBy = ref('time') // time 最新发布 | difficulty 难度高→低

async function load() {
  const id = ++requestId
  loading.value = true
  loadError.value = false
  const offset = (page.value - 1) * pageSize
  let query = supabase
    .from('problems')
    .select('id, title, created_at, difficulty, profiles!problems_user_id_fkey(username), problem_likes(count), tags(name)')
  if (tagFilter.value) query = query.eq('tag_id', tagFilter.value)
  query =
    sortBy.value === 'time'
      ? query.order('created_at', { ascending: false })
      : // 难度排序：星多的在前，未设置难度的排在最后
        query.order('difficulty', { ascending: false, nullsFirst: false })
  const { data, error } = await query
    .order('id', { ascending: false })
    .range(offset, offset + pageSize)
  if (id !== requestId) return
  loadError.value = Boolean(error)
  hasNextPage.value = (data?.length ?? 0) > pageSize
  problems.value = data?.slice(0, pageSize) ?? []
  loading.value = false
}

async function loadTags() {
  const { data: tagData } = await supabase.from('tags').select('id, name').order('name')
  tags.value = tagData ?? []
}

onMounted(() => {
  load()
  loadTags()
})

watch([tagFilter, sortBy], () => {
  if (page.value === 1) load()
  else page.value = 1
})
watch(page, load)
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
    <el-alert v-if="loadError" type="error" :closable="false" style="margin-top: 16px">
      题目加载失败。<el-button link type="primary" @click="load">重试</el-button>
    </el-alert>
    <el-table
      v-else
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
    <div v-if="page > 1 || hasNextPage" style="display: flex; justify-content: center; align-items: center; gap: 12px; margin-top: 16px">
      <el-button size="small" :disabled="loading || page === 1" @click="page--">上一页</el-button>
      <span>第 {{ page }} 页</span>
      <el-button size="small" :disabled="loading || !hasNextPage" @click="page++">下一页</el-button>
    </div>
  </el-card>
</template>
