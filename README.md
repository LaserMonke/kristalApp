# Stock Options Academy

A Flutter app that teaches how options and derivatives work — lessons, a Q&A after each
lesson, interactive pricers, and a fake-money practice market.

**Educational only.** Nothing in this app is financial, investment, tax or legal advice, or a
recommendation to buy or sell any security. See [CLAUDE.md](CLAUDE.md) for the full rules
that govern content and framing.

## Status

Phases 0 and 1 of [BUILD_PROMPTS.md](BUILD_PROMPTS.md) are complete. No server yet — all data
is on-device.

| Phase | Scope | State |
| --- | --- | --- |
| 0 | Shell, themes, repositories, local auth, onboarding | done |
| 1 | Lesson engine, card/reel UI, first three lessons | done |
| 2 | Q&A engine | next |
| 3 | Pricer core (BSM + Greeks, pure Dart) | |
| 4 | Interactive pricer | |
| 5 | Points, streaks, levels, certificate | |
| 6–10 | Supabase, leaderboard, advanced pricer, paywall, release | |

## Running it

```bash
flutter pub get
flutter run            # pick a device
flutter test
flutter analyze
```

Target devices: iOS and Android are the shipping platforms. On a Windows host neither
simulator is available, so use Chrome (`flutter run -d chrome`) for quick checks and verify
on a real simulator/emulator before each release. Windows desktop builds additionally need
Developer Mode enabled for plugin symlinks.

## Layout

```
assets/
  lessons/         lesson content as JSON — adding a lesson means editing this
lib/
  core/
    router/        go_router config + the redirect gates (disclaimer -> sign-in -> tabs)
    theme/         light + dark ThemeData, colourblind-safe P/L colours
    widgets/       shared UI (disclaimer strings and banner, payoff diagram, theme toggle)
  data/
    models/        AppUser, EducationLevel, LessonProgress, Lesson + card types
    repositories/  AuthRepo, LessonRepo, ProfileRepo, ProgressRepo — abstract interfaces
    local/         on-device implementations (shared_preferences, bundled assets)
  features/        one folder per screen area
  pricing/         pure Dart maths — NO Flutter imports, unit-tested
  providers/       Riverpod controllers and the repository wiring
```

### The repository seam

Every screen depends on the abstract interfaces in `lib/data/repositories/`, never on a
concrete backend. Phase 6 adds Supabase implementations and rebinds the providers in
[repository_providers.dart](lib/providers/repository_providers.dart) — no UI changes.

### Lessons are data

A lesson is an entry in [assets/lessons/lessons.json](assets/lessons/lessons.json) made of
typed cards (`title`, `text`, `term`, `payoff`, `warning`, `summary`). The engine renders
them, so authoring a lesson requires no engine code. `LessonCard` is a sealed hierarchy: a
new card type will not compile until it has been given a visual treatment.

Payoff cards declare strategy legs, and the diagram is computed by
[lib/pricing/payoff.dart](lib/pricing/payoff.dart) — pure Dart, no Flutter imports, tested
against hand-worked reference values in [test/pricing/payoff_test.dart](test/pricing/payoff_test.dart).

### Content review

Every lesson carries a `reviewed_by` field. It is currently `null` for all three, which the
app states out loud at the end of each lesson. A practitioner with real derivatives knowledge
must review the content and fill this in before release.

### Local auth is a stub

[LocalAuthRepo](lib/data/local/local_auth_repo.dart) is a device-only mock so the app is
usable offline before a server exists. Its password digest is deliberately non-cryptographic
and offers no real protection; real authentication arrives with Supabase Auth in Phase 6.
Nothing sensitive is stored, and no credential leaves the device.

## Colour

Gain/loss uses blue vs. vermillion from the Okabe–Ito palette rather than red/green, which is
indistinguishable to a significant share of colourblind users. Colour is never the only
signal — the loss region of a payoff chart is dashed and hatched as well as coloured, and
every diagram carries a spoken description for screen readers.
