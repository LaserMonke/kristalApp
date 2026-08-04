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
| Free or paid | **Free** — with an in-app purchase. Free→Paid cannot be reversed later; Paid→Free can |
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
| Purchase history | **Yes** (via Google Play) | No | Optional | Unlocking the practice market |
| Location, contacts, photos, files, messages, calendar, health, financial info | **No** | — | — | Never requested |
| Device or advertising IDs | **No** | — | — | No ad network, no analytics SDK |

**Two answers you must get right:**

- **"Is any collected data shared with other users?"** → **Yes.** Username and
  point total appear on the leaderboard. This is easy to skip and it is exactly
  the kind of omission that gets an app pulled.
- **"Can users request data deletion?"** → see the blocker below. Until in-app
  deletion exists, the honest answer is that deletion is by email request only,
  and Google increasingly expects better.

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
| Allows purchase of digital goods | **Yes** — one-time unlock |
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

- **Account deletion** — Play requires apps with account creation to offer
  in-app deletion *and* a public web deletion-request URL. Not built. See
  DEPLOY.md.
- **Developer Mode** on the Windows build machine, or no bundle can be built at
  all.
- **Release keystore** — the Gradle config now supports one; the key itself does
  not exist yet.
- **Leaderboard opt-out** — not required by policy, but "my username is visible
  to strangers" is a poor default for an audience that may include 16-year-olds
  (CLAUDE.md rule 6).
