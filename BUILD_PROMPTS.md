# OptionsSchool — Build Prompts for Claude Code (Flutter)

The whole app, broken into sessions you paste one at a time into Claude Code. Run in order.
Review the diffs, run it on a simulator, and `git commit` after each phase before moving on.
Keep CLAUDE.md in the project root so every session follows the rules and disclaimers.

Stack: Flutter + Dart + Supabase. One codebase → iOS + Android.

──────────────────────────────────────────────────────────────────────────────
PREREQUISITES (do once)
──────────────────────────────────────────────────────────────────────────────
- Install Flutter (includes the Dart SDK) from flutter.dev; run `flutter doctor` and fix any
  reported issues (Xcode for iOS, Android Studio/SDK for Android).
- In VS Code, install the Flutter and Dart extensions.
Then, in a terminal:
    flutter create optionsschool
    cd optionsschool
    flutter pub add supabase_flutter flutter_riverpod go_router fl_chart \
      flutter_local_notifications flutter_dotenv in_app_purchase
    git init && git add -A && git commit -m "scaffold"
Put CLAUDE.md in the project root. Create a .env (and add it to .gitignore):
    SUPABASE_URL=...            (Supabase → Project Settings → API)
    SUPABASE_PUBLISHABLE_KEY=...
Run anytime with `flutter run` (pick the iOS simulator or Android emulator when prompted).

──────────────────────────────────────────────────────────────────────────────
PHASE 0 — App shell, theme, auth
──────────────────────────────────────────────────────────────────────────────
"Set up the OptionsSchool Flutter app per CLAUDE.md. Create a professional, clean
trading-terminal look with full dark AND light ThemeData and a theme toggle, using
colorblind-safe colors for gains/losses (not red/green alone). Set up go_router navigation
with tabs: Learn, Practice, Leaderboard, Profile. Load SUPABASE_URL and
SUPABASE_PUBLISHABLE_KEY from .env with flutter_dotenv and initialize supabase_flutter in
main(). Build username/email + password sign-up and login, capturing the user's education
level at sign-up, stored in a Supabase profiles table with Row Level Security. Show a one-time
onboarding screen with the 'educational only, not financial advice' disclaimer. Use Riverpod
for auth state. No lessons yet — just a themed, running, authenticated app."

──────────────────────────────────────────────────────────────────────────────
PHASE 1 — Lesson engine + card/reel UI + first lessons
──────────────────────────────────────────────────────────────────────────────
"Build the data-driven lesson engine. Lessons are Dart models / JSON assets; the engine
renders them. Present each lesson as vertically swipeable 'cards' (reel/deck style) using a
vertical PageView, with short, visual content per card. Author the first lessons in original
wording (do not copy any book text): (1) What is an option — calls and puts, right vs
obligation; (2) Payoff at expiry with a simple payoff diagram drawn via CustomPainter;
(3) Why people use options — benefits AND honest risks, including that long options can
expire worthless (total premium loss) and short/naked positions can lose far more. Every
risky concept states the downside plainly per the CLAUDE.md rules."

──────────────────────────────────────────────────────────────────────────────
PHASE 2 — Q&A after each lesson
──────────────────────────────────────────────────────────────────────────────
"Add a Q&A engine that runs after each lesson: multiple-choice and short questions defined as
data per lesson. Give immediate feedback with a plain-language explanation for right and wrong
answers. Record results to Supabase (per user, per lesson: score, attempts). Gate the next
lesson on completing the current Q&A."

──────────────────────────────────────────────────────────────────────────────
PHASE 3 — Pricer core: Black-Scholes-Merton + Greeks
──────────────────────────────────────────────────────────────────────────────
"Create a pure Dart pricing library (lib/pricing/, NO Flutter imports) with Black-Scholes-
Merton pricing for European calls and puts, plus the Greeks (delta, gamma, vega, theta, rho).
Document each function's assumptions in comments. Write unit tests (flutter_test/dart test)
validating outputs against known textbook reference values. Then add a reusable payoff-diagram
widget using CustomPainter that plots profit/loss vs underlying price for a given option or
position."

──────────────────────────────────────────────────────────────────────────────
PHASE 4 — Interactive pricer inside lessons
──────────────────────────────────────────────────────────────────────────────
"Build an interactive pricer screen used inside lessons: sliders/inputs for spot, strike,
volatility, time to expiry, and rate that update the option price, the Greeks, and the payoff
diagram live. Add a strategy view that composes multiple legs (spreads, straddle, covered
call, protective put) and shows the combined payoff. Label all output as an idealized
simulation per CLAUDE.md."

──────────────────────────────────────────────────────────────────────────────
PHASE 5 — Points, streaks, levels, certificate
──────────────────────────────────────────────────────────────────────────────
"Add the engagement system: points for completing lessons and Q&A, daily streaks
(Duolingo/Snapchat style) with a streak-freeze grace, and a level-up scheme culminating in a
certificate, with a nicer badge icon at each stage. Persist in Supabase. Add opt-in local
notifications via flutter_local_notifications for streak reminders and new content — kept
reasonable and easy to disable (no guilt/dark patterns). Never use profit-promise wording."

──────────────────────────────────────────────────────────────────────────────
PHASE 6 — Leaderboard (real users + labeled bots)
──────────────────────────────────────────────────────────────────────────────
"Add a leaderboard backed by Supabase showing points across real users. If bot entries are
used to populate it early on, label them clearly as bots — never present them as real people.
Include weekly and all-time views and the current user's rank."

──────────────────────────────────────────────────────────────────────────────
PHASE 7 — Advanced pricer (Monte Carlo, Heston, exotics)
──────────────────────────────────────────────────────────────────────────────
"Extend the pure Dart pricing library: a Monte Carlo engine for path-dependent and
multi-asset payoffs (basket options; barrier knock-out/knock-in options), and the Heston
stochastic-volatility model (semi-analytic for vanillas, Monte Carlo for exotics). Add
structured-product payoffs as compositions. Keep everything in the pure Dart library with
unit tests against reference values, documenting assumptions. Run heavy Monte Carlo on a Dart
Isolate via compute() so the UI stays smooth, with a loading state; for very large runs,
outline a Supabase Edge Function fallback."

──────────────────────────────────────────────────────────────────────────────
PHASE 8 — Paywall + fake-money practice market
──────────────────────────────────────────────────────────────────────────────
"Add an in-app-purchase paywall (in_app_purchase or RevenueCat) that unlocks the advanced
pricer tools and a fake-money real-time practice options market. In the practice market the
user trades options with simulated money using data from a paid data API — fetch it through a
Supabase Edge Function so the API key never ships in the app; if data is delayed, label it
delayed. Track simulated P&L. Label the entire feature as a learning simulation with idealized
models per CLAUDE.md — no real trading, no profit claims."

──────────────────────────────────────────────────────────────────────────────
PHASE 9 — Personalized learning by education level
──────────────────────────────────────────────────────────────────────────────
"Use the education level captured at sign-up to personalize: order and depth of lessons,
difficulty of Q&A, and which advanced topics surface. Beginners get gentler explanations and
more practice; advanced users unlock Heston/exotics/structured products sooner. Personalize
notification content to the user's current path. Keep everything accurate and non-promissory."

──────────────────────────────────────────────────────────────────────────────
PHASE 10 — Polish & deploy prep
──────────────────────────────────────────────────────────────────────────────
"Polish: loading/empty/error states, accessibility (Semantics labels, captions), and confirm
disclaimers appear at onboarding and in Settings. Prepare for release: app icons and splash
(flutter_launcher_icons / flutter_native_splash), `flutter build appbundle` for Android and
`flutter build ipa` for iOS, and a privacy policy link. See DEPLOY.md for the full publishing
and test-run process."

──────────────────────────────────────────────────────────────────────────────
Tips
- If Claude Code tries to do too much at once, tell it to stop and split the task.
- Start a fresh Claude session per phase so context stays clean; keep CLAUDE.md in root.
- After each phase: `flutter run` on a simulator, then git commit. If it breaks, git revert.
- Run `flutter doctor` whenever the toolchain acts up (missing Xcode/Android bits, etc.).
- Get the options content reviewed by someone with real derivatives knowledge before release.
