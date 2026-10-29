<script setup>
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { authState, changePassword } from '../composables/useAuth'

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
    <p>
      用户名：<strong>{{ authState.profile?.username }}</strong>
      <el-tag v-if="authState.profile?.role === 'admin'" size="small" style="margin-left: 8px">
        管理员
      </el-tag>
    </p>
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
