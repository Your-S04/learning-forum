begin;

-- These functions are used by triggers or cron and must not be callable via RPC.
-- Only trusted database roles may create objects on their search path.
revoke create on schema public from public, anon, authenticated;

alter function public.handle_new_user() set search_path = pg_catalog, public, pg_temp;
alter function public.protect_role_change() set search_path = pg_catalog, public, pg_temp;
alter function public.get_app_config(text) set search_path = pg_catalog, public, pg_temp;
alter function public.add_notification(uuid, text, text, bigint) set search_path = pg_catalog, public, pg_temp;
alter function public.notify_problem_author() set search_path = pg_catalog, public, pg_temp;
alter function public.notify_comment_replied() set search_path = pg_catalog, public, pg_temp;
alter function public.notify_comment_liked() set search_path = pg_catalog, public, pg_temp;
alter function public.notify_problem_liked() set search_path = pg_catalog, public, pg_temp;
alter function public.notify_due_soon() set search_path = pg_catalog, public, pg_temp;

revoke execute on function
  public.handle_new_user(),
  public.protect_role_change(),
  public.get_app_config(text),
  public.add_notification(uuid, text, text, bigint),
  public.notify_problem_author(),
  public.notify_comment_replied(),
  public.notify_comment_liked(),
  public.notify_problem_liked(),
  public.notify_due_soon()
from public, anon, authenticated;

-- Existing policies still limit reads and writes to the recipient's rows.
revoke update on public.notifications from public, anon, authenticated;
grant update (is_read) on public.notifications to authenticated;

alter view public.leaderboard set (security_invoker = true);
alter view public.checkin_board set (security_invoker = true);
revoke select on public.leaderboard, public.checkin_board from public, anon;
grant select on public.leaderboard, public.checkin_board to authenticated;

-- Only the author may edit their comment text or images. The author cannot
-- set a pin on insert, reassign the comment, or edit its creation time.
drop policy if exists "comments update" on public.comments;
create policy "comments update" on public.comments
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke insert, update on public.comments from public, anon, authenticated;
grant insert (problem_id, user_id, parent_id, content, images) on public.comments to authenticated;
grant update (content, images) on public.comments to authenticated;

create or replace function public.set_comment_pin(p_comment_id bigint, p_pinned boolean)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  pin_time timestamptz;
begin
  if caller_id is null or p_pinned is null then
    raise exception '无权置顶此评论' using errcode = '42501';
  end if;

  update public.comments as c
    set pinned_at = case when p_pinned then coalesce(c.pinned_at, now()) else null end
    where c.id = p_comment_id
      and (
        exists (select 1 from public.problems p where p.id = c.problem_id and p.user_id = caller_id)
        or exists (select 1 from public.profiles p where p.id = caller_id and p.role = 'admin')
      )
    returning c.pinned_at into pin_time;

  if not found then
    raise exception '无权置顶此评论' using errcode = '42501';
  end if;
  return pin_time;
end;
$$;

revoke execute on function public.set_comment_pin(bigint, boolean) from public, anon, authenticated;
grant execute on function public.set_comment_pin(bigint, boolean) to authenticated;

create index if not exists problems_created_at_id_idx on public.problems (created_at desc, id desc);

commit;
