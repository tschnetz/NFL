# NFL SwiftUI client

iOS/macOS/iPadOS SwiftUI client for the personal NFL stack. Backend is deployed and serving real data; this repo is the frontend port from the legacy React app at `~/Documents/Development/Webstorm/nfl/`.

## Read first

- **`BACKEND_API.md`** (in this repo) — the API contract: every endpoint, every payload field, sign conventions, recommended Codable shapes, first-steps plan. Start here.
- **`MIGRATE_MINI.md`** (in this repo) — the master plan for the whole migration. The backend phases are done; the frontend section is what we're starting now.
- **`Docs/SwiftUI Visual Design & Polish — 2026.md`** — the design system to follow.
- **`Docs/Tom's Best Practices — SwiftUI, iOS, iPadOS, macOS & Widgets (2026 Edition).md`** — coding conventions for this codebase.

## Where the backend lives

- **Live**: `https://nfl.schnetz.us` (Mac Mini, Cloudflare Tunnel). Serves real predictions.
- **Repo**: `~/Documents/Development/IntelliJ/Python/NFL/` — FastAPI + Postgres + nflverse. If a wire shape needs to change, open that repo, edit the relevant router under `app/routers/`, write a test, `./deploy/sync.sh`.
- **Auth**: bearer-token middleware wired but `API_KEY` is unset on the Mini — unauthenticated requests work today.

## Current state of this repo

⚠️⚠️ **This section asserted "Nothing else has been written" for 82 days while the client was being
built.** Measured 2026-08-27: **34 Swift files, ~5,865 lines, five shipped tabs.** The claim also
propagated — `MY_PORTFOLIO.md` carried "the SwiftUI client is still a scaffold" off the back of it,
which is why a stale doc is worse than a missing one. Re-measure before trusting a state claim here.

- **Five tabs** (`Views/Tabs/RootView.swift`, Pigskin pattern): Scoreboard · Schedule · Results ·
  More · Picks. Picks has Active / History / Standings sub-pages.
- **Structure** mirrors Pigskin: `API/APIClient.swift` (one actor), `Models/`, `Services/`,
  `Views/{Tabs,Game,Team,Picks,Predictions,Standings,Settings,Onboarding,Components}`.
- **Navigation uses closure-based `NavigationLink`s** — switched deliberately from the value-based
  form in Teams and More; follow that when adding screens.
- Backend is **fully ready to consume** — every endpoint in `BACKEND_API.md` works against
  `nfl.schnetz.us`.
- Legacy React frontend at `~/Documents/Development/Webstorm/nfl/` is the visual + UX reference.

## Pickers

Two pickers forever: **Jim** and **Tom**. No rooms, no Socket.IO. Pick state is polled (5–15s) from the picks endpoints.

## Conventions

- SwiftUI + async/await. No Combine, no UIKit unless absolutely needed.
- One `APIClient` actor for all backend calls. Decode at the boundary.
- Read `Docs/Tom's Best Practices...` for the style guide before introducing new patterns.
- Defer state management framework decisions until a real screen needs it. Default to `@Observable` + plain types.
