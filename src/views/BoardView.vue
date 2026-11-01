<script setup>
import { ref, computed, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { supabase } from '../lib/supabase'
import { authState } from '../composables/useAuth'

const TYPE_MAP = {
  homework: { label: '作业', tagType: 'primary' },
  exam: { label: '考试', tagType: 'danger' },
  course: { label: '课程', tagType: 'success' },
  notice: { label: '公告', tagType: 'warning' },
}

const items = ref([])
const loading = ref(true)
const activeTab = ref('all')

const filtered = computed(() =>
  activeTab.value === 'all'
    ? items.value
    : items.value.filter((i) => i.type === activeTab.value)
)

const isAdmin = computed(() => authState.profile?.role === 'admin')

// 管理员新建看板项
const dialogVisible = ref(false)
const form = ref({ type: 'homework', title: '', course: '', note: '', start: null, end: null })
const saving = ref(false)

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('board_items')
    .select('*')
    .order('start_at', { ascending: true, nullsFirst: false })
  items.value = data ?? []
  loading.value = false
}

onMounted(load)

function formatTime(iso) {
  return iso ? new Date(iso).toLocaleString('zh-CN') : ''
}

async function save() {
  saving.value = true
  const { error } = await supabase.from('board_items').insert({
    type: form.value.type,
    title: form.value.title,
    course: form.value.course || null,
    note: form.value.note || null,
    // el-date-picker value-format="x" 给的是毫秒时间戳，转成 ISO 字符串存库
    start_at: form.value.start ? new Date(Number(form.value.start)).toISOString() : null,
    end_at: form.value.end ? new Date(Number(form.value.end)).toISOString() : null,
    created_by: authState.session.user.id,
  })
  saving.value = false
  if (error) return ElMessage.error(error.message)
  dialogVisible.value = false
  form.value = { type: 'homework', title: '', course: '', note: '', start: null, end: null }
  load()
}

async function remove(id) {
  await ElMessageBox.confirm('确定删除这条看板信息吗？', '删除确认', { type: 'warning' })
  const { error } = await supabase.from('board_items').delete().eq('id', id)
  if (error) return ElMessage.error(error.message)
  load()
}
</script>

<template>
  <el-card v-loading="loading">
    <div style="display: flex; justify-content: space-between; align-items: center">
      <h2 style="margin: 0">课程看板</h2>
      <el-button v-if="isAdmin" type="primary" @click="dialogVisible = true">
        发布信息
      </el-button>
    </div>

    <el-tabs v-model="activeTab" style="margin-top: 8px">
      <el-tab-pane label="全部" name="all" />
      <el-tab-pane :label="TYPE_MAP.homework.label" name="homework" />
      <el-tab-pane :label="TYPE_MAP.exam.label" name="exam" />
      <el-tab-pane :label="TYPE_MAP.course.label" name="course" />
      <el-tab-pane :label="TYPE_MAP.notice.label" name="notice" />
    </el-tabs>

    <el-timeline style="padding-left: 4px">
      <el-timeline-item
        v-for="item in filtered"
        :key="item.id"
        :timestamp="formatTime(item.start_at)"
        placement="top"
      >
        <div style="display: flex; align-items: center; gap: 8px">
          <el-tag :type="TYPE_MAP[item.type].tagType" size="small">
            {{ TYPE_MAP[item.type].label }}
          </el-tag>
          <strong>{{ item.title }}</strong>
          <span v-if="item.course" style="color: var(--el-text-color-secondary)">
            （{{ item.course }}）
          </span>
          <el-button
            v-if="isAdmin"
            link
            type="danger"
            size="small"
            @click="remove(item.id)"
          >
            删除
          </el-button>
        </div>
        <div v-if="item.note" style="margin-top: 4px; white-space: pre-wrap">{{ item.note }}</div>
        <div v-if="item.end_at" style="color: var(--el-text-color-secondary); font-size: 13px">
          截止：{{ formatTime(item.end_at) }}
        </div>
      </el-timeline-item>
      <el-empty v-if="!filtered.length" description="暂无安排" :image-size="80" />
    </el-timeline>

    <el-dialog v-model="dialogVisible" title="发布看板信息" width="480px">
      <el-form label-width="80px">
        <el-form-item label="类型">
          <el-radio-group v-model="form.type">
            <el-radio-button value="homework">作业</el-radio-button>
            <el-radio-button value="exam">考试</el-radio-button>
            <el-radio-button value="course">课程</el-radio-button>
            <el-radio-button value="notice">公告</el-radio-button>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="标题">
          <el-input v-model="form.title" placeholder="如：第三章练习题" />
        </el-form-item>
        <el-form-item label="课程">
          <el-input v-model="form.course" placeholder="如：高等数学" />
        </el-form-item>
        <el-form-item label="开始时间">
          <el-date-picker v-model="form.start" type="datetime" value-format="x" placeholder="可选" style="width: 100%" />
        </el-form-item>
        <el-form-item label="截止时间">
          <el-date-picker v-model="form.end" type="datetime" value-format="x" placeholder="可选" style="width: 100%" />
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="form.note" type="textarea" :rows="3" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :disabled="!form.title.trim()" :loading="saving" @click="save">
          发布
        </el-button>
      </template>
    </el-dialog>
  </el-card>
</template>
