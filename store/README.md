# Store assets

Everything the Play Console asks for as a file, in one place. Text answers —
descriptions, Data safety, content rating, App access — are in `PLAY_LISTING.md`
at the repo root.

Generated 6 August 2026 from a release build.

## icons/

| File | Where it goes |
|---|---|
| `play-listing-icon-512.png` | Play Console → Store listing → **App icon**. 512x512 |
| `play-feature-graphic-1024x500.png` | Play Console → Store listing → **Feature graphic**. 1024x500 |
| `launcher-icon-master-1024.png` | NOT uploaded. Source for the in-app launcher icon |
| `launcher-adaptive-foreground-1024.png` | NOT uploaded. Source for the Android adaptive foreground layer |

The two launcher sources are copies of `assets/branding/`, which is what
`flutter_launcher_icons` actually reads. **Edit the originals in
`assets/branding/`, not these** — then re-run `dart run flutter_launcher_icons`
and refresh the copies here. The mark is inset for the adaptive layer because
Android masks it to a circle and crops the outer third.

## screenshots/

Seven phone screenshots, in listing order. Play accepts 2–8.

Captured from a **release** build on a Pixel emulator, in dark mode.

They are 1280x2424, not the raw 1080x2424 the device produced. Play rejects a
screenshot whose long side is more than twice its short side, and 2424/1080 is
2.24. The extra width is padding in `#0B0E13` — the app's own background colour,
so the seam is invisible — and they are flattened to 24-bit because Play also
rejects an alpha channel.

## What is deliberately absent

**A Ranks (leaderboard) screenshot.** The board shows real usernames from the
live Supabase project, and a public store listing is not the place to publish
them. `supabase/migrations/20260806140000_review_access_and_bots.sql` seeds a
labelled bot roster; once that has been run, a Ranks screenshot can be taken
that shows no real accounts.

**Anything advertising a purchase.** The paywall was removed on 6 August 2026 —
the app is free in full. If a screenshot or graphic ever shows a price, it is
out of date.
