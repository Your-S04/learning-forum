<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { MdPreview } from 'md-editor-v3'
import 'md-editor-v3/lib/style.css'
import { supabase } from '../lib/supabase'
import { authState } from '../composables/useAuth'

const route = useRoute()
const router = useRouter()
const problemId = Number(route.params.id)

const problem = ref(null)
const comments = ref([])
const newComment = ref('')
const submitting = ref(false)

const isAdmin = computed(() => authState.profile?.role === 'admin')
const currentUserId = computed(() => authState.session?.user.id)

async function load() {
  const [{ data: problemData }, { data: commentData }] = await Promise.all([
    supabase
      .from('problems')
      .select('id, title, content, created_at, user_id, profiles(username)')
      .eq('id', problemId)
      .single(),
    supabase
      .from('comments')
      .select('id, content, created_at, user_id, profiles(username)')
      .eq('problem_id', problemId)
      .order('created_at', { ascending: true }),
  ])
  problem.value = problemData
  comments.value = commentData ?? []
}

onMounted(load)

function canDelete(userId) {
  return isAdmin.value || userId === currentUserId.value
}

async function submitComment() {
  if (!newComment.value.trim()) return
  submitting.value = true
  const { error } = await supabase.from('comments').insert({
    problem_id: problemId,
    user_id: currentUserId.value,
    content: newComment.value.trim(),
  })
  submitting.value = false
  if (error) {
    ElMessage.error(error.message)
    return
  }
  newComment.value = ''
  load()
}

async function removeProblem() {
  await ElMessageBox.confirm('确定删除这道题目及其全部讨论吗？', '删除确认', {
    type: 'warning',
  })
  const { error } = await supabase.from('problems').delete().eq('id', problemId)
  if (error) return ElMessage.error(error.message)
  router.push({ name: 'problems' })
}

async function removeComment(id) {
  const { error } = await supabase.from('comments').delete().eq('id', id)
  if (error) return ElMessage.error(error.message)
  load()
}
</script>

<template>
  <div v-if="problem">
    <el-card>
      <div style="display: flex; justify-content: space-between; align-items: flex-start">
        <h2 style="margin: 0">{{ problem.title }}</h2>
        <div v-if="canDelete(problem.user_id)" style="display: flex; gap: 8px">
          <el-button size="small" @click="router.push({ name: 'problem-edit', params: { id: problemId } })">
            编辑
          </el-button>
          <el-button size="small" type="danger" plain @click="removeProblem">删除</el-button>
        </div>
      </div>
      <div style="color: var(--el-text-color-secondary); margin: 8px 0 16px; font-size: 14px">
        {{ problem.profiles?.username }} ·
        {{ new Date(problem.created_at).toLocaleString('zh-CN') }}
      </div>
      <MdPreview :modelValue="problem.content" />
    </el-card>

    <el-card style="margin-top: 16px">
      <h3 style="margin-top: 0">讨论（{{ comments.length }}）</h3>
      <div v-for="c in comments" :key="c.id" style="border-top: 1px solid var(--el-border-color-lighter); padding: 12px 0">
        <div style="display: flex; justify-content: space-between">
          <strong>{{ c.profiles?.username }}</strong>
          <span style="color: var(--el-text-color-secondary); font-size: 13px">
            {{ new Date(c.created_at).toLocaleString('zh-CN') }}
            <el-button
              v-if="canDelete(c.user_id)"
              link
              type="danger"
              size="small"
              style="margin-left: 8px"
              @click="removeComment(c.id)"
            >
              删除
            </el-button>
          </span>
        </div>
        <p style="white-space: pre-wrap; margin: 8px 0 0">{{ c.content }}</p>
      </div>
      <el-input
        v-model="newComment"
        type="textarea"
        :rows="3"
        placeholder="写下你的思路或解答…"
        style="margin-top: 16px"
      />
      <el-button
        type="primary"
        style="margin-top: 8px"
        :disabled="!newComment.trim()"
        :loading="submitting"
        @click="submitComment"
      >
        发表回复
      </el-button>
    </el-card>
  </div>
  <el-empty v-else description="题目不存在或已删除" />
</template>
