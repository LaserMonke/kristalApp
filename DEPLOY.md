# Stock Options Academy — Server & Deployment Guide

Covers the SERVER/INFRASTRUCTURE side: Supabase (your baseline backend) and, for when you
outgrow it, the classic cloud architecture (load balancer, databases, dedicated compute).
Plus how to connect the client and ship test builds.

Guiding principle: DON'T over-build. For a student-education app, Supabase alone is very
likely your entire backend for a long time. The load-balanced server fleet is a "when you
actually need heavy custom compute or large scale" upgrade — included here so you know the
path, not because you need it on day one.

════════════════════════════════════════════════════════════════════════════════
1. BASELINE BACKEND — SUPABASE (start here; usually all you need)
════════════════════════════════════════════════════════════════════════════════
Supabase gives you, as managed services, everything this app needs:
- Auth              → username/password login, sessions (used by AuthRepo)
- Postgres database → profiles, lesson progress, points, streaks, leaderboard
- Row Level Security→ each user can only read/write their own rows
- Storage           → images/assets if needed
- Edge Functions    → server-side code: paid data-API proxy, heavy pricing offload
- Realtime          → live leaderboard / practice-market updates

### 1a. Create the project
1. Create a project at the Supabase dashboard. Pick a region close to your users.
2. Copy the Project URL and the publishable/anon key (Project Settings → API). These go in
   the client .env as SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (safe to ship WITH RLS on).
   Copy `.env.example` → `.env` and fill both in. `.env` is gitignored; it is bundled as a
   Flutter asset (see pubspec.yaml) and read by `lib/core/config/supabase_config.dart`, which
   REFUSES to start if the value looks like a service_role key.
3. Keep the service_role key SECRET — server-side only, never in the app.
4. Auth settings that this client depends on (Authentication → Providers → Email):
   - **Turn "Confirm email" OFF.** The app collects no email address (CLAUDE.md rule 6 — the
     audience may include minors). Each account gets an unroutable synthetic address derived
     from the username (`<username>@users.optionsschool.invalid`, RFC 2606). There is no
     mailbox, so a confirmation mail can never be answered and sign-up would hang forever.
     `SupabaseAuthRepo.signUp` detects this misconfiguration and says so explicitly.
   - Leave email/password sign-in ENABLED; no other provider is used.
   - Password rules: minimum length 6, and "Password Requirements" set to letters AND
     digits. This is mirrored by `PasswordRule` in
     `lib/data/supabase/account_identity.dart`, which the sign-up form, `LocalAuthRepo` and
     `SupabaseAuthRepo` all defer to. CHANGE THEM TOGETHER.
     Why it matters: the server can only refuse a password after a round trip, and it
     refuses with an error rather than with guidance — so a project rule stricter than
     `PasswordRule` reappears to the learner as "couldn't create the account" with no
     mention of what was wrong. `PasswordRule.describe` is shown under the field while the
     password is being chosen, which is the only place the rule is any use.
     Note the rule is NOT applied when signing in: accounts made under an older rule still
     have to be able to get in.
   - Enable "leaked password protection" (HaveIBeenPwned check) if your plan offers it.
   - CONSEQUENCE OF NO EMAIL: there is no password reset. The sign-in screen says so plainly
     rather than implying recovery exists. If you later decide recovery matters more than
     collecting no contact details, that is a product decision with privacy obligations
     attached — don't add an email field without revisiting rule 6 and the privacy policy.

### 1b. Database schema
The schema lives in git, one file per phase, applied in order:

    supabase/migrations/20260730120000_phase6_init.sql       <- accounts + progress
    supabase/migrations/20260730130000_phase7_leaderboard.sql <- rankings

**`supabase/README.md` has the step-by-step, plus how to verify it landed and the one
harmless notice to expect.** Both files are idempotent, so re-running is safe.

- CLI (preferred, keeps environments in step):
  `supabase link --project-ref <ref>` then `supabase db push`
- Dashboard: paste each file into the SQL editor and run it. Note that the editor runs a
  file as ONE transaction — a single failing statement rolls back the whole thing and leaves
  you with nothing, so read the result rather than assuming success.

Phase 6 creates:
- `profiles(id → auth.users, username, education_level, created_at, updated_at)`, with a
  case-insensitive unique index on the username so "Alice" and "alice" are one person.
- `lesson_progress(user_id, lesson_id, …)`, primary key `(user_id, lesson_id)`.
- `streaks(user_id, current_streak, longest_streak, last_active_day, …)`.
- `handle_new_user()` trigger on `auth.users` — writes the profile row from the sign-up
  metadata, so a profile always exists even if the app dies mid-sign-up.
- `username_available(candidate)` — lets sign-up fail with "that username is taken" instead
  of a raw unique-index error from inside the trigger.

Two decisions worth knowing about:
- **RLS is on for all three tables**, every policy is `auth.uid() = <owner>`, and `profiles`
  deliberately has NO delete policy (rows go only when the auth user is deleted, which
  cascades). Never add a user table without RLS.
- **`lesson_progress.points_earned` is a GENERATED column**, computed by Postgres from the
  same formula as `lib/engagement/points.dart` (20 per finished deck + 10 per correct answer
  + 15 for a perfect Q&A). The client never sends it, so a modified client cannot report its
  own score — that is what will make the Phase 7 leaderboard honest (CLAUDE.md rule 7). If
  the Dart constants change, change the SQL in the same commit.
  Not yet solved: the server does not know a lesson's true question count, so
  `correct_answers` is still client-asserted (bounded by `correct_answers <= total_questions`).
  Moving Q&A grading server-side belongs with Phase 7.

Phase 7 adds, in its own file:
- `leaderboard_bots` — seeded EMPTY on purpose. RLS on with NO policies, so nothing in the
  client can read or write it directly; rows reach the app only through the functions below,
  which stamp `is_bot = true` on every one of them. Labelling is therefore structural rather
  than something the UI has to remember (CLAUDE.md rule 7).
- `leaderboard_page(period, limit_count)` and `leaderboard_standing(period)` — the only
  cross-user reads in the app. Both are SECURITY DEFINER, so they see past RLS by design, but
  they return only a display name, a point total and the bot flag. The alternative — relaxing
  the RLS policies so learners can read each other's rows — would have exposed whole profile
  and progress rows for the sake of two numbers.
- Weekly is defined as points from lessons FIRST finished since `date_trunc('week', now())`,
  i.e. Monday 00:00 UTC. `completed_at` is written once and never moved, so re-reading old
  cards cannot recycle points into a new week. The UI states the UTC rule rather than
  implying it follows the learner's own clock.
- Ties share a rank (`rank()`, not `row_number()`).

### 1c. Migrations & environments
- Use the Supabase CLI (`supabase init`, `supabase db diff`, `supabase db push`) so schema
  changes are versioned in git, not clicked in by hand.
- Run THREE separate Supabase projects: dev, staging, prod. Never test against prod data.
- Store each environment's keys in its own .env (dev/staging/prod); none committed to git.

### 1d. Edge Functions (your server-side logic)
Deploy with `supabase functions deploy <name>`. Use them for:
- market-data-proxy: calls the PAID finance API using a key stored in Supabase secrets
  (`supabase secrets set DATA_API_KEY=...`), returns only what the client needs, and lets you
  cache + rate-limit. The key NEVER ships in the app.
- price-heavy: optional endpoint for very large Monte Carlo/Heston runs if on-device isolates
  aren't enough. Returns results the client displays with a loading state.

════════════════════════════════════════════════════════════════════════════════
2. SCALE-UP ARCHITECTURE (load balancer, databases, cloud) — only when needed
════════════════════════════════════════════════════════════════════════════════
Reach for this when you hit real limits: pricing compute too heavy/frequent for Edge
Functions, a high-throughput real-time market engine, or large concurrent user counts.

Reference architecture:

    [ iOS / Android app ]
             │  HTTPS
             ▼
    [ Load Balancer ]  ← TLS termination, health checks, autoscaling front door
             │
      ┌──────┴───────┐
      ▼              ▼
 [ App/API   ]   [ Pricing/Compute ]     ← stateless containers, scale horizontally
 [ servers   ]   [ workers          ]
      │              │
      ▼              ▼
 [ Postgres (managed) ]   [ Cache: Redis ]   [ Queue for heavy jobs ]
   primary + read replica    hot data          (Monte Carlo batches)

Component notes:
- LOAD BALANCER: distributes traffic across multiple server instances, terminates HTTPS/TLS,
  runs health checks, and enables zero-downtime deploys + autoscaling. (Cloud LB, AWS ALB,
  GCP HTTPS LB, etc.)
- APP/API SERVERS: stateless containers (Docker) behind the LB so you can add/remove copies
  freely. Keep them stateless — session/state lives in the DB/cache, not on the box.
- PRICING/COMPUTE WORKERS: separate service for CPU-heavy Monte Carlo/Heston, pulled from a
  QUEUE so a spike in pricing requests never takes down the API. Scale these independently.
- DATABASE: managed Postgres. Supabase's Postgres can remain your DB; if you move off, use a
  managed Postgres (Cloud SQL / RDS). Add a READ REPLICA for read-heavy screens (leaderboard),
  and use CONNECTION POOLING (Supabase pooler / PgBouncer) so many app instances don't exhaust
  DB connections. Enable automated backups + point-in-time recovery.
- CACHE (Redis): cache market-data responses and leaderboard reads to cut DB/API load.
- QUEUE: for batching/deferring heavy pricing jobs; workers consume and write results back.

Where to host (pick by how much ops you want):
- Lowest ops:  Google Cloud Run / Fly.io / Render — containers with built-in LB + autoscale.
- More control: AWS ECS/Fargate or Kubernetes (GKE/EKS) behind a cloud load balancer.
Start with the lowest-ops option; graduate only if you must.

Cost reality: Supabase-only can run on free/low tiers early. The moment you add a load
balancer + always-on servers + replicas + Redis, you're into steady monthly cost — don't
turn these on until traffic or compute genuinely requires them.

════════════════════════════════════════════════════════════════════════════════
3. SECURITY & COMPLIANCE (do these regardless of scale)
════════════════════════════════════════════════════════════════════════════════
- HTTPS/TLS everywhere (LB terminates it); never plain HTTP.
- Secrets (data API key, service_role key) in a secret manager / Supabase secrets — NEVER in
  the client binary or git.
- RLS on every user table; least-privilege DB roles.
- Rate-limit the market-data proxy and auth endpoints.
- Automated DB backups + a tested restore procedure.
- Privacy: publish a privacy policy (required by app stores). Collect minimum data. Some users
  may be under 18 — honor COPPA/GDPR-K obligations and keep options content strictly
  educational (no profit promises), per CLAUDE.md.
- Keep the "educational simulation, not financial advice" and delayed-data labels server-side
  too where responses are generated.

════════════════════════════════════════════════════════════════════════════════
4. CONNECTING THE CLIENT (Phase 6 of BUILD_PROMPTS)
════════════════════════════════════════════════════════════════════════════════
DONE in Phase 6 — this section is now a description of what is wired, not a to-do list.

1. Create dev Supabase project, apply `supabase/migrations/` (§1b), confirm RLS is on, and
   turn "Confirm email" OFF (§1a).
2. Put SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY in the client dev `.env`.
3. `main()` calls `Supabase.initialize` only if `.env` supplies a project, then overrides
   `supabaseClientProvider`. A null client (blank .env, failed init, any widget test) leaves
   the app on the Part A on-device repositories — degraded, never broken.
4. The swap itself is `lib/providers/repository_providers.dart` and nowhere else:
   | interface     | no backend          | backend configured      |
   |---------------|---------------------|-------------------------|
   | `AuthRepo`    | `LocalAuthRepo`     | `SupabaseAuthRepo`      |
   | `ProfileRepo` | `LocalProfileRepo`  | `SupabaseProfileRepo`   |
   | `ProgressRepo`| `LocalProgressRepo` | `SupabaseProgressRepo`  |
   No screen, controller or test above that file knows which it got.
5. Offline behaviour (`SupabaseProgressRepo`): every write hits the local cache FIRST, then
   the server; a write that fails for NETWORK reasons is queued and retried on the next
   successful round trip, and the queue is flushed before any read so a stale server row can
   never overwrite fresher local work. A non-network rejection (RLS, constraint) is thrown,
   not queued — hiding it would bury a bug. Conflicts are last-write-wins; progress is close
   to monotonic so nothing valuable is destroyed, but this is not a general sync engine.
6. Android: `INTERNET` is declared in `android/app/src/main/AndroidManifest.xml`. The Flutter
   template only grants it for debug/profile, so without that line a RELEASE build silently
   has no network. iOS needs nothing (no deep links; `detectSessionInUri: false`).
7. Phase 7 adds `LeaderboardRepo` to the same table: `SupabaseLeaderboardRepo` when a backend
   is configured, `LocalLeaderboardRepo` otherwise. The local one returns a board of exactly
   one — the learner — and the screen explains that standings need a server rather than
   implying nobody else is learning. Rankings are deliberately NOT cached offline: a stale
   ranking shown as current would be a false claim about other people's scores.
8. Phase 8 adds the `price-heavy` Edge Function (see §1d and
   `supabase/functions/price-heavy/README.md`). It is an OPTIMISATION, NEVER A DEPENDENCY:
   `AdvancedPricer` runs jobs inline below ~200k random draws, on a `compute()` isolate up to
   ~20M, and only offers anything larger to the server — falling back to an isolate if the
   call fails, since the same pure-Dart engine is already on the device. The app is fully
   functional with the function never deployed.
   Two things to know before deploying it. (a) It re-implements the path generator in
   TypeScript, and the two engines are held together by `vectors.json` — reference prices
   generated from the DART engine, which `engine.test.ts` checks bit-for-bit. Regenerate and
   re-run that test after touching anything in `lib/pricing/`; if they disagree, the Dart
   wins. (b) It requires a real session, because the publishable key ships in every copy of
   the app and would otherwise make the project free compute. Requests carry only a
   contract's numbers — no id, no username, nothing stored, and the success log deliberately
   omits the request body.
9. Phase 9 (part 1 — practice market) is BUILT. The `market-data-proxy` Edge Function is
   deployed and its secret is set (`supabase secrets set FINNHUB_API_KEY=…`, provider:
   Finnhub `/quote`). It proxies an allow-listed set of symbols, attaches the "delayed /
   learning simulation only" label SERVER-SIDE, and is the ONLY place the Finnhub key exists
   — never the app binary (rule 8). The client (`MarketRepo` → `SupabaseMarketRepo`) calls it
   and falls back to a labelled synthetic walk (`LocalMarketRepo`) when the function is
   unreachable, so the Market tab (Sandbox → Market) works offline too. The fake-money
   portfolio is device-local (`PortfolioRepo`); fills are idealised — last price, no spread,
   no fees — and labelled as such. Shares only for now; option-contract trading (priced with
   the Phase 8 BSM engine) is the natural next increment.

   PHASE 9b — PAYWALL: REMOVED, 6 August 2026. The app is free in full.

   The paywall was built (RevenueCat-shaped `EntitlementRepo`, `PaywallView`, a stub that
   started unlocked) but never wired to a store product. That plan was dropped before
   launch, and the code came out with it: `entitlement_repo.dart`,
   `local_entitlement_repo.dart`, `entitlement.dart`, `entitlement_providers.dart`,
   `paywall_view.dart`, `marketUnlockedProvider` and `paywall_test.dart` are all gone.
   `MarketView` now renders the market directly, with nothing to check first.

   What this removes from the launch path, which is most of the reason it is worth stating:
     - No payments/merchant profile, no Paid Applications Agreement, no banking or tax setup.
     - No store products to create, and no RevenueCat account, keys or server notifications.
     - No sandbox purchase testing on real devices.
     - No "minors and purchases" review under rule 6, and no purchase-pressure question
       under rule 9. Nothing is being sold to anyone, of any age.
     - Play: "contains in-app purchases" stays UNTICKED, Data safety declares no purchase
       history, and the content rating says no digital goods are sold. See PLAY_LISTING.md.

   Reintroducing it is a product decision, not a refactor. It would need new Data safety
   declarations, a privacy-policy revision naming the payment processor as a third party,
   and a change to a Play listing already published as free — so ask before rebuilding it.

   The Apple track is unaffected and still costs $99/yr if you want iOS, but note it needs
   macOS and this repo's owner is on Windows: budget for a Mac or cloud-Mac CI (Codemagic).
   Google Play remains $25 one-time, and a personal account still needs 12 testers opted in
   for 14 consecutive days on a closed test before production. That is the longest lead
   time in the whole launch — start it first.
10. DONE: the privacy policy is published and its URL is filed with Play (August 2026).
    PRIVACY.md in this repo is the source text — edit it here, then re-publish the hosted
    copy, or the two drift and the published one is the one that counts. Settings → "Data
    we collect" discloses the leaderboard visibility in-app; the policy is not linked from
    there, which is allowed (Play wants it on the listing) but would be worth adding.
    §7 states a 3+ content rating and a 13+ account floor (decided 8 August 2026) — the
    Play "target audience" answer must stay 13+ to match. See PLAY_LISTING.md.
    Worth deciding before release: whether learners can opt out of appearing on the
    leaderboard. Not built, because it was not asked for — but the audience may include
    under-18 users (CLAUDE.md rule 6), and "my username is visible to strangers" is the kind
    of default that deserves a deliberate decision rather than an inherited one.

════════════════════════════════════════════════════════════════════════════════
5. SHIPPING TEST & RELEASE BUILDS
════════════════════════════════════════════════════════════════════════════════
- iOS simulator (dev): `flutter run` with the simulator open (used throughout Part A).
- Real-device / tester testing:
    iOS  → `flutter build ipa` → upload to TestFlight (needs Apple Developer, ~$99/yr, + a Mac).
    Android → `flutter build appbundle` → Play Console internal testing (one-time ~$25).
- CI/CD: GitHub Actions to run tests, build, and `supabase functions deploy` on merge to main.
- Environments: point test builds at the STAGING Supabase project; only release builds use PROD.
- Pre-submit checklist: disclaimers visible at onboarding + Settings; privacy policy URL live;
  delayed-data labels present; no profit-promise copy anywhere; content reviewed by an expert.

### 5a. Android release signing
`android/app/build.gradle.kts` signs release builds with a real keystore when
`android/key.properties` exists, and falls back to DEBUG keys with a loud warning when it
does not — so a teammate without the keystore can still `flutter run --release`, but nobody
ships a debug-signed bundle by accident. Play rejects debug-signed uploads outright.

One-time setup on the machine that builds releases:

    keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
      -keyalg RSA -keysize 2048 -validity 10000 -alias upload

`keytool` ships with the JDK. On this Windows machine that is Android Studio's bundled JDK,
which is NOT on PATH — either use the full path
(`"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"`) or set JAVA_HOME first.

Then move `upload-keystore.jks` OUTSIDE the repo, copy `android/key.properties.example` to
`android/key.properties`, and fill in the four values. Both `key.properties` and `*.jks` are
gitignored; committing either hands out the ability to sign as you.

BACK THE KEYSTORE UP, somewhere that is not this laptop. Play binds the upload key to the
listing. Losing it means requesting an upload-key reset from Google, which takes days.
Enrol in Play App Signing (the default for new apps) so Google holds the app signing key and
your upload key stays replaceable.

### 5b. Windows build prerequisite
`flutter build appbundle` fails on Windows with "Building with plugins requires symlink
support" until Developer Mode is on: `start ms-settings:developers`. This blocks building
ANY release bundle from this machine, so do it before anything else.

### 5c. Account deletion — BUILT
Play requires any app that lets users create an account to offer BOTH an in-app way to
delete it AND a publicly reachable web URL for deletion requests. Both are covered.

In-app: Profile → "Delete account". It asks the learner to TYPE THEIR USERNAME rather than
tap a button — with no email on file there is no recovery and no way to verify a change of
mind afterwards, so a mis-tap has to be impossible rather than merely unlikely.

Server: `public.delete_own_account()` in
`supabase/migrations/20260804160000_account_deletion.sql`. SECURITY DEFINER with an empty
search_path, takes NO arguments (identity comes from `auth.uid()`, so a modified client
cannot aim it at another account), granted to `authenticated` and revoked from `anon`. It
deletes the `auth.users` row; profiles, lesson_progress and streaks cascade from it.

Unlike sign-out, deletion FAILS LOUDLY. A learner told "deleted" when the server never heard
the request cannot discover the truth — we hold no email, and a live account looks identical
to a failed delete. `deleteAccountErrorMessage` therefore states in every branch that
nothing was removed. Tests: `test/supabase/account_deletion_test.dart`.

Web URL: PRIVACY.md §5 documents the email route for anyone locked out, so hosting the
policy satisfies the web half.

APPLY THE MIGRATION (`supabase db push`) before shipping a build that shows the button —
without it the RPC 404s and every delete fails.

════════════════════════════════════════════════════════════════════════════════
RECOMMENDED PATH (tl;dr)
════════════════════════════════════════════════════════════════════════════════
Start: Supabase only (auth + Postgres + RLS + Edge Functions). Ship to TestFlight / Play
internal testing. Add Redis/queue/load-balanced compute servers ONLY when heavy pricing or
scale forces it. Keep secrets server-side, RLS on, privacy policy live, disclaimers everywhere.
