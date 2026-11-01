// 深色模式：全局唯一状态，切换即写入 <html> 的 dark class 并记住选择
import { ref, watchEffect } from 'vue'

const isDark = ref(localStorage.getItem('theme') === 'dark')

watchEffect(() => {
  document.documentElement.classList.toggle('dark', isDark.value)
  localStorage.setItem('theme', isDark.value ? 'dark' : 'light')
})

export function useTheme() {
  return {
    isDark,
    toggleTheme: () => {
      isDark.value = !isDark.value
    },
  }
}
