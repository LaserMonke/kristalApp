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
   - Minimum password length: 6, matching `minPasswordLength` in
     `lib/data/supabase/account_identity.dart` and the sign-in form's own validator. Change
     all three together or the form will accept a password the server rejects.
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

   PHASE 9b — PAYWALL. The app side is BUILT; the store side is not, and cannot be from code.

   Decisions, settled 2026-08-03 and baked into the code — changing any of them is a code
   change, and changing the entitlement id after launch orphans existing purchasers:
     - Paid feature: the PRACTICE MARKET ONLY. The advanced pricer stays free.
     - Product: a one-time non-consumable at roughly $5. Not a subscription.
     - Entitlement identifier: `practice_market`. Offering `default`, package type Lifetime.
     - The unlock is tied to the signed-in Supabase account, not the device.
     - Store layer: RevenueCat (`purchases_flutter`).

   Built: `EntitlementRepo` (lib/data/repositories/) with `LocalEntitlementRepo` as the
   no-store stub, `entitlementControllerProvider` (lib/providers/entitlement_providers.dart),
   `marketUnlockedProvider` now an `AsyncValue<bool>` off real state, and `PaywallView`
   (lib/features/market/) with Restore Purchase, an Ask-to-Buy pending state, and no
   hardcoded price. Tests: test/market/paywall_test.dart.

   The stub starts UNLOCKED on purpose. A build with no store cannot verify a purchase, so
   locking would leave a tab nobody could open; a shipped build carries RevenueCat keys and
   is handed the store-backed repo instead. That choice lives in `entitlementRepoProvider`.

   Still to do, in order:
     a. Apple Developer Program ($99/yr) — enrol as Individual, then sign the Paid Applications
        Agreement and complete banking + tax in App Store Connect → Business. IAP does not
        function until that agreement is active. NOTE: iOS builds need macOS; this repo's
        owner is on Windows, so budget for a Mac or a cloud-Mac CI (Codemagic) before paying.
     b. Google Play Console ($25 one-time) — plus the payments/merchant profile. Personal
        accounts also need 12 testers opted in for 14 consecutive days on a closed test before
        production access. That is usually the longest lead time; start it first.
     c. Create the non-consumable in both stores. Suggested id, same on both:
        `com.optionsschool.optionsschool.practice_market`.
     d. RevenueCat project: add both apps (bundle id / package name are both
        `com.optionsschool.optionsschool`), upload Apple's In-App Purchase Key (.p8) and
        Google's service-account JSON, wire both stores' server notifications, then create the
        products, the `practice_market` entitlement and the Lifetime package.
     e. Add `purchases_flutter` and a `RevenueCatEntitlementRepo` behind the existing
        interface; pick it in `entitlementRepoProvider` on whether the keys are present, the
        way `marketRepoProvider` picks on Supabase. Public SDK keys go in `.env`
        (`REVENUECAT_APPLE_KEY` / `REVENUECAT_GOOGLE_KEY`) — the SECRET key never ships.
     f. Add the terms-of-use and privacy-policy links to `PaywallView`. Deliberately absent
        rather than stubbed, because the URLs do not exist yet (Phase 10). RevenueCat is a
        third-party processor and must be named in that policy.
     g. Sandbox testing needs real devices — an App Store Connect Sandbox Tester on iOS, a Play
        licence tester on an internal-testing build on Android. The iOS simulator with a
        StoreKit config file will drive the UI but will not reliably reach RevenueCat.
     h. Minors + purchases (rule 6) and no purchase pressure (rule 9) still need a real review
        before release. The store rating is 16+, which clears COPPA but not GDPR-K everywhere
        (EU consent age varies 13–16 by member state). Core learning stays free.
10. Still to do: publish the privacy policy (Phase 10) — data now leaves the device and
    usernames plus point totals are visible to other learners on the leaderboard, so the
    policy is a release requirement. Settings → "Data we collect" discloses both.
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

### 5c. Account deletion — REQUIRED by Play, NOT BUILT
Play requires any app that lets users create an account to offer BOTH an in-app way to
delete it AND a publicly reachable web URL for deletion requests. `AuthRepo` currently has
`signUp`/`signIn`/`signOut`/`restoreSession` and no delete; Settings offers "Reset learning
progress" (wipes progress, keeps the account) and "Sign out". Neither is deletion.

What it needs: a `deleteAccount()` on `AuthRepo`, a SECURITY DEFINER Postgres function that
deletes the caller's `auth.users` row so the existing FK cascades clear profile/progress/
streak rows, a confirming destructive-action dialog in `profile_screen.dart` that is honest
that it cannot be undone, and a public deletion-request page. Note the account cannot be
recovered afterwards and there is no email on file to verify a change of mind.

════════════════════════════════════════════════════════════════════════════════
RECOMMENDED PATH (tl;dr)
════════════════════════════════════════════════════════════════════════════════
Start: Supabase only (auth + Postgres + RLS + Edge Functions). Ship to TestFlight / Play
internal testing. Add Redis/queue/load-balanced compute servers ONLY when heavy pricing or
scale forces it. Keep secrets server-side, RLS on, privacy policy live, disclaimers everywhere.
