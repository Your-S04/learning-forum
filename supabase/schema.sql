-- ============================================================
-- You-Forum 数据库初始化脚本
-- 使用方式：Supabase Dashboard → SQL Editor → 粘贴本文件全部内容 → Run
-- ============================================================

-- 1. 用户资料表（与 Supabase Auth 的用户一一对应）
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null,              -- 显示名，可在个人中心修改
  student_no text,                     -- 学号：登录凭证（邮箱前缀），建档时自动写入
  role text not null default 'student' check (role in ('admin', 'student')),
  created_at timestamptz not null default now()
);

-- 新账号创建时自动建档（用户名与学号默认都取邮箱 @ 前面的部分）
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, student_no)
  values (new.id, split_part(new.email, '@', 1), split_part(new.email, '@', 1));
  return new;
end;
$$ language plpgsql security definer;

-- 只有管理员能修改 role 字段（防止用户通过 API 自助提权）
create or replace function public.protect_role_change()
returns trigger as $$
begin
  if new.role is distinct from old.role
     and not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception '只有管理员可以修改角色';
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger profiles_protect_role
  before update on profiles for each row execute function public.protect_role_change();

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. 分类标签库：所有人可读，仅管理员可增删
create table tags (
  id bigint generated always as identity primary key,
  name text not null unique
);

-- 2.1 题目（content 存 Markdown 原文）
create table problems (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  content text not null,
  tag_id bigint references tags(id),           -- 分类：由管理员维护标签库
  difficulty int check (difficulty between 1 and 5),  -- 难度：发布者打星，1~5
  created_at timestamptz not null default now()
);

-- 3. 讨论（楼层回复）
create table comments (
  id bigint generated always as identity primary key,
  problem_id bigint not null references problems(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  parent_id bigint references comments(id) on delete cascade,  -- 楼中楼：回复的评论
  content text not null,
  images jsonb not null default '[]',  -- 评论配图：[{thumb, original}]，页面显示压缩图 thumb
  pinned_at timestamptz,               -- 置顶时间：楼主/管理员可设置，置顶按此时间排序
  created_at timestamptz not null default now()
);

-- 4. 看板：作业/考试/课程/公告共用一张表，type 字段区分
create table board_items (
  id bigint generated always as identity primary key,
  type text not null check (type in ('homework', 'exam', 'course', 'notice')),
  title text not null,
  course text,
  note text,
  start_at timestamptz,
  end_at timestamptz,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- 4.1 点赞：题目点赞与讨论点赞各一张表，联合主键防止重复点赞
create table problem_likes (
  problem_id bigint not null references problems(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (problem_id, user_id)
);

create table comment_likes (
  comment_id bigint not null references comments(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- 5. 排行榜视图：发题 3 + 回复 1 + 获赞 2 + 被置顶 2（改规则只改这里）
create or replace view leaderboard as
select p.id, p.username,
  (select count(*) from problems where user_id = p.id) * 3 +
  (select count(*) from comments where user_id = p.id) * 1 +
  (select count(*) from problem_likes pl join problems pr on pr.id = pl.problem_id
     where pr.user_id = p.id) * 2 +
  (select count(*) from comment_likes cl join comments c on c.id = cl.comment_id
     where c.user_id = p.id) * 2 +
  (select count(*) from comments where user_id = p.id and pinned_at is not null) * 2
  as score
from profiles p
order by score desc;

-- 5.1 我的收藏：每人每题一条
create table favorites (
  problem_id bigint not null references problems(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (problem_id, user_id)
);

-- 6. 每日访问记录：联合主键保证每人每天只记一条，按天统计去重访客数
create table daily_visits (
  user_id uuid not null references profiles(id) on delete cascade,
  visited_on date not null default current_date,
  primary key (user_id, visited_on)
);

-- ============================================================
-- 权限（RLS）：先启用，再建策略
-- ============================================================
alter table profiles    enable row level security;
alter table problems    enable row level security;
alter table comments    enable row level security;
alter table board_items enable row level security;

-- profiles：登录后人人可读；本人可改资料，管理员可改任何人（角色变更受触发器保护）
create policy "profiles read"   on profiles for select to authenticated using (true);
create policy "profiles update" on profiles for update to authenticated using (
  auth.uid() = id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- problems：人人可读；本人可增改；本人或管理员可删
create policy "problems read"   on problems for select to authenticated using (true);
create policy "problems insert" on problems for insert to authenticated with check (auth.uid() = user_id);
create policy "problems update" on problems for update to authenticated using (auth.uid() = user_id);
create policy "problems delete" on problems for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- tags：人人可读，仅管理员可新增
alter table tags enable row level security;
create policy "tags read"      on tags for select to authenticated using (true);
create policy "tags admin add" on tags for insert to authenticated with check (
  exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- daily_visits：人人可读（用于显示今日访客数），只能记自己的到访
alter table daily_visits enable row level security;
create policy "visits read"      on daily_visits for select to authenticated using (true);
create policy "visits insert own" on daily_visits for insert to authenticated with check (auth.uid() = user_id);

-- favorites：只能看和操作自己的收藏
alter table favorites enable row level security;
create policy "favorites read own"   on favorites for select to authenticated using (auth.uid() = user_id);
create policy "favorites insert own" on favorites for insert to authenticated with check (auth.uid() = user_id);
create policy "favorites delete own" on favorites for delete to authenticated using (auth.uid() = user_id);

-- comments：人人可读；本人可发；本人/题目楼主/管理员可改（用于置顶）；本人或管理员可删
create policy "comments read"   on comments for select to authenticated using (true);
create policy "comments insert" on comments for insert to authenticated with check (auth.uid() = user_id);
create policy "comments update" on comments for update to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
  or exists (select 1 from problems where problems.id = comments.problem_id and problems.user_id = auth.uid())
);
create policy "comments delete" on comments for delete to authenticated using (
  auth.uid() = user_id
  or exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- board_items：人人可读，仅管理员可写
create policy "board read"  on board_items for select to authenticated using (true);
create policy "board write" on board_items for all to authenticated using (
  exists (select 1 from profiles where id = auth.uid() and role = 'admin')
);

-- 点赞：人人可读（前端要数数），本人可点赞/取消
alter table problem_likes enable row level security;
alter table comment_likes enable row level security;

create policy "problem likes read"   on problem_likes for select to authenticated using (true);
create policy "problem likes insert" on problem_likes for insert to authenticated with check (auth.uid() = user_id);
create policy "problem likes delete" on problem_likes for delete to authenticated using (auth.uid() = user_id);

create policy "comment likes read"   on comment_likes for select to authenticated using (true);
create policy "comment likes insert" on comment_likes for insert to authenticated with check (auth.uid() = user_id);
create policy "comment likes delete" on comment_likes for delete to authenticated using (auth.uid() = user_id);

-- ============================================================
-- 图片存储：题目配图上传到 images 桶（公开可读，登录后可传）
-- ============================================================
insert into storage.buckets (id, name, public) values ('images', 'images', true);

create policy "images public read" on storage.objects for select using (bucket_id = 'images');
create policy "images auth upload" on storage.objects for insert to authenticated with check (bucket_id = 'images');
create policy "images owner delete" on storage.objects for delete to authenticated using (
  bucket_id = 'images' and auth.uid() = owner
);
