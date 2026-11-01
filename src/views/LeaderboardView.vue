<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { authState } from '../composables/useAuth'

const contributors = ref([]) // 贡献榜（leaderboard 视图）
const checkinBoard = ref([]) // 签到榜（checkin_board 视图）
const loading = ref(true)
const checkedInToday = ref(false)

const currentUserId = computed(() => authState.session?.user.id)
const myCheckinRow = computed(() => checkinBoard.value.find((r) => r.id === currentUserId.value))

async function load() {
  loading.value = true
  const [contribRes, checkinRes] = await Promise.all([
    supabase.from('leaderboard').select('*'),
    supabase.from('checkin_board').select('*'),
  ])
  contributors.value = (contribRes.data ?? []).sort((a, b) => b.score - a.score)
  checkinBoard.value = (checkinRes.data ?? []).sort(
    (a, b) => b.streak - a.streak || b.total - a.total
  )
  // 今天是否已打卡（checkin_date 用数据库日期，即 UTC 日期）
  const today = new Date().toISOString().slice(0, 10)
  const { data } = await supabase
    .from('checkins')
    .select('checkin_date')
    .eq('user_id', currentUserId.value)
    .eq('checkin_date', today)
    .maybeSingle()
  checkedInToday.value = !!data
  loading.value = false
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <el-row :gutter="12">
      <!-- 贡献榜 -->
      <el-col :xs="24" :md="12">
        <el-card>
          <h2 style="margin-top: 0">贡献排行榜</h2>
          <p style="color: var(--el-text-color-secondary); margin-top: 0; font-size: 13px">
            发布题目 +3，回复讨论 +1，收到点赞 +2，回答被置顶 +2
          </p>
          <el-table :data="contributors">
            <el-table-column type="index" label="排名" width="70" />
            <el-table-column prop="username" label="用户名" />
            <el-table-column prop="score" label="贡献分" width="90" align="center" />
          </el-table>
        </el-card>
      </el-col>

      <!-- 签到榜 -->
      <el-col :xs="24" :md="12">
        <el-card>
          <div style="display: flex; justify-content: space-between; align-items: center">
            <h2 style="margin: 12px 0 0">签到榜</h2>
            <el-tag v-if="checkedInToday" type="success" size="small">今日已打卡</el-tag>
            <el-tag v-else type="info" size="small">今日还没打卡（登录即打卡）</el-tag>
          </div>
          <p style="color: var(--el-text-color-secondary); font-size: 13px">
            每天登录即自动打卡；今天打过、昨天也打过，连续天数就会 +1
            <template v-if="myCheckinRow">
              —— 你已连续 <strong>{{ myCheckinRow.streak }}</strong> 天，累计
              {{ myCheckinRow.total }} 天
            </template>
          </p>
          <el-table :data="checkinBoard">
            <el-table-column type="index" label="排名" width="70" />
            <el-table-column prop="username" label="用户名" />
            <el-table-column prop="streak" label="连续天数" width="100" align="center">
              <template #default="{ row }">
                <strong>{{ row.streak }}</strong> 天
              </template>
            </el-table-column>
            <el-table-column prop="total" label="累计" width="80" align="center" />
          </el-table>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>
