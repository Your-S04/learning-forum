<script setup>
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { authState, changePassword } from '../composables/useAuth'
import { supabase } from '../lib/supabase'

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
  <el-card style="max-width: 480px">
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
