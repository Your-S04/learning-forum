-- ============================================================
-- You-Forum 数据库初始化脚本
-- 使用方式：Supabase Dashboard → SQL Editor → 粘贴本文件全部内容 → Run
-- ============================================================

-- 1. 用户资料表（与 Supabase Auth 的用户一一对应）
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null,
  role text not null default 'student' check (role in ('admin', 'student')),
  created_at timestamptz not null default now()
);

-- 新账号创建时自动建档（用户名取邮箱 @ 前面的部分）
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

-- 2. 题目（content 存 Markdown 原文）
create table problems (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  content text not null,
  created_at timestamptz not null default now()
);

-- 3. 讨论（楼层回复）
create table comments (
  id bigint generated always as identity primary key,
  problem_id bigint not null references problems(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

-- 4. 看板：作业 / 考试 / 课程时间共用一张表，type 字段区分
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

-- 5. 排行榜视图：发题 3 分 + 回复 1 分（改规则只改这里）
create view leaderboard as
select p.id, p.username,
  (select count(*) from problems where user_id = p.id) * 3 +
  (select count(*) from comments where user_id = p.id) * 1 as score
from profiles p
order by score desc;

-- ============================================================
-- 权限（RLS）：先启用，再建策略
-- ============================================================
alter table profiles    enable row level security;
alter table problems    enable row level security;
alter table comments    enable row level security;
alter table board_items enable row level security;

-- profiles：登录后人人可读，用户名只允许自己改
create policy "profiles read"   on profiles for select to authenticated using (true);
create policy "profiles update" on profiles for update to authenticated using (auth.uid() = id);

-- problems：人人可读；本人可增改；本人或管理员可删
create policy "problems read"   on problems for select to authenticated using (true);
create policy "problems insert" on problems for insert to authenticated with check (auth.uid() = user_id);
create policy "problems update" on problems for update to authenticated using (auth.uid() = user_id);
create policy "problems delete" on problems for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- comments：同 problems
create policy "comments read"   on comments for select to authenticated using (true);
create policy "comments insert" on comments for insert to authenticated with check (auth.uid() = user_id);
create policy "comments update" on comments for update to authenticated using (auth.uid() = user_id);
create policy "comments delete" on comments for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- board_items：人人可读，仅管理员可写
create policy "board read"  on board_items for select to authenticated using (true);
create policy "board write" on board_items for all to authenticated using (
  exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- ============================================================
-- 图片存储：题目配图上传到 images 桶（公开可读，登录后可传）
-- ============================================================
insert into storage.buckets (id, name, public) values ('images', 'images', true);

create policy "images public read" on storage.objects for select using (bucket_id = 'images');
create policy "images auth upload" on storage.objects for insert to authenticated with check (bucket_id = 'images');
create policy "images owner delete" on storage.objects for delete to authenticated using (
  bucket_id = 'images' and auth.uid() = owner
);
