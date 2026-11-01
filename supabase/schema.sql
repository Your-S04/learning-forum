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

-- 7. WxPusher 微信推送：每人存自己的 UID（不注册账号、无实名、免费）
-- appToken 存在下面的私有配置表 app_config（无 RLS 策略，任何 API 用户都读不到），
-- UID 严格只有本人可读写
create table push_tokens (
  user_id uuid primary key references profiles(id) on delete cascade,
  pusher_uid text not null,            -- UID_ 开头，同学从 WxPusher 公众号复制
  created_at timestamptz not null default now()
);
alter table push_tokens enable row level security;
create policy "push tokens own" on push_tokens for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 私有配置表：不建任何 RLS 策略 = 所有 API 用户都无法访问，只有 security definer 函数可用
create table app_config (
  key text primary key,
  value text not null
);
alter table app_config enable row level security;

create or replace function public.get_app_config(k text)
returns text as $$
  select value from app_config where key = k;
$$ language sql security definer stable;

-- 通知 1：别人顶层评论你的题目 → 微信推送题目作者
-- 楼中楼回复（parent_id 非空）不在这里处理，由下面的 notify_comment_replied 推给被回复者
create or replace function public.notify_problem_author()
returns trigger as $$
declare
  v_app_token text := public.get_app_config('wxpusher_app_token');
  v_author uuid;
  v_uid text;
  v_actor text;
begin
  if coalesce(v_app_token, '') = '' then return new; end if;
  if new.parent_id is not null then return new; end if;
  select user_id into v_author from problems where id = new.problem_id;
  if v_author is null or v_author = new.user_id then return new; end if;
  select pusher_uid into v_uid from push_tokens where user_id = v_author;
  if v_uid is null or v_uid = '' then return new; end if;
  select username into v_actor from profiles where id = new.user_id;
  perform net.http_post(
    url := 'https://wxpusher.zjiecode.com/api/send/message',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'appToken', v_app_token,
      'uids', jsonb_build_array(v_uid),
      'summary', '【学习论坛】' || coalesce(v_actor, '有人') || ' 回复了你的题目',
      'content', coalesce(v_actor, '有人') || ' 回复了你的题目：' || left(new.content, 300),
      'contentType', 1
    )
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists notify_comment on comments;
create trigger notify_comment after insert on comments
  for each row execute function public.notify_problem_author();

-- 通知 1.1：楼中楼回复了你的评论 → 微信推送被回复的评论作者
create or replace function public.notify_comment_replied()
returns trigger as $$
declare
  v_app_token text := public.get_app_config('wxpusher_app_token');
  v_parent_author uuid;
  v_uid text;
  v_actor text;
begin
  if coalesce(v_app_token, '') = '' then return new; end if;
  if new.parent_id is null then return new; end if;
  select user_id into v_parent_author from comments where id = new.parent_id;
  if v_parent_author is null or v_parent_author = new.user_id then return new; end if;
  select pusher_uid into v_uid from push_tokens where user_id = v_parent_author;
  if v_uid is null or v_uid = '' then return new; end if;
  select username into v_actor from profiles where id = new.user_id;
  perform net.http_post(
    url := 'https://wxpusher.zjiecode.com/api/send/message',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'appToken', v_app_token,
      'uids', jsonb_build_array(v_uid),
      'summary', '【学习论坛】' || coalesce(v_actor, '有人') || ' 回复了你的评论',
      'content', coalesce(v_actor, '有人') || ' 回复了你的评论：' || left(new.content, 300),
      'contentType', 1
    )
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists notify_comment_reply on comments;
create trigger notify_comment_reply after insert on comments
  for each row execute function public.notify_comment_replied();

-- 通知 1.2：你的评论被点赞 → 微信推送评论作者
create or replace function public.notify_comment_liked()
returns trigger as $$
declare
  v_app_token text := public.get_app_config('wxpusher_app_token');
  v_comment_author uuid;
  v_content text;
  v_uid text;
  v_actor text;
begin
  if coalesce(v_app_token, '') = '' then return new; end if;
  select user_id, content into v_comment_author, v_content
    from comments where id = new.comment_id;
  if v_comment_author is null or v_comment_author = new.user_id then return new; end if;
  select pusher_uid into v_uid from push_tokens where user_id = v_comment_author;
  if v_uid is null or v_uid = '' then return new; end if;
  select username into v_actor from profiles where id = new.user_id;
  perform net.http_post(
    url := 'https://wxpusher.zjiecode.com/api/send/message',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'appToken', v_app_token,
      'uids', jsonb_build_array(v_uid),
      'summary', '【学习论坛】' || coalesce(v_actor, '有人') || ' 赞了你的回复',
      'content', coalesce(v_actor, '有人') || ' 赞了你的回复：' || left(v_content, 200),
      'contentType', 1
    )
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists notify_comment_like on comment_likes;
create trigger notify_comment_like after insert on comment_likes
  for each row execute function public.notify_comment_liked();

-- 通知 2：别人点赞你的题目 → 微信推送题目作者
create or replace function public.notify_problem_liked()
returns trigger as $$
declare
  v_app_token text := public.get_app_config('wxpusher_app_token');
  v_author uuid;
  v_title text;
  v_uid text;
  v_actor text;
begin
  if coalesce(v_app_token, '') = '' then return new; end if;
  select user_id, title into v_author, v_title from problems where id = new.problem_id;
  if v_author is null or v_author = new.user_id then return new; end if;
  select pusher_uid into v_uid from push_tokens where user_id = v_author;
  if v_uid is null or v_uid = '' then return new; end if;
  select username into v_actor from profiles where id = new.user_id;
  perform net.http_post(
    url := 'https://wxpusher.zjiecode.com/api/send/message',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object(
      'appToken', v_app_token,
      'uids', jsonb_build_array(v_uid),
      'summary', '【学习论坛】' || coalesce(v_actor, '有人') || ' 赞了你的题目',
      'content', coalesce(v_actor, '有人') || ' 赞了你的题目「' || v_title || '」',
      'contentType', 1
    )
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists notify_problem_like on problem_likes;
create trigger notify_problem_like after insert on problem_likes
  for each row execute function public.notify_problem_liked();

-- 通知 3：作业/考试截止前 1 小时 → 微信推送给所有开启了推送的用户
-- 由 pg_cron 定时任务每 10 分钟跑一次；remind_sent 标记保证每条只提醒一次
alter table board_items add column remind_sent boolean not null default false;

create or replace function public.notify_due_soon()
returns void as $$
declare
  v_app_token text := public.get_app_config('wxpusher_app_token');
  v_item record;
  v_uid record;
begin
  if coalesce(v_app_token, '') = '' then return; end if;
  for v_item in
    select * from board_items
    where type in ('homework', 'exam')
      and end_at is not null
      and remind_sent = false
      and end_at > now()
      and end_at <= now() + interval '1 hour'
  loop
    for v_uid in select pusher_uid from push_tokens
    loop
      perform net.http_post(
        url := 'https://wxpusher.zjiecode.com/api/send/message',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := jsonb_build_object(
          'appToken', v_app_token,
          'uids', jsonb_build_array(v_uid.pusher_uid),
          'summary', '【学习论坛】' || (case v_item.type when 'exam' then '考试' else '作业' end) || '即将截止',
          'content', v_item.title
            || (case when v_item.course is not null then '（' || v_item.course || '）' else '' end)
            || ' 将于 ' || to_char(v_item.end_at, 'MM月DD日 HH24:MI') || ' 截止，抓紧完成！',
          'contentType', 1
        )
      );
    end loop;
    update board_items set remind_sent = true where id = v_item.id;
  end loop;
end;
$$ language plpgsql security definer;

-- 每 10 分钟检查一次即将截止的任务
select cron.schedule('due-soon-notify', '*/10 * * * *', $cron$
  select public.notify_due_soon()
$cron$);

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
