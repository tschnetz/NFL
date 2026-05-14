# NFL backend — API contract for the SwiftUI client

The Python/FastAPI backend is **deployed and live** at `https://nfl.schnetz.us` (Mac Mini, Cloudflare Tunnel, port 8008 on loopback). Backend repo: `~/Documents/Development/IntelliJ/Python/NFL/`. Phases 1–9 of `MIGRATE_MINI.md` are complete, including the full Phase 7 ML pipeline. **No frontend work has shipped yet** — the SwiftUI app under `NFL/` is the scaffold from `xcodegen`.

This doc is the contract the SwiftUI client should code against. When in doubt, hit the URL with curl — every endpoint serves real data today.

## Base config

```swift
struct Config {
    static let baseURL = URL(string: "https://nfl.schnetz.us")!     // release
    // static let baseURL = URL(string: "http://127.0.0.1:8008")!  // debug, when the Mini is on the LAN
}
```

- **Auth**: bearer-token middleware is wired but unconfigured. As of 2026-05-14 the `API_KEY` env var is empty on the Mini, so `/api/*` accepts unauthenticated requests. Future-you can flip it on by setting `API_KEY` in `~/.nfl/.env` on the Mini and sending `Authorization: Bearer <key>` from the client.
- **CORS**: not configured. SwiftUI doesn't care (no browser preflight); add CORS only if a web client ever needs it.
- **Wire format**: JSON; field names in `snake_case` for picks/scoreboard/schedule, `camelCase` for `/api/team`, `/api/venue`, `/api/weather` (legacy contract preserved per route). Plan for both in the Swift decoder layer (`JSONDecoder().keyDecodingStrategy = .useDefaultKeys` + manual `CodingKeys`).
- **Health**: `GET /healthz` returns `{"status":"ok|degraded","database":"ok|fail"}`. No auth.

## Endpoint catalog

All read endpoints are cached server-side via the Postgres `api_cache` table (no Redis). First call ~150ms, subsequent calls <10ms.

### Read paths the home screen needs

| Method | Path | Notes |
|---|---|---|
| GET | `/api/scoreboard` | Today's NFL slate. ESPN-passthrough live state. |
| GET | `/api/scoreboard/day` | Same as above (alias) |
| GET | `/api/scoreboard/day/{YYYY-MM-DD}` | Slate for a given calendar day |
| GET | `/api/scoreboard/week/{year}/{week}` | All games for a regular-season week |
| GET | `/api/scoreboard/year/{year}` | All scoreboards for a season |
| GET | `/api/schedule/{season}` | Full-season schedule from nflverse `games_historical` |
| GET | `/api/schedule/team/{ABBR}` | One team's full season |
| GET | `/api/standings` | League standings |
| GET | `/api/standings/{ABBR}` | Single team's record |
| GET | `/api/team` | All teams (32 rows) |
| GET | `/api/team/abbr/{ABBR}` | Team by 2-3 letter abbreviation |
| GET | `/api/team/espn/{espn_id}` | Team by ESPN integer id |
| GET | `/api/team/{ABBR}/roster` | Active roster from `rosters_weekly` |
| GET | `/api/calendar/{year}` | Week boundaries (start/end dates per week #) |

### Per-game detail screen

| Method | Path | Notes |
|---|---|---|
| GET | `/api/preview/{game_id}` | Pre-game card data (matchup, trends) |
| GET | `/api/box/{event_id}` | Box score (uses ESPN event id, not nflverse game_id) |
| GET | `/api/scoring-plays/{event_id}` | Drive summary / scoring plays |
| GET | `/api/event-odds/{event_id}` | Live odds for in-game state |
| GET | `/api/venue/{espn_id}` | Stadium info (lat/lon/indoor/capacity/surface) |
| GET | `/api/weather?lat=X&lon=Y&time=ISO` | Open-Meteo forecast for the venue at kickoff |

### Predictions (the ML payload)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/preds/{season}/{week}` | Per-game ML predictions for a week |
| GET | `/api/preds/{season}/{week}/v{ver}` | Versioned variant (same shape) |
| POST | `/api/admin/retrain-and-cache` | Kicks a full retrain (~50s sync). Returns trained_through + validation metrics. Optional query params: `tune_margin`, `start_season`, `end_season`, `through_week` |

Top-level shape:
```json
{
  "season": 2024, "week": 6, "seasonType": "regular",
  "version": "1", "source": "model",
  "predictions": [ <game>, <game>, ... ]
}
```

Each `<game>` object carries the full calibration payload (May 2026 model, val MAE 10.66, spread cover acc 55.4%):

```json
{
  "season": 2024, "week": 6, "game_id": "2024_06_SF_SEA", "id": "401671660",
  "home_team": "SEA", "away_team": "SF",
  "spread_line": -3.5, "over_under_line": 47.5,

  // Primary prediction (calibrated posterior, what to display as the model's pick)
  "pred_home_margin": 0.23,
  "pred_home_margin_raw": -6.92,
  "injury_adjustment": 0.0,

  // Bayesian blend transparency
  "mu_model": -6.92, "sigma_model": 6.21,
  "mu_post": 0.23, "sigma_post": 6.21,
  "tau_prior": 7.5, "vegas_home_margin": -3.5,

  // Cover + win probabilities
  "pred_cover_prob": 0.32,          // raw, uncalibrated
  "pred_cover_prob_cal": 0.075,     // isotonic-calibrated, prefer this for UI
  "pred_home_win_prob": 0.423,

  // Confidence intervals around mu_post
  "margin_ci_50_lower": -3.95, "margin_ci_50_upper":  4.42,
  "margin_ci_80_lower": -7.72, "margin_ci_80_upper":  8.19,
  "margin_ci_95_lower": -11.94,"margin_ci_95_upper": 12.41,

  // Betting picks (matches the legacy contract)
  "spread_edge": 3.73, "spread_pick": "SEA +3.5", "spread_bet_strength": "Strong",
  "total_edge": 0.45,  "total_pick": "Over",      "total_bet_strength": "Pass",
  "best_bet": "SEA +3.5", "best_bet_edge": 3.73,
  "best_bet_strength": "Strong", "best_bet_market": "spread",

  // Kelly stake (fractional, capped at 1%)
  "kelly_fraction": 0.01, "kelly_fraction_raw": 0.08, "p_side_used": 0.92,

  // "Why this pick" feature columns (28 features, useful for an info-card UI)
  "off_diff": ..., "def_diff": ..., "off_def_interaction": ...,
  "qb_ypa_l5_diff": ..., "press_rate_diff": ..., "press_rate_l5_diff": ...,
  "injury_burden_diff": ...,
  "off_cont_diff": ..., "def_cont_diff": ..., "ol_cont_diff": ..., "db_cont_diff": ...,
  "qb_change_diff": ..., "qb_cont_diff": ...,
  "rest_days_diff": ..., "home_rest_adv": ...,
  "short_week_diff": ..., "b2b_away_diff": ...,
  "roof_dome": 0.0, "cold": 0.0, "windy": 0.0
}
```

**Sign conventions you'll trip on:**
- `spread_line` follows nflverse: **home minus away**, so a `-3.5` spread = home is favored by 3.5. The pre-rendered `spread_pick` string (`"SEA +3.5"`) already does the math; prefer it over re-computing in the client.
- `pred_home_margin` > 0 ⇒ home wins by that many; ⇒ the model thinks home covers when `pred_home_margin > -spread_line`.
- `best_bet_strength` ∈ `{"Strong", "Medium", "Lean", "Pass"}` (edge thresholds 3 / 2 / 1 / <1).
- `kelly_fraction` capped at 0.01 (1% of bankroll). Render as `Int(fraction * 10000)` "units" if you want integer presentation.

### Picks (the social layer)

Two pickers forever: **Jim** and **Tom**. No rooms, no Socket.IO — Postgres polling on a 5-15s interval is fine.

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/api/picks/state` | — | Current week's pick state + scores |
| GET | `/api/picks/history` | — | All-time picker stats |
| POST | `/api/picks/open` | `{season, week}` | Open the week (admin) |
| POST | `/api/picks/pick` | `{week_id, game_id, picker, side}` | Place a pick |
| POST | `/api/picks/unpick` | `{week_id, game_id, picker}` | Undo a pick |
| POST | `/api/picks/advanceTurn` | `{week_id}` | Hand off picking turn |
| POST | `/api/picks/markDoubles` | `{week_id, game_id, picker}` | Mark a pick as a double-up |
| POST | `/api/picks/markPresses` | `{week_id, game_id, picker}` | Mark a press |
| POST | `/api/picks/close` | `{week_id}` | Close the slate |
| POST | `/api/picks/score` | `{week_id}` | Run scoring (idempotent) |

Picks state machine and scoring are ported verbatim from the legacy Express backend (`~/Documents/Development/Webstorm/nfl/backend/routes/picksRoute.js`); pytest cases in the Python repo (`tests/test_picks_scoring.py`) pin the math.

## What's in the Swift project today

```
Swift/NFL/
  NFL.xcodeproj/        # Xcode project
  NFL/
    NFLApp.swift        # 17 lines — App entrypoint
    ContentView.swift   # 24 lines — placeholder
    Assets.xcassets/
  Docs/
    SwiftUI Visual Design & Polish — 2026.md      # design system reference
    Tom's Best Practices — SwiftUI, ... 2026.md   # style conventions
    ESPN_SERVICE.md                               # backend dep
    MINI_ENV.md                                   # infra reference
  MIGRATE_MINI.md       # the master migration plan (1585 lines); read this first
```

The Mini infrastructure doc lives at `Docs/MINI_ENV.md` — it covers the deployment topology, Postgres, Cloudflare Tunnel, launchd. You don't need it for client work, but it explains why the API is at `nfl.schnetz.us` instead of a Render URL.

## Recommended first steps for the SwiftUI port

1. **Generate a Codable layer from the wire shapes above.** Start with `Predictions` + `Game` + `PickRow`; everything else is shallow.
2. **Single `APIClient` actor** for all requests. Hold a `URLSession` + base URL + optional bearer token. Use `async/await`, no Combine.
3. **Mirror the React app's screens.** Legacy frontend lived at `~/Documents/Development/Webstorm/nfl/`; the routes consumed are identical (just different protocol — REST instead of Express → Render). Read `App.jsx` + a couple of page components there to see what data each screen pulls.
4. **Predictions card first** — it's the highest-value screen and exercises the full calibration payload. Render the `best_bet_strength` badge, `pred_home_margin` ± `sigma_post`, and the `pred_cover_prob_cal` as a percentage. Defer charts/CIs.
5. **Cache via SwiftData or `URLCache`** — the backend's cache headers are minimal; client-side keep responses fresh for ~5 min during gameday.

## When the backend needs to change

The backend is in active maintenance mode. If the SwiftUI client needs a payload field that doesn't exist:
1. Open the backend repo at `~/Documents/Development/IntelliJ/Python/NFL/`.
2. The relevant router under `app/routers/` + service under `app/services/`.
3. Add the field, write a pytest, run `uv run pytest -q`, then `./deploy/sync.sh` to push.

The Mini auto-restarts the backend via launchd; the new field is live in ~30s.

## Known follow-ups on the backend side (not blockers for the client)

- `cold`/`windy` weather features are real for live (current-week) games but always zero for historical games — Open-Meteo's free tier serves a ±9 day window. Doesn't affect serving.
- The May 2026 model bundle is a fixed-hyperparameter retrain. A tuned retrain (`POST /api/admin/retrain-and-cache?tune_margin=true`) takes ~5 min and typically buys 0.2–0.4 pts of val MAE.
- `depth_charts` table is intentionally empty. If a client screen needs depth-chart data, the backend has the nflverse loader code but currently excludes it from the weekly refresh (nflverse rebroke the 2026 schema).
- No retrain cron scheduled. The admin endpoint is on-demand only; add `launchd/com.nfl.retrain.plist` (Wed 03:00 ET) if/when you want a weekly cadence.
