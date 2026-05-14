# NEXT — Predictions / Standings / Teams / Results expansion

After the React parity audit (2026-05-16), four legacy routes are still missing from
the SwiftUI client:

- `/preds` — week-level predictions summary (best-bets ranked list, strength
  distribution, performance tiles, top totals + spreads).
- `/standings` — AFC/NFC toggle with divisional grouping.
- `/team` — Team browser with Roster / Schedule / Stats / Leaders tabs.
- `/results` — past-weeks-only game list (currently folded into Games).

We're following Pigskin's pattern: **pre-load aggregates into Postgres** so the
client never blocks on an external API for screens that browse historical data.
Pigskin uses CFBD bulk CSVs + a weekly archive script; the NFL equivalent is
nflverse via `nflreadpy`.

## Patterns we're adopting from Pigskin

**Backend** (`~/Documents/Development/IntelliJ/Python/Pigskin/`)

- **DB-first read paths.** Service-layer pattern: if all games for a week are
  `completed` in DB, serve from DB; otherwise fall through to live source.
  Eliminates ESPN/external calls for past weeks. See
  `app/services/games.py` for the gating template.
- **Composite aggregate tables.** `team_season_stats`, `team_season_advanced`,
  `team_records`, etc. populated once and refreshed weekly. A single SQL query
  replaces several upstream calls.
- **Idempotent upsert backfill scripts.** `scripts/cfbd_archive.py` uses
  `INSERT … ON CONFLICT DO UPDATE` so weekly cron + manual reruns are safe.
- **Weekly pipeline orchestrator.** `scripts/weekly_pipeline.py` with
  `~/.pigskin/pipeline_state.json` gates each step on mtime/state. Already
  scheduled via `launchd/com.pigskin.weekly.plist`.

**Frontend** (`~/Documents/Development/Swift/Pigskin/`)

- **TabView with `.sidebarAdaptable`** — bottom tabs on iPhone, sidebar on
  iPad/Mac, no extra code.
- **`WeekSelection` as `@EnvironmentObject`** — year + seasonType + week shared
  across Predictions / Results (and any future Rankings). Standings/Teams share
  only year. Change the week once, multiple tabs pivot.
- **`AppSettings` singleton** (UserDefaults + iCloud KV) — API key, active
  picker (Jim/Tom), favorite teams. Collapses Settings + Onboarding into one
  piece of infrastructure.
- **`LoadState` enum + `ContentUnavailableView`** — already mirrored in NFL.
- **Reusable components**: `YearWeekPicker`, `ConferenceLogoView` (we'll do
  `DivisionLogoView`), `WinProbabilityBar`.

## Backend work (Slice B1 — first)

Lives in `~/Documents/Development/IntelliJ/Python/NFL/`.

**New tables (Alembic migration `0002_team_aggregates.py`):**

- `team_records` — per `(season, season_type, team_abbr)`: wins / losses / ties,
  conference_wins / conference_losses, division_wins / division_losses,
  home_wins / home_losses, away_wins / away_losses, points_for / points_against,
  rank_within_division, current_streak.
- `team_season_stats` — per `(season, team_abbr)`: JSONB box aggregates from
  nflverse player_stats rolled up at team level (pass yards, rush yards,
  points scored, points allowed, turnovers, third-down %, red-zone %, etc.).
- `divisions` — seed table (8 rows: AFC East/North/South/West + NFC
  East/North/South/West) mapping abbreviation → conference + division name.

**Backfill script:** `scripts/refresh_team_aggregates.py`

- `compute_team_records(season)` — read from `games_historical`, derive W-L /
  splits via SQL aggregation, upsert into `team_records`.
- `compute_team_season_stats(season)` — `nflreadpy.load_player_stats(season)`,
  roll up to team-week then to team-season, upsert as JSONB.
- Idempotent. Run for `[2020 … current]` on first invocation; weekly cron for
  the current season.
- Wire into the existing weekly refresh launchd plist.

**Routes (additive, no breaking changes):**

- `GET /api/standings` — already exists. Verify shape; extend to include
  divisional grouping + conference splits if not already present.
- `GET /api/team-stats/{season}/{team_abbr}` — return joined team_records +
  team_season_stats JSONB for one team.
- `GET /api/preds/summary/{season}/w{week}?seasonType=regular` — aggregate the
  per-game predictions for the week: best-bets count + by-strength breakdown,
  spread / total counts, perf tiles (win % vs final outcomes when graded),
  top-N spreads, top-N totals.

**Service-layer pattern:** mirror Pigskin's frozen-week gating. For
`/api/standings?season=2024`, read from `team_records` (preloaded). For
`/api/standings?season=2026` mid-season, read whatever's in `team_records`
(stale until refresh) — don't fall through to ESPN. The weekly cron is the
freshness guarantee.

## Frontend work (Slices F1–F5)

Lives in `~/Documents/Development/Swift/NFL/`.

**Slice F1 — nav restructure + shared state**

- `RootView` → `TabView` with `.sidebarAdaptable`. Five tabs:
  - **Games** (existing — schedule + per-game predictions inline)
  - **Predictions** (new — week-level summary; reuses `WeekSelection`)
  - **Standings** (new — drill-down nav)
  - **Teams** (new — drill-down nav)
  - **Picks** (existing)
- New `WeekSelection.swift` `@MainActor @Observable` env object: `year`,
  `seasonType`, `week`. Inject at `NFLApp` root via `.environment(_:)`.
- New `AppSettings.swift` singleton: `apiKey`, `activePicker` (Jim / Tom /
  none), `favoriteTeamAbbrs: Set<String>`. UserDefaults; iCloud KV later.
- Migrate `PicksViewModel.season/week` and `GamesViewModel.season/week` to
  read from `WeekSelection` (replace the local state where it makes sense;
  Games may keep an override since it's "browse any season").

**Slice F2 — Predictions tab**

- `PredictionsView` + `PredictionsViewModel` + `PredictionsSummary` model.
- Hits `/api/preds/summary/{season}/w{week}` + `/api/preds/{season}/w{week}`.
- Sections: summary tiles (games count, best-bets breakdown), strength
  distribution chart, top spreads list, top totals list, all best-bets list
  with per-pick strength capsule + result coloring when graded.
- Reuse `GamePrediction` model + strength capsules from Game detail.

**Slice F3 — Standings**

- `StandingsView` + `StandingsViewModel`.
- Hits `/api/standings` and the new divisional shape.
- AFC/NFC segmented control, sectioned list grouped by division, rows show
  team logo + abbr + W-L + PF/PA + division rank.
- Reuse `TeamLogoView`.

**Slice F4 — Teams browser**

- `TeamsListView` + `TeamsListViewModel` (list with search + division filter).
- `TeamDetailView` with menu picker for sub-tabs:
  - **Schedule** (from `/api/schedule/team/{ABBR}`)
  - **Stats** (from `/api/team-stats/{season}/{team_abbr}`)
  - **Roster** (from `/api/team/{ABBR}/roster`)
- Defer News / Injuries / Leaders (no equivalent endpoints yet).

**Slice F5 — Results**

- Either a separate `ResultsView` (Pigskin-style) or a segmented control
  ("Upcoming / Results") at the top of Games. Decide based on whether F1's
  5-tab bar feels crowded.

## Sequence

1. Backend slice B1 (schema + backfill + routes) → deploy to Mini via
   `./deploy/sync.sh`. Verify endpoints with curl.
2. Frontend F1 (nav + WeekSelection + AppSettings).
3. Frontend F2 (Predictions). High info value, validates B1 pred-summary route.
4. Frontend F3 (Standings). Smallest surface.
5. Frontend F4 (Teams browser). Most surface.
6. Frontend F5 (Results). Quick wrap-up.

## Out of scope (deliberately deferring)

- **Preview / Boxscore / Live game detail** — backend returns 503 for these
  routes; revisit in-season when ESPN gateway lights them up.
- **Rankings** — no NFL equivalent of CFP rankings.
- **Coaches table** — not needed for the four features.
- **News / Injuries on Team detail** — nice-to-haves; can layer after F4 ships.
- **Apple Watch, Widgets, Live Activities, Push notifications** — already on
  the long-term punch list; not part of this expansion.
- **iCloud KV sync** in `AppSettings` — UserDefaults first, KV layer when
  multi-device sync becomes a real need.
