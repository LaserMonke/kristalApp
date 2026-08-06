# Play Console — answers for the forms

Answers to the Play Console questionnaires, derived from what the code actually
does. Written 4 August 2026. **Re-check these whenever data handling changes** —
a Data safety declaration that no longer matches the app is a policy violation,
not a paperwork slip.

Verify against the console's own wording; Google reorders and renames these
fields regularly.

---

## App details

| Field | Answer |
|---|---|
| App name | Stock Options Academy (21 chars, limit 30) |
| Default language | English (United Kingdom) — the app's copy uses "colour", "idealised", "labelled" |
| App or game | App |
| Free or paid | **Free**, with NO in-app purchases. The planned practice-market unlock was dropped on 6 August 2026 and the paywall removed from the code. Leave "contains in-app purchases" unticked |
| Category | **Education** — not Finance. See note below |
| Tags | Education, Educational, Simulation |
| Contact email | REQUIRED and public. Use one you monitor — it is also the deletion-request address in PRIVACY.md |
| Privacy policy URL | REQUIRED. See "Hosting the policy" below |

### Why Education, not Finance

The app teaches how options work and lets people practise with simulated money.
It places no real trades, touches no real money, and connects to no brokerage.
Filing under Finance invites the financial-services policy track — extra
declarations, and in some markets a licensing check — for no benefit. If a
reviewer asks, the honest description is: *educational content about derivatives,
with a fake-money simulator; no real trading, no brokerage, no money movement.*

---

## Store listing copy

Written to the CLAUDE.md content rules: no profit promises, downside stated
plainly, simulation labelled as simulation. Paste verbatim; if you rewrite it,
re-read rules 2–5 first.

### Short description (80 char limit)

```
Learn how options really work: lessons, quizzes and a fake-money simulator.
```

### Full description (4000 char limit)

```
Stock Options Academy teaches you how options and derivatives actually work -
from what a call and a put are, through payoff diagrams, to the Greeks and the
models used to price them.

This is a learning app, not a trading app. It places no real trades, connects to
no brokerage, and moves no real money.

HOW IT WORKS
Short, swipeable lesson cards explain one idea at a time. Each lesson ends with
a few questions so you find out whether it landed. Points, streaks and levels
track your progress and unlock what comes next.

WHAT YOU WILL LEARN
- Calls, puts, strikes, expiry and premium
- Reading and drawing payoff diagrams
- Why an option loses value as expiry approaches
- The Greeks: delta, gamma, vega, theta, rho
- Black-Scholes-Merton, and what it assumes
- Spreads, straddles, strangles, covered calls, protective puts and collars
- Monte Carlo simulation, barrier and basket options, and stochastic volatility

HONEST ABOUT RISK
Options can and do expire worthless: a long option can lose 100% of the premium
paid. Some strategies carry very large or theoretically unlimited losses. Every
lesson states the downside plainly. Nothing here is presented as easy money,
because it is not.

INTERACTIVE PRICERS
Move a slider and watch the price and the payoff respond. The engine underneath
is the real mathematics - Black-Scholes-Merton in closed form, Monte Carlo for
path-dependent payoffs - with its assumptions stated wherever it is used.

PRACTICE MARKET
A fake-money simulator for trying out what you have learned. Balances are
simulated, fills are idealised (no spreads, no fees, no slippage) and market
data is delayed. Simulated results tell you nothing about real-world outcomes.

EDUCATIONAL ONLY
Stock Options Academy is not financial, investment, tax or legal advice, and is
not a recommendation to buy or sell any security. Models are simplified; real
markets differ in ways that matter, including liquidity, bid/ask spreads,
dividends, early exercise and fees.

Everything here is free. There are no in-app purchases, no subscription and no
adverts.
```

---

## App access (reviewer credentials)

The app requires an account and collects no email, so a reviewer cannot sign
themselves up and receive anything. Play's **App content → App access** section
must therefore carry working credentials, or review fails with "we could not
access your app".

A demo account with the username `playreview` exists for this. **The password is
deliberately not recorded here — this repository is public.** It lives in the
Play Console field and your password manager, nowhere else.

Instructions to paste into the App access form:

> All functionality is behind a single sign-in. Use the supplied username and
> password on the sign-in screen — no email, no verification code, no other
> steps. Every feature including the practice market is reachable immediately
> after signing in.

### The account must be UNLOCKED, not just valid

Lessons are progression-gated (`lib/providers/lesson_providers.dart`): each one
stays locked until the previous lesson's Q&A is finished, and the Sandbox
**Strategy** tab stays locked until `options-strategies` is done. A reviewer
handed a fresh account sees locked screens and can fail the submission for
inaccessible functionality.

Run `supabase/migrations/20260806140000_review_access_and_bots.sql` after the
account exists. It marks all nine lessons finished for that one account.

Two consequences to know about:

- `points_earned` is a generated column, so the unlock necessarily awards 20
  points per lesson — 180 total — and the account then sits on the leaderboard
  next to real learners without having earned it. That is a rule 7 wrinkle. The
  intended fix is lifecycle, not accounting: delete the account via Profile ->
  Delete account once review passes.
- `correct_answers` is left at 0 deliberately. Recording a perfect score would
  be inventing a result the account never produced.

Note the account is an ordinary learner account: its username appears on the
in-app leaderboard like any other.

---

## Data safety form

Google asks, per data type: collected? shared? optional? why? encrypted in
transit? deletable?

**Everything below is encrypted in transit (HTTPS). Nothing is shared with third
parties for advertising. No data is used for tracking across apps or websites.**

| Data type | Collected | Shared | Required | Purpose |
|---|---|---|---|---|
| Name / username | **Yes** | No | Required | App functionality; account management. *Also visible to other users on the leaderboard — declare this* |
| Email address | **No** | — | — | We never ask for one. The `@users.optionsschool.invalid` placeholder is internal, unroutable, and derived from the username |
| Password / credentials | **Yes** | No | Required | App functionality. Hashed by the auth provider |
| App activity — in-app actions | **Yes** | No | Required | Lessons finished, Q&A scores, points, streak. Purpose: app functionality, personalisation (lesson difficulty) |
| "Other info" — education level | **Yes** | No | Required | Personalisation: pitches lesson depth |
| App activity — in-app search history | **Yes** | No | Optional | The Market search box sends what you type to the `market-data-proxy` function, which forwards it to Finnhub so search works by company name and not only by exact ticker. Our function stores nothing |
| Purchase history | **No** | — | — | There are no purchases. The paywall was removed on 6 August 2026 and no store SDK ships in the binary |
| Location, contacts, photos, files, messages, calendar, health, financial info | **No** | — | — | Never requested |
| Device or advertising IDs | **No** | — | — | No ad network, no analytics SDK |

**Two answers you must get right:**

- **"Is any collected data shared with other users?"** → **Yes.** Username and
  point total appear on the leaderboard. This is easy to skip and it is exactly
  the kind of omission that gets an app pulled.
- **"Can users request data deletion?"** → **Yes, both ways.** In-app at
  Profile → Delete account (type-to-confirm, deletes account + all data
  immediately), and by email request for anyone locked out. Declare the
  deletion URL as well — Play wants a web route, not only the in-app one.

---

## Content rating questionnaire

Rate as **Reference, News, or Educational**.

| Question | Answer |
|---|---|
| Violence, sexual content, profanity, controlled substances | No to all |
| **Gambling** | **No** — and be ready to justify it. See below |
| Simulated gambling | No |
| Users can interact / share content | **Yes, limited** — usernames and point totals on a leaderboard. No chat, no messaging, no user-generated content, no photo sharing |
| Shares user location | No |
| Allows purchase of digital goods | **No** — nothing in the app is for sale |
| Target age | 16+ |

### The gambling question

Answer **No**, honestly and confidently. The app has no wagering, no stake, no
prize, and no real or virtual currency that can be bought, cashed out, or
converted to anything of value. The practice market's money is fixed, fake, and
resettable from a button in the UI. Options *are* a real financial instrument,
but teaching how one works is not gambling any more than a textbook is.

Be ready to say this in an appeal, because "options trading app" pattern-matches
badly with automated review.

---

## Hosting the privacy policy

Play requires a **publicly accessible URL**, not a file. Two options:

1. **GitHub Pages** (nicer, ~5 min): Settings → Pages → deploy from `main`,
   `/root`. The policy lands at
   `https://lasermonke.github.io/kristalApp/PRIVACY` once `PRIVACY.md` is
   pushed. Note the repo must be public.
2. **The GitHub-rendered file** (instant): the `PRIVACY.md` blob URL on
   github.com is publicly readable and Play accepts it. Less polished, and it
   leaks the internal repo name `kristalApp`.

Either way the URL must be live **before** you submit, and it must stay live.

---

## Still blocking, tracked elsewhere

- **Web deletion URL** — in-app deletion is now built (Profile → Delete
  account). Play also wants a publicly reachable page describing how to request
  deletion without installing the app; PRIVACY.md §5 covers the wording, so
  hosting the policy satisfies it.
- **Developer Mode** on the Windows build machine, or no bundle can be built at
  all.
- **Release keystore** — the Gradle config now supports one; the key itself does
  not exist yet.
- **Leaderboard opt-out** — not required by policy, but "my username is visible
  to strangers" is a poor default for an audience that may include 16-year-olds
  (CLAUDE.md rule 6).
