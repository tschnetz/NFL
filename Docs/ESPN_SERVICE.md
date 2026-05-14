# ESPN Service — Personal Gateway Design

> **Purpose:** Consolidate sports data access for three personal apps (SportsBar, WorldCup, Braves) behind one self-hosted FastAPI gateway running on the Mac Mini, instead of each app hitting ESPN/MLB/FanGraphs directly.
>
> **Status:** Design — captures decisions and gaps. Implementation lives in this directory (`/Users/tgschnetzer/Documents/Development/IntelliJ/Python/ESPN`); upstream reference is the open-source `Public-ESPN-API` repo at `~/Documents/Development/Python/CFB Bowls/Public-ESPN-API`.
> **Last updated:** 2026-05-11

---

## Table of Contents

1. [Why This Exists](#1-why-this-exists)
2. [Topology](#2-topology)
3. [Tech Stack Decisions](#3-tech-stack-decisions)
4. [Service Inventory (Upstream Reference)](#4-service-inventory-upstream-reference)
5. [Consumer Apps](#5-consumer-apps)
   - [5.1 SportsBar](#51-sportsbar)
   - [5.2 WorldCup](#52-worldcup)
   - [5.3 Braves](#53-braves)
6. [Cross-Cutting Gaps to Close](#6-cross-cutting-gaps-to-close)
7. [Migration Plan](#7-migration-plan)
8. [Operations](#8-operations)
9. [Decision Log](#9-decision-log)
10. [Open Questions](#10-open-questions)

---

## 1. Why This Exists

Three personal sports apps each maintain their own networking layer against external APIs:

| App | External APIs Today |
|-----|---------------------|
| SportsBar | `site.api.espn.com`, `site.web.api.espn.com` (direct, from 3 targets: app, watch, widget) |
| WorldCup | `site.api.espn.com/.../soccer/fifa.world/scoreboard` (via FastAPI poller) |
| Braves | `statsapi.mlb.com`, `fangraphs.com`, MLB.com RSS (no ESPN today) |

Problems with the status quo:
- ESPN response-shape changes break apps independently — three places to patch.
- No shared rate-limit budget or cache.
- SportsBar duplicates ESPN-fetch logic across app/watch/widget targets.
- No central place to add cross-sport features (e.g. unified injuries/news feed).

The play: build `espn_service` (a FastAPI gateway, modeled on the upstream Public-ESPN-API reference implementation but rewritten in the user's preferred stack) and host it on the Mac Mini. The three apps consume from it. ESPN is still the upstream — but only `espn_service` talks to ESPN.

**Mission-criticality:** none. A Mini hiccup or Cloudflare-tunnel blip is acceptable. This unlocks the consolidation tradeoff.

---

## 2. Topology

```
                    ┌───────────────────────────────────────────────┐
                    │                 Mac Mini                      │
                    │                                               │
                    │  shared services already running:             │
                    │  ├─ Postgres 18 (Orbit, Braves, Hearth, ...) │
                    │  └─ Cloudflare Tunnel (cloudflared)           │
                    │                                               │
                    │  new for ESPN gateway:                        │
                    │  ┌────────────────────────────────────────┐   │
                    │  │ launchd com.espn.backend (port 8005)   │   │
                    │  │   uv run uvicorn app.main:app          │   │
                    │  └────────────────────────────────────────┘   │
                    │  ┌────────────────────────────────────────┐   │
                    │  │ launchd com.espn.worker                │   │
                    │  │   uv run python -m app.worker          │   │
                    │  │   (in-process asyncio poll loops)      │   │
                    │  └────────────────────────────────────────┘   │
                    │                                               │
                    │  other personal backends (separate):          │
                    │  worldcup (FastAPI) · braves (FastAPI)        │
                    │  hearth (FastAPI + sidecars) · orbit · ...    │
                    └────────────────┬──────────────────────────────┘
                                     │
                          Cloudflare Tunnel
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
        SportsBar               WorldCup                  Braves
        (iOS/watch/widget)      (iOS/macOS)               (web SvelteKit)
```

**Public hostnames** (aligns with existing `{app}.schnetz.us` pattern):
- `espn.schnetz.us` → `127.0.0.1:8005` (new)
- `worldcup.schnetz.us`, `braves.schnetz.us`, `hearth.schnetz.us`, `orbit.schnetz.us`, `portfolio.schnetz.us` (existing)

**Port allocation on Mini (probed 2026-05-11):** Orbit 8000 · Braves 8001 · 8002 (unidentified) · Hearth 8003 · WorldCup 8004 · **ESPN 8005** · Portfolio (Node) 3001.

**Upstream:** all ESPN traffic egresses only from this gateway. Single rate-limit budget.

**Upstream:** all ESPN traffic egresses only from `espn_service`. Single rate-limit budget.

---

## 3. Tech Stack Decisions

| Concern | Choice | Rationale |
|---------|--------|-----------|
| Web framework | **FastAPI** | User's default for personal Python backends (Braves, WorldCup, Hearth, Orbit all use it). |
| Async runtime | `asyncio` (FastAPI native) | I/O-bound workload (HTTP to ESPN, Postgres); async fan-out across many leagues |
| ORM | **SQLAlchemy 2.x (async)** | Modern typed query API; matches existing personal backends |
| Migrations | **Alembic** | Standard SQLAlchemy companion |
| Validation / serialization | **Pydantic v2** | Native to FastAPI; typed request/response models |
| Primary store | **PostgreSQL 18** | OLTP workload (live scoreboards, concurrent reads, mutable game rows). Use the Mini's existing shared instance, separate `espn_prod` database. |
| Cold/analytical store | (Not used here) | Reserve DuckDB for Braves' historical archive — wrong tool for live game state |
| Background jobs | **In-process asyncio poll loops** (Hearth pattern) | No Redis, no queue. `app/worker.py` runs as a separate launchd-managed process with `run_poll_loop(name, interval, poll_fn)` per source. See "Why in-process" below. |
| HTTP client (to ESPN) | **httpx** (async) + **tenacity** | Async retries with exponential backoff + jitter |
| Package + env mgmt | **uv** | Fast resolver; lockfile; matches user's modern Python toolchain |
| Testing | **pytest + httpx.AsyncClient** | Standard async test stack |
| Linting / format | **ruff** | Single tool for lint + format |
| Type checking | mypy or pyright | TBD — Q5 still open |
| API docs | FastAPI's built-in OpenAPI at `/docs` + `/redoc` | — |
| Auth | **Bearer token** on `/api/v1/*` via `Authorization: Bearer <API_KEY>` | Defense in depth even behind the Cloudflare Tunnel. Matches Hearth. Bypassed locally when `API_KEY` env var is unset. |
| Response format | Normalized Pydantic models, **not** ESPN pass-through (with one passthrough exception for live scoreboards — see 6.1) | Stable contract for clients; isolates ESPN shape changes |
| Ingest model | Scheduled (in-process loops) + on-demand (POST `/ingest/...`) + live passthrough endpoint (Phase 2) | See 6.1 |
| Process supervision | **launchd** (two agents: `com.espn.backend`, `com.espn.worker`) | Matches Hearth (launchd for the HTTP service); no need for PM2 since we have no sidecars yet |
| Deployment | **rsync from laptop + `launchctl kickstart`** via `deploy/sync.sh` | Matches Hearth/Orbit/Portfolio. Excludes `.env`, `.venv`, caches, logs. |
| Containerization | **None for v1.** Native Homebrew Postgres + launchd. | Adds operational burden without matching benefit at personal scale; user doesn't normally use Docker; matches Mini's existing pattern. Revisit if we ever multi-host. |
| State / secrets on Mini | `~/.espn/.env` (chmod 600, never rsync'd) + `~/.espn/{backend,worker}.{log,err}` | Mirrors `~/.hearth/`, `~/.orbit/`. Survives reinstalls. |
| Cloudflare Tunnel | `espn.schnetz.us` → `http://127.0.0.1:8005` | Add ingress rule to existing `/etc/cloudflared/config.yml` |
| Project location | `/Users/tgschnetzer/Documents/Development/IntelliJ/Python/ESPN` | Personal project; sibling to Braves, Orbit, NASCAR, NCAA |
| Upstream reference | `~/Documents/Development/Python/CFB Bowls/Public-ESPN-API` | Open-source Django repo — borrow endpoint shapes, ingest logic, models conceptually; do not copy code |

### Why Postgres over DuckDB
- Workload is OLTP: live scoreboards upsert every few minutes; rows mutate as game state changes; concurrent readers.
- SQLAlchemy + Alembic migrations target row-store/OLTP backends.
- DuckDB shines on read-heavy analytical scans over immutable data — the *opposite* of live game state.
- If a historical archive layer is added later (e.g. nightly snapshots for trend queries), DuckDB alongside Postgres is the right combo. Not needed yet.

### Why in-process poll loops (over ARQ, Celery, or APScheduler)

After auditing the user's three other data-intensive Mini-hosted services (Hearth, Orbit, Portfolio) on 2026-05-11, the consistent pattern is **no job queue at all**:

- **Hearth** has 21 data sources polling on fixed cadences via a `run_poll_loop()` helper in a standalone async worker. No Redis, no ARQ, no Celery. Process-supervised by PM2/launchd; restarts on crash.
- **Orbit** uses daemon threads for Gmail/calendar polling. No queue.
- **Portfolio** caches quotes in Redis but has no job queue — Express handles scheduling itself.

For our ~10-league × few-data-type rotation (estimate: 20–40 scheduled tasks, all stable cadence), a queue is overkill. The reliability benefits (retries, dead-letter, parallel workers) don't justify the operational cost (running Redis, debugging via `arq` CLI, queue-state inspection) when:
- Personal scale, single host
- Upstream API (ESPN) is stable; failed polls auto-retry on next interval
- Worker restarts are cheap (`launchctl kickstart`)

**Tradeoff accepted:** no persistent retry queue, no parallel worker scaling, no dead-letter. Cron-style polling against a stable upstream doesn't need any of those.

### Build fresh (decided)

We are **not** forking the upstream Django service. The upstream code is reference only — borrow:
- Endpoint shapes (URL paths, query filters)
- Sport/league slug mappings (`SPORT_NAMES`, `LEAGUE_INFO`)
- Model field design (Team, Event, Competitor, Athlete, Venue, NewsArticle, Injury, Transaction, AthleteSeasonStats)
- ESPN client method coverage (which endpoints to wrap)
- Ingest logic (what to fetch, how to normalize)

Rewrite all of it in FastAPI + SQLAlchemy 2 + Pydantic v2 + in-process asyncio loops. Lose the upstream's existing test coverage in the process; write new tests as we go.

---

## 4. Service Inventory (Target API — based on upstream reference)

The target API surface for our FastAPI rewrite, modeled on the upstream Django service. This is what each phase of the migration plan needs to deliver.

**Base:** `/api/v1/`  ·  **Auth:** `Authorization: Bearer <API_KEY>` in production (bypassed when `API_KEY` env var is unset, for local dev/tests)  ·  **Format:** normalized JSON via Pydantic v2 response models

#### Query endpoints

| Path | Filters |
|------|---------|
| `/sports/` | — |
| `/leagues/` | `?sport=` |
| `/teams/` | `?sport=`, `?league=`, `?search=` |
| `/teams/{id}/` | — |
| `/teams/espn/{espn_id}/` | — |
| `/events/` | `?league=`, `?date=`, `?status=`, `?team=` |
| `/events/{id}/` | — |
| `/events/espn/{espn_id}/` | — |
| `/news/` | `?sport=`, `?league=`, `?date_from=` |
| `/injuries/` | `?sport=`, `?league=`, `?status=`, `?team=` |
| `/transactions/` | `?sport=`, `?league=`, `?date_from=` |
| `/athlete-stats/` | `?sport=`, `?league=`, `?season=`, `?athlete_espn_id=` |

#### Ingest endpoints (POST)

| Path | Body |
|------|------|
| `/ingest/teams/` | `{sport, league}` |
| `/ingest/scoreboard/` | `{sport, league, date?}` |
| `/ingest/news/` | `{sport, league, limit?}` |
| `/ingest/injuries/` | `{sport, league}` |
| `/ingest/transactions/` | `{sport, league}` |

#### Sports covered (target)
17 sports, 139 leagues. Full coverage matrix in upstream `docs/sports/`. Initial cut for v1 can be narrower — see Phase 0.

#### Scheduled ingest (target — in-process `run_poll_loop` per source)
| Loop | Interval | Notes |
|------|----------|-------|
| `refresh_news` | 30 min | All active leagues |
| `refresh_injuries` | 4 h | All active leagues |
| `refresh_transactions` | 6 h | All active leagues |
| `refresh_scoreboard` | 2 min during live windows; 1 h otherwise | Per-league; live passthrough also available (see 6.1). "Live window" is a small predicate inside the loop body. |
| `refresh_teams` | Weekly | All active leagues |

Each loop is an asyncio task launched in `app/worker.py:run()`; failures are caught and logged, the loop continues. Worker writes per-source health to a `worker_health` table (Phase 1) so clients can show staleness indicators.

> ⚠️ Upstream's 1h scoreboard cadence is too slow for SportsBar/WorldCup live UX. Our target above plus the passthrough endpoint in 6.1 fixes this.

---

## 5. Consumer Apps

### 5.1 SportsBar

**Location:** `/Users/tgschnetzer/Documents/Development/Swift/SportsBar`
**Targets:** iOS app, watchOS app, iOS widget
**Coverage:** NFL, MLB, NBA, NHL, MLS, NCAAF, NCAAM, NCAAB, NCAAS, March Madness, PGA, F1, NASCAR

#### Today
| Target | File | Calls |
|--------|------|-------|
| App | `SportsBar/Services/ESPNService.swift` | `site.api.espn.com/.../scoreboard`, `/teams/{id}/schedule`, `/teams?limit=1000`, plus `site.web.api.espn.com/.../scoreboard/header` |
| Widget | `SportsBarWidget/WidgetDataService.swift` | Same ESPN endpoints, separate URLSession |
| Watch | `SportsBarWatch/WatchESPNFetcher.swift` | Same ESPN endpoints, separate URLSession |

Shared: `ESPNParser` (pure JSON parsing), `LeagueConfig` (base URLs in `LeagueConfig.swift:11-12`).

#### After migration
- Replace the two base URLs in `LeagueConfig.swift` with `https://espn.schnetz.us/api/v1`.
- Rewrite `ESPNParser` to consume our normalized Pydantic-shaped JSON instead of ESPN's raw shape — **or** keep raw via a `?passthrough=1` mode on the gateway (see [Gap 6.1](#61-live-freshness-for-scoreboards)).
- Keep team logos served from `a.espncdn.com` (no need to proxy CDN assets).
- Optionally surface new data not in the app today: injuries, league news, transactions, athlete stats.

#### Gaps to close before SportsBar can switch
1. **Live freshness** — gateway needs sub-5-minute scoreboard updates (upstream is 1h). See 6.1.
2. **"Top Games" header endpoint** — `site.web.api.espn.com/apis/personalized/v2/scoreboard/header` has no equivalent route upstream. See 6.2.
3. **March Madness query params** — confirm `/events/` filters cover `?groups=100&seasontype=3` semantics. See 6.3.
4. **Dated scoreboard queries** — `?dates=YYYYMMDD` for past/future days. The `/events/?date=` filter covers this but needs verification it returns the same set as ESPN's scoreboard.

#### Availability tradeoff
SportsBar today: zero backend dependency. Goes dark only if ESPN does.
SportsBar after: depends on Mini + Cloudflare tunnel + Postgres.
**Decision:** acceptable (not mission-critical). No "fall back to direct ESPN" path for v1, but `LeagueConfig` keeps the original URLs commented for emergency revert.

---

### 5.2 WorldCup

**Location:** `/Users/tgschnetzer/Documents/Development/Swift/WorldCup`
**Backend:** FastAPI at `worldcup.schnetz.us`, Postgres 18
**Coverage:** FIFA World Cup 2026 only (104 matches, June–July 2026)

#### Today
- iOS/macOS apps call `worldcup.schnetz.us` (never ESPN directly).
- Backend `match_poller.py:28` calls `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard` every 60s during tournament.
- Reference data (teams, venues, groups, fixtures) seeded once from `openfootball` snapshot.

#### After migration
**Option A — minimal change (recommended for v1):**
Swap the one ESPN URL in `match_poller.py:28` to `https://espn.schnetz.us/api/v1/events/?league=fifa.world`. Adjust response mapping for our normalized shape. ~30 min of work.

**Option B — eliminate WorldCup backend (future):**
If `espn_service` exposes everything WorldCup needs (events, teams, venues, standings for FIFA), WorldCupKit calls `espn_service` directly and the FastAPI service is retired. Postgres for reference data moves into `espn_service` (or stays seeded but unused).

Recommend Option A first — proves the integration; Option B is a follow-up if it's worth the cleanup.

#### Gaps
- Confirm `espn_service` exposes `fifa.world` soccer scoreboards correctly (upstream covers soccer broadly; verify the specific league slug ends up in scheduled ingest).
- WorldCup's poller cadence is 60s — same freshness concern as SportsBar (see 6.1).

---

### 5.3 Braves

**Location:** `/Users/tgschnetzer/Documents/Development/IntelliJ/Python/Braves`
**Backend:** FastAPI, SvelteKit frontend
**Coverage:** MLB (Atlanta Braves focus)

#### Today
- Backend uses **`statsapi.mlb.com`** (not ESPN) for live game data: schedule, rosters, standings, pitch-by-pitch via diffPatch RFC 6902.
- **FanGraphs** for advanced metrics (WAR, wRC+, Barrel%, etc.).
- MLB.com RSS for news.
- DuckDB for 1871–2025 historical archive.
- Frontend has one direct call to `statsapi.mlb.com` as SSE fallback (`scorebug.svelte.js:235`).

#### Why not swap to `espn_service`
- ESPN's MLB endpoints don't match `statsapi.mlb.com` fidelity (no diffPatch, weaker pitch-by-pitch).
- FanGraphs has no ESPN equivalent.
- Swap would be a feature **downgrade**.

#### What `espn_service` *can* contribute (additive)
| Use case | Endpoint |
|----------|----------|
| MLB news (additional source) | `/api/v1/news/?league=mlb` |
| Cross-team injury report | `/api/v1/injuries/?league=mlb` |
| MLB transactions (signings/trades/waivers) | `/api/v1/transactions/?league=mlb` |
| ESPN-only content (analysts, columns) | `/api/v1/news/?sport=baseball` |

**Plan:** Braves gets a new "League Wire" or "Around MLB" section sourced from `espn_service`. Live game data and advanced stats stay as-is.

#### Gaps
- Verify our ARQ ingest jobs include `mlb` in the active league rotation for news, injuries, and transactions before Phase 3.

---

## 6. Cross-Cutting Gaps to Close

### 6.1 Live freshness for scoreboards

**Problem:** Upstream scoreboard ingest runs hourly (NBA/NFL only). SportsBar and WorldCup need sub-5-minute updates during live games.

**Options:**

| Option | Pros | Cons |
|--------|------|------|
| **A. Aggressive scheduled ingest** — ARQ cron every 60–120s for leagues with live games | All requests served from DB; predictable load on ESPN | Wasteful when no live games; "live games today?" gating logic adds complexity |
| **B. On-demand passthrough endpoint** — `/api/v1/live/{sport}/{league}/scoreboard` proxies ESPN with short cache TTL (5–10s) | Always fresh; clients hammer gateway, not ESPN | Cache hit/miss depends on coordinated client polling; Postgres bypass for live state |
| **C. Hybrid** — passthrough for `?live=1`, DB-backed for historical | Best of both | More code paths |

**Recommendation:** **B (passthrough)** for v1 — simplest, lowest infra burden, matches existing Cloudflare-tunnel-fronted pattern. Cache TTL of 10s on the gateway means at most one ESPN call per league per 10s regardless of client count.

### 6.2 Missing "Top Games" header endpoint

**SportsBar uses:** `site.web.api.espn.com/apis/personalized/v2/scoreboard/header?region=us&lang=en`
**Returns:** ESPN's curated cross-sport "featured games" list.

No equivalent in upstream `espn_service` today. Options:
- Add a passthrough route: `/api/v1/featured/header` → proxies to the ESPN endpoint with a 60s cache.
- Drop the feature in SportsBar.

**Recommendation:** add the passthrough route — small, isolated, low maintenance.

### 6.3 Tournament/seasontype query params

**SportsBar uses:** `?groups=100&seasontype=3` for March Madness; `?dates=YYYYMMDD` for daily filters.

Verify `/api/v1/events/` filters accept equivalent params:
- `?date=` → maps to `?dates=`
- Tournament group filter → may need a new `?group=` filter
- `?seasontype=` → may need a new filter

Action: add these as query parameters on the events router (FastAPI `Query(...)` deps) where missing.

### 6.4 Logo / asset hosting

`a.espncdn.com` URLs are returned as-is in ESPN responses. Clients fetch logos directly from ESPN's CDN. Don't proxy these — bandwidth and complexity not worth it. Just ensure Pydantic response models preserve the logo URL field.

### 6.5 OpenAPI client generation

FastAPI exposes an OpenAPI schema at `/openapi.json` by default (plus Swagger UI at `/docs` and ReDoc at `/redoc`). Use it to generate:
- Swift client for SportsBar/WorldCup (e.g. via `swift-openapi-generator`)
- TypeScript client for Braves frontend (if eventually consumed there)
- Python client for Braves backend (if we automate the additive ESPN-supplement section)

This avoids hand-maintaining DTOs in three languages.

---

## 7. Migration Plan

### Phase 0 — Bootstrap this project (✅ complete 2026-05-11)
1. ✅ Scaffolded with `uv init` + `uv add fastapi 'uvicorn[standard]' 'sqlalchemy[asyncio]' asyncpg alembic pydantic-settings httpx tenacity`.
2. ✅ Project structure: `app/` (routers, models, schemas, services, deps, auth), `app/worker.py` (in-process loops), `alembic/`, `tests/`, `deploy/`, `launchd/`.
3. ✅ SQLAlchemy models for `Sport`, `League`, `Team` (defer Event/Athlete/News/Injury/Transaction/Venue/AthleteSeasonStats to Phase 1).
4. ✅ Alembic async env + initial migration (`alembic/versions/0001_initial.py`).
5. ✅ Minimal `ESPNClient` (httpx async, tenacity retry) covering teams + scoreboard.
6. ✅ Bearer-token auth dep on `/api/v1/*` (`app/auth.py`).
7. ✅ launchd plists for backend + worker; `deploy/sync.sh` for rsync deploy.
8. ✅ Smoke tests (healthz, openapi, auth) pass.

Next: bring up local Postgres and run a real end-to-end round-trip (ingest NHL → query teams). Then Phase 1.

### Phase 1 — Deploy + WorldCup swap (✅ complete 2026-05-11)
1. ✅ Deployed to Mini at `espn.schnetz.us` (Cloudflare Tunnel) + loopback `http://127.0.0.1:8005`.
2. ✅ `fifa.world` events ingested via worker poll loop (2 events pre-tournament; will populate fully June 10+).
3. ✅ WorldCup `match_poller.py` swapped: now calls `http://127.0.0.1:8005/api/v1/events/?league=fifa.world` with bearer token from `~/.worldcup/.env`. Response parser updated for normalized gateway shape (flat `competitors[]`, embedded `team.abbreviation`, `status_state`/`status_name`).
4. ✅ Cut over — no side-by-side needed since tournament hasn't started; forced-poll test for 2026-06-11 returned `events=1, upserted=1, unmatched=0`. WorldCup public API serves the match correctly.
5. ✅ Gateway gap fixes deployed: `Event.status_name` (e.g. `STATUS_POSTPONED`), `TeamMini` embedded in `CompetitorRead` (id, espn_id, abbreviation, display_name, logo_url).

**Success criteria** (deferred verification): WorldCup app shows correct live scores during a real FIFA match window — first opportunity 2026-06-10 (tournament start). Plumbing is verified; live behavior to be observed on first matchday.

### Phase 2 — SportsBar swap (✅ complete 2026-05-11)
1. ✅ Live passthrough (Gap 6.1) — `/api/v1/live/{sport}/{league}/scoreboard` with 10s TTL cache.
2. ✅ Featured header (Gap 6.2) — `/api/v1/featured/header` with 60s TTL cache.
3. ✅ `?seasontype=` filter on DB-backed events router (Gap 6.3). `?group=` works via live passthrough.
4. ✅ Two more live passthroughs added that SportsBar needs: `/live/{sport}/{league}/teams` (1d cache) and `/live/{sport}/{league}/teams/{team_id}/schedule` (5min cache).
5. ✅ SportsBar `LeagueConfig.swift` — `espnBase` → `\(Secrets.espnAPIBaseURL)/live`, `espnHeader` → `/featured/header`.
6. ✅ Bearer auth on all 3 targets (app, widget, watch) — `Secrets.swift` added to membership exception sets in `project.pbxproj` (same pattern as `LeagueConfig.swift`).
7. ✅ All three iOS/macOS/watchOS targets built and passed live tests.

**Success criteria met.** `ESPNParser` worked unchanged since the live endpoints return ESPN's raw JSON shape (passthrough). Logos still load directly from `a.espncdn.com`.

### Phase 3 — Braves additive integration (skipped 2026-05-11)
**Decision:** deferred indefinitely. Braves' existing `statsapi.mlb.com` + FanGraphs + MLB.com RSS sources cover MLB news, injuries, and roster moves at higher fidelity than ESPN's equivalents. No active pain point that an ESPN supplement would solve. Revisit only if a specific Braves feature emerges that genuinely needs ESPN-only content (analyst columns, ESPN BPI-style ranks, cross-team ESPN insight).

If/when revisited, the gateway work this phase would require: `NewsArticle`, `Injury`, `Transaction` models + ingest services + routers + worker poll loops. None of those are built today — Phase 3 was always going to be larger than the other phases.

---

## 8. Operations

### Deployment
- Single Mac Mini at `~/Applications/ESPN/`.
- Two launchd agents (`com.espn.backend.plist`, `com.espn.worker.plist`) installed in `~/Library/LaunchAgents/`.
- Cloudflare Tunnel ingress: `espn.schnetz.us` → `http://127.0.0.1:8005`.
- Postgres 18 already running on the Mini (shared with Hearth/Orbit/Braves); database `espn_prod`.
- Deploy from laptop with `./deploy/sync.sh` (rsync + `uv sync` + `alembic upgrade head` + `launchctl kickstart`).
- Persistent state lives in `~/.espn/` (`.env` chmod 600, never rsync'd; `backend.log`, `worker.log`, etc.).
- See [`deploy/README.md`](deploy/README.md) for the full runbook.

### Monitoring (minimum bar)
- `/healthz` returns DB connectivity (`SELECT 1`). Cloudflare Tunnel + a 1-minute external ping (UptimeRobot or similar) is sufficient — non-critical service.
- Worker writes per-source `worker_health` table rows every cycle (Phase 1); clients use this to render "ESPN data is stale" indicators (Hearth pattern).
- FastAPI/uvicorn + worker logs to `~/.espn/{backend,worker}.{log,err}`. No structured logging in v1; add `structlog` later if it gets noisy.
- Worker loop failures: caught per-iteration, logged with `logger.exception(...)`, loop continues on next interval.

### Backups
- Postgres `pg_dump` nightly to local Mini storage (shared script with other Mini-hosted services). Data is replayable from ESPN (re-ingest), so backups are convenience, not survival.

### Rate limiting (downstream to ESPN)
- ESPN has no published limits; our `ESPNClient` budget (3 retries, 30s timeout, exponential backoff with jitter via tenacity, single shared `httpx.AsyncClient`) keeps us polite.
- Single gateway means one egress point — easier to enforce. If needed, add a token-bucket limiter in front of `ESPNClient` (e.g. `aiolimiter`).

### Fallback policy
- If gateway is down: WorldCup and Braves degrade (gateway data unavailable, app shows cached/stale or empty). Acceptable.
- SportsBar v1: same. Consider adding emergency "direct to ESPN" toggle in v2 if outages prove disruptive.

---

## 9. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-11 | Build a single gateway on Mac Mini, not per-app | Consolidates ESPN coupling, shared cache, one place to patch on ESPN changes |
| 2026-05-11 | Postgres over DuckDB for primary store | OLTP workload (concurrent writes during live games); SQLAlchemy/Alembic target row-store |
| 2026-05-11 | Accept SPoF for SportsBar in exchange for consolidation | Apps not mission-critical; gain > cost |
| 2026-05-11 | Braves stays on `statsapi.mlb.com` + FanGraphs; gateway is additive only | ESPN can't match MLB-API fidelity (diffPatch, advanced metrics) |
| 2026-05-11 | Migration order: WorldCup → SportsBar → Braves | WorldCup is smallest blast radius; Braves is incremental anyway |
| 2026-05-11 | ~~No auth for v1.~~ **Superseded:** require `Authorization: Bearer <API_KEY>` on `/api/v1/*` | Defense in depth even behind Cloudflare Tunnel. Matches Hearth's pattern. Auth bypassed locally when `API_KEY` is unset. |
| 2026-05-11 | Project lives at `IntelliJ/Python/ESPN`, not in Public-ESPN-API clone | Public-ESPN-API is upstream OSS reference, not personal project space |
| 2026-05-11 | FastAPI + SQLAlchemy 2 (async) + Pydantic v2 + uv as the stack | Matches Braves/WorldCup/Hearth/Orbit pattern; user avoids Django |
| 2026-05-11 | ~~ARQ for background jobs.~~ **Superseded:** in-process asyncio poll loops (Hearth pattern) | Audit of Hearth/Orbit/Portfolio on 2026-05-11 showed none of them use a job queue. ARQ + Redis is overkill for personal-scale polling; in-process loops match the user's existing operational mental model. |
| 2026-05-11 | ~~Redis for cache + queue.~~ **Superseded:** No Redis at all in v1. | If response caching becomes needed on a live-passthrough endpoint, add an in-memory `cachetools.TTLCache` or revisit Redis then. |
| 2026-05-11 | ~~Docker + Docker Compose for Mini deploy.~~ **Superseded:** rsync + launchd (Hearth/Orbit pattern). | User doesn't normally use Docker; native is simpler and matches existing Mini-hosted services. |
| 2026-05-11 | launchd agents `com.espn.backend` (uvicorn on 127.0.0.1:8005) and `com.espn.worker` (`python -m app.worker`) | Two-process split mirrors Hearth's backend+worker decomposition. KeepAlive=true on both. |
| 2026-05-11 | Build fresh, do not fork upstream Django service | Upstream is Django; user's stack is FastAPI. Borrow endpoint shapes, model design, ingest logic conceptually — rewrite the code. |
| 2026-05-11 | v1 active league rotation: `nfl`, `nba`, `nhl`, `mlb`, `mens-college-basketball`, `college-baseball`, `mls`, `fifa.world`, `nascar-premier`, `nascar-secondary` | Covers SportsBar's most-used leagues + Braves' supplemental MLB data + WorldCup's FIFA. NASCAR Cup + Xfinity (Truck deferred). |

---

## 10. Open Questions

- **Q1.** Passthrough vs. scheduled ingest for live scoreboards — pick before Phase 2. Leaning passthrough (Option B in 6.1).
- **Q2.** ~~Initial active league rotation for cron jobs.~~ **Resolved 2026-05-11.** v1 rotation: `nfl`, `nba`, `nhl`, `mlb`, `mens-college-basketball`, `college-baseball`, `mls`, `fifa.world`, `nascar-premier`, `nascar-secondary`. Optional add-ons (defer until needed): `college-football`, `wnba`, `nascar-truck`, `f1`, `pga`.
- **Q3.** Long-term: should `worldcup` backend be retired (Option B in 5.2)? Decide after Phase 1 has been running 30+ days.
- **Q4.** Cloudflare Access (zero-trust auth on the tunnel) instead of no-auth? Useful if hosts ever leak; trivial to add.
- **Q5.** Type checker: mypy or pyright? Pyright integrates better with Pydantic v2 + modern IDE story; mypy is stricter and more conventional. Pick before serious typing work.

---

## Appendix A — Quick Reference: App → Gateway Mappings

### SportsBar
| SportsBar call (today) | Gateway equivalent |
|---|---|
| `site.api.espn.com/.../{sport}/{league}/scoreboard?dates=YYYYMMDD` | `GET /api/v1/events/?league={league}&date=YYYY-MM-DD` |
| `site.api.espn.com/.../{sport}/{league}/teams/{teamId}/schedule` | `GET /api/v1/events/?team={teamId}` (after team filter parity) |
| `site.api.espn.com/.../{sport}/{league}/teams?limit=1000` | `GET /api/v1/teams/?league={league}` |
| `site.web.api.espn.com/apis/personalized/v2/scoreboard/header` | `GET /api/v1/featured/header` (to be added — Gap 6.2) |
| `site.api.espn.com/.../basketball/mens-college-basketball/scoreboard?groups=100&seasontype=3` | `GET /api/v1/events/?league=mens-college-basketball&group=100&seasontype=3` (to be added — Gap 6.3) |

### WorldCup
| WorldCup backend call (today) | Gateway equivalent |
|---|---|
| `site.api.espn.com/.../soccer/fifa.world/scoreboard` | `GET /api/v1/events/?league=fifa.world` |

### Braves (additive)
| New feature | Gateway endpoint |
|---|---|
| MLB league news | `GET /api/v1/news/?league=mlb` |
| MLB injury report | `GET /api/v1/injuries/?league=mlb` |
| MLB transactions | `GET /api/v1/transactions/?league=mlb` |

---

## Appendix B — Upstream Reference

The upstream open-source Public-ESPN-API repo lives at `~/Documents/Development/Python/CFB Bowls/Public-ESPN-API`. We are **not** copying its code — it's a Django project and we're building in FastAPI. Use it as a reference for:

- **`espn_service/clients/espn_client.py`** — which ESPN endpoints to wrap and how (URL patterns, query params, retry handling). Port the *method signatures* to async httpx; rewrite the implementation.
- **`espn_service/apps/espn/models.py`** — model field design (Sport, League, Team, Event, Competitor, Athlete, Venue, NewsArticle, Injury, Transaction, AthleteSeasonStats). Translate to SQLAlchemy 2 async declarative models.
- **`espn_service/config/celery.py`, `apps/ingest/tasks.py`** — ingest task design (what to fetch, how to normalize). Reimplement as ARQ functions.
- **`espn_service/apps/core/sport_config.py`** (or wherever `SPORT_NAMES` / `LEAGUE_INFO` live) — the 17-sport, 139-league slug mapping. Worth copying verbatim into a config module since it's pure data.
- **`README.md`** — comprehensive ESPN endpoint reference (370 v2 + 79 v3 endpoints, 17 sports, 139 leagues). Primary reference for endpoint discovery.
- **`docs/sports/`** — per-sport endpoint reference (one .md per sport).
- **`docs/response_schemas.md`** — example JSON for common endpoints. Useful for writing Pydantic response models.

Treat that directory as read-only reference. All changes to our gateway live in this directory (`/Users/tgschnetzer/Documents/Development/IntelliJ/Python/ESPN`).
