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
3. Keep the service_role key SECRET — server-side only, never in the app.

### 1b. Database schema (run as SQL in the Supabase SQL editor)
Core tables (let Claude Code generate exact SQL, but the shape is):
- profiles(id uuid pk → auth.users, username, education_level, created_at)
- progress(id, user_id fk, lesson_id, score, attempts, completed_at)
- points(user_id fk, total_points, level, updated_at)
- streaks(user_id fk, current_streak, longest_streak, last_active, freezes_left)
- leaderboard is a VIEW over points (+ a separate bots table clearly flagged is_bot=true)
Enable Row Level Security on every user table and add policies so
`auth.uid() = user_id` for select/insert/update. Never leave a user table without RLS.

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
1. Create dev Supabase project + run the schema SQL + enable RLS.
2. Put SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY in the client dev .env.
3. Implement the Supabase versions of AuthRepo/ProfileRepo/ProgressRepo (interfaces already
   exist from Part A), keeping local repos as offline fallback.
4. Deploy the market-data-proxy Edge Function with its secret before building Phase 9.

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
