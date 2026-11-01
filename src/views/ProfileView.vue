<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { authState, changePassword } from '../composables/useAuth'
import { supabase } from '../lib/supabase'

const router = useRouter()

// 我的收藏列表
const favorites = ref([])

async function loadFavorites() {
  const { data } = await supabase
    .from('favorites')
    .select('problem_id, created_at, problems(title, created_at)')
    .eq('user_id', authState.session.user.id)
    .order('created_at', { ascending: false })
  favorites.value = data ?? []
}

onMounted(loadFavorites)

// 微信推送（WxPusher）：每人存自己的 UID，别人评论我的题目时微信提醒我
const pusherUid = ref('')
const pushSaved = ref(false)
const savingPush = ref(false)

onMounted(async () => {
  const { data } = await supabase
    .from('push_tokens')
    .select('pusher_uid')
    .eq('user_id', authState.session.user.id)
    .maybeSingle()
  if (data) {
    pusherUid.value = data.pusher_uid
    pushSaved.value = true
  }
})

async function savePushUid() {
  const uid = pusherUid.value.trim()
  if (!uid.startsWith('UID_')) {
    return ElMessage.warning('UID 以 UID_ 开头，请从 WxPusher 公众号复制完整的 UID')
  }
  savingPush.value = true
  const { error } = await supabase
    .from('push_tokens')
    .upsert({ user_id: authState.session.user.id, pusher_uid: uid })
  savingPush.value = false
  if (error) return ElMessage.error(error.message)
  pushSaved.value = true
  ElMessage.success('已开启微信推送')
}

async function disablePush() {
  const { error } = await supabase
    .from('push_tokens')
    .delete()
    .eq('user_id', authState.session.user.id)
  if (error) return ElMessage.error(error.message)
  pusherUid.value = ''
  pushSaved.value = false
  ElMessage.success('已关闭微信推送')
}

async function removeFavorite(item) {
  const { error } = await supabase
    .from('favorites')
    .delete()
    .eq('problem_id', item.problem_id)
    .eq('user_id', authState.session.user.id)
  if (error) return ElMessage.error(error.message)
  loadFavorites()
}

// 更改显示名（登录凭证仍是学号邮箱，不受影响）
const newUsername = ref(authState.profile?.username ?? '')
const savingName = ref(false)

async function saveUsername() {
  const name = newUsername.value.trim()
  if (!name) return ElMessage.warning('用户名不能为空')
  if (name === authState.profile?.username) return
  savingName.value = true
  const { error } = await supabase
    .from('profiles')
    .update({ username: name })
    .eq('id', authState.session.user.id)
  savingName.value = false
  if (error) return ElMessage.error(error.message)
  authState.profile.username = name
  ElMessage.success('用户名已更新')
}

// 修改密码
const newPassword = ref('')
const confirmPassword = ref('')
const loading = ref(false)

async function submit() {
  if (newPassword.value.length < 6) {
    return ElMessage.warning('新密码至少 6 位')
  }
  if (newPassword.value !== confirmPassword.value) {
    return ElMessage.warning('两次输入的密码不一致')
  }
  loading.value = true
  try {
    await changePassword(newPassword.value)
    ElMessage.success('密码修改成功')
    newPassword.value = ''
    confirmPassword.value = ''
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <el-card style="max-width: 560px">
    <h2 style="margin-top: 0">个人中心</h2>
    <p style="color: var(--el-text-color-secondary); font-size: 13px">
      登录账号：{{ authState.session?.user.email }}（学号，不可更改）
      <el-tag v-if="authState.profile?.role === 'admin'" size="small" style="margin-left: 8px">
        管理员
      </el-tag>
    </p>
    <el-divider />

    <h3>显示用户名</h3>
    <p style="color: var(--el-text-color-secondary); font-size: 13px; margin-top: 0">
      显示在题目、讨论和排行榜上，可随时修改
    </p>
    <div style="display: flex; gap: 8px">
      <el-input v-model="newUsername" maxlength="20" placeholder="输入显示名" @keyup.enter="saveUsername" />
      <el-button type="primary" :disabled="!newUsername.trim()" :loading="savingName" @click="saveUsername">
        保存
      </el-button>
    </div>

    <el-divider />
    <h3>我的收藏（{{ favorites.length }}）</h3>
    <div
      v-for="f in favorites"
      :key="f.problem_id"
      style="display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid var(--el-border-color-lighter)"
    >
      <el-button link type="primary" style="max-width: 75%" @click="router.push({ name: 'problem-detail', params: { id: f.problem_id } })">
        {{ f.problems?.title ?? '（题目已删除）' }}
      </el-button>
      <el-button link type="danger" size="small" @click="removeFavorite(f)">取消收藏</el-button>
    </div>
    <div v-if="!favorites.length" style="color: var(--el-text-color-secondary); font-size: 13px">
      还没有收藏，在题目详情页点"☆ 收藏"即可保存
    </div>

    <el-divider />
    <h3>微信推送（可选）</h3>
    <p style="color: var(--el-text-color-secondary); font-size: 13px; margin-top: 0">
      开启后，别人回复你的题目时你会收到微信通知（免费、无需注册账号）。获取 UID：
      在微信里关注公众号「wxpusher」（或扫描本论坛应用的二维码）→ 公众号菜单里查看你的
      <strong>UID</strong>（UID_ 开头）→ 复制粘贴到下面。
    </p>
    <div style="display: flex; gap: 8px">
      <el-input v-model="pusherUid" placeholder="粘贴你的 UID（UID_ 开头）" />
      <el-button type="primary" :loading="savingPush" @click="savePushUid">保存</el-button>
      <el-button v-if="pushSaved" @click="disablePush">关闭推送</el-button>
    </div>
    <el-tag v-if="pushSaved" type="success" size="small" style="margin-top: 8px">
      已开启：有人回复你的题目会推送到微信
    </el-tag>

    <el-divider />
    <h3>修改密码</h3>
    <el-form label-width="90px">
      <el-form-item label="新密码">
        <el-input v-model="newPassword" type="password" show-password placeholder="至少 6 位" />
      </el-form-item>
      <el-form-item label="确认密码">
        <el-input v-model="confirmPassword" type="password" show-password @keyup.enter="submit" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :loading="loading" @click="submit">保存</el-button>
      </el-form-item>
    </el-form>
  </el-card>
</template>
