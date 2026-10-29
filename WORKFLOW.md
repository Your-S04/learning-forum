# You-Forum 完整工作流程

> 技术栈：Vue 3 + Vite + Element Plus + Supabase + Vercel
> 原则：不做公开注册（管理员预建账号）、不做自建后端、能用现成组件就绝不手写。

---

## 第 0 阶段：准备工作（半天）

1. 安装 [Node.js LTS](https://nodejs.org) 和 Git。
2. 注册三个账号：
   - **Supabase**（数据库 + 认证 + 文件存储，全免费档够用）
   - **GitHub**（存代码）
   - **Vercel**（用 GitHub 账号直接登录即可）
3. 准备好域名（国内域名需备案，Vercel 默认域名 vercel.app 在国内访问不稳定，建议备案或用 Cloudflare 托管）。

## 第 1 阶段：Vue 项目骨架（1 天）

```bash
cd D:\work\you-forum
npm create vue@latest .   # 选项全选默认（Router 选 Yes，Pinia 可不选）
npm install
npm install @supabase/supabase-js element-plus @element-plus/icons-vue vue-router md-editor-v3
npm run dev
```

目录约定（从第一天就建好，后面不返工）：

```
src/
├── lib/supabase.js      # Supabase 客户端（唯一出口）
├── composables/useAuth.js  # 登录状态
├── router/index.js
├── views/               # 页面：LoginView, ProblemListView, ...
└── components/          # 只有 Element Plus 满足不了的才写
```

**路由守卫**（登录状态判断，核心就这几行）：

```js
// router/index.js
router.beforeEach(async (to) => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session && to.name !== 'login') return { name: 'login' }
})
```

## 第 2 阶段：Supabase 建库（半天）

Dashboard → SQL Editor，依次执行：

```sql
-- 1. 用户资料表（与 Supabase Auth 的用户一一对应）
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null,
  role text not null default 'student' check (role in ('admin', 'student')),
  created_at timestamptz not null default now()
);

-- 注册新账号时自动建档（复制即用，不用理解细节）
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, split_part(new.email, '@', 1));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. 题目
create table problems (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  content text not null,               -- Markdown 原文
  created_at timestamptz not null default now()
);

-- 3. 讨论（楼层回复；parent_id 楼中楼，可留空）
create table comments (
  id bigint generated always as identity primary key,
  problem_id bigint not null references problems(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  parent_id bigint references comments(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

-- 4. 看板（作业/考试/课程时间共用一张表，一个 type 字段区分）
create table board_items (
  id bigint generated always as identity primary key,
  type text not null check (type in ('homework', 'exam', 'course')),
  title text not null,
  course text,
  note text,
  start_at timestamptz,
  end_at timestamptz,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- 5. 排行榜：不用建表，用视图实时算（发题 3 分 + 回复 1 分，想改规则改这里）
create view leaderboard as
select p.id, p.username,
  (select count(*) from problems where user_id = p.id) * 3 +
  (select count(*) from comments  where user_id = p.id) * 1 as score
from profiles p
order by score desc;
```

**权限（Row Level Security）**——先开 RLS 再建策略，否则外网可读写你的库：

```sql
alter table profiles    enable row level security;
alter table problems    enable row level security;
alter table comments    enable row level security;
alter table board_items enable row level security;

create policy "read all"   on profiles for select to authenticated using (true);
create policy "read all"   on problems for select to authenticated using (true);
create policy "insert own" on problems for insert to authenticated with check (auth.uid() = user_id);
create policy "update own" on problems for update to authenticated using (auth.uid() = user_id);
create policy "del own or admin" on problems for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);
-- comments 复用 problems 的五条策略（把表名换掉即可）
create policy "read all"   on comments for select to authenticated using (true);
create policy "insert own" on comments for insert to authenticated with check (auth.uid() = user_id);
create policy "update own" on comments for update to authenticated using (auth.uid() = user_id);
create policy "del own or admin" on comments for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- 看板：所有人可读，仅管理员可写
create policy "read all"  on board_items for select to authenticated using (true);
create policy "admin write" on board_items for all to authenticated using (
  exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);
```

## 第 3 阶段：认证（半天，Supabase 帮你做完了 90%）

### 3.1 预建账号（"初始固定账号密码"的落地方式）

Supabase Dashboard → **Authentication → Users → Add user → Create new user**：
- Email 填学号风格的地址，如 `stu001@youforum.local`（这个域名收不到邮件也没关系，密码登录不依赖真实邮箱）
- Password 统一设成 `You123456`（你的固定初始密码）
- Display name 填真实姓名

需要管理员时，SQL Editor 执行：
```sql
update profiles set role = 'admin' where username = '张三';
```

### 3.2 前端接入（三小段代码）

```js
// src/lib/supabase.js —— 全项目唯一的 Supabase 出口
import { createClient } from '@supabase/supabase-js'
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
)
```

登录页（Element Plus 的 `el-form` 包一层即可）：
```js
const { error } = await supabase.auth.signInWithPassword({ email, password })
if (!error) router.push('/problems')
```

改密码（"个人中心"页一个表单）：
```js
const { error } = await supabase.auth.updateUser({ password: newPassword })
```

**保留登录状态：零代码。** `supabase-js` 默认把会话存进 localStorage，刷新、关浏览器重开都还在；`router.beforeEach` 里 `getSession()` 就能读到。想实现"首次登录强制改密码"，在 profiles 加个 `password_changed boolean default false` 字段，登录后检查并跳转改密页即可（可选，非必须）。

## 第 4 阶段：四个业务模块（每个 0.5~1 天，可并行学习）

所有数据操作都是同一个模式，**学会一个就全会了**：

```js
// 查（排行榜甚至不用写 SQL）
const { data } = await supabase.from('problems').select('*, profiles(username)').order('created_at', { ascending: false })

// 增
await supabase.from('problems').insert({ title, content, user_id: session.user.id })

// 删（RLS 已保证只能删自己的）
await supabase.from('problems').delete().eq('id', id)
```

| 模块 | 页面 | 用到的现成组件 |
|---|---|---|
| 题目 | 列表页 + 详情页 + 新建/编辑页 | `el-table` / `el-form`，Markdown 用 **md-editor-v3**（编辑+预览一体，含代码高亮） |
| 讨论 | 题目详情页下半部分 | `el-comment` 风格的布局自己拼 + md-editor-v3 |
| 看板 | 按时间排序的卡片列表 | `el-timeline` + `el-tag`（type 区分作业/考试/课程颜色） |
| 排行榜 | 一张表格 | `el-table` 直接查 `leaderboard` 视图 |

**题目里的图片**：Storage 建一个 `images` bucket（设为 authenticated 可读），md-editor-v3 的图片上传钩子调 `supabase.storage.from('images').upload()`，拿返回的 URL 插入正文。

## 第 5 阶段：部署上线（半天）

1. 代码推 GitHub：`git init && git add -A && git commit -m init` 然后建仓库推送。
2. Vercel → **Add New Project** → 导入该仓库（Vite 项目零配置自动识别）。
3. Vercel → Settings → Environment Variables，添加：
   - `VITE_SUPABASE_URL` 和 `VITE_SUPABASE_ANON_KEY`（在 Supabase Project Settings → API 里复制）
4. 根目录加一个 `vercel.json` 解决刷新 404（Vue Router history 模式必需）：
   ```json
   { "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }
   ```
5. 之后每次 `git push` 自动部署。
6. **绑定域名**：Vercel → Settings → Domains → 填你的域名 → 按提示到域名服务商加一条 `CNAME` 记录指向 `cname.vercel-dns.com`，等几分钟生效。

## 第 6 阶段：维护（每月 5 分钟）

- **加账号**：Dashboard 手动 Add user，一分钟搞定。
- **备份**：Supabase Dashboard → Database → Backups（免费档每日自动备份，手动点 Download 存档更稳）。
- **免费额度监控**：Dashboard 首页看 DB/Storage 用量，百人内几乎不可能超限。
- **出问题先看两处**：浏览器 F12 Console 的报错；Supabase Dashboard → Logs。

---

## 风险与简化决策备忘

| 决策 | 理由 |
|---|---|
| 不做公开注册 | 需求就是固定人群；省掉注册页、邮箱验证、防滥用全部工作 |
| Email 当账号 | Supabase Auth 原生支持，省掉自定义登录体系 |
| 看板/题目图片不用富文本编辑器 | Markdown + md-editor-v3 覆盖 95% 场景（代码、公式、图片） |
| 排行榜用视图 | 不维护积分表，规则改了只改视图，不可能出现积分不同步的 bug |
| 不做 WebSocket 实时刷新 | 讨论区进入页面时拉一次 + 手动刷新按钮即可 |
| 暂不上 Pinia | 全局状态只有"当前用户"一个，composable 里一个 ref 就够 |
