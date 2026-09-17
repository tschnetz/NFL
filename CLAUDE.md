# NFL SwiftUI client

iOS/macOS/iPadOS SwiftUI client for the personal NFL stack. Backend is deployed and serving real data; this repo is the frontend port from the legacy React app at `~/Documents/Development/Webstorm/nfl/`.

## Read first

- **`BACKEND_API.md`** (in this repo) — the API contract: every endpoint, every payload field, sign conventions, Codable shapes. Start here.
- **`~/Documents/Development/Guides/SwiftUI Best Practices & Visual Design — 2026.md`** — the design system *and* the coding conventions. ⚠️ This repo used to carry its own `Docs/` copies of two separate docs; they were deleted 2026-08-29 and the upstream pair has since been merged into that one file. Don't re-add local copies — they drift.
- **`docs/archive/`** — finished plans, kept for the *why*, not as current reference: `MIGRATE_MINI.md` (the Render→mini migration, ✅ complete), `NEXT.md` (the Predictions/Standings/Teams/Results expansion, ✅ complete), `ESPN_SERVICE.md`.

## Where the backend lives

- **Live**: `https://nfl.schnetz.us` (Mac Mini, Cloudflare Tunnel). Serves real predictions.
- **Repo**: `~/Documents/Development/IntelliJ/Python/NFL/` — FastAPI + Postgres + nflverse. If a wire shape needs to change, open that repo, edit the relevant router under `app/routers/`, write a test, `./deploy/sync.sh`.
- **Auth**: bearer-token middleware wired but `API_KEY` is unset on the Mini — unauthenticated requests work today.

## Current state of this repo

⚠️⚠️ **This section asserted "Nothing else has been written" for 82 days while the client was being
built.** Measured 2026-08-27: **34 Swift files, ~5,865 lines, five shipped tabs.** The claim also
propagated — `MY_PORTFOLIO.md` carried "the SwiftUI client is still a scaffold" off the back of it,
and `BACKEND_API.md` carried its own copy ("no frontend work has shipped yet") until 2026-08-29.
That is why a stale doc is worse than a missing one. Re-measure before trusting a state claim here.

- **Five tabs** (`Views/Tabs/RootView.swift`, Pigskin pattern): Scoreboard · Schedule · Results ·
  More · Picks. Picks has Active / History / Standings sub-pages.
- **Structure** mirrors Pigskin: `API/APIClient.swift` (one actor), `Models/`, `Services/`,
  `Views/{Tabs,Game,Team,Picks,Predictions,Standings,Settings,Onboarding,Components}`.
- **Navigation uses closure-based `NavigationLink`s** — switched deliberately from the value-based
  form in Teams and More; follow that when adding screens.
- Backend is **fully ready to consume** — every endpoint in `BACKEND_API.md` works against
  `nfl.schnetz.us`.
- Legacy React frontend at `~/Documents/Development/Webstorm/nfl/` is the visual + UX reference.

## Season boundaries

⚠️ **Cap every season picker at `WeekSelection.currentSeason`, never at the last *completed*
season.** The backend publishes a season's schedule and predictions months ahead of kickoff, so
"most recently completed season" as a picker ceiling silently hides the upcoming one — measured
2026-08-29: `/api/preds/2026/w1` served 16 games while the app offered 2025 as its newest choice
and defaulted Predictions to it, so 2026 was unreachable from any screen. `WeekSelection` now
exposes `latestSelectableSeason` (= `currentSeason`) for ceilings; `defaultYear` (last completed
season) stays the *default* only for backward-looking views (Results, Picks History).
⚠️ The failure renders as an empty/wrong-year screen, not an error — it reads as "the data isn't
there yet" when the data is fine.

## Week / season selection (`Views/Components/SeasonWeekToolbar.swift`)

Predictions, Results, Picks Active and Picks History share ONE toolbar component: two short
menus, **Week first, then Season**, labels showing the current choice. `WeekSelection.currentWeek
(for:)` opens each of them on the week in progress (Tuesday rollover → the *upcoming* slate from
Tuesday on); off-season and other seasons fall back to week 1.
⚠️ Until 2026-09-16 each screen carried its own copy of one combined menu with Season above
Week. Seasons run 2026 → 1999, so the Week rows sat below 28 season rows and the only way to
reach week 2 was to scroll the menu past 1999 — on Mac and phone alike. The control existed; it
was unreachable, and every screen also defaulted to week 1 all season. ⭐ A picker that needs
scrolling to reach its second section is the same bug as no picker; keep each menu shorter than a
screen. Standings keeps its own season-only menu (no week, short list).

## Pickers

Two pickers forever: **Jim** and **Tom**. No rooms, no Socket.IO. Pick state is polled (5–15s) from the picks endpoints.

## Conventions

- SwiftUI + async/await. No Combine, no UIKit unless absolutely needed.
- One `APIClient` actor for all backend calls. Decode at the boundary.
- Read `~/Documents/Development/Guides/SwiftUI Best Practices & Visual Design — 2026.md` for the style guide before introducing new patterns.
- Defer state management framework decisions until a real screen needs it. Default to `@Observable` + plain types.
