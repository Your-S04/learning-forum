<script setup>
// 轻量 emoji 选择器：点击任意 emoji 通过 select 事件抛出
const emit = defineEmits(['select'])

const EMOJIS = [
  '😀', '😄', '😁', '🤣', '😂', '😊', '😍', '🥰',
  '😘', '🤔', '🤨', '😐', '😑', '😅', '😭', '😢',
  '😡', '🥺', '😴', '🤯', '🥳', '😎', '🤗', '🫡',
  '👍', '👎', '👏', '🙌', '🙏', '💪', '🤝', '✌️',
  '👌', '🤌', '✍️', '💅', '❤️', '💔', '💯', '✨',
  '🔥', '🎉', '🎊', '⭐', '🌟', '💫', '🌈', '☀️',
  '🌙', '⚡', '☁️', '❄️', '🌸', '🍀', '🌵', '🌲',
  '🐶', '🐱', '🐼', '🦊', '🐸', '🐵', '🐰', '🦄',
  '🍎', '🍊', '🍉', '🍇', '🍓', '🍑', '🍒', '🥭',
  '🍔', '🍟', '🍕', '🌮', '🍜', '🍣', '🍦', '🍰',
  '☕', '🧋', '🍺', '🍻', '🥛', '🥤', '🍵', '🧃',
  '📚', '📖', '📝', '✏️', '📌', '📎', '🔍', '💡',
  '🔒', '🔑', '⚙️', '🧩', '📈', '📉', '📊', '🗓️',
  '✅', '❌', '⚠️', '❓', '❗', '⏰', '🏆', '🚀',
]
</script>

<template>
  <el-popover placement="top-start" trigger="click" :width="300">
    <template #reference>
      <el-button size="small">😊 Emoji</el-button>
    </template>
    <div style="display: grid; grid-template-columns: repeat(8, 1fr); gap: 2px; max-height: 220px; overflow-y: auto">
      <button
        v-for="e in EMOJIS"
        :key="e"
        type="button"
        style="font-size: 18px; line-height: 1; border: none; background: none; cursor: pointer; padding: 5px; border-radius: 4px"
        @click="emit('select', e)"
      >
        {{ e }}
      </button>
    </div>
  </el-popover>
</template>
