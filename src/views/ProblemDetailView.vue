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

// 点赞状态：题目一个，讨论按 id 建映射
const problemLike = ref({ count: 0, liked: false })
const commentLikes = ref({}) // { [commentId]: { count, liked } }

// 讨论区：排序与筛选
const sortBy = ref('time') // time 时间正序 | hot 热度
const userFilter = ref('')

const isAdmin = computed(() => authState.profile?.role === 'admin')
const currentUserId = computed(() => authState.session?.user.id)
// 楼主或管理员可以置顶回答
const canPin = computed(
  () => isAdmin.value || problem.value?.user_id === currentUserId.value
)

async function load() {
  const [{ data: problemData }, { data: commentData }] = await Promise.all([
    supabase
      .from('problems')
      .select('id, title, content, created_at, user_id, profiles!problems_user_id_fkey(username)')
      .eq('id', problemId)
      .single(),
    supabase
      .from('comments')
      .select('id, content, created_at, user_id, pinned_at, profiles!comments_user_id_fkey(username)')
      .eq('problem_id', problemId)
      .order('created_at', { ascending: true }),
  ])
  problem.value = problemData
  comments.value = commentData ?? []
  await loadLikes()
}

async function loadLikes() {
  const commentIds = comments.value.map((c) => c.id)
  const { data: plData } = await supabase
    .from('problem_likes')
    .select('user_id')
    .eq('problem_id', problemId)
  problemLike.value = {
    count: plData?.length ?? 0,
    liked: !!plData?.some((l) => l.user_id === currentUserId.value),
  }

  const map = {}
  for (const c of commentIds) map[c] = { count: 0, liked: false }
  if (commentIds.length) {
    const { data: clData } = await supabase
      .from('comment_likes')
      .select('comment_id, user_id')
      .in('comment_id', commentIds)
    for (const l of clData ?? []) {
      map[l.comment_id].count++
      if (l.user_id === currentUserId.value) map[l.comment_id].liked = true
    }
  }
  commentLikes.value = map
}

onMounted(load)

// 展示顺序：先按置顶时间排置顶回答，其余按所选方式排序
const displayedComments = computed(() => {
  const kw = userFilter.value.trim().toLowerCase()
  const list = kw
    ? comments.value.filter((c) => c.profiles?.username?.toLowerCase().includes(kw))
    : comments.value
  const pinned = list
    .filter((c) => c.pinned_at)
    .sort((a, b) => new Date(a.pinned_at) - new Date(b.pinned_at))
  const rest = list.filter((c) => !c.pinned_at)
  rest.sort((a, b) => {
    if (sortBy.value === 'hot') {
      const diff =
        (commentLikes.value[b.id]?.count ?? 0) -
        (commentLikes.value[a.id]?.count ?? 0)
      if (diff !== 0) return diff
    }
    return new Date(a.created_at) - new Date(b.created_at)
  })
  return [...pinned, ...rest]
})

function canDelete(userId) {
  return isAdmin.value || userId === currentUserId.value
}

async function toggleProblemLike() {
  if (problemLike.value.liked) {
    const { error } = await supabase
      .from('problem_likes')
      .delete()
      .eq('problem_id', problemId)
      .eq('user_id', currentUserId.value)
    if (error) return ElMessage.error(error.message)
    problemLike.value = { count: problemLike.value.count - 1, liked: false }
  } else {
    const { error } = await supabase
      .from('problem_likes')
      .insert({ problem_id: problemId, user_id: currentUserId.value })
    if (error) return ElMessage.error(error.message)
    problemLike.value = { count: problemLike.value.count + 1, liked: true }
  }
}

async function toggleCommentLike(comment) {
  const state = commentLikes.value[comment.id]
  if (state.liked) {
    const { error } = await supabase
      .from('comment_likes')
      .delete()
      .eq('comment_id', comment.id)
      .eq('user_id', currentUserId.value)
    if (error) return ElMessage.error(error.message)
    state.liked = false
    state.count--
  } else {
    const { error } = await supabase
      .from('comment_likes')
      .insert({ comment_id: comment.id, user_id: currentUserId.value })
    if (error) return ElMessage.error(error.message)
    state.liked = true
    state.count++
  }
}

async function togglePin(comment) {
  const pinned = !comment.pinned_at
  const { error } = await supabase
    .from('comments')
    .update({ pinned_at: pinned ? new Date().toISOString() : null })
    .eq('id', comment.id)
  if (error) return ElMessage.error(error.message)
  comment.pinned_at = pinned ? new Date().toISOString() : null
  ElMessage.success(pinned ? '已置顶' : '已取消置顶')
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
      <div
        style="
          display: flex;
          justify-content: space-between;
          align-items: center;
          color: var(--el-text-color-secondary);
          margin: 8px 0 16px;
          font-size: 14px;
        "
      >
        <span>
          {{ problem.profiles?.username }} ·
          {{ new Date(problem.created_at).toLocaleString('zh-CN') }}
        </span>
        <el-button
          size="small"
          :type="problemLike.liked ? 'primary' : 'default'"
          :disabled="problem.user_id === currentUserId"
          @click="toggleProblemLike"
        >
          {{ problemLike.liked ? 'Liked' : 'Like' }} {{ problemLike.count }}
        </el-button>
      </div>
      <MdPreview :modelValue="problem.content" />
    </el-card>

    <el-card style="margin-top: 16px">
      <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px">
        <h3 style="margin: 0">讨论（{{ comments.length }}）</h3>
        <div style="display: flex; gap: 8px; align-items: center">
          <el-input
            v-model="userFilter"
            placeholder="筛选用户回答"
            clearable
            style="width: 160px"
            size="small"
          />
          <el-radio-group v-model="sortBy" size="small">
            <el-radio-button value="time">时间</el-radio-button>
            <el-radio-button value="hot">热度</el-radio-button>
          </el-radio-group>
        </div>
      </div>

      <div
        v-for="c in displayedComments"
        :key="c.id"
        style="border-top: 1px solid var(--el-border-color-lighter); padding: 12px 0"
      >
        <div style="display: flex; justify-content: space-between; align-items: center">
          <span>
            <strong>{{ c.profiles?.username }}</strong>
            <el-tag v-if="c.pinned_at" type="warning" size="small" style="margin-left: 8px">
              置顶
            </el-tag>
          </span>
          <span style="color: var(--el-text-color-secondary); font-size: 13px">
            {{ new Date(c.created_at).toLocaleString('zh-CN') }}
            <el-button
              v-if="canPin"
              link
              size="small"
              style="margin-left: 8px"
              @click="togglePin(c)"
            >
              {{ c.pinned_at ? '取消置顶' : '置顶' }}
            </el-button>
            <el-button
              v-if="canDelete(c.user_id)"
              link
              type="danger"
              size="small"
              @click="removeComment(c.id)"
            >
              删除
            </el-button>
          </span>
        </div>
        <p style="white-space: pre-wrap; margin: 8px 0">{{ c.content }}</p>
        <el-button
          size="small"
          text
          :type="commentLikes[c.id]?.liked ? 'primary' : 'default'"
          :disabled="c.user_id === currentUserId"
          @click="toggleCommentLike(c)"
        >
          {{ commentLikes[c.id]?.liked ? 'Liked' : 'Like' }} {{ commentLikes[c.id]?.count ?? 0 }}
        </el-button>
      </div>
      <el-empty v-if="!displayedComments.length" description="暂无讨论" :image-size="80" />

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
