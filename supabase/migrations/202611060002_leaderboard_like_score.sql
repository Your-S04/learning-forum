begin;

-- score changes from bigint to numeric, so the view must be recreated.
drop view public.leaderboard;

create view public.leaderboard with (security_invoker = true) as
select p.id, p.username,
  (select count(*) from public.problems where user_id = p.id) * 3 +
  (select count(*) from public.comments where user_id = p.id) +
  (select count(*) from public.problem_likes pl join public.problems pr on pr.id = pl.problem_id
     where pr.user_id = p.id) * 0.5 +
  (select count(*) from public.comment_likes cl join public.comments c on c.id = cl.comment_id
     where c.user_id = p.id) * 0.5 +
  (select count(*) from public.comments where user_id = p.id and pinned_at is not null) * 2
  as score
from public.profiles p
where p.student_no <> 'admin'
order by score desc;

revoke select on public.leaderboard from public, anon;
grant select on public.leaderboard to authenticated;

commit;
