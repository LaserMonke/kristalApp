# OptionsSchool — Server & Deployment Guide

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
The Phase 6 schema is written and lives in git:

    supabase/migrations/20260730120000_phase6_init.sql

Apply it either way — it is idempotent, so re-running is safe:
- CLI (preferred, keeps environments in step):
  `supabase link --project-ref <ref>` then `supabase db push`
- Dashboard: paste the file into the SQL editor and run it.

What it creates:
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

Phase 7 adds the leaderboard view over these tables plus a bots table flagged `is_bot = true`.

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
7. Still to do: deploy the market-data-proxy Edge Function with its secret before Phase 9,
   and publish the privacy policy (Phase 10) — data now leaves the device, so the policy is a
   release requirement, and Settings → "Data we collect" says so.

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

════════════════════════════════════════════════════════════════════════════════
RECOMMENDED PATH (tl;dr)
════════════════════════════════════════════════════════════════════════════════
Start: Supabase only (auth + Postgres + RLS + Edge Functions). Ship to TestFlight / Play
internal testing. Add Redis/queue/load-balanced compute servers ONLY when heavy pricing or
scale forces it. Keep secrets server-side, RLS on, privacy policy live, disclaimers everywhere.
