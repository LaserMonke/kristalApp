# CLAUDE.md — OptionsSchool (working title)

Project constitution. Claude Code reads this automatically every session. Follow it unless
I explicitly override it in a message.

## What this app is

A mobile app that teaches options and derivatives to students and undergraduates interested
in finance. The MAIN GOAL is high-quality lessons that explain what options are and the
basics of payoffs, risks, and benefits — followed by a Q&A the user answers after each
lesson. Interactive option pricers support the lessons and (in advanced form) power a
fake-money practice market. Engagement features (points, streaks, levels, leaderboard) keep
learners coming back, Duolingo-style.

Core loop: Learn (card/reel lesson) → Answer (Q&A) → Earn (points/streak) → Level up →
Unlock next lesson → Apply (interactive pricer / practice market).

## Honest scope & STACK DECISION

- Framework: **Flutter** (Dart). NOT React Native, NOT Expo, NOT JavaScript/TypeScript.
  Do not add any JS/TS/React code. All app code is Dart.
- One Flutter codebase builds for iOS and Android. Test on the Xcode iOS simulator and the
  Android emulator via `flutter run`.
- "Advanced algorithms" are real but must run somewhere sensible (see Pricer section) — heavy
  Monte Carlo belongs on a Dart isolate or a backend, not the UI thread.

## Tech stack (don't swap without asking)

- Flutter + Dart (stable channel)
- Backend: Supabase via the `supabase_flutter` package (^2.x): auth, Postgres DB (users,
  progress, points, leaderboard), storage. Row Level Security ON. Keys loaded from a .env via
  flutter_dotenv (add .env to .gitignore).
- State management: Riverpod (flutter_riverpod)
- Navigation: go_router
- Charts: fl_chart; payoff diagrams drawn with a CustomPainter for full control
- Local notifications: flutter_local_notifications
- In-app purchase: in_app_purchase (or purchases_flutter / RevenueCat) for the paid pricer +
  practice market
- Heavy compute: Dart Isolates (compute()) to keep the UI smooth; escalate to a Supabase
  Edge Function / small backend for very large simulations
- IDE: VS Code with the Flutter + Dart extensions (or Android Studio). Source control: GitHub.

## Architecture principles

- Lessons, Q&A questions, and learning paths are DATA (Dart models / JSON assets), not
  hardcoded screens. The engine renders them. Adding a lesson = adding data, not engine code.
- The PRICER is a pure Dart library with NO Flutter imports, fully unit-tested (dart test /
  flutter_test) against known reference values. UI calls into it. This keeps the math
  verifiable and reusable across lessons and the practice market.
- Card/reel UI: lessons are vertically swipeable "cards" (reel/deck style) using a vertical
  PageView (or flutter_card_swiper). Keep card content short and visual.
- Keep money/simulation logic separate from widgets. All simulated outcomes clearly labeled.

## FINANCIAL DISCLAIMERS & RULES (non-negotiable — this is a finance app for young users)

1. EDUCATIONAL ONLY. The app is not financial, investment, tax, or legal advice, and not a
   recommendation to buy or sell any security. Show clearly at onboarding; keep accessible
   in Settings.
2. RISK IS TOLD HONESTLY. Every options lesson must explain downside honestly: long options
   can expire worthless (100% loss of premium), and some strategies (e.g. naked/short options)
   carry very large or theoretically unlimited losses. Never present options as easy money.
3. NO PROFIT PROMISES. Do NOT use "how to make money", "get rich", "guaranteed returns", or
   similar framing anywhere — marketing, lessons, or notifications. Reframe as "understand
   options" / "learn how options work". Profit-promise language misleads learners, risks
   app-store rejection, and can create legal/regulatory exposure.
4. SIMULATION != REAL. The fake-money practice market and any pricer output are simplified,
   idealized models. Label everywhere: "Simulation for learning. Models are idealized; real
   markets differ (liquidity, bid/ask spreads, dividends, early exercise, fees). Past or
   simulated performance does not indicate future results."
5. MODEL LIMITATIONS STATED. BSM assumes no arbitrage, constant volatility, European
   exercise, etc. Note key assumptions where a model is used; don't imply models are exact.
6. AUDIENCE MAY INCLUDE MINORS. Students/undergrads can be under 18. If we target or admit
   under-18 users: extra privacy obligations apply (parental considerations, COPPA/GDPR-K),
   and options-trading promotional content to minors is especially inappropriate — keep it
   strictly educational. Collect the minimum data needed. A privacy policy is required.
7. HONEST LEADERBOARD. If bots pad the leaderboard, they must be clearly labeled as bots.
   Never present bot scores as real people.
8. DATA HONESTY. If market data is delayed, label it delayed. Keep any paid data API key
   server-side (Edge Function), never in the shipped Flutter binary.
9. NO DARK PATTERNS. Streaks and notifications encourage learning, not guilt or compulsion.
   Reasonable frequency, easy to turn off.

## Content sources & accuracy

- Ground content in standard references: John C. Hull, "Options, Futures, and Other
  Derivatives" (vanilla theory, Greeks, strategies); Heston (1993) for stochastic vol;
  Glasserman, "Monte Carlo Methods in Financial Engineering" (MC & exotics).
- Do NOT reproduce copyrighted text from these — teach concepts in original wording.
- All formulas and numbers must be accurate. Write unit tests for the pricer against known
  reference values. Flag anything uncertain in a comment rather than guessing.
- Content should be reviewed by someone with real options knowledge before release
  (CFA/finance professor/experienced practitioner). Keep a "reviewed by/date" note per lesson.

## Monetization rules

- Core LEARNING (lessons + Q&A) stays free — best for reach, learning outcomes, and store
  approval. Points/streaks/levels/certificate free.
- Paid (in-app purchase, "donation"-style unlock): the advanced pricer tools and the
  fake-money real-time practice market. Be clear about what payment unlocks.
- App stores take ~15-30% on in-app purchases; plan pricing accordingly.

## Pricer requirements

Build progressively; each model is a tested function in the pure Dart pricer library.
- Vanilla European calls/puts: Black-Scholes-Merton closed form + Greeks (delta, gamma,
  vega, theta, rho). Runs fine on-device.
- Payoff diagrams (CustomPainter) for single options and strategies (spreads, straddles,
  strangles, covered call, protective put, collars, etc.).
- Monte Carlo engine for path-dependent and multi-asset payoffs (basket options; barrier
  KO/KI options). Run on a Dart Isolate (compute()) so the UI stays responsive; escalate very
  heavy runs to a Supabase Edge Function.
- Stochastic volatility: Heston model — semi-analytic (Fourier/characteristic function) for
  vanillas, Monte Carlo for exotics.
- Structured products / option strategies as compositions of the above.
- Every model: document assumptions, add unit tests, show a "simulation/idealized" label in UI.

## Accessibility & UX

- Professional, clean "trading terminal" aesthetic. Dark AND light mode (Flutter ThemeData
  for both, with a toggle).
- Colorblind-safe payoff/PnL colors (don't rely on red/green alone).
- Readable typography; Semantics labels for screen readers; captions on any narrated content.

## Build order (follow unless I say otherwise)

1. App shell: Flutter + light/dark themes + Supabase init + auth (username/password +
   education level) + go_router navigation.
2. Lesson engine + card/reel (vertical PageView) UI + first options lessons (calls, puts,
   payoffs, risk/benefit).
3. Q&A engine after each lesson.
4. Pricer core: BSM + Greeks (pure Dart library + tests) and payoff-diagram CustomPainter.
5. Interactive pricer inside lessons (sliders update price/payoff live).
6. Engagement: points, streaks, levels, certificate progression, local notifications.
7. Leaderboard (real users + clearly labeled bots).
8. Advanced pricer: Monte Carlo (basket, barrier KO/KI) on isolates, Heston, strategies,
   structured products.
9. Paywall + fake-money real-time practice market (paid data API via Edge Function,
   delayed-data labels).
10. Personalized learning paths & notifications by education level. Then deploy (see DEPLOY.md).

## Coding conventions

- Dart with sound null safety and lints (flutter_lints / very_good_analysis). Small widgets.
  Comments explain the FINANCE, not just the code.
- Pricer library has NO Flutter imports and full unit tests.
- Commit after every working slice (GitHub). Never leave the app non-running.
- If a request is too big for one clean pass, propose splitting it before writing code.