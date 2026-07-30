-- ============================================================================
-- OptionsSchool — Phase 7: leaderboard (real learners + clearly labelled bots).
--
-- Safe to re-run. Depends on the Phase 6 migration.
--
-- THE HONESTY PROBLEM THIS SOLVES (CLAUDE.md rule 7)
-- A leaderboard has to read OTHER people's scores, but Phase 6 deliberately
-- locked every table to `auth.uid() = owner`. Loosening those policies to let
-- learners read each other's rows would expose whole profile and progress rows
-- for the sake of two numbers.
--
-- So access goes through SECURITY DEFINER functions instead. They run as the
-- owner (bypassing RLS by design) but return ONLY what a leaderboard needs —
-- a display name, a point total, and whether the entry is a bot. Nothing can
-- ask them for anything else, and the underlying tables stay locked.
--
-- Points come from `lesson_progress.points_earned`, which Postgres generates
-- itself (Phase 6), so a modified client cannot inflate its own ranking.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- Bots: seeded EMPTY on purpose
-- ---------------------------------------------------------------------------
-- Rule 7 allows bots to pad an early leaderboard, but only if they are labelled
-- as bots and never presented as real people. This table exists so that if you
-- ever do seed it, labelling is structural rather than something the UI has to
-- remember: every row here surfaces with is_bot = true, and the app renders a
-- "BOT" chip from that flag.
--
-- Shipping zero bots is the honest default. An empty leaderboard is the truth
-- about a new app; invented rivals are not.

create table if not exists public.leaderboard_bots (
  id            uuid primary key default gen_random_uuid(),
  username      text not null,
  total_points  integer not null default 0,
  weekly_points integer not null default 0,
  created_at    timestamptz not null default now(),

  constraint leaderboard_bots_points_sane check (
    total_points >= 0
    and weekly_points >= 0
    -- A bot cannot have earned more this week than in its whole existence.
    and weekly_points <= total_points
  )
);

alter table public.leaderboard_bots enable row level security;

-- Deliberately NO policies: with RLS on and no policy, neither `anon` nor
-- `authenticated` can read or write this table directly. The only way these
-- rows reach a client is through the functions below, which always stamp
-- is_bot = true.


-- ---------------------------------------------------------------------------
-- leaderboard_scores — the shared, unranked score set (INTERNAL)
-- ---------------------------------------------------------------------------
-- `period` is 'week' or anything else for all-time.
--
-- WEEKLY IS DEFINED AS: points from lessons FIRST FINISHED since the start of
-- this week. `completed_at` is written once and never moved, so re-reading old
-- cards cannot recycle points into a new week. The week boundary is Monday
-- 00:00 in the database's timezone (UTC on Supabase) — the UI says so rather
-- than implying it follows the learner's own clock.

create or replace function public.leaderboard_scores(period text)
returns table (
  user_id  uuid,
  username text,
  points   integer,
  is_bot   boolean
)
language sql
security definer
set search_path = ''
stable
as $$
  with params as (
    select (period = 'week') as weekly
  ),
  learners as (
    select
      p.id as user_id,
      p.username,
      coalesce(sum(lp.points_earned), 0)::integer as all_time_points,
      coalesce(
        sum(lp.points_earned) filter (
          where lp.completed_at >= date_trunc('week', now())
        ),
        0
      )::integer as weekly_points
    from public.profiles p
    left join public.lesson_progress lp on lp.user_id = p.id
    group by p.id, p.username
  )
  select
    l.user_id,
    l.username,
    case when params.weekly then l.weekly_points else l.all_time_points end,
    false
  from learners l cross join params
  union all
  select
    b.id,
    b.username,
    case when params.weekly then b.weekly_points else b.total_points end,
    true
  from public.leaderboard_bots b cross join params;
$$;

-- Internal helper: only the two functions below (which run as the owner) may
-- call it. Clients never reach it directly.
revoke all on function public.leaderboard_scores(text) from public;


-- ---------------------------------------------------------------------------
-- leaderboard_page — the visible ranking
-- ---------------------------------------------------------------------------
-- Ties share a rank (`rank()`, not `row_number()`): two learners on 140 points
-- are both 4th, and the next is 6th. Reporting one of them as ahead of the
-- other would be a fiction.
--
-- `limit_count` is clamped server-side so a client cannot ask for the whole
-- user table one page at a time.

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
language sql
security definer
set search_path = ''
stable
as $$
  with ranked as (
    select
      rank() over (order by s.points desc, lower(s.username) asc) as rank,
      s.user_id,
      s.username,
      s.points,
      s.is_bot
    from public.leaderboard_scores(period) s
  )
  select r.rank, r.user_id, r.username, r.points, r.is_bot
  from ranked r
  order by r.rank, lower(r.username)
  limit least(greatest(coalesce(limit_count, 50), 1), 200);
$$;

revoke all on function public.leaderboard_page(text, integer) from public;
grant execute on function public.leaderboard_page(text, integer) to authenticated;


-- ---------------------------------------------------------------------------
-- leaderboard_standing — where the CALLER sits, even if off the visible page
-- ---------------------------------------------------------------------------
-- Keyed on auth.uid(), so it can only ever report your own rank. Returns no
-- row when the caller has no profile yet.

create or replace function public.leaderboard_standing(period text default 'all_time')
returns table (
  rank          bigint,
  points        integer,
  total_players bigint
)
language sql
security definer
set search_path = ''
stable
as $$
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
$$;

revoke all on function public.leaderboard_standing(text) from public;
grant execute on function public.leaderboard_standing(text) to authenticated;
