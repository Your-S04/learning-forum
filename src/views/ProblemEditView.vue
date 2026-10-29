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
const loading = ref(false)
const canSubmit = computed(() => title.value.trim() && content.value.trim())

onMounted(async () => {
  if (!problemId) return
  const { data } = await supabase
    .from('problems')
    .select('title, content')
    .eq('id', problemId)
    .single()
  if (data) {
    title.value = data.title
    content.value = data.content
  }
})

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
    if (problemId) {
      const { error } = await supabase
        .from('problems')
        .update({ title: title.value.trim(), content: content.value })
        .eq('id', problemId)
      if (error) throw error
    } else {
      const { error } = await supabase.from('problems').insert({
        title: title.value.trim(),
        content: content.value,
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
    <MdEditor
      v-model="content"
      :style="{ height: '420px' }"
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
