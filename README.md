# 学习交流论坛（You-Forum）

Vue 3 + Element Plus + Supabase + Vercel 的学习交流平台：题目上传与讨论、作业/考试/课程看板、贡献排行榜。无公开注册，账号由管理员预建。

## 本地启动

```bash
npm install
cp .env.example .env.local   # Windows 用 copy .env.example .env.local
# 编辑 .env.local 填入 Supabase URL 和 ANON KEY
npm run dev
```

## 一次性配置（详见 WORKFLOW.md）

1. **Supabase 建库**：Dashboard → SQL Editor → 粘贴 [supabase/schema.sql](supabase/schema.sql) 全部内容 → Run。
2. **预建账号**：Dashboard → Authentication → Users → Add user，Email 填 `学号@youforum.local`（如 `stu001@youforum.local`），密码统一如 `You123456`。
3. **设管理员**：SQL Editor 执行
   ```sql
   update profiles set role = 'admin' where username = '学号';
   ```
4. **取密钥**：Project Settings → API，把 `Project URL` 和 `anon public` key 填进 `.env.local`。

## 部署到 Vercel

1. 代码推 GitHub，Vercel 导入该仓库（Vite 自动识别，零额外配置，`vercel.json` 已随仓库提供）。
2. Vercel → Settings → Environment Variables：添加 `VITE_SUPABASE_URL` 和 `VITE_SUPABASE_ANON_KEY`。
3. Settings → Domains 绑定自己的域名（域名服务商加 CNAME 记录指向 `cname.vercel-dns.com`）。
4. 之后每次 `git push` 自动部署。
