-- ============================================================================
-- OptionsSchool — lock the leaderboard functions to signed-in learners.
--
-- Safe to re-run. Fixes a real exposure introduced by the Phase 7 migration.
--
-- WHAT WENT WRONG
-- The Phase 7 file said the leaderboard functions "require authenticated" and
-- wrote, for each of them:
--
--     revoke all on function public.leaderboard_page(text, integer) from public;
--     grant execute on function public.leaderboard_page(text, integer) to authenticated;
--
-- That looks right and does nothing. Supabase projects ship with
--
--     alter default privileges in schema public
--       grant all on functions to anon, authenticated, service_role;
--
-- so every newly created function in `public` receives an EXPLICIT grant to
-- the `anon` role at creation time. `revoke ... from PUBLIC` removes the
-- implicit grant to the pseudo-role PUBLIC; it does not touch an explicit
-- grant to a named role. The revoke therefore removed nothing that mattered
-- and `anon` kept its EXECUTE.
--
-- The consequence, verified against the live project before writing this:
-- anyone holding the publishable key — which ships inside every copy of the
-- app and is trivially extracted — could call `leaderboard_page` WITHOUT
-- SIGNING IN and receive every learner's username, point total and auth user
-- id. `leaderboard_scores`, commented in Phase 7 as "INTERNAL: clients never
-- reach it directly", was exposed the same way.
--
-- This is exactly the flaw Phase 7 called out in the legacy `leaderboard()`
-- function it dropped ("granted to anon, which serves the whole board to
-- anyone holding the publishable key"). It reproduced it.
--
-- Row Level Security was never the thing protecting these: SECURITY DEFINER
-- functions bypass RLS by design, which is the whole reason they exist here.
-- The grant WAS the control, and the grant was not applied.
--
-- WHAT THIS FILE DOES
-- 1. Revokes EXECUTE from `anon` by name, not just from PUBLIC.
-- 2. Adds an auth.uid() check INSIDE each function, so a future stray grant —
--    or simply creating a new function under those same default privileges —
--    cannot re-expose the data. Grants are now the second line of defence
--    rather than the only one.
-- 3. Stops returning other learners' auth user ids at all. The client only
--    ever needed to know which row is its own, so the caller's own id comes
--    back and everyone else's is null (CLAUDE.md rule 6 — collect and
--    transmit the minimum; the audience may include minors).
-- ============================================================================


-- ---------------------------------------------------------------------------
-- leaderboard_page — the visible ranking
-- ---------------------------------------------------------------------------
-- Now plpgsql rather than sql, purely so it can refuse to answer an
-- unauthenticated caller instead of quietly returning rows.
--
-- `#variable_conflict use_column` is required: RETURNS TABLE turns `rank`,
-- `points` and the rest into plpgsql variables, which would otherwise shadow
-- the identically named columns in the query below.

create or replace function public.leaderboard_page(
  period text default 'all_time',
  limit_count integer default 50
)
returns table (
  rank     bigint,
  user_id  uuid,
  username text,
  points   integer,
  is_bot   boolean
)
language plpgsql
security definer
set search_path = ''
stable
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Standings are only available to signed-in learners.'
      using errcode = '42501';
  end if;

  return query
  with ranked as (
    select
      rank() over (order by s.points desc, lower(s.username) asc) as rank,
      s.user_id,
      s.username,
      s.points,
      s.is_bot
    from public.leaderboard_scores(period) s
  )
  select
    r.rank,
    -- Only ever the caller's own id. Everyone else's is withheld, which is
    -- all the client ever needed to highlight "you" in the list.
    case when r.user_id = auth.uid() then r.user_id else null end,
    r.username,
    r.points,
    r.is_bot
  from ranked r
  order by r.rank, lower(r.username)
  limit least(greatest(coalesce(limit_count, 50), 1), 200);
end;
$$;


-- ---------------------------------------------------------------------------
-- leaderboard_standing — where the CALLER sits
-- ---------------------------------------------------------------------------
-- Already keyed on auth.uid(), so an anonymous caller got an empty result
-- rather than someone else's rank. The guard is added anyway: "returns
-- nothing useful" and "refuses to run" are different security properties, and
-- only the second one survives a future edit that adds a fallback.

create or replace function public.leaderboard_standing(period text default 'all_time')
returns table (
  rank          bigint,
  points        integer,
  total_players bigint
)
language plpgsql
security definer
set search_path = ''
stable
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Standings are only available to signed-in learners.'
      using errcode = '42501';
  end if;

  return query
  with scores as (
    select * from public.leaderboard_scores(period)
  ),
  ranked as (
    select
      rank() over (order by s.points desc, lower(s.username) asc) as rank,
      s.user_id,
      s.points
    from scores s
  )
  select r.rank, r.points, (select count(*) from scores)
  from ranked r
  where r.user_id = auth.uid();
end;
$$;


-- ---------------------------------------------------------------------------
-- Grants — this time naming the roles that actually hold them
-- ---------------------------------------------------------------------------
-- Ordering matters: `create or replace function` PRESERVES the existing ACL,
-- so revoking before replacing would have been undone. Revoke after.
--
-- `anon` and `authenticated` are named explicitly. Revoking from PUBLIC is
-- kept as well, for a project that does not carry Supabase's default
-- privileges.

-- The internal helper: not for clients at all. The two functions above are
-- SECURITY DEFINER, so they run as the owner and can still reach it.
revoke all on function public.leaderboard_scores(text) from public;
revoke all on function public.leaderboard_scores(text) from anon;
revoke all on function public.leaderboard_scores(text) from authenticated;

revoke all on function public.leaderboard_page(text, integer) from public;
revoke all on function public.leaderboard_page(text, integer) from anon;
grant execute on function public.leaderboard_page(text, integer) to authenticated;

revoke all on function public.leaderboard_standing(text) from public;
revoke all on function public.leaderboard_standing(text) from anon;
grant execute on function public.leaderboard_standing(text) to authenticated;


-- ---------------------------------------------------------------------------
-- Self-test
-- ---------------------------------------------------------------------------
-- Runs as the migration role, where auth.uid() is null — so the guard must
-- FIRE. A migration that silently failed to apply the fix is the thing worth
-- catching here, since the symptom otherwise is invisible until someone
-- thinks to probe the endpoint with a publishable key.

do $$
declare
  blocked boolean := false;
begin
  begin
    perform * from public.leaderboard_page('all_time', 5);
  exception
    when insufficient_privilege then blocked := true;
  end;

  if not blocked then
    raise exception
      'leaderboard_page still answers an unauthenticated caller. The lockdown '
      'did not apply — do not treat this migration as successful.';
  end if;

  blocked := false;
  begin
    perform * from public.leaderboard_standing('all_time');
  exception
    when insufficient_privilege then blocked := true;
  end;

  if not blocked then
    raise exception 'leaderboard_standing still answers an unauthenticated caller.';
  end if;

  raise notice
    'Leaderboard locked down: both functions now refuse callers without a '
    'session, anon holds no EXECUTE, and only the caller''s own user id is '
    'ever returned.';
end;
$$;
