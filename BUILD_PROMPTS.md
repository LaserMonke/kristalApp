OptionsSchool — Build Prompts for Claude Code (Flutter, client-first)

Strategy: build a WORKING CLIENT first, runnable on the iOS simulator from Phase 0 using LOCAL/mock data — so you can see and test the app immediately. All data access goes through repository interfaces with a local implementation now; the SERVER (Supabase) is swapped in later (Phase 6) without rewriting the UI. Server/infra deployment lives in DEPLOY.md.

Run in order. After each phase: flutter run on the iOS simulator, review, then git commit. Keep CLAUDE.md in the project root so every session follows the rules and disclaimers.

Stack: Flutter + Dart. One codebase → iOS + Android. Server: Supabase (added in Phase 6).

STATUS (last updated 2026-08-03): Phases 0–8 are DONE. Phase 9 is PARTLY done — the practice market shipped, and the paywall's app side now exists but cannot talk to a real store yet (see Phase 9 below). Then PHASE 10.

────────────────────────────────────────────────────────────────────────────── PREREQUISITES — DONE ──────────────────────────────────────────────────────────────────────────────

Flutter + Xcode + VS Code extensions installed, flutter doctor clear, project scaffolded and running on the iOS simulator. Keep the repo in ~/app (not Desktop/Documents) — iCloud extended attributes break iOS codesigning.

Dependencies (pubspec.yaml): flutter_riverpod, go_router, fl_chart, shared_preferences, flutter_local_notifications, timezone, flutter_timezone, supabase_flutter, flutter_dotenv, http. No in-app-purchase package yet — that arrives with the paywall.

.env is gitignored, so a fresh clone or a machine that only pulled has NO credentials, and the build fails outright because .env is a declared asset. Copy .env.example to .env and fill in SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY. Blank values are supported — the app then runs fully on-device.

════════════════════════════════════════════════════════════════════════════════ PART A — CLIENT (all local data; fully testable on the iOS simulator) — COMPLETE ════════════════════════════════════════════════════════════════════════════════

PHASE 0 — Client shell + theme + local auth stub — DONE (commit cc609ba)
Shipped: trading-terminal light/dark ThemeData with a toggle, colorblind-safe gain/loss colours, go_router shell, Riverpod state, repository INTERFACES (AuthRepo, ProfileRepo, ProgressRepo, LessonRepo) with local shared_preferences/asset implementations, local mock login, one-time onboarding disclaimer.
The nav has moved twice since. It is now Home · Learn · Sandbox · Market — "Practice" became "Sandbox" (4fb9265), Home was added (a0c15ba), Settings moved to a gear icon (1ab77b9, then reachable from every tab in 18e3954), and Ranks gave up its slot to Market in Phase 9.

PHASE 1 — Lesson engine + card/reel UI + first lessons (local) — DONE (commits 672b02d, 709fdca)
Shipped: data-driven engine reading assets/lessons/lessons.json, vertical PageView card/reel player with deck-style swipe, interactive cards, CustomPainter payoff diagrams. Nine lessons now: What is an option? · Payoff at expiry · Why use options — and what can go wrong · The Black-Scholes-Merton price · The Greeks · Options strategies · Options that watch the path · Volatility is not a constant · Structured products: taking the wrapper off.

PHASE 2 — Q&A after each lesson (local) — DONE (commits 334e02f, 05d1a04, c464a76)
Shipped: multiple-choice + short-answer questions as data per lesson, immediate plain-language feedback, results saved via ProgressRepo, next lesson gated on the current Q&A. Fixes since: MCQ answer-position bias, double-tap races, stale gate accessor, submit button pinned above the keyboard.

PHASE 3 — Pricer core: BSM + Greeks (pure Dart) — DONE (commit 37b631c)
Shipped: lib/pricing/ with no Flutter imports — black_scholes.dart (European calls/puts + delta, gamma, vega, theta, rho), payoff.dart, priced_leg.dart; assumptions documented; unit tests against textbook reference values. Reusable payoff-diagram widget at lib/core/widgets/payoff_diagram.dart.

PHASE 4 — Interactive pricer inside lessons — DONE (commits 37b631c, 4fb9265, f2c2860)
Shipped: Sandbox tab with a single-option pricer (spot/strike/vol/time/rate sliders updating price, Greeks and payoff live) and a strategy view composing legs (spreads, straddle, covered call, protective put). Payoff graph at the top; a step-by-step tutorial walks first-time users through it. Output labelled an idealized simulation.

PHASE 5 — Points, streaks, levels, certificate (local) — DONE (commits b838848, 715cc3d, a0c15ba)
Shipped: lib/engagement/ (points, streak with freeze grace, levels), certificate screen with per-stage badge icons, Home tab with standing, next lesson and certificate progress. Daily reminder on by default via flutter_local_notifications, easy to disable, wired for iOS and Android, no profit-promise wording.

════════════════════════════════════════════════════════════════════════════════ PART B — SERVER (swap local repos for Supabase; needs the backend from DEPLOY.md) ════════════════════════════════════════════════════════════════════════════════

PHASE 6 — Wire up Supabase (client ↔ server) — DONE (commit 3cab868)
Shipped: supabase_flutter + flutter_dotenv, credentials from .env, Supabase initialised in main(). Supabase implementations of AuthRepo / ProfileRepo / ProgressRepo in lib/data/supabase/, schema and RLS in supabase/migrations/20260730120000_phase6_init.sql. Local implementations kept as the offline fallback; the UI did not change. Tests in test/supabase/.

PHASE 7 — Leaderboard (real users + labeled bots) — DONE (commits 6cbae99, 2c1473d, d14a00e, 374c5b5)
Shipped: Supabase-backed leaderboard (lib/features/leaderboard/, supabase_leaderboard_repo.dart, leaderboard_providers.dart) with weekly/all-time views, a standing card and rank rows. Schema in supabase/migrations/20260730130000_phase7_leaderboard.sql — leaderboard_bots, leaderboard_page(period, limit_count), leaderboard_standing(period) — reconciling an existing leaderboard, with an off switch for bots. Bots are labelled as bots. 374c5b5 fixed a real hole: the board was readable without signing in.

PHASE 8 — Advanced pricer (Monte Carlo, Heston, exotics) — DONE (commits 8f560ac, d92d875, 0bc1646, d01443e, 734d208, 8044380, ef2197a)
Shipped in six parts: Monte Carlo core with barrier KO/KI and basket options (monte_carlo.dart, barrier.dart, basket.dart, random.dart); Heston stochastic vol (heston.dart, quadrature.dart, complex.dart); structured products as compositions (structured.dart); isolates with serialisable jobs (pricing_job.dart, lib/services/advanced_pricer.dart) plus a price-heavy Edge Function for very large runs, cross-checked and noted in DEPLOY.md; an Advanced pricer tab; and three lessons on the advanced instruments.

PHASE 9 — Paywall + fake-money practice market — PARTLY DONE (commit 5636420)
Shipped: the Market tab — a fake-money practice options market (lib/features/market/market_view.dart, lib/data/models/market.dart, market_repo.dart, portfolio_repo.dart, supabase_market_repo.dart, lib/providers/market_providers.dart), simulated P&L, a simulation distribution chart for the advanced pricer, and supabase/functions/market-data-proxy/index.ts so the data API key stays server-side. Market took Ranks' slot in the bottom nav.
PHASE 9b — the paywall's app side — DONE. Decided first: the paid feature is the PRACTICE MARKET ONLY (the advanced pricer stays free — it is the best evidence the teaching is real), the unlock is a one-time non-consumable at ~$5, tied to the signed-in account rather than the device, entitlement id `practice_market`, store layer RevenueCat.
Shipped: `EntitlementRepo` (interface) + `LocalEntitlementRepo` (the no-store stub) + `entitlementControllerProvider`, `marketUnlockedProvider` now an AsyncValue read from real state, and `PaywallView` replacing the old `_LockedPlaceholder` — with restore, a pending/Ask-to-Buy state, and no hardcoded price. 15 tests in test/market/paywall_test.dart.
STILL TO DO before this can charge anyone: the Apple ($99/yr, needs a Mac or a cloud-Mac CI for the iOS build) and Google Play ($25) developer accounts, the non-consumable product in each store, the RevenueCat project, then `purchases_flutter` + a `RevenueCatEntitlementRepo` behind the same interface (chosen in `entitlementRepoProvider` on whether the keys are present, exactly as marketRepoProvider chooses on Supabase). Also the terms-of-use and privacy-policy links on the paywall, which need live URLs (Phase 10). Note Google's 12-testers-for-14-days rule before a personal account gets production access — start that early.

PHASE 10 — Personalization, polish, release prep — NEXT AFTER 9b "Personalize by education level: lesson order/depth, Q&A difficulty, which advanced topics surface for people with higher education, and notification content. Polish loading/empty/error states and accessibility (Semantics labels, captions); confirm disclaimers at onboarding and in Settings. Prepare release: app icons/splash, flutter build appbundle and flutter build ipa, privacy policy link — make it fit Apple's and Google's regulations and safety requirements so it is ready to publish. Full publishing + infra steps are in DEPLOY.md."

────────────────────────────────────────────────────────────────────────────── Tips

Parts A→B order means you have a demoable iOS-simulator app long before any server exists.
Keep the repository interfaces clean — that's what makes the local→Supabase swap painless.
If Claude Code overreaches, tell it to stop and split the task. One phase per fresh session.
After each phase: flutter run on the iOS simulator, then git commit; revert if it breaks.
Get the options content reviewed by someone with real derivatives knowledge before release.
NEVER paste an API key into this file or any other tracked file. One was committed here in the
Phase 9 text and is in git history — rotate it. Keys belong in .env (gitignored) or, for paid
data APIs, only in the Edge Function's server-side secrets.
