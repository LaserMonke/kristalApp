OptionsSchool — Build Prompts for Claude Code (Flutter, client-first)

Strategy: build a WORKING CLIENT first, runnable on the iOS simulator from Phase 0 using LOCAL/mock data — so you can see and test the app immediately. All data access goes through repository interfaces with a local implementation now; the SERVER (Supabase) is swapped in later (Phase 6) without rewriting the UI. Server/infra deployment lives in DEPLOY.md.

Run in order. After each phase: flutter run on the iOS simulator, review, then git commit. Keep CLAUDE.md in the project root so every session follows the rules and disclaimers.

Stack: Flutter + Dart. One codebase → iOS + Android. Server: Supabase (added in Phase 6).

────────────────────────────────────────────────────────────────────────────── PREREQUISITES (do once) ──────────────────────────────────────────────────────────────────────────────

Install Flutter (includes Dart) from flutter.dev. Run flutter doctor and clear issues.
Install Xcode (for the iOS simulator) and the VS Code Flutter + Dart extensions.
Scaffold and confirm the iOS simulator works BEFORE building features: flutter create optionsschool cd optionsschool open -a Simulator # launches the iOS simulator flutter run # pick the iOS simulator; you should see the demo app
Add client-only deps for now (no server yet): flutter pub add flutter_riverpod go_router fl_chart flutter_local_notifications
shared_preferences git init && git add -A && git commit -m "scaffold" Put CLAUDE.md in the project root. (Supabase deps are added in Phase 6.)

════════════════════════════════════════════════════════════════════════════════ PART A — CLIENT (all local data; fully testable on the iOS simulator) ════════════════════════════════════════════════════════════════════════════════

PHASE 0 — Client shell + theme + local auth stub "Set up the OptionsSchool Flutter client per CLAUDE.md. Create a professional, clean trading-terminal look with full dark AND light ThemeData and a toggle, colorblind-safe gain/loss colors. Set up go_router with tabs: Learn, Practice, Leaderboard, Profile. Use Riverpod for state. IMPORTANT: put all data access behind repository INTERFACES (AuthRepo, ProgressRepo, ProfileRepo) and provide LOCAL implementations backed by shared_preferences / in-memory — NO server yet. Implement a local mock login (username + education level saved locally) so the app is usable offline. Show a one-time onboarding disclaimer ('educational only, not financial advice'). Goal: runs on the iOS simulator immediately."

PHASE 1 — Lesson engine + card/reel UI + first lessons (local) "Build the data-driven lesson engine. Lessons are Dart models / JSON assets bundled with the app; the engine renders them. Present each lesson as vertically swipeable 'cards' (reel/deck style) via a vertical PageView, short and visual. Author the first lessons in original wording (don't copy book text): (1) What is an option — calls/puts, right vs obligation; (2) Payoff at expiry with a payoff diagram via CustomPainter; (3) Why use options — benefits AND honest risks (long options can expire worthless = total premium loss; short/naked can lose far more). State downside plainly per CLAUDE.md. Test on the iOS simulator."

PHASE 2 — Q&A after each lesson (local) "Add a Q&A engine after each lesson: multiple-choice and short questions defined as data per lesson, with immediate plain-language feedback for right/wrong. Save results via the local ProgressRepo. Gate the next lesson on completing the current Q&A. Test on the iOS simulator."

PHASE 3 — Pricer core: BSM + Greeks (pure Dart) "Create a pure Dart pricing library (lib/pricing/, NO Flutter imports): Black-Scholes-Merton for European calls/puts plus Greeks (delta, gamma, vega, theta, rho). Document assumptions. Write unit tests validating against known textbook reference values. Add a reusable payoff- diagram widget (CustomPainter) plotting P/L vs underlying. Test on the iOS simulator."

PHASE 4 — Interactive pricer inside lessons "Build an interactive pricer screen: sliders/inputs for spot, strike, volatility, time, and rate that update price, Greeks, and payoff diagram live. Add a strategy view composing legs (spreads, straddle, covered call, protective put) with combined payoff. Label output as an idealized simulation per CLAUDE.md. Test on the iOS simulator."

PHASE 5 — Points, streaks, levels, certificate (local) "Add the engagement system, persisted LOCALLY via repositories for now: points for lessons/ Q&A, daily streaks (Duolingo/Snapchat style) with a streak-freeze grace, and a level-up scheme culminating in a certificate with a nicer badge icon per stage. Add opt-in local notifications (flutter_local_notifications) for streak/new-content reminders — reasonable, easy to disable, no profit-promise wording. Test on the iOS simulator."

════════════════════════════════════════════════════════════════════════════════ PART B — SERVER (swap local repos for Supabase; needs the backend from DEPLOY.md) ════════════════════════════════════════════════════════════════════════════════

PHASE 6 — Wire up Supabase (client ↔ server) "Add the server backend. First follow DEPLOY.md to create the Supabase project, tables, and RLS policies. Then: flutter pub add supabase_flutter flutter_dotenv, load SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY from .env, and initialize Supabase in main(). Provide SUPABASE implementations of the existing AuthRepo / ProfileRepo / ProgressRepo interfaces (real username/password auth capturing education level; profiles + progress synced to Postgres with RLS). Keep the local implementations as an offline fallback. The UI must not change — only the repository implementation swaps. Test sign-up/login and progress sync, then run on the iOS simulator."

PHASE 7 — Leaderboard (real users + labeled bots) "Add a leaderboard backed by Supabase across real users, with weekly and all-time views and the user's rank. If bot entries pad it early on, label them clearly as bots — never as real people. Test on the iOS simulator."

PHASE 8 — Advanced pricer (Monte Carlo, Heston, exotics) "Extend the pure Dart pricing library: Monte Carlo for path-dependent and multi-asset payoffs (basket; barrier KO/KI) and the Heston stochastic-vol model (semi-analytic vanillas, MC exotics). Add structured products as compositions. Unit-test against reference values; document assumptions. Run heavy Monte Carlo on a Dart Isolate via compute() with a loading state; for very large runs, call the Supabase Edge Function described in DEPLOY.md. Test on the simulator."

PHASE 9 — Paywall + fake-money practice market "Add an in-app-purchase paywall (in_app_purchase or RevenueCat) unlocking the advanced pricer and a fake-money real-time practice options market. Fetch market data through a Supabase Edge Function so the paid data API key never ships in the app (see DEPLOY.md); label delayed data. Track simulated P&L. Label the whole feature a learning simulation with idealized models — no real trading, no profit claims. Test on the iOS simulator."

PHASE 10 — Personalization, polish, release prep "Personalize by education level: lesson order/depth, Q&A difficulty, which advanced topics surface, and notification content. Polish loading/empty/error states and accessibility (Semantics labels, captions); confirm disclaimers at onboarding and in Settings. Prepare release: app icons/splash, flutter build appbundle and flutter build ipa, privacy policy link. Full publishing + infra steps are in DEPLOY.md."

────────────────────────────────────────────────────────────────────────────── Tips

Parts A→B order means you have a demoable iOS-simulator app long before any server exists.
Keep the repository interfaces clean — that's what makes the local→Supabase swap painless.
If Claude Code overreaches, tell it to stop and split the task. One phase per fresh session.
After each phase: flutter run on the iOS simulator, then git commit; revert if it breaks.
Get the options content reviewed by someone with real derivatives knowledge before release.