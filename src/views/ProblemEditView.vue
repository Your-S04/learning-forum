<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { MdEditor } from 'md-editor-v3'
import 'md-editor-v3/lib/style.css'
import { supabase } from '../lib/supabase'
import { authState } from '../composables/useAuth'

const route = useRoute()
const router = useRouter()

// 同一个组件同时服务"发布新题"和"编辑旧题"两个路由，靠路由里有没有 id 区分
const problemId = route.params.id ? Number(route.params.id) : null
const pageTitle = problemId ? '编辑题目' : '发布题目'

const title = ref('')
const content = ref('')
const tagId = ref(null) // 选中已有分类时为数字；管理员新建分类时为字符串
const difficulty = ref(0) // 0 = 未设置；1~5 为难度星
const tags = ref([])
const loading = ref(false)
const canSubmit = computed(() => title.value.trim() && content.value.trim())
const isAdmin = computed(() => authState.profile?.role === 'admin')

onMounted(async () => {
  const { data: tagData } = await supabase.from('tags').select('id, name').order('name')
  tags.value = tagData ?? []
  if (!problemId) return
  const { data } = await supabase
    .from('problems')
    .select('title, content, tag_id, difficulty')
    .eq('id', problemId)
    .single()
  if (data) {
    title.value = data.title
    content.value = data.content
    tagId.value = data.tag_id
    difficulty.value = data.difficulty ?? 0
  }
})

// 选中的是新建分类名（字符串）时先入库拿到 id；重名则直接用已有 id
async function ensureTagId(value) {
  if (typeof value !== 'string') return value
  const name = value.trim()
  if (!name) return null
  const { data: created } = await supabase.from('tags').insert({ name }).select('id').single()
  if (created) {
    tags.value.push({ id: created.id, name })
    return created.id
  }
  const { data: exist } = await supabase.from('tags').select('id').eq('name', name).single()
  return exist?.id ?? null
}

// md-editor-v3 的图片上传：存入 Supabase Storage 的 images 桶，拿回公网 URL
async function onUploadImg(files, callback) {
  const urls = []
  for (const file of files) {
    const path = `${Date.now()}-${file.name}`
    const { error } = await supabase.storage.from('images').upload(path, file)
    if (error) {
      ElMessage.error(`图片上传失败：${error.message}`)
      continue
    }
    const { data } = supabase.storage.from('images').getPublicUrl(path)
    urls.push(data.publicUrl)
  }
  callback(urls)
}

async function submit() {
  loading.value = true
  try {
    const finalTagId = await ensureTagId(tagId.value)
    const payload = {
      title: title.value.trim(),
      content: content.value,
      tag_id: finalTagId,
      difficulty: difficulty.value || null,
    }
    if (problemId) {
      const { error } = await supabase.from('problems').update(payload).eq('id', problemId)
      if (error) throw error
    } else {
      const { error } = await supabase.from('problems').insert({
        ...payload,
        user_id: authState.session.user.id,
      })
      if (error) throw error
    }
    router.push({ name: 'problems' })
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <el-card>
    <h2 style="margin-top: 0">{{ pageTitle }}</h2>
    <el-input
      v-model="title"
      placeholder="题目标题"
      style="margin-bottom: 16px"
      maxlength="100"
      show-word-limit
    />
    <div style="display: flex; gap: 24px; align-items: center; margin-bottom: 16px; flex-wrap: wrap">
      <el-select
        v-model="tagId"
        filterable
        :allow-create="isAdmin"
        default-first-option
        :placeholder="isAdmin ? '选择或输入新分类' : '选择分类'"
        clearable
        style="width: 220px"
      >
        <el-option v-for="t in tags" :key="t.id" :label="t.name" :value="t.id" />
      </el-select>
      <span style="display: flex; align-items: center; gap: 8px">
        <span style="color: var(--el-text-color-secondary); font-size: 14px">难度</span>
        <el-rate v-model="difficulty" clearable />
      </span>
    </div>
    <MdEditor
      v-model="content"
      :style="{ height: '400px' }"
      :placeholder="'描述你的题目，支持 Markdown、代码块，可粘贴/上传图片'"
      @onUploadImg="onUploadImg"
    />
    <div style="margin-top: 16px; display: flex; gap: 12px">
      <el-button type="primary" :disabled="!canSubmit" :loading="loading" @click="submit">
        提交
      </el-button>
      <el-button @click="router.back()">取消</el-button>
    </div>
  </el-card>
</template>
