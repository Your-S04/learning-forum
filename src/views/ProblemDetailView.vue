<script setup>
import { ref, computed, onMounted, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { MdPreview } from 'md-editor-v3'
import 'md-editor-v3/lib/style.css'
import { supabase } from '../lib/supabase'
import { uploadImages } from '../lib/image'
import { authState } from '../composables/useAuth'
import EmojiPicker from '../components/EmojiPicker.vue'

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

// 楼中楼：正在回复的评论 + 回复内容
const replyTo = ref(null)
const replyText = ref('')
const replySubmitting = ref(false)

// 评论配图：本地待上传列表
const pendingImages = ref([]) // [{ file, preview }]
const fileInput = ref(null)

// 两个文本域的引用，用于 emoji 插入到光标处
const commentInput = ref(null)
const replyInput = ref(null)

// 在 textarea 的光标位置插入文本（没有光标信息时追加到末尾）
async function insertEmoji(inputRef, emoji, get, set) {
  const el = inputRef.value?.$el?.querySelector('textarea')
  if (!el) {
    set(get() + emoji)
    return
  }
  const text = get()
  const start = el.selectionStart ?? text.length
  const end = el.selectionEnd ?? start
  set(text.slice(0, start) + emoji + text.slice(end))
  await nextTick()
  el.focus()
  const pos = start + emoji.length
  el.setSelectionRange(pos, pos)
}

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
      .select('id, title, content, created_at, user_id, tag_id, difficulty, profiles!problems_user_id_fkey(username), tags(name)')
      .eq('id', problemId)
      .single(),
    supabase
      .from('comments')
      .select('id, content, created_at, user_id, parent_id, images, pinned_at, profiles!comments_user_id_fkey(username)')
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

// 组织成两层树：顶层排序（置顶优先）+ 各自的楼中楼按时间排
const commentTree = computed(() => {
  const kw = userFilter.value.trim().toLowerCase()
  const match = (c) => !kw || c.profiles?.username?.toLowerCase().includes(kw)

  const repliesOf = {}
  for (const c of comments.value) {
    if (c.parent_id) (repliesOf[c.parent_id] ??= []).push(c)
  }

  const tops = comments.value.filter((c) => !c.parent_id && match(c))
  tops.sort((a, b) => {
    if (!!a.pinned_at !== !!b.pinned_at) return a.pinned_at ? -1 : 1
    if (a.pinned_at && b.pinned_at) return new Date(a.pinned_at) - new Date(b.pinned_at)
    if (sortBy.value === 'hot') {
      const diff =
        (commentLikes.value[b.id]?.count ?? 0) -
        (commentLikes.value[a.id]?.count ?? 0)
      if (diff !== 0) return diff
    }
    return new Date(a.created_at) - new Date(b.created_at)
  })

  return tops.map((t) => ({
    ...t,
    replies: (repliesOf[t.id] ?? [])
      .filter((r) => match(r) || !kw)
      .sort((a, b) => new Date(a.created_at) - new Date(b.created_at)),
  }))
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

function startReply(comment) {
  replyTo.value = comment
  replyText.value = ''
}

function cancelReply() {
  replyTo.value = null
  replyText.value = ''
}

async function submitReply() {
  if (!replyText.value.trim()) return
  replySubmitting.value = true
  const { error } = await supabase.from('comments').insert({
    problem_id: problemId,
    user_id: currentUserId.value,
    parent_id: replyTo.value.id,
    content: replyText.value.trim(),
    images: [],
  })
  replySubmitting.value = false
  if (error) return ElMessage.error(error.message)
  cancelReply()
  load()
}

function onPickImages(e) {
  for (const file of e.target.files) {
    pendingImages.value.push({ file, preview: URL.createObjectURL(file) })
  }
  e.target.value = ''
}

function removeImage(i) {
  URL.revokeObjectURL(pendingImages.value[i].preview)
  pendingImages.value.splice(i, 1)
}

async function submitComment() {
  if (!newComment.value.trim() && !pendingImages.value.length) return
  submitting.value = true
  const uploaded = pendingImages.value.length
    ? await uploadImages(pendingImages.value.map((i) => i.file))
    : []
  if (pendingImages.value.length && !uploaded.length) {
    submitting.value = false
    return // 图片全传失败，中止提交
  }
  const { error } = await supabase.from('comments').insert({
    problem_id: problemId,
    user_id: currentUserId.value,
    parent_id: null,
    content: newComment.value.trim(),
    images: uploaded,
  })
  submitting.value = false
  if (error) {
    ElMessage.error(error.message)
    return
  }
  newComment.value = ''
  pendingImages.value = []
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
          <el-tag v-if="problem.tags?.name" size="small" type="info" style="margin-left: 8px">
            {{ problem.tags.name }}
          </el-tag>
          <el-rate
            v-if="problem.difficulty"
            :model-value="problem.difficulty"
            disabled
            size="small"
            style="display: inline-flex; vertical-align: middle; margin-left: 8px"
          />
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

      <!-- 顶层评论 -->
      <div
        v-for="c in commentTree"
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
            <el-button v-if="canPin" link size="small" style="margin-left: 8px" @click="togglePin(c)">
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
        <p v-if="c.content" style="white-space: pre-wrap; margin: 8px 0">{{ c.content }}</p>

        <!-- 评论配图：显示压缩图，可下载原图 -->
        <div v-if="c.images?.length" style="display: flex; gap: 12px; flex-wrap: wrap; margin: 8px 0">
          <div v-for="(img, i) in c.images" :key="i" style="text-align: center">
            <el-image
              :src="img.thumb"
              :preview-src-list="[img.thumb]"
              fit="cover"
              preview-teleported
              style="width: 120px; height: 120px; border-radius: 4px"
            />
            <div>
              <a :href="img.original" target="_blank" download style="font-size: 12px">下载原图</a>
            </div>
          </div>
        </div>

        <div style="display: flex; gap: 4px; align-items: center">
          <el-button
            size="small"
            text
            :type="commentLikes[c.id]?.liked ? 'primary' : 'default'"
            :disabled="c.user_id === currentUserId"
            @click="toggleCommentLike(c)"
          >
            {{ commentLikes[c.id]?.liked ? 'Liked' : 'Like' }} {{ commentLikes[c.id]?.count ?? 0 }}
          </el-button>
          <el-button size="small" text @click="startReply(c)">回复</el-button>
        </div>

        <!-- 楼中楼回复输入框 -->
        <div
          v-if="replyTo?.id === c.id"
          style="margin: 8px 0 4px; padding: 10px; background: var(--el-fill-color-light); border-radius: 6px"
        >
          <div style="font-size: 13px; color: var(--el-text-color-secondary); margin-bottom: 6px">
            回复 @{{ c.profiles?.username }}
          </div>
          <el-input ref="replyInput" v-model="replyText" type="textarea" :rows="2" placeholder="写下你的回复…" />
          <div style="margin-top: 6px; display: flex; gap: 8px; align-items: center">
            <el-button
              size="small"
              type="primary"
              :disabled="!replyText.trim()"
              :loading="replySubmitting"
              @click="submitReply"
            >
              发表
            </el-button>
            <el-button size="small" @click="cancelReply">取消</el-button>
            <EmojiPicker @select="(e) => insertEmoji(replyInput, e, () => replyText, (v) => (replyText = v))" />
          </div>
        </div>

        <!-- 楼中楼 -->
        <div
          v-for="r in c.replies"
          :key="r.id"
          style="margin: 8px 0 0 36px; padding: 8px 12px; background: var(--el-fill-color-light); border-radius: 6px"
        >
          <div style="display: flex; justify-content: space-between; font-size: 13px">
            <strong>{{ r.profiles?.username }}</strong>
            <span style="color: var(--el-text-color-secondary)">
              {{ new Date(r.created_at).toLocaleString('zh-CN') }}
              <el-button
                v-if="canDelete(r.user_id)"
                link
                type="danger"
                size="small"
                @click="removeComment(r.id)"
              >
                删除
              </el-button>
            </span>
          </div>
          <p style="white-space: pre-wrap; margin: 6px 0">{{ r.content }}</p>
          <el-button
            size="small"
            text
            :type="commentLikes[r.id]?.liked ? 'primary' : 'default'"
            :disabled="r.user_id === currentUserId"
            @click="toggleCommentLike(r)"
          >
            {{ commentLikes[r.id]?.liked ? 'Liked' : 'Like' }} {{ commentLikes[r.id]?.count ?? 0 }}
          </el-button>
        </div>
      </div>
      <el-empty v-if="!commentTree.length" description="暂无讨论" :image-size="80" />

      <!-- 发表新评论 -->
      <el-input
        ref="commentInput"
        v-model="newComment"
        type="textarea"
        :rows="3"
        placeholder="写下你的思路或解答…（可添加图片）"
        style="margin-top: 16px"
      />
      <div style="display: flex; gap: 12px; align-items: flex-start; margin-top: 8px; flex-wrap: wrap">
        <div style="display: flex; gap: 8px; flex-wrap: wrap">
          <div
            v-for="(img, i) in pendingImages"
            :key="i"
            style="position: relative"
          >
            <img :src="img.preview" style="width: 72px; height: 72px; object-fit: cover; border-radius: 4px" />
            <el-button
              link
              size="small"
              style="position: absolute; top: -6px; right: -6px; background: rgba(0,0,0,.55); color: #fff; border-radius: 50%; padding: 2px"
              @click="removeImage(i)"
            >
              ×
            </el-button>
          </div>
        </div>
        <div style="display: flex; gap: 8px; align-items: center; flex-wrap: wrap">
          <el-button size="small" @click="fileInput.click()">添加图片</el-button>
          <input ref="fileInput" type="file" accept="image/*" multiple hidden @change="onPickImages" />
          <EmojiPicker @select="(e) => insertEmoji(commentInput, e, () => newComment, (v) => (newComment = v))" />
          <el-button
            type="primary"
            :disabled="!newComment.trim() && !pendingImages.length"
            :loading="submitting"
            @click="submitComment"
          >
            发表回复
          </el-button>
        </div>
      </div>
    </el-card>
  </div>
  <el-empty v-else description="题目不存在或已删除" />
</template>
