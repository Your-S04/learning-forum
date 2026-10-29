<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { signIn } from '../composables/useAuth'

const router = useRouter()
const username = ref('')
const password = ref('')
const loading = ref(false)
const errorMsg = ref('')

async function submit() {
  loading.value = true
  errorMsg.value = ''
  try {
    await signIn(username.value.trim(), password.value)
    router.push({ name: 'problems' })
  } catch {
    errorMsg.value = '登录失败：账号或密码错误'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div
    style="
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: var(--el-bg-color-page);
    "
  >
    <el-card style="width: 380px">
      <template #header>
        <strong>学习交流论坛</strong>
      </template>
      <el-form @submit.prevent="submit">
        <el-form-item>
          <el-input
            v-model="username"
            placeholder="学号 / 用户名"
            :prefix-icon="'User'"
            autofocus
          />
        </el-form-item>
        <el-form-item>
          <el-input
            v-model="password"
            type="password"
            placeholder="密码"
            :prefix-icon="'Lock'"
            show-password
            @keyup.enter="submit"
          />
        </el-form-item>
        <el-alert
          v-if="errorMsg"
          :title="errorMsg"
          type="error"
          :closable="false"
          style="margin-bottom: 16px"
        />
        <el-button type="primary" style="width: 100%" :loading="loading" @click="submit">
          登录
        </el-button>
      </el-form>
    </el-card>
  </div>
</template>
