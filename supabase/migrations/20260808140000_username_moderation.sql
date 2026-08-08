-- ---------------------------------------------------------------------------
-- Stock Options Academy — word rules for usernames, enforced in the database.
--
-- A username is the one piece of user-authored text this app shows to other
-- people: it sits on the leaderboard beside every learner and is printed on the
-- certificate. The Dart half (lib/core/moderation/username_words.dart) refuses
-- a bad one with a friendly message, but a modified client can skip every check
-- it makes. This is the half that cannot be skipped.
--
-- Terms live in a TABLE rather than in this function's body so the list can be
-- extended with an insert, without an app release. Keep it in step with the
-- Dart list — test/moderation/username_sql_parity_test.dart fails if they drift.
--
-- Existing rows are deliberately NOT re-checked. The trigger fires only when a
-- username is set or changed, so adding a term tomorrow cannot lock an existing
-- learner out of a row they already own; that is a moderation job for a person.
--
-- Idempotent: safe to re-run.
-- ---------------------------------------------------------------------------

create table if not exists public.blocked_username_terms (
  term text primary key,
  -- 'substring' — blocked anywhere in the name (terms that do not occur inside
  --               ordinary words).
  -- 'word'      — blocked only as a whole word, so `assess` survives `ass`.
  -- 'reserved'  — blocked as the whole name; impersonation of staff or of the
  --               labelled leaderboard bots (CLAUDE.md rule 7).
  -- 'allowed'   — a real word that contains a blocked term and is nobody's
  --               fault (the Scunthorpe problem). Beats the term lists when it
  --               is the whole name.
  kind text not null check (kind in ('substring', 'word', 'reserved', 'allowed')),
  added_at timestamptz not null default now()
);

comment on table public.blocked_username_terms is
  'Username word blocklist. Mirrors lib/core/moderation/username_words.dart.';

-- The list is not secret, but nothing outside the trigger needs to read it, and
-- publishing a slur list to every client is pointless. No policies are created,
-- so RLS denies everything to anon and authenticated; the trigger runs as
-- definer and is unaffected.
alter table public.blocked_username_terms enable row level security;

-- --------------------------------------------------------------------------
-- Normalisation, mirroring UsernameWords.normalise/collapseRuns in Dart.
-- --------------------------------------------------------------------------

-- Lowercase, undo leetspeak, then drop everything that is not a letter — so
-- `f.u.c.k` and `sh1t` reduce to what they actually say.
create or replace function public.username_flatten(candidate text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    translate(lower(coalesce(candidate, '')),
              '01!|34@5$7+89',
              'oiiieaassttbg'),
    '[^a-z]', '', 'g')
$$;

-- Runs of one letter squeezed to a single letter: `fuuuck` reads as `fuck`.
-- Applied to the candidate only, never to the terms — squeezing both sides
-- would turn `coon` into `con` and start matching innocent words.
create or replace function public.username_squeeze(candidate text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(coalesce(candidate, ''), '(.)\1+', '\1', 'g')
$$;

-- The name split into the words a reader would see: separators, digit runs and
-- camelCase humps all break it up, so `bigAss`, `big_ass` and `big2ass` each
-- yield `ass` while `assess` stays whole. Both readings of a digit are kept —
-- as a separator and as a stand-in letter — because guessing wrong either way
-- lets one through.
create or replace function public.username_words(candidate text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array_remove(
    array(
      select public.username_flatten(part)
      from unnest(
        regexp_split_to_array(
          regexp_replace(coalesce(candidate, ''), '([a-z])([A-Z])', '\1 \2', 'g'),
          '[^A-Za-z0-9!|@$+]+')
        || regexp_split_to_array(
          regexp_replace(coalesce(candidate, ''), '([a-z])([A-Z])', '\1 \2', 'g'),
          '[^A-Za-z]+')
      ) as part
    ),
    '')
$$;

-- --------------------------------------------------------------------------
-- The check itself. Returns the offending kind, or null when the name is fine.
-- --------------------------------------------------------------------------
create or replace function public.username_block_reason(candidate text)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  flat     text := public.username_flatten(candidate);
  squeezed text := public.username_squeeze(flat);
  parts    text[] := public.username_words(candidate);
  hit      text;
begin
  if flat = '' then
    return null;
  end if;

  select t.term into hit
  from public.blocked_username_terms t
  where t.kind = 'reserved'
    and (t.term = flat or t.term = squeezed)
  limit 1;
  if hit is not null then
    return 'reserved';
  end if;

  -- An exact known-innocent word beats the term lists. Checked after the
  -- reserved names so the exception list can never hand out a staff name.
  perform 1
  from public.blocked_username_terms t
  where t.kind = 'allowed' and t.term = flat;
  if found then
    return null;
  end if;

  select t.term into hit
  from public.blocked_username_terms t
  where t.kind = 'substring'
    and (position(t.term in flat) > 0 or position(t.term in squeezed) > 0)
  limit 1;
  if hit is not null then
    return 'blocked';
  end if;

  -- The squeezed form of a word only counts when the word was at least as long
  -- as the term, so `as` is not read as a squeezed `ass`.
  select t.term into hit
  from public.blocked_username_terms t
  cross join unnest(parts) as w(word)
  where t.kind = 'word'
    and (w.word = t.term
         or (length(w.word) >= length(t.term)
             and public.username_squeeze(w.word) = t.term))
  limit 1;
  if hit is not null then
    return 'blocked';
  end if;

  return null;
end;
$$;

-- --------------------------------------------------------------------------
-- Enforcement: on insert, and on any update that CHANGES the username.
-- --------------------------------------------------------------------------
create or replace function public.enforce_username_words()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  reason text;
begin
  if tg_op = 'UPDATE'
     and lower(btrim(new.username)) = lower(btrim(old.username)) then
    return new;
  end if;

  reason := public.username_block_reason(new.username);

  if reason = 'reserved' then
    raise exception 'That username is reserved. Please choose another.'
      using errcode = 'check_violation';
  elsif reason is not null then
    raise exception 'Please choose a different username — this one shows on the leaderboard for everyone.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_username_words on public.profiles;
create trigger profiles_username_words
  before insert or update of username on public.profiles
  for each row execute function public.enforce_username_words();

-- --------------------------------------------------------------------------
-- The list. Mirrors lib/core/moderation/username_words.dart — keep in step.
-- --------------------------------------------------------------------------
insert into public.blocked_username_terms (term, kind) values
  ('fuck', 'substring'),
  ('shit', 'substring'),
  ('cunt', 'substring'),
  ('bitch', 'substring'),
  ('whore', 'substring'),
  ('nigger', 'substring'),
  ('nigga', 'substring'),
  ('faggot', 'substring'),
  ('retard', 'substring'),
  ('kike', 'substring'),
  ('wetback', 'substring'),
  ('tranny', 'substring'),
  ('molest', 'substring'),
  ('pedo', 'substring'),
  ('rapist', 'substring'),
  ('nazi', 'substring'),
  ('hitler', 'substring'),
  ('incest', 'substring'),
  ('bestiality', 'substring'),
  ('goatse', 'substring'),
  ('kiddyfiddler', 'substring'),
  ('ass', 'word'),
  ('arse', 'word'),
  ('rape', 'word'),
  ('spic', 'word'),
  ('chink', 'word'),
  ('coon', 'word'),
  ('dyke', 'word'),
  ('fag', 'word'),
  ('homo', 'word'),
  ('slut', 'word'),
  ('dick', 'word'),
  ('cock', 'word'),
  ('prick', 'word'),
  ('wank', 'word'),
  ('twat', 'word'),
  ('bastard', 'word'),
  ('piss', 'word'),
  ('crap', 'word'),
  ('tits', 'word'),
  ('boob', 'word'),
  ('anal', 'word'),
  ('kkk', 'word'),
  ('kys', 'word'),
  ('admin', 'reserved'),
  ('administrator', 'reserved'),
  ('moderator', 'reserved'),
  ('mod', 'reserved'),
  ('staff', 'reserved'),
  ('team', 'reserved'),
  ('support', 'reserved'),
  ('help', 'reserved'),
  ('helpdesk', 'reserved'),
  ('official', 'reserved'),
  ('system', 'reserved'),
  ('root', 'reserved'),
  ('owner', 'reserved'),
  ('bot', 'reserved'),
  ('bots', 'reserved'),
  ('optionsschool', 'reserved'),
  ('stockoptionsacademy', 'reserved'),
  ('anonymous', 'reserved'),
  ('guest', 'reserved'),
  ('deleted', 'reserved'),
  ('null', 'reserved'),
  ('undefined', 'reserved'),
  ('everyone', 'reserved'),
  ('scunthorpe', 'allowed'),
  ('penistone', 'allowed'),
  ('clitheroe', 'allowed'),
  ('shiitake', 'allowed'),
  ('shitake', 'allowed'),
  ('cockfosters', 'allowed'),
  ('lightwater', 'allowed')
on conflict (term) do update set kind = excluded.kind;
