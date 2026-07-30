-- ============================================================================
-- OptionsSchool — Phase 6 schema: profiles, lesson progress, streaks.
--
-- Run with the Supabase CLI (`supabase db push`) so the schema is versioned in
-- git rather than clicked in by hand (DEPLOY.md §1c). Safe to re-run.
--
-- Design rules this file enforces, not just documents:
--   * Row Level Security is ON for every table here, and every policy is
--     `auth.uid() = <owner column>`. A learner can only ever see or write their
--     own rows.
--   * We collect the MINIMUM data (CLAUDE.md rule 6 — the audience may include
--     under-18 users): a username, a coarse education band, and learning
--     progress. No email address, no birthdate, no contact details. The
--     synthetic address Supabase Auth stores is derived from the username and
--     is never a real mailbox (see lib/data/supabase/supabase_auth_repo.dart).
--   * Points are a GENERATED column computed by Postgres from the same formula
--     as lib/engagement/points.dart, so the client cannot report its own score.
--     That is what makes the Phase 7 leaderboard honest (CLAUDE.md rule 7).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- profiles — one row per auth user
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  username        text not null,
  education_level text not null default 'other',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint profiles_username_length
    check (char_length(btrim(username)) between 3 and 24),

  -- Mirrors the EducationLevel enum names in
  -- lib/data/models/education_level.dart. Adding a band means adding it here.
  constraint profiles_education_level_known
    check (education_level in (
      'highSchool', 'undergraduate', 'postgraduate', 'earlyCareer', 'other'
    ))
);

-- Usernames are unique case-insensitively: "Alice" and "alice" are one person.
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(btrim(username)));

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "profiles: read own" on public.profiles;
create policy "profiles: read own"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "profiles: insert own" on public.profiles;
create policy "profiles: insert own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Deliberately NO delete policy: a profile disappears only when the auth user
-- is deleted, which cascades. Nothing in the client can orphan an account.


-- ---------------------------------------------------------------------------
-- lesson_progress — one row per (user, lesson)
-- ---------------------------------------------------------------------------

create table if not exists public.lesson_progress (
  user_id         uuid not null references auth.users (id) on delete cascade,
  lesson_id       text not null,

  cards_viewed    integer not null default 0,
  lesson_completed boolean not null default false,
  quiz_completed  boolean not null default false,
  correct_answers integer not null default 0,
  total_questions integer not null default 0,
  quiz_attempts   integer not null default 0,

  -- Server-computed, mirroring lib/engagement/points.dart:
  --   20 for finishing the card deck
  -- + 10 per correct Q&A answer (best attempt)
  -- + 15 bonus for a perfect Q&A
  -- Kept generated rather than client-supplied so a modified client cannot
  -- inflate its own score. If the Dart constants change, change them here too.
  points_earned   integer generated always as (
                    (case when lesson_completed then 20 else 0 end)
                    + (correct_answers * 10)
                    + (case
                         when total_questions > 0
                          and correct_answers = total_questions then 15
                         else 0
                       end)
                  ) stored,

  last_opened_at  timestamptz,
  completed_at    timestamptz,
  updated_at      timestamptz not null default now(),

  primary key (user_id, lesson_id),

  constraint lesson_progress_counts_sane check (
    cards_viewed >= 0
    and correct_answers >= 0
    and total_questions between 0 and 50
    and quiz_attempts >= 0
    -- A score can never exceed the number of questions asked. This is a floor,
    -- not real anti-cheat: the server does not yet know a lesson's true
    -- question count, so grading stays client-side until Phase 7 moves Q&A
    -- scoring server-side.
    and correct_answers <= total_questions
  )
);

drop trigger if exists lesson_progress_touch_updated_at on public.lesson_progress;
create trigger lesson_progress_touch_updated_at
  before update on public.lesson_progress
  for each row execute function public.touch_updated_at();

alter table public.lesson_progress enable row level security;

drop policy if exists "lesson_progress: read own" on public.lesson_progress;
create policy "lesson_progress: read own"
  on public.lesson_progress for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "lesson_progress: insert own" on public.lesson_progress;
create policy "lesson_progress: insert own"
  on public.lesson_progress for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "lesson_progress: update own" on public.lesson_progress;
create policy "lesson_progress: update own"
  on public.lesson_progress for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Settings → "reset progress" deletes the learner's own rows.
drop policy if exists "lesson_progress: delete own" on public.lesson_progress;
create policy "lesson_progress: delete own"
  on public.lesson_progress for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- streaks — one row per user
-- ---------------------------------------------------------------------------

create table if not exists public.streaks (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  current_streak     integer not null default 0,
  longest_streak     integer not null default 0,

  -- A streak is a human "did I learn today", so the active day is stored as a
  -- DATE in the learner's local reckoning — not a UTC timestamp.
  last_active_day    date,

  freeze_available   boolean not null default true,
  days_toward_freeze integer not null default 0,
  updated_at         timestamptz not null default now(),

  constraint streaks_counts_sane check (
    current_streak >= 0
    and longest_streak >= current_streak
    and days_toward_freeze between 0 and 7
  )
);

drop trigger if exists streaks_touch_updated_at on public.streaks;
create trigger streaks_touch_updated_at
  before update on public.streaks
  for each row execute function public.touch_updated_at();

alter table public.streaks enable row level security;

drop policy if exists "streaks: read own" on public.streaks;
create policy "streaks: read own"
  on public.streaks for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "streaks: insert own" on public.streaks;
create policy "streaks: insert own"
  on public.streaks for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "streaks: update own" on public.streaks;
create policy "streaks: update own"
  on public.streaks for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "streaks: delete own" on public.streaks;
create policy "streaks: delete own"
  on public.streaks for delete
  to authenticated
  using (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- Sign-up: create the profile from auth metadata
-- ---------------------------------------------------------------------------
-- A trigger on auth.users is the nicest place for this: the profile then exists
-- even if the app is killed the instant after sign-up. SECURITY DEFINER because
-- the row is written before the new user has a session to satisfy RLS with.
--
-- BUT it is only an optimisation, and attaching a trigger to auth.users needs
-- privileges that the SQL-editor role does not always have. On projects where
-- it is refused, an unguarded CREATE TRIGGER aborts the whole migration and
-- NOTHING above this point gets created — so the attempt is wrapped and the
-- failure downgraded to a notice.
--
-- The client covers the same ground either way: SupabaseAuthRepo._resolveUser
-- upserts the profile from the session's own metadata when no row is found, and
-- RLS allows that because the learner is inserting their own id.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, education_level)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'username'), ''),
      'learner-' || left(new.id::text, 8)
    ),
    coalesce(nullif(new.raw_user_meta_data ->> 'education_level', ''), 'other')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

do $$
begin
  execute 'drop trigger if exists on_auth_user_created on auth.users';
  execute '
    create trigger on_auth_user_created
      after insert on auth.users
      for each row execute function public.handle_new_user()';
  raise notice 'Profile trigger installed on auth.users.';
exception
  when insufficient_privilege or undefined_table then
    raise notice
      'Could not attach the profile trigger to auth.users (%). This is fine: '
      'the app creates the profile row itself on first sign-in.', sqlerrm;
end;
$$;


-- ---------------------------------------------------------------------------
-- username_available — pre-flight check so sign-up can fail politely
-- ---------------------------------------------------------------------------
-- Without this, a taken username surfaces as a raw database error from the
-- unique index inside the sign-up trigger. Usernames are public on the
-- leaderboard anyway, so answering "is this name free" leaks nothing; Supabase
-- rate-limits the endpoint.

create or replace function public.username_available(candidate text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select not exists (
    select 1
    from public.profiles p
    where lower(btrim(p.username)) = lower(btrim(candidate))
  );
$$;

revoke all on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;
