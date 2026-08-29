# Migrate NFL from Render + Upstash + RapidAPI to Mac Mini

> **Status: ✅ complete — archived 2026-08-29.**
> Phases 0–9 all landed. NFL runs on the mini as service #10: FastAPI on
> `:8008`, `nfl_prod` in Postgres, public at `https://nfl.schnetz.us` via
> Cloudflare Tunnel, weekly refresh under `com.nfl.weekly.plist`, registered
> in both backup jobs. Render, Upstash and the RapidAPI dependency are gone.
> Live infra facts are canonical in `~/Documents/Development/Guides/MINI_ENV.md`
> (NFL row); this doc is kept for the *why*, not as a current reference.

Plan for moving the NFL app off the Render-hosted React/Express stack and onto
the Mac mini that already runs Orbit, Braves, Headline, Hearth, WorldCup, ESPN
gateway, SportsBar, Portfolio, and Pigskin. The React UI (which the user
wants to keep visually intact) gets replicated **exactly** in SwiftUI on top
of a new FastAPI + Postgres backend. Paid `nfl-api-data.p.rapidapi.com`
calls get largely replaced with the self-hosted ESPN gateway at
`espn.schnetz.us`.

The two existing NFL-side codebases get **consolidated into one backend**,
exactly like Pigskin did for CFB:

| CFB (already done) | NFL (this plan) |
|---|---|
| `~/Documents/Development/Webstorm/cfb2025/` (React + Express + Upstash) | `~/Documents/Development/Webstorm/nfl/` (React + Express + Upstash) |
| `~/Documents/Development/Python/cfbd/` (Flask predictor, Render-hosted, writes to Upstash key `cfb:preds:*`) | `~/Documents/Development/Python/nfl_predictor/` (Flask/FastAPI "Gridiron API" at `gridiron-api.onrender.com`, writes to Upstash key `nfl:preds:*`) |
| → consolidated into `~/Documents/Development/IntelliJ/Python/Pigskin/` (FastAPI + Postgres + `app/ml/`) | → consolidate into `~/Documents/Development/IntelliJ/Python/NFL/` (FastAPI + Postgres + `app/ml/`) |
| → SwiftUI client at `~/Documents/Development/Swift/Pigskin/` | → SwiftUI client at `~/Documents/Development/Swift/NFL/` (skeleton exists) |

Two Render services (the Express NFL app + the Flask Gridiron API predictor)
become one Mini service. Two Upstash key prefixes (`nfl:preds:*` for
predictions, `room:*` for picks) become Postgres tables.

This doc mirrors the pattern in:

- `~/Documents/Development/Swift/Headline/MIGRATE_MINI.md` — Supabase → Mini cutover
- `~/Documents/Development/IntelliJ/Python/Pigskin/CLAUDE.md` — the cleanest reference for FastAPI + Postgres + ESPN-gateway + Swift on the Mini
- `~/Documents/Development/Guides/MINI_ENV.md` — shared Mini infrastructure reference (Postgres, launchd, Cloudflare Tunnel, deploy pattern)
- `docs/archive/ESPN_SERVICE.md` — what the local ESPN gateway provides

Pigskin (CFB) is the closest analog: same Mini, same two-author "picks"
feature, same flavor of ML predictions, same SwiftUI patterns. **Copy
Pigskin shamelessly.** Where Pigskin already solved a problem, this doc
points to it instead of repeating it.

## Goals

- Kill three external dependencies in one move: **Render** (hosting),
  **Upstash Redis** (state + cache), **RapidAPI nfl-api-data** (paid data).
  Bring the whole stack home.
- Reuse the Mini infrastructure already standing up nine apps. One backup
  job, one tunnel, one ops surface. NFL is service #10.
- Re-platform the clients to **SwiftUI** (iOS + macOS, multi-target) so
  this matches the rest of the personal stack and the existing Swift
  skeleton at `~/Documents/Development/Swift/NFL/`.
- **Preserve the current React UI 1:1.** The mobile-first design, dark
  `bg-metal` palette, week pills, game cards, picks board — all of it
  ports to SwiftUI as a visual-fidelity copy. No redesign opportunity
  here; that's a separate project.
- Reduce/eliminate RapidAPI cost. Use the self-hosted `espn_service`
  gateway (`espn.schnetz.us` / `127.0.0.1:8005`) for everything ESPN
  covers; keep RapidAPI as a **temporary** fallback only for the gaps
  (see Phase 0).

## Non-goals

- **Real-time WebSocket sync for Picks.** The current app uses Socket.IO
  to broadcast pick/unpick events across two users (Jim/Tom). Two-user
  collaboration at NFL cadence (weekly, ~16 picks each) doesn't need
  sub-second latency. Replace with **Postgres + polling + offline queue**
  (Pigskin pattern) and drop Socket.IO entirely. Saves us a Redis
  dependency and a whole class of state-sync bugs. Picks land within 5–30s
  on the other client — acceptable.
- **PWA / web frontend.** This becomes Apple-platform-only. The React
  app stays available as a fallback for ~2 weeks post-cutover, then gets
  archived.
- **Containerization.** Native Homebrew Postgres + launchd, same as every
  other Mini app.
- **Rebuilding the prediction model.** The existing
  `~/Documents/Development/Python/nfl_predictor/` (a.k.a. "Gridiron API")
  is a working `nfl_data_py`-based ML predictor (GradientBoosting +
  Ridge, EPA features, Platt + isotonic calibration, market blending,
  injury/QB-continuity adjustments). Port it **verbatim** into
  `app/ml/`, mirroring Pigskin's `cfbd` → `app/ml/` migration. Keep the
  same features, the same model files, the same training pipeline.
  Just change the persistence target from Upstash key
  `nfl:preds:{season}:w{week:02d}:v{version}` to a Postgres
  `predictions` table.
- **Reworking how Picks scoring is computed.** Port the existing logic
  (cover/non-cover, doubles 2×, presses, push, postseason week mapping)
  verbatim from `backend/routes/picksRoute.js` and pin it down with
  pytest cases mirroring Pigskin's `test_picks_scoring.py`.
- **Carrying over dead code.** Both `Webstorm/nfl/` and
  `Python/nfl_predictor/` accumulated dead code, archived models,
  experimental notebooks, `(1).js` copies, and old per-week JSON
  snapshots over the course of the season. **Only the live code paths
  port.** That means: from `nfl_predictor`, bring `training/train.py`,
  `training/score_and_publish.py`, `scripts/build_features.py` +
  `build_feature_frame.py` + `data_sources.py` + `roster_features.py` +
  `best_bets.py`, the **single most recent** margin + totals `.joblib`
  pair (with their `.meta.json` + `.metrics.json`), and the tests that
  actually run. Drop everything else — old models, `archive/`,
  `examples/`, `notebooks/`, the parquet test fixtures, `compare-models.py`,
  `nfl_pipeline.py` stub, `predict_2025.py`, `static_data (1).py`,
  `app (1).py`, every `*(1).{js,py}` duplicate. From `Webstorm/nfl/`,
  bring routes + services that are actually wired into the React app
  today; drop the `(1).js` duplicates and any unreferenced files. If
  it's not on a code path from `App.jsx` or the FastAPI router, it
  doesn't port.

---

## Source-of-truth inventory (current Render + Upstash + RapidAPI)

What's being moved off (three production surfaces, two Render services,
one managed Redis):

### React + Express stack (Render service #1)

- **Frontend:** Vite + React 19, TanStack Query v5, Tailwind, Socket.IO
  client, IndexedDB persistence. ~10 pages, ~40 hooks, ~50 components.
  Lives in `frontend/src/`.
- **Backend:** Express 4, Socket.IO server. ~17 route files in
  `backend/routes/`. Repo: `~/Documents/Development/Webstorm/nfl/`.
- **Deployment:** single Render service serving built frontend (`/dist`)
  + `/api/*` from the same process on a single Render port.

### Gridiron API — `nfl_predictor` (Render service #2)

Repo: `~/Documents/Development/Python/nfl_predictor/`. Hosted at
`gridiron-api.onrender.com`. **This is where the React app's
`useWeeklyPredictions` data comes from** — `nfl_predictor` writes the
output of `training/score_and_publish.py` to Upstash at
`nfl:preds:{season}:w{week:02d}:v{version}`; the React app's
`backend/services/predictionService.js` reads from the same key.

Stack:

- Built around `nfl_data_py` (the now-deprecated nflverse Python
  library — schedules, weekly stats, play-by-play with EPA, betting
  lines, injuries, snap counts). **Not RapidAPI.** This is one of
  three reasons RapidAPI's `/nfl-predictor` endpoint is unnecessary —
  we already have our own model. As part of the port into `app/ml/`
  (Phase 7), swap the import to `nflreadpy` (same nflverse data,
  active maintenance, drop-in API differences: `import_*` → `load_*`).
- `training/train.py` — production training. GradientBoostingRegressor
  for margin, Ridge for totals, Platt calibration for win prob,
  isotonic calibration for cover prob, heteroskedastic sigma model.
- `training/score_and_publish.py` — generate predictions per
  season/week, blend with market lines (default `market_influence=0.3`),
  apply injury/QB-continuity adjustments, compute spread + total edges,
  build best-bets (Strong ≥3pt / Medium ≥2pt / Lean ≥1pt), publish to
  Redis or save JSON/Parquet.
- `scripts/build_features.py` + `build_feature_frame.py` — EPA-based
  feature engineering with graceful fallbacks when data is missing.
- `models/` — 20+ archived `.joblib` model artifacts; each has a
  matching `.meta.json` (feature list, calibration coefficients,
  market integration tau) and `.metrics.json` (MAE, RMSE, R², AUC).
  Latest: `model-20251215-181113-totals.joblib`. Bundle the *latest*
  pair (margin + totals) when porting.

Public surface (from `docs/frontend.md`):

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /predictions?season=&week=&version=` | none | per-week predictions |
| `GET /predictions/upcoming?season=&version=` | none | next slate with future games |
| `POST /admin/retrain-and-cache` | `X-API-Key` header | trigger retrain + republish |

Response shape: per-game `{season, week, game_id, home_team, away_team, spread_line, over_under_line, pred_home_margin, pred_home_win_prob, pred_total_points, pred_home_score, pred_away_score}`. There are no LLM-generated *narratives* — the "predictions" are pure model numbers + edges + best-bet labels. The React app renders them as cards.

**Why this matters for the migration:** the prediction service is the
direct analog to the `cfbd` Flask app that Pigskin absorbed. Pigskin's
`app/ml/` is the template for what NFL's `app/ml/` becomes after the
port. Same shape: 1 inference module, 1 training script, joblib
artifacts in `app/ml/models/`, feature builder in `app/ml/features.py`,
weekly pipeline in `scripts/weekly_pipeline.py`.

### Upstash Redis (managed)

Two responsibilities, both moving to Postgres on the Mini:

1. **Cache layer** for RapidAPI responses (key prefixes: `nfl:sched:*`,
   `nfl:desc`, `nfl:calendar-*`, `nfl:venues:2025`, per-team and per-game
   keys). TTLs from 45s (scoreboard) to 24h (past games) to indefinite
   (calendar/venues).
2. **Picks state** for the two-user collaborative pick feature. Four keys
   per room+week:
   - `room:${roomId}:state:${season}:${week}` — status, currentTurn, totalGames, lockedAt
   - `room:${roomId}:picks:${season}:${week}` — HSET keyed by user → `byGameId → {teamId, pickedAt, doubled?, pressedBy?}`
   - `room:${roomId}:spreads:${season}:${week}` — snapshot of odds at close time
   - `room:${roomId}:scores:${season}:${week}` — final tallies + per-game point details
   - Plus `room:${roomId}:history` and `:history:map`

### RapidAPI (`nfl-api-data.p.rapidapi.com`)

11 endpoints currently called from `backend/services/`:

| Endpoint | Service | Purpose |
|---|---|---|
| `/nfl-scoreboard` | scoreboardService.js | weekly/daily scoreboard |
| `/nfl-predictor` | previewService.js | per-game win-probability model output |
| `/nfl-gamesummary` | boxscoreService.js | boxscore (teams, players, linescore) |
| `/nfl-team-record` | standingsService.js | W-L, division, playoff seed |
| `/nfl-team-roster` | rosterService.js | roster |
| `/nfl-depth-chart` | rosterService.js | depth chart |
| `/nfl-team-statistics` | teamStatsService.js | team offense/defense stats |
| `/nfl-team-leaders` | teamLeadersService.js | top-5 passers, rushers, etc. |
| `/nfl-singlevenue` | venueService.js | stadium details |
| `/nfl-betting-odds` | eventOddsService.js | spread/total/moneyline |
| `/nfl-scoringplays` | scoringPlaysService.js | scoring-play summary |

Also: external weather service (independent of RapidAPI — check what
`backend/services/weatherService.js` uses; likely Open-Meteo or similar
free API. Keep as-is.)

### Frontend surface (what we're replicating in SwiftUI)

- **Pages (10):** Scoreboard (`/`), Schedule, Results, Predictions,
  Picks, Standings, Team, Boxscore, Preview, LiveGameModal.
- **Hooks (~40):** wrap TanStack Query. Each maps to one or more
  backend endpoints. See agent inventory above; full list in
  `frontend/src/hooks/`.
- **Component folders:** `scoreboard/`, `schedule/`, `picks/`,
  `predictions/`, `team/`, `boxscore/`, `live/`, `standings/`,
  `games/`, `venue/`, `common/`, `ui/`, `pwa/`.

---

## Target machine reality

The Mini (`schnetzermini@Schnetzer-mini.local`, static `192.168.7.200`) is
fully provisioned. From `~/Documents/Development/Guides/MINI_ENV.md` (as of 2026-05-11):

- [x] **PostgreSQL 18** via Homebrew, launchd-managed, trust auth for
      `schnetzermini` user. NFL gets a separate `nfl_prod` database on
      the same instance.
- [x] **Python 3.14** via Homebrew at `/opt/homebrew/bin/python3.14`;
      `uv` at `/opt/homebrew/bin/uv`. Pigskin's preferred toolchain.
- [x] **Redis 7** running for Portfolio + Braves caches. **We don't need
      it** for NFL — see "Why no Redis" below.
- [x] **Cloudflare Tunnel `mini`** with the `schnetz.us` zone. NFL adds
      one ingress rule. No new tunnel.
- [x] **ESPN gateway** at `espn.schnetz.us` (`127.0.0.1:8005`). The NFL
      backend talks to it via **loopback** (`http://127.0.0.1:8005`),
      not the public hostname. Pattern verified by Pigskin's
      `app/clients/espn.py`.
- [x] **Central Postgres backup** at
      `~/.mini/scripts/backup-postgres.sh`. Adding `nfl_prod` is one new
      line in the `JOBS` array.
- [x] **Apps directory convention:** `~/Applications/NFL/` for code;
      `~/.nfl/` for `.env` + logs (chmod 600 on `.env`).

### Why no Redis for NFL

Pigskin (the closest analog) **does** use Redis for read-through caching
of CFBD responses. NFL doesn't need that because:

1. The ESPN gateway already does its own caching (Postgres-backed DB rows
   plus per-source schedules). We just call it.
2. Picks state moves to Postgres rows, not Redis HSETs (see Phase 6).
3. **Historical data is backfilled into Postgres locally** — same
   strategy Pigskin uses for CFBD season history. The new
   `nfl_prod` DB gets a one-shot bulk load from `nflreadpy` (the
   maintained nflverse successor to the deprecated `nfl_data_py`):
   schedules, weekly stats, play-by-play summaries, betting lines,
   rosters, depth charts, injuries, snap counts — covering ~2016
   through current. After that, a weekly refresh job pulls the same
   tables forward; live in-game state comes from the ESPN gateway.
   No per-request fan-out to external APIs from user-facing endpoints.
   Same pattern as Pigskin's `alembic/versions/0002_historical_tables.py`.

If we ever need a hot cache, Redis is already running on `:6379` — just
add a client. Don't bother on day one.

---

## Port and hostname layout

Per `~/Documents/Development/Guides/MINI_ENV.md`, **next free port is `:8008`**. Apps in the 8000s
are FastAPI; Node services use `:3xxx`.

| Service | Local port | Public URL |
|---|---:|---|
| Orbit | 8000 | `https://orbit.schnetz.us/` |
| Braves | 8001 | `https://braves.schnetz.us/` |
| Headline | 8002 | `https://headline.schnetz.us/` |
| Hearth | 8003 | `https://hearth.schnetz.us/` |
| WorldCup | 8004 | `https://worldcup.schnetz.us/` |
| ESPN gateway | 8005 | `https://espn.schnetz.us/` |
| SportsBar | 8006 | `https://sportsbar.schnetz.us/` |
| Pigskin | 8007 | `https://pigskin.schnetz.us/` |
| **NFL** | **8008** | **`https://nfl.schnetz.us/`** |
| Portfolio | 3001 | `https://portfolio.schnetz.us/` |

Cloudflare terminates TLS; FastAPI listens on plain HTTP at
`127.0.0.1:8008`.

---

## Phase 0 — Data-source split: ESPN gateway + nflverse (do this first)

**Decision the rest of the plan depends on:** for each RapidAPI call
the React app makes today, what's the cleanest free replacement —
ESPN gateway (live current-day data), `nflreadpy` / nflverse (weekly
snapshots, completed-game data, historical tables), or something
else?

The audit-verified ESPN gateway state (as of 2026-05-13) ships exactly
6 client methods (`get_teams`, `get_scoreboard`, `get_standings`,
`get_news`, `get_league_injuries`, `passthrough`) — **not** the
broader set of `get_team_stats` / `get_team_leaders` / `get_odds` /
`get_cdn_game` etc. this doc originally assumed. Building 7 new
gateway endpoints to wrap RapidAPI-equivalent ESPN calls is the wrong
fight when nflverse already serves most of that surface for free, via
parquet downloads, with no rate limit. The right split:

**ESPN gateway** — for data that has to be live within minutes during
a game. Scoreboard ticks, in-game state, live scoring plays during a
game, standings, news, injuries. Already shipped or trivial extensions.

**`nflreadpy`** (the maintained successor to the deprecated
`nfl_data_py`) — for everything else. Rosters, depth charts, team
stats, team leaders, settled betting lines, completed-game boxscores +
scoring plays, snap counts, advanced metrics, historical seasons.
Weekly refresh into Postgres tables; no live API at request time.

Per-endpoint decisions:

| RapidAPI today | Replacement | Plan |
|---|---|---|
| `/nfl-scoreboard` (week/day/year) | **ESPN gateway** | `GET /api/v1/events/?league=nfl&date=YYYY-MM-DD` already DB-backed, refreshed every 120s during live games. Small patch: add `week` filter param. Increase cadence to ~2 min during NFL game windows if not already. |
| `/nfl-team-record` (standings) | **ESPN gateway** | `GET /api/v1/standings/?league=nfl` already DB-backed at 6h cadence. Small patch: add `playoff_seed` column to `Standing` model (ESPN returns it in `standings.entries[].stats[]` but ingest currently skips it). |
| `/nfl-singlevenue` | **NFL backend static seed** | Gateway's `Venue` model auto-populates from scoreboard ingest but `capacity`/`indoor` are inconsistently set by ESPN. Ship a curated `app/data/venues.json` covering all 32 NFL stadiums (ported from the React app's `venueWeatherMapping.js`, which also has weather-station coordinates). Read at startup. **No gateway change required.** |
| `/nfl-gamesummary` (boxscore) | **nflverse for completed games, ESPN passthrough for live current week** | Completed games: derive linescore + team stats from `nflreadpy.load_pbp()` + `load_player_stats()` rolled to game grain. Live current-week game: optionally add a passthrough route to the gateway forwarding ESPN's CDN summary endpoint with a 60s TTL (one-line addition since gateway already has `passthrough()`). |
| `/nfl-team-roster` | **nflverse** | `nflreadpy.load_rosters_weekly(seasons=...)` returns the per-player roster — exactly what the React Team page renders. Refresh weekly into a `rosters_weekly` Postgres table. |
| `/nfl-depth-chart` | **nflverse** | `nflreadpy.load_depth_charts(seasons=...)`. Refresh weekly into a `depth_charts` table. Merge with rosters in `app/services/roster.py` to match the React app's combined response shape. |
| `/nfl-team-statistics` | **nflverse** | Aggregate from `nflreadpy.load_pbp()` (offensive/defensive EPA, success rate, etc.) — or use the prebuilt `load_team_stats(...)` if applicable. Refresh weekly into a `team_stats_season` table. |
| `/nfl-team-leaders` | **nflverse** | Top-N per category from `nflreadpy.load_player_stats(seasons=...)` sorted server-side at query time. No new ingest needed beyond the player-stats refresh; compute on read. |
| `/nfl-betting-odds` | **nflverse for settled; ESPN gateway for live** | `nflreadpy.load_schedules()` includes spread/total/moneyline at close. For intraday live movement (rare requirement — only `useEventOddsBatch` on the Picks page uses it pre-lock), add a small gateway passthrough route forwarding ESPN's odds endpoint. |
| `/nfl-scoringplays` | **nflverse for completed; ESPN gateway for live** | Completed games: filter `nflreadpy.load_pbp()` to scoring rows. Live-game updates inside `LiveGameModal`: add a passthrough route forwarding ESPN's scoring-plays endpoint with a 30–60s TTL. |
| `/nfl-predictor` (win-prob model) | **Drop entirely** | Replaced by the ML port (`nfl_predictor` → `app/ml/`, Phase 7). The React app already reads Gridiron API output; this just moves the producer in-process. |
| Weather (`backend/services/weatherService.js`) | **Open-Meteo (unchanged)** | Move into the new backend as `app/services/weather.py` with httpx + a Postgres `weather_cache` table keyed by `(lat, lon, hour_truncated_iso)`. |

### What this means in terms of order of operations

1. **Two small gateway patches** (the only ESPN-side work needed for
   day-one): add `week` query filter to `/events/`; add `playoff_seed`
   column + ingest line to `Standing`. ~1 day total. Reusable across
   SportsBar / WorldCup.
2. **Optional gateway passthroughs** for the handful of *live*-only
   endpoints (boxscore, scoring plays during a game, intraday odds).
   These are 5–10 lines each — one passthrough route per endpoint
   forwarding to ESPN's URL with a short TTL — and only need to land
   before the LiveGameModal feature is wired in the SwiftUI client.
3. **Build the nflverse refresh pipeline** in the NFL backend:
   `app/services/nflverse.py` + `scripts/refresh_nflverse.py` +
   `launchd/com.nfl.weekly.plist`. Weekly job (Tuesday morning ET,
   after MNF) pulls `load_schedules`, `load_pbp`, `load_player_stats`,
   `load_rosters_weekly`, `load_depth_charts`, `load_injuries`,
   `load_snap_counts` into Postgres tables. First run is the
   historical backfill (see Phase 3.5); subsequent runs upsert the
   latest week's deltas.
4. **Stand up the NFL FastAPI backend** that reads from those local
   Postgres tables for everything except scoreboard / standings /
   live-game endpoints (which call the gateway via loopback). Port
   `nfl_predictor` into `app/ml/` (Phase 7) in parallel — same data
   source (nflverse), same Postgres tables.
5. **Cancel RapidAPI as soon as the new backend ships.** There is no
   "bulk historical pull before cancellation" because nflverse already
   has the same historical data (and more) for free — no need to drain
   the paid subscription on the way out.

The gateway patches and live passthroughs are reusable across
SportsBar / WorldCup / any future Mini app. The nflverse pipeline is
NFL-specific but mirrors how `nfl_predictor` (the existing predictor)
already consumes the same data — no new tools to learn.

### Live updates from the gateway (no external webhooks)

There's no free public NFL webhook surface worth building around.
Paid push feeds (Sportradar, SportsDataIO, Genius Sports) provide
sub-second play-by-play push but at enterprise pricing ($300–$1,000+/mo
for NFL). ESPN / NFL.com / nflverse don't push — ESPN is polling-only,
nflverse is daily/weekly parquet snapshots. The Odds API has webhooks
for odds movement only (~$30–60/mo) — could be useful for Picks pre-lock
line shifts, but not worth the spend.

**Use the gateway's existing Postgres `LISTEN/NOTIFY` channel.**
SportsBar already does this (per MINI_ENV.md): the ESPN gateway emits
NOTIFY on `espn_prod.event_changed` whenever its scoreboard ingest
upserts an event row; SportsBar listens and fans out APNs silent
pushes to wake the iOS widget. NFL gets the same wiring for free:

1. ESPN gateway polls ESPN every 120s during live game windows
   (existing behavior — `_has_live_event_for()` predicate).
2. When an event row changes, gateway fires `NOTIFY event_changed,
   '<event_id>'`.
3. NFL backend's lifespan opens a long-lived asyncpg connection on
   the gateway DB, `LISTEN event_changed`, and on each notification
   either (a) refreshes its own cached `live_game_state` row for that
   event, or (b) sends an APNs silent push to the SwiftUI client to
   trigger a refresh of LiveGameModal / Scoreboard.

Two-minute resolution is fine for the live UX — two-user fantasy
picks don't need sub-second. This pattern gives the NFL app "webhook
behavior" without an external service, riding on infra that's
already paid for and proven.

If a feature later needs faster than 120s (e.g. live scoring-play
toasts), the lever is to tighten gateway poll cadence on `nfl`
during game windows, not to bolt on a paid push service.

---

## Phase 1 — Scaffold the FastAPI backend (MacBook)

Backend lives at `~/Documents/Development/IntelliJ/Python/NFL/`, sibling
to Pigskin/Headline/Orbit/Braves. Copy Pigskin's layout almost verbatim.

```
~/Documents/Development/IntelliJ/Python/NFL/
├── app/
│   ├── main.py                      # FastAPI factory + lifespan (singletons)
│   ├── config.py                    # pydantic-settings, env-driven
│   ├── auth.py                      # bearer-token dependency (/healthz exempt)
│   ├── database.py                  # async SQLAlchemy 2 + asyncpg
│   ├── healthz.py                   # GET + HEAD via api_route() — see MINI_ENV
│   ├── deps.py                      # singletons: espn client, cache, ml artifacts
│   │
│   ├── clients/
│   │   └── espn.py                  # copy from Pigskin, point at ESPN gateway
│   │                                # (no RapidAPI client — nfl_predictor replaces /nfl-predictor; gateway covers the rest)
│   │
│   ├── core/
│   │   ├── cache.py                 # Postgres-backed read-through (no Redis); in-flight coalescing
│   │   └── season.py                # current_nfl_season(), week_classification()
│   │
│   ├── models/                      # SQLAlchemy ORM
│   │   ├── picks.py                 # rooms, picks, weeks, spreads, scores, history
│   │   ├── predictions.py           # LLM narratives + grades (vNN keyed)
│   │   ├── cache.py                 # generic cache rows keyed by (resource, key) → JSONB, fetched_at
│   │   └── venues.py                # venue + weather-station mapping
│   │
│   ├── routers/                     # thin handlers; business logic in services/
│   │   ├── scoreboard.py            # day, week, year
│   │   ├── schedule.py
│   │   ├── preview.py
│   │   ├── boxscore.py
│   │   ├── team.py                  # teams, roster, stats, leaders, standings
│   │   ├── standings.py
│   │   ├── venue.py
│   │   ├── weather.py
│   │   ├── calendar.py
│   │   ├── event_odds.py
│   │   ├── scoring_plays.py
│   │   ├── predictions.py           # /preds/:season/w:week
│   │   ├── picks.py                 # 10 endpoints (state + mutations + score)
│   │   └── live_game.py             # day-scoped scoreboard + plays for LiveGameModal
│   │
│   ├── services/                    # business logic
│   │   ├── scoreboard.py
│   │   ├── picks.py                 # PORT verbatim from picksRoute.js; pure-function scoring
│   │   ├── predictions.py
│   │   ├── boxscore.py
│   │   ├── team_stats.py
│   │   ├── team_leaders.py
│   │   ├── roster.py
│   │   ├── standings.py
│   │   ├── event_odds.py
│   │   ├── scoring_plays.py
│   │   ├── venue.py
│   │   ├── weather.py
│   │   ├── calendar.py
│   │   └── preview.py
│   │
│   ├── data/
│   │   └── venues.json              # ported from frontend/src/utils/venueWeatherMapping.js
│   │
│   └── ml/                          # PORTED FROM ~/Documents/Development/Python/nfl_predictor/
│       ├── inference.py             # score_and_publish.py → callable function predict_week(season, week)
│       ├── features.py              # scripts/build_features.py + build_feature_frame.py merged
│       ├── data_sources.py          # scripts/data_sources.py (load_schedule, last_completed_week, etc.)
│       ├── roster_features.py       # scripts/roster_features.py (injury/QB-continuity health features)
│       ├── best_bets.py             # scripts/best_bets.py (edge → Strong/Medium/Lean)
│       ├── train.py                 # training/train.py
│       ├── data/
│       │   └── (sample inputs kept for tests; nflverse-backed Postgres tables feed prod)
│       └── models/
│           ├── latest-margin.joblib       # symlink to newest model-YYYYMMDD-HHMMSS.joblib
│           ├── latest-margin.meta.json
│           ├── latest-totals.joblib       # symlink to newest model-YYYYMMDD-HHMMSS-totals.joblib
│           └── latest-totals.meta.json
│           (plus archived dated artifacts retained for rollback)
│
├── alembic/
│   └── versions/
│       ├── 0001_picks_initial.py
│       ├── 0002_predictions.py
│       ├── 0003_cache_tables.py
│       └── ...
│
├── scripts/
│   ├── start-backend.py             # waits for pg_isready, execvs uvicorn (copy from Pigskin)
│   ├── weekly_pipeline.py           # orchestrator: ingest → retrain (if needed) → predict → load to Postgres
│   ├── run_week_predictions.py      # one-shot wrapper around app.ml.inference.predict_week()
│   ├── ingest_results.py            # final-score reconciliation after games (for retraining labels)
│   ├── train.py                     # wrapper around app.ml.train (matches Pigskin's scripts/train.py)
│   └── load_predictions.py          # JSON/Parquet → predictions Postgres table
│
├── deploy/
│   ├── sync.sh                      # rsync + uv sync --frozen + alembic + launchctl kickstart (copy Pigskin)
│   ├── setup-tunnel.sh              # one-time CF tunnel ingress (copy Pigskin)
│   └── README.md
│
├── launchd/
│   ├── com.nfl.backend.plist
│   └── com.nfl.weekly.plist         # daily 06:15 ET pipeline (results ingest + retrain + predict)
│
├── tests/
│   ├── test_picks_scoring.py        # PORT verbatim test cases from current Express picks
│   ├── test_cache.py                # in-flight coalescing
│   └── parity/
│       └── run.py                   # diff backend responses vs Render endpoints (cutover safety)
│
├── pyproject.toml
└── .env.example
```

### `pyproject.toml` deps (lifted from Pigskin)

```toml
[project]
dependencies = [
  "alembic>=1.18",
  "asyncpg>=0.31",
  "fastapi>=0.136",
  "httpx>=0.28",
  "joblib>=1.5",          # only needed once ML model ships
  "lightgbm~=4.6.0",      # ML — pinned for parity (same as Pigskin)
  "nflreadpy>=0.1.5",     # nflverse data: schedules, PBP, rosters, depth, stats, injuries, snaps
  "numpy~=2.3.3",
  "pandas~=2.3.3",
  "pydantic-settings>=2.14",
  "scikit-learn~=1.7.2",
  "sqlalchemy[asyncio]>=2.0.49",
  "tenacity>=9.1",
  "uvicorn[standard]>=0.46",
  "xgboost~=3.1.1",
]
```

(`redis` intentionally omitted — see "Why no Redis" above. Add it later
if needed; the dep is cheap.)

### Endpoints — 1:1 with the current React app's hook surface

The frontend hooks already define the contract. Mirror them so the
SwiftUI client (Phase 2) gets a drop-in replacement.

| React hook | New endpoint | Notes |
|---|---|---|
| `useScoreboardWeek` | `GET /api/scoreboard/week/{year}/{week}?type=` | Type=1 pre, 2 reg, 3 post |
| `useLiveScoreboardDay` | `GET /api/scoreboard/day/{date}` | Date as YYYY-MM-DD |
| `useSeasonSchedule` | `GET /api/sched/{season}` | Full season |
| `useWeekGames` | (composite of scoreboard/week + event-odds) | Compose client-side |
| `useWeeklyPredictions` | `GET /api/preds/{season}/w{week}?v=` | LLM narratives from Postgres |
| `useEventOddsBatch` | `GET /api/event-odds/{gameId}` (batch via parallel call) | One per game |
| `useBoxscore` | `GET /api/box/{gameId}` | |
| `usePreview` | `GET /api/preview/{gameId}` | Calls our ML once shipped, falls back to RapidAPI |
| `useTeams` | `GET /api/team` | All 32 + metadata |
| `useTeam` | `GET /api/team/{abbr}` | Single team |
| `useRoster` | `GET /api/roster/{year}/teamId/{teamId}` | Merged roster + depth |
| `useTeamStats` | `GET /api/teamStats/{teamId}?year=` | |
| `useTeamLeaders` | `GET /api/teamLeaders/{teamId}?year=` | |
| `useStandings` | `GET /api/standings/{teamId}?year=` | |
| `useWeather` | `GET /api/weather?lat=&lon=&time=` | Open-Meteo |
| `useVenueEnrichment` | `GET /api/venue/{venueId}` | Gateway + local static |
| `useNflCalendar` | `GET /api/calendar/{year}` | Preseason/regular/playoffs |
| `useLiveGameData` | `GET /api/scoreboard/day/{date}` (polled) | Same endpoint, polled |
| `useLivePlays` | `GET /api/scoring-plays/{gameId}` + plays | |
| `usePicksRoom` | `GET /api/picks/state?season=&week=` | Phase 6. Room dimension dropped — two pickers forever. |
| `usePicksMutations` | `POST /api/picks/{pick,unpick,markDoubles,markPresses,close,score,advanceTurn}` | Phase 6 |
| `useHealth` (new) | `GET /healthz` | GET + HEAD via `api_route()` |

### Schema (Alembic initial migration)

Tables (full DDL deferred to actual migration; this is the shape):

**Picks domain** (port from Pigskin's `models/picks.py`):

- `pickers (id, name)` — seed exactly two rows: Jim and Tom. **Two pickers forever.** No room/multi-user dimension — the React app's `roomId` plumbing was speculative; drop it from the schema entirely.
- `picks_weeks (id, season, week, season_type, status, current_turn, total_games, locked_at, updated_at)` — one row per (season, week). `UNIQUE(season, week, season_type)`.
- `picks (id, week_id, picker_id, game_id, team_id, spread_snapshot, is_double, is_pressed_by_picker_id, points)` with `UNIQUE(week_id, game_id, picker_id)`
- `picks_scores (week_id, picker_id, total)` — flattened scoreboard

**Predictions domain:**

- `predictions (season, week, version, payload JSONB, updated_at)` — primary key `(season, week, version)`. Payload is the LLM narrative array. Loaded by `scripts/generate_weekly_predictions.py`.

**Cache domain** (replaces Upstash):

- `api_cache (resource_key TEXT PRIMARY KEY, body JSONB, fetched_at TIMESTAMPTZ, ttl_seconds INT)` — generic read-through cache. `core/cache.py` reads-or-fetches with in-flight coalescing (Pigskin's pattern).
- `nfl_calendar (year PRIMARY KEY, payload JSONB)` — loaded once per season.
- `venues (espn_id, name, city, state, is_indoor, surface, capacity, weather_lat, weather_lon)` — seeded from `app/data/venues.json` on startup.

**Historical + weekly nflverse data domain** (backfilled and refreshed
via `nflreadpy`, ~Pigskin's CFBD historical tables analog — see
Phase 3.5 for the load step):

- `games_historical (season, week, season_type, game_id, kickoff, home_team, away_team, home_score, away_score, …)` — `nflreadpy.load_schedules()` rows.
- `weekly_stats (season, week, player_id, team, …)` — `load_player_stats()`.
- `pbp_summary (season, week, game_id, team_offense, plays, epa_total, epa_pass, epa_rush, success_rate, pressure_rate, …)` — `load_pbp()` rolled up to team-game grain (the model doesn't need play-level rows for inference; keep the raw `pbp` per-play table for the current season only).
- `betting_lines (season, week, game_id, source, spread, total, moneyline_home, moneyline_away, …)` — from `load_schedules()` (which includes closing lines).
- `rosters_weekly (season, week, team, player_id, position, jersey, status, …)` — `load_rosters_weekly()`.
- `depth_charts (season, week, team, position, depth_position, player_id, …)` — `load_depth_charts()`.
- `injuries (season, week, team, player_id, status, primary_injury, report_status, …)` — `load_injuries()`.
- `snap_counts (season, week, game_id, player_id, offense_snaps, defense_snaps, st_snaps, …)` — `load_snap_counts()`.

Indexes are `(season, week)` and `(season, week, team)` everywhere
that matters. These tables are append-only outside of the current
season; rows for the current season get upserted by the weekly
pipeline.

### Service patterns

Port Pigskin's three patterns wholesale:

1. **Lifespan singletons** (`app/main.py`):
   ```python
   @asynccontextmanager
   async def lifespan(app: FastAPI):
       espn = ESPNGatewayClient(base_url=settings.espn_gateway_url, api_key=settings.espn_gateway_api_key)
       cache = PostgresCache(SessionLocal)
       set_espn(espn); set_cache(cache)
       yield
       await espn.aclose()
   ```
2. **Read-through caching with coalescing** for any external call — Pigskin's `core/cache.py` translates trivially with Postgres rows instead of Redis keys.
3. **Result envelope for mutations**: `Result(ok=True, data=...)` / `Result(ok=False, error="...")`. Route turns `ok=False` into HTTP 400.

### Picks scoring — port verbatim

The scoring logic in `backend/routes/picksRoute.js` is the only piece of
business logic that's actually load-bearing. **Don't reinvent it.**

1. Open the existing JS file alongside `app/services/picks.py`.
2. Translate function-by-function (cover/non-cover, push, spread sign
   parsing, doubles 2×, presses, basePoints argument, postseason week
   mapping).
3. Write the test cases first in `tests/test_picks_scoring.py` —
   directly copy the input/output cases from the React app's behavior
   (you can hit the prod endpoint with curl to capture them, before
   the cutover). Pigskin has 16 test cases for ATS scoring; we should
   end up with similar coverage.

---

## Phase 2 — Scaffold the SwiftUI frontend

The Xcode skeleton already exists at `~/Documents/Development/Swift/NFL/`:

```
Swift/NFL/
├── NFL.xcodeproj/        # existing
├── NFL/
│   ├── NFLApp.swift      # @main entry (Hello-world default)
│   └── ContentView.swift # placeholder
└── Docs/                 # reference: ESPN_SERVICE, MINI_ENV, best-practices, design-polish
```

Mirror Pigskin's structure verbatim. Pigskin's directory layout is the
template:

```
NFL/
├── API/
│   └── APIClient.swift              # actor singleton, ~50 endpoints
├── Models/                          # Decodable value types per resource
│   ├── Game.swift
│   ├── Team.swift
│   ├── Pick.swift
│   ├── Prediction.swift
│   ├── Roster.swift
│   ├── TeamStats.swift
│   ├── TeamLeaders.swift
│   ├── Standings.swift
│   ├── Venue.swift
│   ├── Weather.swift
│   ├── BoxScore.swift
│   ├── PreviewModel.swift
│   ├── LivePlay.swift
│   └── ScoringPlay.swift
├── ViewModels/                      # @MainActor ObservableObject, one per feature
│   ├── ScoreboardViewModel.swift
│   ├── ScheduleViewModel.swift
│   ├── ResultsViewModel.swift
│   ├── PicksViewModel.swift
│   ├── PredictionsViewModel.swift
│   ├── StandingsViewModel.swift
│   ├── TeamViewModel.swift
│   ├── BoxScoreViewModel.swift
│   ├── PreviewViewModel.swift
│   └── LiveGameViewModel.swift
├── Views/
│   ├── Tabs/                        # 6–7 top-level tabs (mirrors React routes)
│   │   ├── ScoreboardTab.swift      # `/`
│   │   ├── ScheduleTab.swift        # `/schedule`
│   │   ├── ResultsTab.swift         # `/results`
│   │   ├── PicksTab.swift           # `/picks`
│   │   ├── PredictionsTab.swift     # `/preds`
│   │   ├── StandingsTab.swift       # `/standings`
│   │   └── TeamTab.swift            # `/team`
│   ├── Game/
│   │   ├── BoxScoreView.swift       # `/boxscore/:gameId`
│   │   ├── PreviewView.swift        # `/preview/:gameId`
│   │   └── LiveGameView.swift       # `/live/:gameId` (sheet, not push)
│   ├── Picks/
│   │   ├── PicksGameCard.swift
│   │   ├── PicksStandings.swift
│   │   ├── WeekScoreSummary.swift
│   │   └── PassTurnFAB.swift
│   ├── Components/                  # shared UI widgets, 1:1 with React `components/common`
│   │   ├── GameCard.swift
│   │   ├── GameCardSkeleton.swift
│   │   ├── WeekPills.swift
│   │   ├── PageHeroHeader.swift
│   │   ├── BottomNav.swift          # might not be needed — TabView covers it
│   │   ├── TeamLogoView.swift
│   │   ├── Linescore.swift
│   │   ├── NetworkStatusBanner.swift
│   │   ├── EmptyState.swift
│   │   └── LoadingSpinner.swift
│   ├── Predictions/
│   │   ├── PredictionCard.swift
│   │   ├── PredictionsSummary.swift
│   │   └── GradingBadge.swift
│   ├── Team/
│   │   ├── TeamHeaderControls.swift
│   │   ├── TeamRosterPane.swift
│   │   ├── TeamSchedulePane.swift
│   │   ├── TeamStatsPane.swift
│   │   └── TeamLeadersPane.swift
│   └── Venue/
│       └── VenueWeatherCard.swift
├── Settings/
│   ├── AppSettings.swift            # @MainActor singleton, mirrors to iCloud KVS
│   ├── WeekSelection.swift          # @EnvironmentObject (year, seasonType, week)
│   └── ActivePicker.swift           # persisted Jim/Tom selection
├── Config.swift                     # baseURL: debug=127.0.0.1:8008, release=nfl.schnetz.us
├── NFLApp.swift                     # entry point (already exists, replace stub)
├── ContentView.swift                # TabView orchestrator (replace stub)
├── Assets.xcassets/
│   ├── TeamLogos/                   # 32 NFL team PNGs (port from frontend/public/logos/)
│   ├── Conferences/                 # AFC, NFC SVGs
│   └── Networks/                    # CBS, FOX, NBC, ESPN, Amazon, Peacock, NFL logos
└── NFL.entitlements                 # iCloud KVS + macOS sandbox + network.client
```

### Tech & target settings

Copy Pigskin's:

- Swift 6.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Multi-platform target (iOS + macOS, single scheme)
- Deployment targets: iOS 26.4+, macOS 26.4+
- No SPM dependencies (URLSession + Foundation only — same as Pigskin)
- Entitlements:
  - `com.apple.developer.ubiquity-kvstore-identifier` (iCloud KVS) for cross-device picker selection + favorites
  - `com.apple.security.app-sandbox` (macOS)
  - `com.apple.security.network.client` (macOS — **mandatory**; without it macOS silently fails on backend reachability — Pigskin learned this)

### `APIClient.swift` patterns to copy from Pigskin

- Actor singleton wrapping `URLSession`.
- Bearer token resolution via `await MainActor.run { AppSettings.shared.apiKey }` at request time (lazy, actor-safe).
- Custom `JSONDecoder` with multi-format date strategy: fractional ISO, plain ISO, date-only. The Express API mixes these.
- `APIError` enum: `.http(Int, body: String?)`, `.decoding(Error)`, `.transport(Error)`, `.missingAuth`.
- `/healthz` unauthenticated.

### `Config.swift`

```swift
enum Config {
    static let baseURL: URL = {
        #if DEBUG
        return URL(string: "http://127.0.0.1:8008")!
        #else
        return URL(string: "https://nfl.schnetz.us")!
        #endif
    }()
}
```

### Visual fidelity — keeping the React UI

The user's hard requirement is "duplicate the UI exactly". For SwiftUI
this means:

1. **Pull the design tokens out of `frontend/index.css` and Tailwind
   config first.** Translate `bg-metal` (#0b162a), accent colors,
   spacing scale, font weights, border-radius values into a
   `Theme.swift` static struct. Use these literally — don't pick "close
   enough" SwiftUI colors.
2. **Re-create components 1:1.** GameCard, WeekPills, PicksGameCard,
   etc. each get one SwiftUI view matching the React component's
   visual structure (header row, body, footer). Side-by-side comparison
   on the same iPhone Mini frame at 390×844 during dev.
3. **Match animations.** The React app uses `framer-motion`. Map to
   SwiftUI `.animation(.spring(...))` and `.transition(.move(...))` —
   most are simple enter/exit fades and slides; nothing in
   `framer-motion` here requires native equivalents we don't have.
4. **Skeleton screens.** The React app uses `animate-pulse`. SwiftUI:
   `.redacted(reason: .placeholder)` + a custom `.shimmer()` view
   modifier, OR a plain animated gray rounded rect. Either matches.
5. **Bottom nav vs. TabView.** The React app has a custom `BottomNav`
   over a stack of routes. SwiftUI `TabView` with custom tab-bar
   styling gets the same effect with way less plumbing — use it.

`~/Documents/Development/Guides/SwiftUI Best Practices & Visual
Design — 2026.md` is the reference for per-platform polish decisions and
the architectural ones alike (state, navigation, environment, MVVM
placement) — the two separate docs this repo once carried were merged
upstream into that single file. Re-read it
before starting `ContentView.swift`.

### React UI → SwiftUI mapping (per page)

| React page | SwiftUI tab | Hooks → ViewModel | Notes |
|---|---|---|---|
| Scoreboard `/` | ScoreboardTab | useScoreboardWeek, useLiveScoreboardDay, useWeeklyPredictions, useCurrentWeek → ScoreboardViewModel | Adaptive polling (Network conditions): copy from `useLiveScoreboardDay`. |
| Schedule `/schedule` | ScheduleTab | useSeasonSchedule, useGamesGroupedByDate, useWeeklyPredictions, useScoreboardWeek → ScheduleViewModel | Independent WeekSelection state. |
| Results `/results` | ResultsTab | useSeasonSchedule, useGamesGroupedByDate, useScoreboardWeek, useScoreboardGrouping → ResultsViewModel | |
| Picks `/picks` | PicksTab | usePicksRoom, useSpreads, useOptimisticPicks, usePicksMutations, useLocalUser → PicksViewModel | Phase 6: polling + offline queue (Pigskin pattern). |
| Predictions `/preds` | PredictionsTab | useWeeklyPredictions, useSeasonSchedule, useScoreboardWeek → PredictionsViewModel | LLM narratives + grading badges. |
| Standings `/standings` | StandingsTab | useTeams, useStandingsDerived → StandingsViewModel | Conference/division toggles. |
| Team `/team` | TeamTab | useTeams, useRoster, useSeasonSchedule, useTeamStats, useTeamLeaders → TeamViewModel | Tab bar inside the tab for Roster/Schedule/Stats/Leaders. |
| Boxscore `/boxscore/:id` | BoxScoreView (sheet/push) | useBoxscore → BoxScoreViewModel | |
| Preview `/preview/:id` | PreviewView (sheet/push) | usePreview, useWeeklyPredictions, useTeamLeaders, useWeather, useVenueEnrichment → PreviewViewModel | |
| LiveGameModal `/live/:id` | LiveGameView (sheet) | useLiveGameData, useLivePlays → LiveGameViewModel | Polling 3–5s while live. |

---

## Phase 3 — Provision on the Mini

Mostly mechanical given the existing pattern. Most of these mirror
Headline's Phase 2 verbatim.

1. **Create the databases:**

   ```bash
   ssh schnetzermini@Schnetzer-mini.local '
     export PATH=/opt/homebrew/opt/postgresql@18/bin:$PATH
     createdb nfl_prod
     createdb nfl_dev
   '
   ```

2. **Create persistent state dir + symlink convention:**

   ```bash
   ssh schnetzermini@Schnetzer-mini.local '
     mkdir -p ~/.nfl ~/.nfl/backups
     chmod 700 ~/.nfl
     touch ~/.nfl/.env
     chmod 600 ~/.nfl/.env
   '
   ```

3. **Write `~/.nfl/.env` on the Mini:**

   ```env
   ENVIRONMENT=prod
   DEBUG=false
   DATABASE_URL=postgresql+asyncpg://schnetzermini@localhost:5432/nfl_prod
   API_KEY=<random-hex-32>            # rotate via change + launchctl kickstart
   ESPN_GATEWAY_URL=http://127.0.0.1:8005
   ESPN_GATEWAY_API_KEY=<copy from ~/.espn/.env>
   PORT=8008
   # weather:
   OPEN_METEO_BASE_URL=https://api.open-meteo.com/v1
   # nflreadpy uses no API key; only network egress is the weekly pipeline
   ```

   Note: **no RapidAPI variables.** Phase 0 + Phase 7 between them
   eliminate the need for `nfl-api-data.p.rapidapi.com`. If during the
   gateway feature work it turns out some endpoint isn't ready yet
   and you need a temporary fallback, add it back here, but the goal
   is zero RapidAPI by cutover.

4. **Initial deploy:**

   ```bash
   ./deploy/sync.sh                       # first run; creates ~/Applications/NFL, runs uv sync --frozen, alembic upgrade head, bootstraps launchd
   ```

   The `deploy/sync.sh` script (copy from Pigskin) rsyncs the backend
   to `~/Applications/NFL/`, runs `uv sync --frozen` and `alembic
   upgrade head`, then `launchctl kickstart -k gui/$(id -u)/com.nfl.backend`.

5. **Symlink the env into the app dir** (survives every rsync because
   `.env` is in the rsync excludes):

   ```bash
   ssh schnetzermini@Schnetzer-mini.local '
     ln -sf ~/.nfl/.env ~/Applications/NFL/.env
   '
   ```

6. **Smoke-test loopback:**

   ```bash
   ssh schnetzermini@Schnetzer-mini.local 'curl -s http://127.0.0.1:8008/healthz'
   # expect: {"status":"ok"}
   ```

### Phase 3.5 — Backfill historical tables (nflverse one-shot)

The model and the in-season "Postgres-first" data flow both depend on
having multi-season history loaded locally. This is the NFL equivalent
of Pigskin's CFBD historical tables — done **once** via a single
nflverse pull, then maintained by the same weekly job during the
season.

#### First: scope what's actually rendered

Before running the backfill, audit what historical data the **current
React app actually displays**. The backfill should serve the UI, not be
exhaustive for its own sake. Walk the pages once and write a small
inventory — this is a 30-minute task that prevents days of wasted
effort. Where to look:

- `frontend/src/pages/Standings.jsx` + `useStandings` — multi-season
  standings? Or current season only?
- `frontend/src/pages/Team.jsx` + `useRoster`, `useTeamStats`,
  `useTeamLeaders`, `useTeam` — do these accept a `?year=` and render
  prior-season data, or only current?
- `frontend/src/pages/Results.jsx` + `useSeasonSchedule` — does it
  expose prior seasons in week pills, or just the current one?
- `frontend/src/pages/Schedule.jsx` — same question.
- `frontend/src/pages/Boxscore.jsx` — historical boxscores accessible
  via direct URL?
- Predictions UI — what does grading look like for completed past
  weeks?

Anything that *only* renders current-season data doesn't need historical
backfill — the weekly job keeps it fresh. Anything that exposes
season pickers, year params, or "all-time" widgets is in-scope. **For
the ML model's training data, the scope is independent of the UI: it
needs full per-team-game EPA back to ~2016 regardless.**

#### Source: nflverse via `nflreadpy`, full stop

Single source of truth. `nflreadpy` (the maintained successor to
`nfl_data_py`) downloads parquet files from the nflverse data
releases. No API key, no rate limit, no paid-tier concern. Same data
the existing `nfl_predictor` already consumes — adopting it means the
ML port (Phase 7) doesn't need a separate data path.

- **No RapidAPI bulk pull.** Earlier drafts proposed draining the
  paid subscription on the way out — drop that plan. nflverse has the
  same (richer) historical data for free, including per-game team
  stats and player leaders derived from PBP that RapidAPI exposes only
  per-season as monolithic blobs.
- **ESPN gateway is not the historical source.** Gateway covers
  current-day live state only; its DB rows aren't backfilled for prior
  seasons. Don't try to pull "all seasons" through it.
- **Existing local backfill from prior `nfl_predictor` work** — if
  you have it on disk, dump + `\copy` is still the fastest start. The
  nflverse pull is the source of truth going forward; existing local
  rows just save the first download.

Once populated, **the only network egress during a season is the
weekly nflverse refresh (Tuesdays) plus the ESPN gateway for
current-day scoreboards and live in-game state.** No per-request
fan-out to external APIs from user-facing endpoints.

#### One-shot run

```bash
# from the new NFL backend directory on the MacBook:
uv run python -m scripts.refresh_nflverse --seasons 2016-2025 --target ssh://schnetzermini@Schnetzer-mini.local/nfl_prod --mode backfill
```

The `scripts/refresh_nflverse.py` script (also used by the weekly
launchd job in `--mode weekly`):

1. For each season in range, call `nflreadpy.load_schedules`,
   `load_player_stats`, `load_pbp`, `load_rosters_weekly`,
   `load_depth_charts`, `load_injuries`, `load_snap_counts`. (Plus
   `load_team_stats` if it covers the season; otherwise derive from
   PBP.)
2. For PBP: roll up to team-game grain in pandas/polars before
   inserting (one row per team per game, not per play). Saves ~100×
   space and matches what the feature builder consumes. Keep the
   raw per-play rows in a `pbp` table only for the seasons that
   currently render in the UI (typically just the active season).
3. `INSERT ... ON CONFLICT (season, week, ...) DO UPDATE` so re-runs
   upsert rather than skip — the weekly job needs in-season rows to
   refresh as games complete and stats settle.
4. Print a summary table (rows per table, range coverage).

Verify on the Mini:

```bash
ssh schnetzermini@Schnetzer-mini.local '
  /opt/homebrew/opt/postgresql@18/bin/psql -d nfl_prod -c "
    SELECT '\''games_historical'\'' AS t, MIN(season), MAX(season), COUNT(*) FROM games_historical
    UNION ALL SELECT '\''weekly_stats'\'',     MIN(season), MAX(season), COUNT(*) FROM weekly_stats
    UNION ALL SELECT '\''pbp_summary'\'',      MIN(season), MAX(season), COUNT(*) FROM pbp_summary
    UNION ALL SELECT '\''betting_lines'\'',    MIN(season), MAX(season), COUNT(*) FROM betting_lines
    UNION ALL SELECT '\''injuries'\'',         MIN(season), MAX(season), COUNT(*) FROM injuries
    UNION ALL SELECT '\''snap_counts'\'',      MIN(season), MAX(season), COUNT(*) FROM snap_counts;
  "
'
```

After backfill, the feature builder in `app/ml/features.py` is rewired
to read from these Postgres tables (via SQLAlchemy) instead of calling
`nflreadpy` at request time. Live current-season deltas come from
the weekly pipeline (Phase 7), which calls `nflreadpy` once and
upserts. Single point of network egress.

---

## Phase 4 — launchd + Cloudflare tunnel

### launchd plist — `~/Library/LaunchAgents/com.nfl.backend.plist`

Use Pigskin's plist as the template; replace label, paths, port:

```xml
<key>Label</key>             <string>com.nfl.backend</string>
<key>ProgramArguments</key>  <array>
  <string>/opt/homebrew/bin/uv</string>
  <string>run</string>
  <string>uvicorn</string>
  <string>app.main:app</string>
  <string>--host</string><string>127.0.0.1</string>
  <string>--port</string><string>8008</string>
</array>
<key>WorkingDirectory</key>  <string>/Users/schnetzermini/Applications/NFL</string>
<key>EnvironmentVariables</key> <dict>
  <key>PATH</key>  <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  <key>HOME</key>  <string>/Users/schnetzermini</string>
</dict>
<key>RunAtLoad</key>           <true/>
<key>KeepAlive</key>           <true/>
<key>ThrottleInterval</key>    <integer>5</integer>
<key>StandardOutPath</key>     <string>/Users/schnetzermini/.nfl/backend.log</string>
<key>StandardErrorPath</key>   <string>/Users/schnetzermini/.nfl/backend.err</string>
```

Bootstrap:

```bash
ssh schnetzermini@Schnetzer-mini.local '
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nfl.backend.plist
'
```

### Cloudflare Tunnel ingress

Use the canonical `setup-tunnel.sh` (copy from Pigskin's `deploy/`):

```bash
ssh -t schnetzermini@Schnetzer-mini.local \
  "cd ~/Applications/NFL && bash deploy/setup-tunnel.sh nfl.schnetz.us 8008"
```

The script registers the DNS CNAME (user-level), backs up
`/etc/cloudflared/config.yml`, inserts the new ingress rule above the
`http_status:404` catch-all, validates, and kickstarts the system
launchdaemon (sudo prompt comes back to your terminal).

### Verify in two stages (from MINI_ENV.md)

**Stage 1 — loopback on the Mini** (proves uvicorn is up):

```bash
ssh schnetzermini@Schnetzer-mini.local 'curl -s http://127.0.0.1:8008/healthz'
```

**Stage 2 — public route from off-LAN** (proves Cloudflare routing):

From a phone on cellular: `https://nfl.schnetz.us/healthz` →
`{"status":"ok"}`.

---

## Phase 5 — Data migration: Upstash → Postgres

Three categories of state in Upstash today; three plans.

### 5.1 RapidAPI response cache (Upstash) → drop

`nfl:sched:*`, `nfl:desc`, `nfl:calendar-*`, per-team and per-game
response bodies. **Don't migrate.** These are derived from the upstream
API. The new backend re-fetches lazily through `core/cache.py` and the
ESPN gateway. The first request for each cold cache item pays an extra
~200ms.

### 5.2 Static dataset — `nfl:venues:2025`

This is the only one worth porting **as a static file**, not via Redis
extract. The current React app ships `frontend/src/utils/venueWeatherMapping.js`
which maps venue IDs to lat/lon. Copy that to
`app/data/venues.json` (or `.csv`) and load it at startup.

### 5.3 Picks state + history → port

This is the only state that *cannot* be re-derived. Two options.

#### Option A — Reseed (recommended if there's no live season mid-cutover)

If the cutover happens during the offseason (March–August), no
historical picks data matters except `history`. Just take a one-shot
dump from Upstash:

```bash
# from MacBook, using upstash REST API
curl -s -H "Authorization: Bearer $UPSTASH_REDIS_REST_TOKEN" \
  "$UPSTASH_REDIS_REST_URL/keys/room:*" \
  > /tmp/nfl-picks-keys.json

# fetch each key's value, write to JSONL
for key in $(jq -r '.result[]' /tmp/nfl-picks-keys.json); do
  curl -s -H "Authorization: Bearer $UPSTASH_REDIS_REST_TOKEN" \
    "$UPSTASH_REDIS_REST_URL/get/$key" \
    | jq -c --arg k "$key" '{key: $k, value: .result}'
done > /tmp/nfl-picks.jsonl
```

Then run `scripts/import_upstash_picks.py` on the Mini to walk that
JSONL and insert into `picks_weeks`, `picks`, `picks_scores`. Pigskin
has `scripts/data/picks_dump_2025.jsonl` and an importer as a
reference.

#### Option B — Mid-season cutover

If the cutover happens mid-season, the picks for the *current* week
matter and the schema mapping needs to preserve them faithfully
(currentTurn, doubles flags, presses by user pair). Do the same JSONL
export, but smoke-test the importer against `nfl_dev` first by reading
state via the new API and comparing to the Render API's
`/api/room/:roomId/state` response. Only flip the Cloudflare ingress
after parity passes.

---

## Phase 6 — Picks feature: drop Socket.IO, add offline queue

The React app uses Socket.IO with rooms (`room:${roomId}`) for live
sync. The SwiftUI app **doesn't.** Picks moves to:

1. **Backend:** plain REST endpoints, Postgres-backed state. No
   WebSocket server.
2. **Frontend:** `PicksViewModel` polls `/api/room/{roomId}/state` on a
   schedule (every 15s when foregrounded; suspend on background;
   one-shot on `scenePhase → active`). 15s is plenty — two human users
   making picks weekly is not a real-time problem.
3. **Offline queue (Pigskin pattern):** pending pick/unpick/markDoubles
   actions get serialized to `UserDefaults` as `PendingPickAction`
   when offline. UI applies them optimistically. On scenePhase active
   or pull-to-refresh, drain the queue. Permanent failures (HTTP 4xx)
   drop with a one-shot alert; transient failures retry.

This is a strictly simpler architecture than the current React + Socket.IO
one. The behavioral loss is: a pick made on one device shows up on the
other within ~15s instead of ~instant. The two users (Jim and Tom) are
not playing tic-tac-toe; this is fine.

### Endpoint surface (port from `picksRoute.js`, drop room dimension)

Drop the `/room/{roomId}/` segment from every path — there's only one
"room" forever, hardcoded.

`GET  /api/picks/state?season=&week=`
`POST /api/picks/open`
`POST /api/picks/pick`
`POST /api/picks/unpick`
`POST /api/picks/advanceTurn`
`POST /api/picks/markDoubles`
`POST /api/picks/markPresses`
`POST /api/picks/close`
`POST /api/picks/score`
`GET  /api/picks/history`

The cross-league `/api/cfb/weekScores` endpoint (currently bridges to
the CFB Render app for the postseason bonus that's hardcoded in
`backend/services/predictionService.js`) becomes a loopback call to
Pigskin: `http://127.0.0.1:8007/api/picks/standings?...`. Pigskin
already exposes this — `app/routers/picks.py`.

### State machine

Same as today:

- `null` → `POST /open` → **picking** (all games picked by alternating turns)
- **picking** → `POST /close` → **closed** (spreads frozen, can mark doubles/presses)
- **closed** → `POST /score` → totals computed (return + persist; clients fetch updated state on next poll)

### Optimistic UI

`PicksViewModel` keeps a layered state:

```swift
@MainActor final class PicksViewModel: ObservableObject {
    @Published var serverState: PicksState?           // last response from /state
    @Published var optimistic: [PickPath: Pick] = [:] // overlay until server confirms or rejects
    @Published var pending: [PendingPickAction] = []  // queued for offline replay
    ...
}
```

`displayed = serverState.merging(optimistic)`. On 2xx from a mutation,
drop the matching optimistic entry. On 4xx, drop and surface an error.
Reconcile on every `/state` poll.

---

## Phase 7 — Port `nfl_predictor` into `app/ml/`

This is the consolidation step: take the working ML predictor at
`~/Documents/Development/Python/nfl_predictor/` and fold it into the
new FastAPI backend, replacing the standalone Render service
(`gridiron-api.onrender.com`) and the Upstash `nfl:preds:*` key.

**Same migration Pigskin already did for `cfbd`.** Pigskin's
`app/ml/inference.py`, `app/ml/train.py`, `app/ml/data/`, and
`app/ml/models/` are the literal templates. Folder shape and lifespan
wiring already proven.

### Step 1 — Cherry-pick only the live code

Don't dump the whole `nfl_predictor/` into `app/ml/`. **Bring just
what's on the active code path:**

| Source (in `nfl_predictor/`) | Destination (in NFL backend) | Notes |
|---|---|---|
| `training/train.py` | `app/ml/train.py` | Production training entry point |
| `training/score_and_publish.py` | `app/ml/inference.py` | Becomes a callable `predict_week(season, week, market_influence=0.3, injury_adjust=1.0) -> list[Prediction]`. Strip Upstash publishing — return values, route them via the FastAPI handler to Postgres. |
| `scripts/build_features.py` + `build_feature_frame.py` | `app/ml/features.py` | Merge the two — there's no reason to keep them split inside our backend. Rewire data fetches to read from `nfl_prod` Postgres (the nflverse-backfilled historical tables from Phase 3.5) instead of calling `nfl_data_py`/`nflreadpy` at request time. |
| `scripts/data_sources.py` | `app/ml/data_sources.py` | `load_schedule`, `last_completed_week`, `upcoming_week`. Backed by Postgres too. |
| `scripts/roster_features.py` | `app/ml/roster_features.py` | Injury burden + QB continuity health features. |
| `scripts/best_bets.py` | `app/ml/best_bets.py` | Edge → Strong/Medium/Lean labels. |
| `models/<latest>.joblib` + `.meta.json` + `.metrics.json` (margin) | `app/ml/models/latest-margin.{joblib,meta.json,metrics.json}` | **One** pair. The most recent: `model-20251202-181825.joblib` or whichever is newest by mtime. |
| `models/<latest>-totals.joblib` + `.meta.json` (totals) | `app/ml/models/latest-totals.{joblib,meta.json}` | **One** totals model. Most recent: `model-20251215-181113-totals.joblib`. |
| `tests/` (only tests that pass) | `tests/test_ml_*.py` | Carry over feature-builder and inference unit tests. |

### Step 2 — Don't bring

Explicit drop list (everything below stays behind in `nfl_predictor/`):

- `archive/`, `examples/`, `notebooks/`, `docs/` — reference only,
  doesn't belong in a production backend.
- `compare-models.py`, `nfl_pipeline.py` (the empty 0-byte stub),
  `nfl_data_py_starter.ipynb`, `test`, `test.parquet`, `teams.json`,
  `week7.json` — one-off scratch files.
- `nfl_pipeline/` package directory — superseded by `scripts/` (the
  CLAUDE.md notes feature engineering was already moved out of it).
- Every `(1).{py,txt,json}` file — IDE duplicates.
- `scripts/predict_2025.py`, `scripts/sample_2025_data.py`,
  `scripts/static_data.py`, `scripts/static_data (1).py`,
  `scripts/season_wins.py`, `scripts/compare_win_totals.py`,
  `scripts/make_charts.py`, `scripts/get_schedule.py`,
  `scripts/train_model.py` — older / parallel implementations
  superseded by `training/` and `scripts/build_features.py`.
- 20+ archived `.joblib` files in `models/`. Bring **one** margin pair
  and **one** totals pair. Old artifacts live in git history for
  rollback; not in `app/ml/models/`.

The point: `app/ml/` should be lean — fewer than 10 .py files. If
something isn't called by `inference.py`, `train.py`, or a test, it
doesn't move.

### Step 3 — Wire it into FastAPI

Pigskin's pattern (verbatim):

1. **Load at startup** via lifespan:
   ```python
   from app.ml.inference import load_artifacts
   set_ml_artifacts(load_artifacts())  # reads latest-margin + latest-totals .joblib
   ```
2. **Singleton via `Depends(get_ml_artifacts)`** in `app/routers/predictions.py`.
3. **Inference is sync** (sklearn predict is fast; doesn't need async).
   FastAPI auto-threads sync `def` handlers — no `asyncio.run_in_executor`
   gymnastics needed.

### Step 4 — Endpoints

Mirror the existing Gridiron API surface and the React frontend's
expectations:

| Endpoint | Behavior |
|---|---|
| `GET /api/preds/{season}/w{week}?v=` | Read from `predictions` table; if absent for current upcoming week, fall through to `app.ml.inference.predict_week(season, week)`, persist, return. Matches React's `useWeeklyPredictions`. |
| `GET /api/predictions/upcoming?season=` | Same as Gridiron's `/predictions/upcoming` — finds the next slate with future games. Optional; the React app doesn't use it today. Keep if helpful for the SwiftUI client. |
| `POST /api/admin/retrain-and-cache` | Auth-gated (bearer token). Kicks `app/ml/train.py` and re-runs predictions for the upcoming week. Equivalent to Gridiron's admin endpoint. |
| `GET /api/preview/{gameId}` | Per-game prediction (single row from `predictions` joined with the game's scoreboard data). Matches React's `usePreview`. |

### Step 5 — Weekly pipeline

`launchd/com.nfl.weekly.plist`, daily 06:15 ET, runs
`scripts/weekly_pipeline.py` (Pigskin's `scripts/weekly_pipeline.py` is
the template). The pipeline is idempotent and file-state-gated:

1. `ingest_results.py` — invokes `scripts/refresh_nflverse.py
   --mode weekly` to pull final scores + new roster/depth/injury/snap
   data via `nflreadpy` for the most recent completed week; upserts
   into `games_historical`, `rosters_weekly`, `depth_charts`,
   `injuries`, `snap_counts`, `pbp_summary`, `betting_lines`. This is
   the only live nflverse fan-out — once per day during season.
2. `analyze_week_performance.py` — score model predictions against
   actuals (cover %, MAE on margin, log-loss on win-prob). Stored in a
   `prediction_performance` table for trend monitoring.
3. `train.py` — only fires if the labeled CSV / Postgres rows have
   advanced beyond the last training timestamp. Writes a new
   `.joblib` + `.meta.json` + `.metrics.json` triple; updates the
   `latest-margin` / `latest-totals` symlinks atomically.
4. `run_week_predictions.py` — calls `app.ml.inference.predict_week()`
   for the upcoming week.
5. `load_predictions.py` — upsert predictions into the Postgres
   `predictions` table.
6. `launchctl kickstart` the backend so it picks up new model
   artifacts (only fires if step 3 retrained).

State file: `~/.nfl/pipeline_state.json` (last 20 runs logged) — same
shape as Pigskin's `~/.pigskin/pipeline_state.json`.

### Step 6 — Delete the standalone Gridiron API service

After the new endpoints answer correctly against the new Postgres
table:

1. Pause `gridiron-api.onrender.com`. Keep for 7 days as a rollback.
2. Delete the Render service.
3. Cancel any Upstash usage tied to it (probably shares the same
   Upstash instance the main NFL app uses — pause both together in
   Phase 9).

### Optional cleanup of `nfl_predictor/` itself

Once `app/ml/` is up and verified, `nfl_predictor/` becomes archive.
Either:

- Tag the repo at the cutover commit, push to a backup remote, then
  delete the local directory. Clean.
- Or leave it on disk but stop touching it. Future improvements happen
  in `app/ml/` only.

User preference per the "no dead code carryover" rule: **delete after
tag**. If the model needs a referenceable snapshot, the tag is enough.

---

## Phase 8 — Backups

Add `nfl_prod` to the central backup. On the Mini, edit
`~/.mini/scripts/backup-postgres.sh` and append to the `JOBS` array:

```bash
JOBS=(
  ...
  "pigskin_prod:.pigskin:14"
  "nfl_prod:.nfl:14"   # ← NEW (14-day retention)
)
```

No new launchd job, no new schedule. Daily at 02:30 ET, three
destinations (local `~/.nfl/backups/`, Google Drive, `/Volumes/Storage`).

Smoke-test restore once after first dump lands:

```bash
ssh schnetzermini@Schnetzer-mini.local '
  export PATH=/opt/homebrew/opt/postgresql@18/bin:$PATH
  createdb nfl_test
  pg_restore -d nfl_test ~/.nfl/backups/<latest>.dump
  psql nfl_test -c "SELECT count(*) FROM picks_weeks;"
  dropdb nfl_test
'
```

Update `~/Documents/Development/Guides/MINI_ENV.md` afterwards: add the NFL row to the services
table, bump the JOBS list, increment "Current rotation lists 10
databases."

---

## Phase 9 — Cutover checklist

Run this when:
- Backend is verified working against `nfl_dev`.
- SwiftUI app builds clean for both iOS and macOS targets.
- Picks scoring tests pass; parity harness shows clean diff against the
  current React API for read endpoints.

1. **Final reseed/dump** of Upstash if mid-season; skip if offseason
   (Phase 5).
2. **Smoke test the parity harness** (`tests/parity/run.py`) against
   prod Render. Diff `/api/scoreboard/week`, `/api/sched`,
   `/api/teamStats`, `/api/preds`, `/api/box`, `/api/standings`.
   Anything red gets fixed before flipping clients.
3. **Build the SwiftUI app:**
   - macOS (MacBook): `xcodebuild -project NFL.xcodeproj -scheme NFL -destination 'platform=macOS,arch=arm64' build`
   - iOS: install to iPhone via Xcode.
4. **Smoke the clients:**
   - Open scoreboard, week pills, scroll through past + upcoming
     weeks. Confirm no white screens.
   - Tap a completed game → boxscore loads, linescore renders, team
     stats visible.
   - Tap an upcoming game → preview loads with odds + venue + weather
     + team leaders (if available).
   - Standings, team detail (roster/schedule/stats/leaders) all load.
   - Picks: make a pick on iOS, wait 15–30s, confirm it appears on
     macOS. Mark a double, mark a press. Close week. Score it.
   - Predictions: weekly narrative card shows; grading badge after
     games final.
5. **Pause both Render services** (`nfl-app` + `gridiron-api`).
   Don't delete yet — keep paused for 7 days as a deletion-delay
   safety net, not as a runnable rollback target.
6. **Pause the Upstash database** for 7 days, same reason.
7. **Cancel the RapidAPI subscription.** Should already be done as
   soon as the new backend shipped — there is no bulk historical pull
   gate; nflverse covers history for free. If not yet cancelled, do
   it now — nothing in the new backend calls it.
8. **Day 8–14**: delete the Render services, delete the Upstash DB,
   tag and archive the source repos (`Webstorm/nfl/` and
   `Python/nfl_predictor/`).

---

## Rollback

This is a **clean cut**, not a parallel run. Per the user's standing
preference (matches Headline/Orbit/Portfolio): retire the old surface
quickly; don't keep a runnable Render fallback target. The React app
+ Gridiron API + Upstash are sunset, not paused-as-warm-spare.

The rollback strategy is **restore-from-backup on the Mini**, not
"resume the old services":

- Before Phase 9 cutover, take:
  - One final `pg_dump -Fc` of `nfl_prod` (post Phase 3.5 backfill,
    post first weekly pipeline run). Stored in two places:
    `~/.nfl/backups/cutover-snapshot.dump` on the Mini + offsite
    (Google Drive + `/Volumes/Storage`, same as the central backup).
  - One JSONL export of Upstash (`room:*` + `nfl:preds:*` keys), so
    picks history and the last good prediction snapshot are preserved
    as raw data even if the Postgres schema turns out to need a
    fix-up.
- Render services (`nfl-app` + `gridiron-api`) are **paused for 7 days
  as a deletion-delay**, not as a runnable target. The SwiftUI build
  is not architected to re-point at Render — `Config.swift` has only
  `127.0.0.1:8008` (debug) and `nfl.schnetz.us` (release). If the
  Mini misbehaves on day 1, the recovery path is "fix the Mini," not
  "fall back to Render."
- Upstash pause is the same: 7-day deletion-delay, not a target.
- **Worst-case scenario**: Mini hardware failure during cutover week.
  Path: provision FastAPI elsewhere (another Mac, even briefly the
  MacBook), restore the `pg_dump`, run alembic, point the SwiftUI
  build at the new host. No Render involvement.
- After 7 days of stable operation: delete the Render services,
  delete the Upstash database, cancel the RapidAPI subscription (if
  not already cancelled when the new backend shipped). Archive both
  source repos via `git tag pre-mini-cutover && git push --tags` and
  remove local working trees.

---

## Risks & open questions

- **ESPN gateway feature work shrank to two small patches** (events
  `week` filter, standings `playoff_seed` column), plus optional
  passthrough routes for live-only endpoints (boxscore / scoring
  plays during a game / intraday odds). Everything else moves to
  nflverse via `nflreadpy`. Budget the gateway side at ~1–2 days
  total. The original "7 new gateway endpoints" plan was based on
  unverified assumptions about `ESPNClient` method coverage; the
  audit (2026-05-13) confirmed only 6 client methods ship today and
  the cleaner replacement for the rest is nflverse, not building out
  ESPN coverage.
- **NFL pre-game predictor — resolved.** The existing
  `~/Documents/Development/Python/nfl_predictor/` ("Gridiron API")
  already supplies pre-game predictions and is the producer of the
  Upstash `nfl:preds:*` data the React app reads. Phase 7 ports it in.
  RapidAPI's `/nfl-predictor` is not needed by anything.
- **Postgres-backfilled historical data is a precondition for Phase 7.**
  The feature builder in `app/ml/features.py` reads from
  `games_historical`, `weekly_stats`, `pbp_summary`, `betting_lines`,
  `injuries`, `snap_counts`. Phase 3.5 has to run before predictions
  work on the new backend. If you already have a local backfill
  database from earlier `nfl_predictor` work, rsync + `\copy` is much
  faster than re-fetching from `nflreadpy`.
- **Visual fidelity is subjective and slow.** "Duplicate the UI
  exactly" is a multi-week side-by-side iteration job, not a
  one-pass port. Budget realistically. Consider an
  "acceptable-fidelity" line: pixel-perfect on iPhone 17 Pro (the
  user's daily driver); good-enough on everything else.
- **Postseason week mapping bug surface.** The current Express picks
  routes have postseason logic that re-maps NFL week 18 → CFB
  postseason week 1 in `StandingsTab.jsx` and `cfbRoute.js` (recent
  commits `38952d7`, `2569694`, `aa915dd`, `da6ee2f`, `b8d8f67`).
  This is the most-recently-changed code, which means it's the
  least-stable. Re-port carefully and write tests for every postseason
  week boundary, not just regular-season.
- **Two-user iCloud KVS coupling — resolved.** Jim and Tom have separate Apple IDs; iCloud KVS scopes per Apple ID, so each device's `activePicker` setting persists for that person automatically. That's the desired behavior and needs no special handling.
- **macOS sandbox + network entitlement.** Pigskin documented that
  without `com.apple.security.network.client`, macOS silently fails
  with "server hostname could not be found." Make sure the entitlement
  file ships with that key. (Listed in Phase 2.)
- **Test on bad networks.** The React app's PWA optimizations
  (skeleton screens, optimistic updates, stale-data display, adaptive
  polling) all need re-implementation in SwiftUI. They're not
  automatic. Test cellular / Lossy Network on iOS Simulator before
  cutover.

---

## Thoughts (the part you asked for)

A few opinions on this migration as drafted:

1. **The single biggest leverage point is the ESPN gateway.** Every
   Mini app (SportsBar, WorldCup, this NFL app, potentially a future
   NBA app) benefits when you fill in the gateway's REST surface for
   standings / team stats / team leaders / roster / odds / scoring
   plays. Do that work once, in `~/Documents/Development/IntelliJ/Python/ESPN/`,
   and three apps get to retire their direct ESPN clients. Phase 0 is
   really "extend the gateway" more than it is "NFL prep."

2. **Drop Socket.IO. Don't be sad about it.** Socket.IO + Redis
   pub/sub for two users making weekly picks is over-engineered for
   the actual cadence. The complexity of running a WebSocket server,
   debugging room subscriptions, and dealing with reconnect races
   costs more than the 15s latency you'd gain. Pigskin's offline-queue
   pattern is the right precedent. Your Picks feature gets *simpler*
   and *more reliable* in the process.

3. **Replicating the React UI in SwiftUI is the longest pole.** Not
   the backend, not the data plumbing — the visual reproduction work.
   Plan it as 6–8 weeks of iteration, not 2. If you have an iPad
   propped up running the current React app while you build in Xcode,
   that's the fastest workflow. Don't try to do it from screenshots.

4. **The NFL ML predictor is already done.** `nfl_predictor`/
   Gridiron API is a working model with ~2 seasons of production
   tuning behind it (latest artifacts dated Dec 2025–Feb 2026). The
   Phase 7 work is *consolidation*, not modeling — fold it into
   `app/ml/`, point it at the local Postgres historical tables
   instead of `nflreadpy`-at-request-time, drop the standalone Render
   service, and you're done. Two Render services collapse to zero.
   Same shape as the `cfbd` → Pigskin migration, which already
   succeeded.

5. **Clean cut, no React stopgap on the Mini or anywhere else.** Per
   the user's standing preference, the React app and Gridiron API are
   sunset, not parallel-run. No "move it to the Mini under
   launchd" hedge, no "keep it deployable just in case." The rollback
   is restore-from-backup on the Mini, not resume-from-Render. Tag
   the source repos at cutover, push tags, archive locals.

6. **Order the phases by reversibility, not by enthusiasm.** Phase 0
   (ESPN gateway) and Phase 1 (FastAPI backend) are entirely reversible
   — they don't touch any production user-facing thing. Get those
   solid. The SwiftUI client (Phase 2) is also independent of cutover
   — you can ship it pointing at the new backend running on your
   MacBook for weeks before flipping the public URL. Cutover (Phase 9)
   should be the last, smallest step.

7. **Two pickers forever — Tom and Jim. Decided.** The schema drops
   the room dimension entirely (no `picks_rooms` table, no `room_id`
   foreign keys, no `roomId` in URLs). `pickers` table seeds exactly
   two rows; the SwiftUI `AppSettings.activePicker` is a `"Tom"` /
   `"Jim"` enum persisted per Apple ID via iCloud KVS. Saves a layer
   of schema + URL clutter inherited from the React app's speculative
   generalization.

---

## One-line summary

Stand up FastAPI + Postgres at `nfl.schnetz.us` on the Mini (port
8008), call the existing `espn_service` gateway via loopback for
~80% of upstream data (with ~7 thin REST endpoints added to the
gateway first), do a one-shot RapidAPI historical backfill into
`nfl_prod` before cancelling, port `nfl_predictor` into `app/ml/`
(killing the standalone Gridiron API Render service), replace
Socket.IO + Upstash with polling + Postgres-backed picks state
(two pickers forever — Tom + Jim, no room dimension), replicate
the React UI 1:1 in SwiftUI on top of the existing `Swift/NFL/`
skeleton, and clean-cut all current code (no React/Render stopgap;
rollback is restore-from-backup on the Mini).
