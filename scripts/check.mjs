// 连通性检查：npm run check
// 验证密钥是否配对、四张表/视图/图片桶是否建好。
// Node 默认不走 Windows 系统代理，这里自动探测并接上（国内访问 Supabase 需要代理）。
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
  } catch {
    console.error(`读取 ${file} 失败`)
  }
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
    console.log(`(已检测到系统代理 ${m[1]}，经代理检查)`)
  } catch {
    // 非 Windows 或读取失败：按直连处理
  }
}
await applySystemProxy()

const url = process.env.VITE_SUPABASE_URL
const key = process.env.VITE_SUPABASE_ANON_KEY
if (!url || !key || url.includes('你的项目')) {
  console.error('请先按 README 配置 .env.local')
  process.exit(1)
}

const supabase = createClient(url, key)

async function checkTable(name) {
  try {
    const { error } = await supabase.from(name).select('*', { head: true })
    console.log(error ? `❌ ${name}: ${error.message}` : `✅ ${name} 存在`)
  } catch (e) {
    console.log(`❌ ${name}: 网络不可达（${e.cause?.code || e.message}）——请确认代理已开启`)
  }
}

for (const t of ['profiles', 'problems', 'comments', 'board_items', 'leaderboard']) {
  await checkTable(t)
}

try {
  const { error } = await supabase.storage.getBucket('images')
  console.log(error ? `❌ 存储桶 images: ${error.message}` : '✅ 存储桶 images 存在')
} catch (e) {
  console.log(`❌ 存储桶 images: 网络不可达（${e.cause?.code || e.message}）——请确认代理已开启`)
}
