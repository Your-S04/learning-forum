// 批量创建用户：node scripts/create-users.mjs stu002 stu003 stu004
//   或按数量生成：node scripts/create-users.mjs --count 10 --prefix stu
//   生成 stu01..stu10，密码 Test123456（可用 --password 改）
// 需要 .env.local 里有 SUPABASE_SERVICE_ROLE_KEY（Dashboard → Settings → API → service_role）
// 注意：service_role 是管理级密钥，只能留在本机 .env.local，绝不能提交或放进前端
import { readFileSync } from 'node:fs'
import { execSync } from 'node:child_process'
import { createClient } from '@supabase/supabase-js'

function loadEnv(file) {
  try {
    const text = readFileSync(file, 'utf8')
    for (const line of text.split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)
      if (m && m[1]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '')
    }
  } catch {}
}
loadEnv('.env.local')

async function applySystemProxy() {
  if (process.env.https_proxy || process.env.HTTPS_PROXY) return
  const REG = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
  try {
    const enable = execSync(`reg query "${REG}" /v ProxyEnable`, { encoding: 'utf8' })
    if (!/ProxyEnable\s+REG_DWORD\s+0x1/.test(enable)) return
    const server = execSync(`reg query "${REG}" /v ProxyServer`, { encoding: 'utf8' })
    const m = server.match(/ProxyServer\s+REG_SZ\s+(\S+)/)
    if (!m) return
    const { ProxyAgent, setGlobalDispatcher } = await import('undici')
    setGlobalDispatcher(new ProxyAgent(`http://${m[1]}`))
  } catch {}
}
await applySystemProxy()

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) {
  console.error('缺少配置：请在 .env.local 里加入 SUPABASE_SERVICE_ROLE_KEY（Dashboard → Settings → API → service_role）')
  process.exit(1)
}

// 解析参数
const args = process.argv.slice(2)
let users = []
let password = 'Test123456'
const pwIdx = args.indexOf('--password')
if (pwIdx !== -1) {
  password = args[pwIdx + 1]
  args.splice(pwIdx, 2)
}
if (args[0] === '--count') {
  const n = Number(args[1])
  const prefixIdx = args.indexOf('--prefix')
  const prefix = prefixIdx !== -1 ? args[prefixIdx + 1] : 'test'
  for (let i = 1; i <= n; i++) users.push(`${prefix}${String(i).padStart(2, '0')}`)
} else {
  users = args
}
if (!users.length) {
  console.error('用法：node scripts/create-users.mjs stu002 stu003 ...')
  console.error('   或：node scripts/create-users.mjs --count 10 --prefix stu [--password Xxx123456]')
  process.exit(1)
}

const supabase = createClient(url, serviceKey)
for (const u of users) {
  const { error } = await supabase.auth.admin.createUser({
    email: `${u}@youforum.local`,
    password,
    email_confirm: true, // 邮箱直接视为已验证，可立即登录
  })
  console.log(error ? `❌ ${u}: ${error.message}` : `✅ ${u} 已创建（密码 ${password}）`)
}
