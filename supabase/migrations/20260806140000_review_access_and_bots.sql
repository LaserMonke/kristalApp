-- Store-review support: an account that can reach every gated feature, and a
-- bot roster so the leaderboard is demonstrable without exposing real learners.
--
-- Both halves are idempotent and safe to re-run.
--
-- ============================================================================
-- 1. UNLOCK THE REVIEW ACCOUNT
-- ============================================================================
-- Play requires that a reviewer can reach ALL functionality. This app gates
-- content on progression (lib/providers/lesson_providers.dart): a lesson is
-- locked until the previous one's Q&A is finished, and the Sandbox "Strategy"
-- tab stays locked until the `options-strategies` lesson is done. A fresh
-- reviewer account therefore sees locked screens and the review can fail.
--
-- This marks every lesson finished for one named account.
--
-- HONESTY NOTE (CLAUDE.md rule 7): `points_earned` is generated, so completing
-- the decks necessarily awards 20 points each — 180 in total — and the account
-- then appears on the leaderboard alongside real learners without having
-- earned it. That is a real wrinkle, not a clean outcome. The intended
-- lifecycle is: unlock for review, then remove the account afterwards via
-- Profile -> Delete account, which cascades these rows away. Re-run this file
-- if a later review needs it again.
--
-- correct_answers is left at 0 on purpose. Claiming a perfect score would be
-- fabricating a result; the reviewer only needs the content unlocked.

do $$
declare
  v_user uuid;
  v_lesson text;
  v_lessons text[] := array[
    'what-is-an-option',
    'payoff-at-expiry',
    'why-use-options',
    'black-scholes-price',
    'the-greeks',
    'options-strategies',
    'path-dependent-options',
    'volatility-is-not-constant',
    'structured-products'
  ];
begin
  -- The app derives an unroutable synthetic address from the username
  -- (see lib/data/supabase/account_identity.dart); there is no real mailbox.
  select id into v_user
  from auth.users
  where email = 'playreview@users.optionsschool.invalid';

  if v_user is null then
    raise notice 'Review account not found — sign up as "playreview" in the app first, then re-run.';
    return;
  end if;

  foreach v_lesson in array v_lessons loop
    insert into public.lesson_progress (
      user_id, lesson_id, cards_viewed,
      lesson_completed, quiz_completed,
      correct_answers, total_questions, quiz_attempts
    )
    values (v_user, v_lesson, 0, true, true, 0, 0, 1)
    on conflict (user_id, lesson_id) do update
      set lesson_completed = true,
          quiz_completed   = true,
          quiz_attempts    = greatest(public.lesson_progress.quiz_attempts, 1);
  end loop;

  raise notice 'Unlocked % lessons for the review account.', array_length(v_lessons, 1);
end $$;

-- ============================================================================
-- 2. SEED THE BOT ROSTER
-- ============================================================================
-- Seeded empty by the Phase 7 migration on purpose. Without any rows the
-- leaderboard shows only real accounts — which is why the Ranks screen could
-- not be screenshotted for the store listing without publishing real learners'
-- usernames to a public page.
--
-- Every row here reaches the client through leaderboard_page() /
-- leaderboard_standing(), which stamp is_bot = true on all of them. The
-- labelling is structural: the UI cannot forget to mark these, and they can
-- never be presented as real people (CLAUDE.md rule 7).
--
-- The names are deliberately not person-shaped. A bot called "Sarah" reads as
-- a human being even with a badge next to it; "Theta Decay" does not.

insert into public.leaderboard_bots (username, total_points, weekly_points, active)
select v.username, v.total_points, v.weekly_points, true
from (values
  ('Delta Hedger',    980, 240),
  ('Theta Decay',     845, 215),
  ('Vega Long',       720, 180),
  ('Gamma Scalper',   615, 155),
  ('Iron Condor',     540, 130),
  ('Covered Call',    430, 95),
  ('Strike Price',    310, 70),
  ('Break Even',      180, 40)
) as v(username, total_points, weekly_points)
where not exists (
  select 1 from public.leaderboard_bots b where b.username = v.username
);
