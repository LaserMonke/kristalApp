# Applying the schema

Three files, and **order matters** — each builds on the last:

| # | File | Creates |
|---|------|---------|
| 1 | `migrations/20260730120000_phase6_init.sql` | `profiles`, `lesson_progress`, `streaks`, RLS policies, sign-up trigger, `username_available()` |
| 2 | `migrations/20260730130000_phase7_leaderboard.sql` | `leaderboard_bots`, `leaderboard_page()`, `leaderboard_standing()` |
| 3 | `migrations/20260801090000_phase7_lockdown.sql` | **Security fix.** Closes an exposure in file 2 — see below. Apply it. |

## File 3 is not optional

File 2 intended the leaderboard functions to require a signed-in caller and
wrote `revoke all on function ... from public` for each. That does nothing on a
Supabase project.

Supabase ships with `alter default privileges in schema public grant all on
functions to anon, authenticated, service_role`, so every new function in
`public` gets an **explicit** grant to `anon` when it is created. Revoking from
the pseudo-role `PUBLIC` does not remove an explicit grant to a named role, so
`anon` kept its EXECUTE and the revoke was theatre.

The effect, confirmed against a live project: anyone holding the publishable key
— which ships in every copy of the app — could call `leaderboard_page` **without
signing in** and read every learner's username, points and auth user id.
`leaderboard_scores`, commented as internal, was open the same way.

RLS was never protecting these. `SECURITY DEFINER` bypasses RLS deliberately;
that is the whole reason those functions exist. The grant was the only control,
and it had not been applied.

File 3 revokes from `anon` **by name**, adds an `auth.uid()` check inside each
function so a stray grant cannot re-expose them, and stops returning other
learners' user ids entirely — the client only ever needed its own, to highlight
"you" in the list.

**If you write another function in `public`, assume `anon` can call it** until
you have revoked from `anon` by name and verified it. Verification, with only
the publishable key:

    curl -s -X POST "$URL/rest/v1/rpc/leaderboard_page" \
      -H "apikey: $KEY" -H "Content-Type: application/json" \
      -d '{"period":"all_time"}'

Before file 3 this returned every learner. After it, it must return a `42501`
permission error.

Both are idempotent: re-running them is safe and is the normal way to pick up a change.

## Option A — dashboard (no tooling needed)

1. Supabase dashboard → **SQL Editor** → New query.
2. Paste the **whole** of file 1. Run it.
3. **Read the result.** Success looks like `Success. No rows returned`, possibly with a
   notice about the profile trigger (see below) — that notice is fine.
   If you get a red error, nothing was applied: the editor runs the file as one
   transaction, so a single failing statement rolls the whole thing back. Send me the error.
4. Repeat with file 2.

## Option B — Supabase CLI

    npx supabase link --project-ref ymwuxoxhftirherwytwh
    npx supabase db push

## Verifying it worked

Ask PostgREST what it can see — no tooling beyond curl, and the anon key is enough:

    KEY=<SUPABASE_PUBLISHABLE_KEY from .env>
    URL=https://ymwuxoxhftirherwytwh.supabase.co

    curl -s -o /dev/null -w '%{http_code}\n' "$URL/rest/v1/profiles?select=id&limit=1" -H "apikey: $KEY"

- `200` → applied, and RLS correctly returns an empty list to an unauthenticated caller.
- `404` → not applied (or applied to a different project).

## If a leaderboard already existed in your project

File 2 reconciles rather than assumes. `create table if not exists` does nothing when
`leaderboard_bots` is already there, so it also runs `add column if not exists` for the
columns the functions need, carries a plain `points` column across to `total_points` if it
finds one, and drops any legacy `public.leaderboard()` function (one seen in the wild was
granted to `anon`, which serves the whole board to anyone holding the publishable key without
signing in).

It ends by calling both functions for real, so a bad apply fails in the editor where you can
see it — look for `Leaderboard functions OK. N entries …` in the notices.

**Pre-seeded bots arrive switched OFF.** Any `leaderboard_bots` rows that predate the `active`
column are parked by the migration: they keep their scores, but they are invisible to the
board, to standings, and to the "of N on the board" count, so real learners are what you see.

    -- bring them all back
    update public.leaderboard_bots set active = true;

    -- park them again
    update public.leaderboard_bots set active = false;

    -- who is on the roster, and are they live?
    select username, total_points, weekly_points, active from public.leaderboard_bots
    order by total_points desc;

    -- gone for good
    delete from public.leaderboard_bots;

Re-running the migration never overrides a bot you deliberately switched back on — the
parking step is guarded on the `active` column not existing yet. A bot you INSERT later is
active by default, and shows up labelled `BOT` (CLAUDE.md rule 7).

## The one notice you might see

`Could not attach the profile trigger to auth.users (...)`

Harmless. Attaching a trigger to `auth.users` needs privileges the SQL-editor role does not
always have, so the attempt is wrapped in an exception handler — otherwise that single
statement would abort the whole migration and leave you with no tables at all. When the
trigger cannot be installed, the app creates the profile row itself on first sign-in
(`SupabaseAuthRepo._resolveUser`), which RLS permits because the learner is inserting their
own id.

## Dashboard settings that are NOT in these files

Authentication → Providers → Email:
- **Confirm email: OFF.** The app has no email address to confirm — accounts use an
  unroutable synthetic address derived from the username. With confirmation on, sign-up can
  never complete. See DEPLOY.md §1a.
- Minimum password length 6, matching `minPasswordLength` in
  `lib/data/supabase/account_identity.dart`.

## Bots

`leaderboard_bots` ships **empty**, and that is the intended state. CLAUDE.md rule 7 permits
bots to pad an early leaderboard only if they are labelled as bots, never presented as real
people — so if you ever seed a row here, the app renders a `BOT` chip from the flag the
leaderboard functions stamp on it. The table has RLS on and no policies at all, so nothing in
the client can read or write it directly.

An empty leaderboard is the truth about a new app. Invented rivals are not.
