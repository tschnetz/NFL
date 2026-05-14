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

- `NFL/NFLApp.swift` + `NFL/ContentView.swift` are the xcodegen scaffold (~40 lines total). Nothing else has been written.
- Backend is **fully ready to consume** — every endpoint listed in `BACKEND_API.md` works against `nfl.schnetz.us`.
- Legacy React frontend at `~/Documents/Development/Webstorm/nfl/` is the visual + UX reference. Routes consumed there are 1:1 with what the backend now serves.

## Pickers

Two pickers forever: **Jim** and **Tom**. No rooms, no Socket.IO. Pick state is polled (5–15s) from the picks endpoints.

## Conventions

- SwiftUI + async/await. No Combine, no UIKit unless absolutely needed.
- One `APIClient` actor for all backend calls. Decode at the boundary.
- Read `Docs/Tom's Best Practices...` for the style guide before introducing new patterns.
- Defer state management framework decisions until a real screen needs it. Default to `@Observable` + plain types.
