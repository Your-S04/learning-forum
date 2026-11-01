<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { supabase } from '../lib/supabase'
import { authState } from '../composables/useAuth'

const router = useRouter()
const loading = ref(true)

// 顶部统计
const stats = ref({ users: 0, todayVisitors: 0, problems: 0, comments: 0, todayNew: 0 })

// 近 14 天访问趋势：{ label, count, height }
const trend = ref([])
const trendMax = ref(1)

// 近 7 天活跃榜
const activeUsers = ref([])

// 最新内容与分类
const recentProblems = ref([])
const recentComments = ref([])
const tags = ref([])

// 用户列表（含学号）
const users = ref([])

// 本周周报预览文本
const weeklyText = ref('')
const publishing = ref(false)

const formatTime = (iso) => new Date(iso).toLocaleString('zh-CN')

async function load() {
  loading.value = true
  const dayStart = new Date()
  dayStart.setHours(0, 0, 0, 0)
  const d14 = new Date(dayStart)
  d14.setDate(d14.getDate() - 13)
  const d7 = new Date(dayStart)
  d7.setDate(d7.getDate() - 6)

  const [
    usersCount,
    problemsCount,
    commentsCount,
    todayVisits,
    todayNewP,
    todayNewC,
    profilesRes,
    visitsRes,
    weekProblemsRes,
    weekCommentsRes,
    recentPRes,
    recentCRes,
    tagsRes,
  ] = await Promise.all([
    supabase.from('profiles').select('*', { count: 'exact', head: true }),
    supabase.from('problems').select('*', { count: 'exact', head: true }),
    supabase.from('comments').select('*', { count: 'exact', head: true }),
    supabase
      .from('daily_visits')
      .select('*', { count: 'exact', head: true })
      .eq('visited_on', dayStart.toLocaleDateString('en-CA')),
    supabase.from('problems').select('id', { count: 'exact', head: true }).gte('created_at', dayStart.toISOString()),
    supabase.from('comments').select('id', { count: 'exact', head: true }).gte('created_at', dayStart.toISOString()),
    supabase.from('profiles').select('id, username, student_no, role, created_at').order('created_at', { ascending: false }),
    supabase.from('daily_visits').select('visited_on').gte('visited_on', d14.toLocaleDateString('en-CA')),
    supabase.from('problems').select('user_id').gte('created_at', d7.toISOString()),
    supabase.from('comments').select('user_id').gte('created_at', d7.toISOString()),
    supabase
      .from('problems')
      .select('id, title, created_at, profiles!problems_user_id_fkey(username)')
      .order('created_at', { ascending: false })
      .limit(10),
    supabase
      .from('comments')
      .select('id, content, created_at, problem_id, profiles!comments_user_id_fkey(username)')
      .order('created_at', { ascending: false })
      .limit(10),
    supabase.from('tags').select('id, name, problems(count)').order('name'),
  ])

  stats.value = {
    users: usersCount.count ?? 0,
    problems: problemsCount.count ?? 0,
    comments: commentsCount.count ?? 0,
    todayVisitors: todayVisits.count ?? 0,
    todayNew: (todayNewP.count ?? 0) + (todayNewC.count ?? 0),
  }

  const profileMap = {}
  for (const p of profilesRes.data ?? []) profileMap[p.id] = p
  users.value = profilesRes.data ?? []

  // 14 天趋势：按天计数，补齐没有访问记录的日期
  const byDay = {}
  for (const v of visitsRes.data ?? []) byDay[v.visited_on] = (byDay[v.visited_on] ?? 0) + 1
  trendMax.value = Math.max(1, ...Object.values(byDay))
  trend.value = Array.from({ length: 14 }, (_, i) => {
    const d = new Date(d14)
    d.setDate(d.getDate() + i)
    const key = d.toLocaleDateString('en-CA')
    return { label: `${d.getMonth() + 1}/${d.getDate()}`, count: byDay[key] ?? 0 }
  })

  // 7 天活跃榜：发题 + 回复次数合计
  const act = {}
  for (const r of weekProblemsRes.data ?? []) act[r.user_id] = (act[r.user_id] ?? 0) + 3
  for (const r of weekCommentsRes.data ?? []) act[r.user_id] = (act[r.user_id] ?? 0) + 1
  activeUsers.value = Object.entries(act)
    .map(([id, score]) => ({
      username: profileMap[id]?.username ?? '已注销用户',
      student_no: profileMap[id]?.student_no ?? '-',
      score,
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 10)

  recentProblems.value = recentPRes.data ?? []
  recentComments.value = recentCRes.data ?? []
  tags.value = tagsRes.data ?? []

  // 周报文本：本周新增 + 活跃榜前三 + 访问峰值
  const weekP = (weekProblemsRes.data ?? []).length
  const weekC = (weekCommentsRes.data ?? []).length
  const top3 = activeUsers.value.slice(0, 3).map((u) => `${u.username}（${u.score}分）`).join('、') || '暂无'
  const end = new Date()
  const start = new Date(d7)
  weeklyText.value =
    `本周（${start.getMonth() + 1}/${start.getDate()} ~ ${end.getMonth() + 1}/${end.getDate()}）` +
    `新增题目 ${weekP} 道、讨论 ${weekC} 条；近 14 天单日访客峰值 ${trendMax.value} 人。\n` +
    `活跃榜前三：${top3}`
  loading.value = false
}

async function publishWeekly() {
  publishing.value = true
  const { error } = await supabase.from('board_items').insert({
    type: 'notice',
    title: `本周周报（${new Date().toLocaleDateString('zh-CN')}发布）`,
    note: weeklyText.value,
    start_at: new Date().toISOString(),
    created_by: authState.session.user.id,
  })
  publishing.value = false
  if (error) return ElMessage.error(error.message)
  ElMessage.success('周报已发布为公告，网站顶部即可看到')
}

onMounted(load)

async function removeProblem(row) {
  await ElMessageBox.confirm(`确定删除题目「${row.title}」及其全部讨论吗？`, '删除确认', { type: 'warning' })
  const { error } = await supabase.from('problems').delete().eq('id', row.id)
  if (error) return ElMessage.error(error.message)
  ElMessage.success('已删除')
  load()
}

async function removeComment(row) {
  await ElMessageBox.confirm('确定删除这条评论吗？', '删除确认', { type: 'warning' })
  const { error } = await supabase.from('comments').delete().eq('id', row.id)
  if (error) return ElMessage.error(error.message)
  ElMessage.success('已删除')
  load()
}

async function removeTag(tag) {
  const used = tag.problems?.[0]?.count ?? 0
  if (used > 0) return ElMessage.warning(`「${tag.name}」下还有 ${used} 道题目，不能删除`)
  await ElMessageBox.confirm(`确定删除分类「${tag.name}」吗？`, '删除确认', { type: 'warning' })
  const { error } = await supabase.from('tags').delete().eq('id', tag.id)
  if (error) return ElMessage.error(error.message)
  ElMessage.success('已删除')
  load()
}

async function toggleRole(u) {
  const newRole = u.role === 'admin' ? 'student' : 'admin'
  const isSelf = u.id === authState.session?.user.id
  await ElMessageBox.confirm(
    `确定把 ${u.student_no ?? u.username} 设为${newRole === 'admin' ? '管理员' : '普通用户'}吗？${isSelf && newRole === 'student' ? '（将失去你自己的管理员权限！）' : ''}`,
    '权限变更',
    { type: 'warning' }
  )
  const { error } = await supabase.from('profiles').update({ role: newRole }).eq('id', u.id)
  if (error) return ElMessage.error(error.message)
  ElMessage.success('已更新')
  load()
}
</script>

<template>
  <div v-loading="loading">
    <!-- 顶部统计卡片 -->
    <div style="display: flex; gap: 12px; flex-wrap: wrap">
      <el-card v-for="s in [
        { label: '总用户数', value: stats.users },
        { label: '今日访客', value: stats.todayVisitors },
        { label: '题目总数', value: stats.problems },
        { label: '讨论总数', value: stats.comments },
        { label: '今日新增内容', value: stats.todayNew },
      ]" :key="s.label" style="flex: 1; min-width: 130px">
        <div style="font-size: 24px; font-weight: 600">{{ s.value }}</div>
        <div style="color: var(--el-text-color-secondary); font-size: 13px">{{ s.label }}</div>
      </el-card>
    </div>

    <el-row :gutter="12" style="margin-top: 12px">
      <!-- 本周周报 -->
      <el-col :span="24">
        <el-card>
          <template #header>
            <div style="display: flex; justify-content: space-between; align-items: center">
              <span>本周周报预览（每周日发布到公告）</span>
              <el-button type="primary" size="small" :loading="publishing" @click="publishWeekly">
                发布为公告
              </el-button>
            </div>
          </template>
          <div style="white-space: pre-wrap; font-size: 14px">{{ weeklyText }}</div>
        </el-card>
      </el-col>
    </el-row>

    <el-row :gutter="12" style="margin-top: 12px">
      <!-- 14 天访问趋势（纯 CSS 柱状图） -->
      <el-col :xs="24" :md="14">
        <el-card>
          <template #header>近 14 天访问趋势</template>
          <div style="display: flex; align-items: flex-end; gap: 6px; height: 160px">
            <div
              v-for="d in trend"
              :key="d.label"
              style="flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: flex-end; height: 100%"
            >
              <span style="font-size: 11px; color: var(--el-text-color-secondary)">{{ d.count || '' }}</span>
              <div
                :title="`${d.label}：${d.count} 人访问`"
                :style="{
                  width: '100%',
                  height: Math.max(2, (d.count / trendMax) * 120) + 'px',
                  background: d.count ? 'var(--el-color-primary)' : 'var(--el-border-color-lighter)',
                  borderRadius: '3px 3px 0 0',
                }"
              />
            </div>
          </div>
          <div style="display: flex; gap: 6px; margin-top: 4px">
            <span v-for="d in trend" :key="d.label" style="flex: 1; text-align: center; font-size: 10px; color: var(--el-text-color-secondary)">
              {{ d.label }}
            </span>
          </div>
        </el-card>
      </el-col>

      <!-- 7 天活跃榜 -->
      <el-col :xs="24" :md="10">
        <el-card>
          <template #header>近 7 天活跃榜（发题 3 分 + 回复 1 分）</template>
          <el-table :data="activeUsers" size="small">
            <el-table-column type="index" label="#" width="46" />
            <el-table-column label="学号" width="140">
              <template #default="{ row }">{{ row.student_no }}</template>
            </el-table-column>
            <el-table-column prop="username" label="显示名" />
            <el-table-column prop="score" label="活跃分" width="80" align="center" />
            <template #empty>近 7 天还没有内容</template>
          </el-table>
        </el-card>
      </el-col>
    </el-row>

    <el-row :gutter="12" style="margin-top: 12px">
      <!-- 最新题目 -->
      <el-col :xs="24" :md="8">
        <el-card>
          <template #header>最新题目</template>
          <div v-for="p in recentProblems" :key="p.id" style="display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid var(--el-border-color-lighter)">
            <el-button link type="primary" style="max-width: 70%" @click="router.push({ name: 'problem-detail', params: { id: p.id } })">
              {{ p.title }}
            </el-button>
            <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--el-text-color-secondary)">
              {{ p.profiles?.username }}
              <el-button link type="danger" size="small" @click="removeProblem(p)">删</el-button>
            </span>
          </div>
        </el-card>
      </el-col>

      <!-- 最新评论 -->
      <el-col :xs="24" :md="8">
        <el-card>
          <template #header>最新评论</template>
          <div v-for="c in recentComments" :key="c.id" style="display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid var(--el-border-color-lighter)">
            <el-button link type="primary" style="max-width: 70%; overflow: hidden" @click="router.push({ name: 'problem-detail', params: { id: c.problem_id } })">
              {{ c.content.slice(0, 30) || '（图片）' }}
            </el-button>
            <span style="display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--el-text-color-secondary)">
              {{ c.profiles?.username }}
              <el-button link type="danger" size="small" @click="removeComment(c)">删</el-button>
            </span>
          </div>
        </el-card>
      </el-col>

      <!-- 分类管理 -->
      <el-col :xs="24" :md="8">
        <el-card>
          <template #header>分类管理（空分类可删）</template>
          <div v-for="t in tags" :key="t.id" style="display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid var(--el-border-color-lighter)">
            <el-tag size="small" type="info">{{ t.name }}</el-tag>
            <span style="display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--el-text-color-secondary)">
              {{ t.problems?.[0]?.count ?? 0 }} 题
              <el-button
                link
                type="danger"
                size="small"
                :disabled="(t.problems?.[0]?.count ?? 0) > 0"
                @click="removeTag(t)"
              >
                删
              </el-button>
            </span>
          </div>
          <div v-if="!tags.length" style="color: var(--el-text-color-secondary); font-size: 13px">还没有分类，发布题目时输入新分类即可创建</div>
        </el-card>
      </el-col>
    </el-row>

    <!-- 用户与权限 -->
    <el-card style="margin-top: 12px">
      <template #header>用户与权限</template>
      <el-table :data="users" size="small">
        <el-table-column prop="student_no" label="学号" width="160">
          <template #default="{ row }">
            <code>{{ row.student_no ?? '-' }}</code>
          </template>
        </el-table-column>
        <el-table-column prop="username" label="显示名" />
        <el-table-column label="角色" width="100">
          <template #default="{ row }">
            <el-tag :type="row.role === 'admin' ? 'warning' : 'info'" size="small">
              {{ row.role === 'admin' ? '管理员' : '学生' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="加入时间" width="180">
          <template #default="{ row }">{{ formatTime(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="140">
          <template #default="{ row }">
            <el-button size="small" link :type="row.role === 'admin' ? 'danger' : 'primary'" @click="toggleRole(row)">
              {{ row.role === 'admin' ? '取消管理员' : '设为管理员' }}
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>
  </div>
</template>
