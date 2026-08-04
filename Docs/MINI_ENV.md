# MINI_ENV — Mac Mini infrastructure reference

> One-stop reference for the self-hosted services running on `schnetzermini@Schnetzer-mini.local`. Use this when bootstrapping a new project so you don't re-discover the same facts every time.
>
> **Last updated:** 2026-05-18 (after NFL deploy + PhotoAlbum prereqs)

## TL;DR

- **Host:** `Schnetzer-mini.local`, user `schnetzermini`, macOS 25.x (Tahoe), Apple Silicon (M-series, arm64)
- **Python:** 3.14 via Homebrew (`/opt/homebrew/bin/uv`)
- **Postgres:** 18 via Homebrew (`/opt/homebrew/opt/postgresql@18`), accepting on `:5432`, peer/trust auth for `schnetzermini` user
- **Public ingress:** Cloudflare Tunnel daemon (`cloudflared`), config at `/etc/cloudflared/config.yml`, one tunnel named `mini`
- **Process supervision:** launchd (single HTTP services) + PM2 (multi-process apps like Hearth)
- **Deploy:** rsync from laptop, per-project `deploy/sync.sh`
- **Persistent state:** `~/.{app}/` for `.env` + logs (never rsync'd; chmod 600 on `.env`)
- **Apps directory:** `~/Applications/{ProjectName}/`

---

## Services running today

| App | Subdomain | Loopback | Backend tech | Postgres DB | Repo |
|---|---|---|---|---|---|
| Orbit | `orbit.schnetz.us` | `:8000` | FastAPI + psycopg (sync) | `orbit_prod` | `IntelliJ/Python/Orbit` |
| Braves | `braves.schnetz.us` | `:8001` | FastAPI + DuckDB + Redis | `braves_prod`* | `IntelliJ/Python/Braves` |
| Headline | `headline.schnetz.us` | `:8002` | FastAPI + asyncpg | `headline_prod` | backend: `IntelliJ/Python/Headline` · client: `Swift/Headline` |
| Hearth | `hearth.schnetz.us` | `:8003` | FastAPI + asyncpg + Node sidecars | `hearth_prod` | backend + clients: `Swift/Hearth/Hearth/` |
| WorldCup | `worldcup.schnetz.us` | `:8004` | FastAPI + psycopg (sync) | `worldcup_prod` | backend: `Swift/WorldCup/backend` · client: `Swift/WorldCup` |
| ESPN gateway | `espn.schnetz.us` | `:8005` | FastAPI + asyncpg + in-process worker | `espn_prod` (+ `espn_dev`) | `IntelliJ/Python/ESPN` (no client app — consumed by SportsBar/WorldCup/etc.) |
| SportsBar backend | `sportsbar.schnetz.us` | `:8006` | FastAPI + asyncpg + APNs (httpx HTTP/2) | `sportsbar_prod` | `IntelliJ/Python/SportsBar` (client: `Swift/SportsBar`) — LISTENs on `espn_prod.event_changed`, fans out APNs silent pushes to wake the iOS widget |
| Portfolio | `portfolio.schnetz.us` | `:3001` | Express (Node) + Redis | `portfolio` (+ `portfolio_local`) | `IntelliJ/React/portfolio` (backend) + `Swift/Portfolio` (clients) |
| Pigskin | `pigskin.schnetz.us` | `:8007` | FastAPI + asyncpg + Redis | `pigskin_prod` (+ `pigskin_dev`) | backend: `IntelliJ/Python/Pigskin` · client: `Swift/Pigskin` — replaces legacy `Webstorm/cfb2025` + `Python/cfbd` (migration plan in `cfb2025/KICKOFF.md`) |
| NFL | `nfl.schnetz.us` | `:8008` | FastAPI + asyncpg | `nfl_prod` (+ `nfl_dev`) | `Swift/NFL` (backend at `app/`, weekly scheduled job via `com.nfl.weekly.plist`) |
| PhotoAlbum | `photoalbum.schnetz.us` | `:8009` | FastAPI + asyncpg + pgvector (planned) | `photoalbum_prod` | backend: `IntelliJ/Python/PhotoAlbums` — see `PHOTO_ALBUMS.md` (Phase 0 complete: DB created, pgvector 0.8.2 installed; backend skeleton TBD) |

\* Verify Braves DB name on next deploy; not probed during this audit.

**Next free port:** `:8010`. Stay in the 8000s for FastAPI services; `:3xxx` for Node.

---

## SSH access

```bash
ssh schnetzermini@Schnetzer-mini.local
```

Key-based auth, no password. Sudo on the Mini requires the schnetzermini password (no TouchID over SSH); only needed for cloudflared config edits.

For commands that need a TTY (e.g. sudo prompts), use `ssh -t`. For non-interactive scripts, anything that needs sudo must run *from* the Mini (e.g. `setup-tunnel.sh` invoked over `ssh -t`).

---

## Postgres

```bash
# CLI tools live here (not in default PATH on some shells):
/opt/homebrew/opt/postgresql@18/bin/{psql,createdb,pg_dump,pg_isready}

# Quick check from anywhere:
pg_isready                                  # default port 5432
psql -d postgres -c "\l"                    # list databases
psql -d <db> -c "\dt"                       # list tables

# Create a new database for a new project:
/opt/homebrew/opt/postgresql@18/bin/createdb <project>_prod
/opt/homebrew/opt/postgresql@18/bin/createdb <project>_dev    # optional
```

### Connection strings used by apps

| Driver | DSN form |
|---|---|
| asyncpg (FastAPI async) | `postgresql+asyncpg://schnetzermini@localhost:5432/<db>` |
| psycopg sync | `postgresql+psycopg://schnetzermini@localhost:5432/<db>` |
| Node `pg` | `postgresql://schnetzermini@localhost:5432/<db>` |

Auth is local trust for the `schnetzermini` user, both unix-socket and TCP localhost. No password required from the Mini itself.

### SSH-tunneled local dev (no Postgres on MacBook)

```bash
# In one terminal, keep open:
ssh -N -L 5433:localhost:5432 schnetzermini@Schnetzer-mini.local

# In your app's .env:
DATABASE_URL=postgresql+asyncpg://schnetzermini@localhost:5433/<project>_dev
```

Use a separate `*_dev` database so local iteration doesn't write to prod.

### Backup

See **[Scheduled launchd jobs](#scheduled-launchd-jobs)** below — the central `~/.mini/scripts/backup-postgres.sh` is what to update when shipping a new project. Don't roll a per-project backup unless you actually need one.

---

## Scheduled launchd jobs

All cron-style jobs on the Mini are launchd `StartCalendarInterval` agents under `~/Library/LaunchAgents/`. There's no actual `cron` in use.

### Backup + snapshot agents (verified 2026-05-11)

| Agent | Schedule | What it does | Script |
|---|---|---|---|
| `com.mini.backup-postgres` | 02:30 daily | Central pg_dump for 6 DBs, 14-day retention, 3× mirror (local + Drive + Storage) | `~/.mini/scripts/backup-postgres.sh` |
| `com.braves.backup` | 04:30 daily | Braves-specific backup (runs after Braves' 04:00 forward-capture refresh) | `~/Applications/Braves/scripts/backup-mini.sh` |
| `com.portfolio.snapshot` | 16:30 Mon-Fri | Daily Portfolio market-close snapshot (Render-cron replacement) | `tsx scripts/createDailySnapshot.ts` |

Logs all land in `~/.<project>/{backup,snapshot}.{log,err}`.

### Central Postgres backup — `com.mini.backup-postgres`

Plist: `~/Library/LaunchAgents/com.mini.backup-postgres.plist`
Script: `~/.mini/scripts/backup-postgres.sh`
Logs: `~/.mini/logs/backup-postgres.{log,err}`

Iterates a `JOBS` list of `db_name:project_dir:retention_days` and:

1. `pg_dump -Fc --no-owner --no-acl` → `~/.<project>/backups/<prefix>_<timestamp>.dump` (local SSD)
2. Mirrors to `~/Library/CloudStorage/GoogleDrive-wreckfan86@gmail.com/My Drive/PostgreSQL Backups` (offsite)
3. Mirrors to `/Volumes/Storage/PostgreSQL Backups` (4 TB attached drive, hedge against Drive flakiness)
4. Prunes each location to its per-job retention

Drive + Storage mirrors are best-effort — macOS TCC blocks launchd-spawned bash from those locations unless `/bin/bash` (or this plist's `Label`) has Full Disk Access. Local copy always works.

**Current JOBS list** (as of 2026-05-18):
```
orbit_prod:.orbit:14
portfolio:.portfolio:14
headline_prod:.headline:14
hearth_prod:.hearth:14
worldcup_prod:.worldcup:14
banktivity_archive:.finance-dashboard:14
espn_prod:.espn:14
sportsbar_prod:.sportsbar:14
pigskin_prod:.pigskin:14
nfl_prod:.nfl:14
```

**`espn_prod` + `sportsbar_prod` added to the rotation 2026-05-11.** **`pigskin_prod` added 2026-05-12** (first dump verified). **`nfl_prod` added with the NFL deploy.** Current rotation lists 10 databases. `photoalbum_prod` will join when its backend ships (see `PHOTO_ALBUMS.md` Phase 3).

### Adding a new project's database to the central backup

1. Make sure `~/.<project>/backups/` exists (will be created on first run).
2. Edit `~/.mini/scripts/backup-postgres.sh` and append `"<db>:.<project>:14"` to `JOBS`.
3. (Optional) Trigger immediately to verify: `launchctl kickstart -k gui/$(id -u)/com.mini.backup-postgres` then tail the log.
4. Verify dump files appear in all three locations.

### Triggering / inspecting backup jobs

```bash
# Run any backup now — invoke the script directly. (launchctl kickstart -k is
# silently a no-op for one-shot calendar jobs that aren't currently running.)
ssh schnetzermini@Schnetzer-mini.local 'bash ~/.mini/scripts/backup-postgres.sh'

# Or for a project-specific one-shot:
ssh schnetzermini@Schnetzer-mini.local \
  'bash ~/Applications/Braves/scripts/backup-mini.sh'

# See last scheduled-run result
ssh schnetzermini@Schnetzer-mini.local 'tail -50 ~/.mini/logs/backup-postgres.log'

# List active scheduled jobs
ssh schnetzermini@Schnetzer-mini.local \
  'launchctl list | grep -E "com\.(mini|braves|portfolio)\.(backup|snapshot)"'
```

### Postgres + Redis daemons

These also run as user launchd agents (standard `brew services` setup):
- `homebrew.mxcl.postgresql@18` — Postgres 18 on `:5432`
- `homebrew.mxcl.redis` — Redis (used by Portfolio + Braves caches; ESPN and Hearth skip it intentionally)
- `homebrew.mxcl.colima` — Docker-compatible runtime (installed but unused by current apps)

### PM2 boot

`pm2.schnetzermini.plist` in `~/Library/LaunchAgents/` bootstraps PM2 at login. PM2 in turn manages Hearth's 4-process arrangement per `~/Applications/Hearth/pm2.config.cjs`.

---

## Cloudflare Tunnel

Daemon: `cloudflared` running as a system launchd service. One tunnel named `mini`.

- Config: `/etc/cloudflared/config.yml` (root-owned, sudo to edit)
- Cert: `~/.cloudflared/cert.pem` (user-level, owned by `schnetzermini`)
- Restart: `sudo launchctl kickstart -k system/com.cloudflare.cloudflared`

### Add a hostname (canonical script)

Every project copies this script verbatim from Hearth into its own `deploy/setup-tunnel.sh` — same Mini, same daemon. Originals at:

- `Swift/Hearth/Hearth/deploy/setup-tunnel.sh`
- `Swift/WorldCup/backend/scripts/setup-tunnel.sh`
- `IntelliJ/Python/ESPN/deploy/setup-tunnel.sh`

Run via SSH with a TTY (sudo prompt comes back to the caller):

```bash
ssh -t schnetzermini@Schnetzer-mini.local \
  "cd ~/Applications/<Project> && bash deploy/setup-tunnel.sh <subdomain>.schnetz.us <port>"
```

The script: registers the DNS CNAME (user-level), backs up the YAML, inserts the new ingress rule before the catch-all `http_status:404`, and kickstarts the daemon.

---

## launchd vs PM2

**Default: launchd for everything.** macOS native, no extra daemon, one plist per process. Used by Orbit, Braves, Headline, WorldCup, ESPN backend + worker, Portfolio backend, Hearth backend.

**PM2 only for multi-process apps with sidecars.** Hearth uses PM2 for its 4-process arrangement (worker + 3 Node sidecars) because PM2 reads a single `pm2.config.cjs` for the whole set. Boot via launchd → PM2 → sidecars.

### launchd plist template

Save to `~/Library/LaunchAgents/com.<project>.<role>.plist`, then bootstrap:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.<project>.<role>.plist
launchctl kickstart -k gui/$(id -u)/com.<project>.<role>     # restart on demand
launchctl print     gui/$(id -u)/com.<project>.<role>        # status
launchctl bootout   gui/$(id -u)/com.<project>.<role>        # stop + unload
```

Required keys for a typical FastAPI service:

```xml
<key>Label</key>             <string>com.<project>.backend</string>
<key>ProgramArguments</key>  <array>
  <string>/opt/homebrew/bin/uv</string>
  <string>run</string>
  <string>uvicorn</string>
  <string>app.main:app</string>
  <string>--host</string><string>127.0.0.1</string>
  <string>--port</string><string><PORT></string>
</array>
<key>WorkingDirectory</key>  <string>/Users/schnetzermini/Applications/<Project></string>
<key>EnvironmentVariables</key> <dict>
  <key>PATH</key>            <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  <key>HOME</key>            <string>/Users/schnetzermini</string>
</dict>
<key>RunAtLoad</key>     <true/>
<key>KeepAlive</key>     <true/>
<key>ThrottleInterval</key> <integer>5</integer>
<key>StandardOutPath</key>  <string>/Users/schnetzermini/.<project>/backend.log</string>
<key>StandardErrorPath</key> <string>/Users/schnetzermini/.<project>/backend.err</string>
```

`PATH` and `HOME` env vars are mandatory — launchd starts with an extremely minimal env and `uv` lives in `/opt/homebrew/bin`. Hearth and ESPN both spell this out.

### Sample plists in the repos

- ESPN: `IntelliJ/Python/ESPN/launchd/com.espn.backend.plist`, `com.espn.worker.plist`
- Hearth: `Swift/Hearth/Hearth/launchd/com.hearth.backend.plist`
- WorldCup: `Swift/WorldCup/backend/deploy/com.worldcup.{backend,poller}.plist`

---

## Deploy pattern (`deploy/sync.sh`)

Every Python project has its own `deploy/sync.sh` doing the same shape of work. Hearth/Orbit/ESPN are the cleanest references. Copy from ESPN's: it handles backend + worker restart and runs `uv sync --frozen` + `alembic upgrade head` on the Mini before kicking services.

```
deploy/sync.sh                # full sync + restart backend + worker
deploy/sync.sh --no-restart   # sync only, no restart
deploy/sync.sh --backend-only # restart just the backend
deploy/sync.sh --worker-only  # restart just the worker
```

Always exclude these from rsync: `.git`, `.venv`, `__pycache__`, `.pytest_cache`, `.ruff_cache`, `.idea`, `.DS_Store`, `.env`, `*.log`, `*.err`.

---

## State + secrets convention (`~/.<project>/`)

Each project owns a hidden directory under `~/` for things that must survive rsyncs and never be committed:

```
~/.<project>/
├── .env          # chmod 600 — DATABASE_URL, API keys, etc.
├── backend.log   # launchd stdout
├── backend.err   # launchd stderr
└── *.tokens      # vendor auth cookies (Hearth has Ring/Eufy/Alexa here)
```

**On first deploy:** create the directory, write `.env`, then symlink the project's `~/Applications/<Project>/.env` to it (so the running app finds it without `.env` ever living in the rsync source).

```bash
ln -sf ~/.espn/.env ~/Applications/ESPN/.env
```

`deploy/sync.sh` excludes `.env`, so the symlink survives every deploy.

---

## Inter-service calls on the Mini

Talk via **loopback** (`http://127.0.0.1:<port>`), not the Cloudflare URL. Skips the tunnel round-trip and the public auth. WorldCup's match_poller hits `http://127.0.0.1:8005` for ESPN gateway, not `https://espn.schnetz.us`.

Public URLs (Cloudflare tunnel) are for **external clients only** — iOS apps, browsers, UptimeRobot, etc.

---

## Auth

| Service | Public auth |
|---|---|
| Hearth | Bearer token + per-route HMAC for webhooks |
| ESPN gateway | Bearer token on `/api/v1/*` (none on `/healthz`) |
| Others | None today (relies on tunnel-as-firewall) |

The pattern when adding auth: `Settings.api_key: str \| None`. If `None`, auth is bypassed (dev/test). If set, required. Mirrors `~/.{app}/.env`.

---

## Power management (essential for a server Mini)

Hearth's MIGRATE_MINI.md spells these out. Run once on Mini setup:

```bash
sudo pmset -a sleep 0           # never sleep
sudo pmset -a disksleep 0       # never spin disks down
sudo pmset -a womp 1            # wake on magic packet (for remote restart)
sudo pmset -a autorestart 1     # restart after power loss
sudo systemsetup -setrestartfreeze on   # auto-recover from freeze
```

---

## Useful one-liners

```bash
# Identify what owns a port (run on Mini)
lsof -nP -iTCP:<port> -sTCP:LISTEN

# All listening ports
lsof -nP -iTCP -sTCP:LISTEN | grep -v '0.0.0.0\|::'

# Health-ping every service from MacBook. Health-endpoint names vary —
# ESPN uses /healthz, Headline uses /health, some have none. Adjust per app.
for d in orbit braves hearth worldcup espn portfolio headline; do
  printf '%-12s ' $d
  curl -sS -o /dev/null -w 'HTTP %{http_code} %{time_total}s\n' "https://${d}.schnetz.us/healthz" 2>&1 \
    || echo "fail"
done

# Tail any service's logs from MacBook
ssh schnetzermini@Schnetzer-mini.local 'tail -f ~/.<project>/{backend,worker,poller}.{log,err} 2>/dev/null'

# Restart a service from MacBook
ssh schnetzermini@Schnetzer-mini.local \
  'launchctl kickstart -k gui/$(id -u)/com.<project>.<role>'

# Postgres size by database
ssh schnetzermini@Schnetzer-mini.local \
  '/opt/homebrew/opt/postgresql@18/bin/psql -d postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC"'
```

---

## Health endpoints (UptimeRobot polls these)

**Convention going forward: `/healthz`, must respond 200 to BOTH `GET` and
`HEAD`.** UptimeRobot polls with `HEAD` (not GET), and FastAPI's default
`@router.get(...)` returns **405 Method Not Allowed** for HEAD — that's
the gotcha that bit Pigskin and is easy to repeat in the next project.

Register both methods on one handler in FastAPI:

```python
@router.api_route(
    "/healthz",
    methods=["GET", "HEAD"],
    response_model=HealthStatus,
)
async def healthz() -> HealthStatus:
    ...
```

Stacking `@router.get("/healthz")` + `@router.head("/healthz")` also
"works" but advertises a `content-length` without a body, which curl flags
as `transfer closed with N bytes remaining` and some monitors interpret
as a malformed response. The `api_route` form is the canonical fix.

Verification:

```bash
curl -sS -o /dev/null -w 'GET  %{http_code} %{size_download}b\n' \
  https://<project>.schnetz.us/healthz
curl -sS -o /dev/null -w 'HEAD %{http_code} %{size_download}b\n' -I \
  https://<project>.schnetz.us/healthz
# Expect: GET 200 31b (or similar), HEAD 200 0b (zero bytes, no warning)
```

Endpoint inventory (audit before pointing UptimeRobot at anything):

| App | Path | HEAD-safe? |
|---|---|---|
| Pigskin | `/healthz` | ✅ |
| ESPN gateway | `/healthz` | check on next touch |
| Hearth | `/health` | check on next touch |
| Headline | `/health` | check on next touch |
| WorldCup | varies | check |

Retrofit the older apps with the `api_route` pattern next time you touch
each one. Until then, point UptimeRobot at GET via the `HTTP method`
option, not HEAD.

---

## Bootstrapping a new Python project — checklist

For a typical FastAPI + SQLAlchemy + Postgres backend, following the ESPN pattern:

1. Pick a port. Survey: `for p in 8000..8010; do ssh mini "lsof -nP -iTCP:$p -sTCP:LISTEN" ; done`.
2. Pick a subdomain: `<project>.schnetz.us`.
3. On the Mini:
   - `createdb <project>_prod` (and `<project>_dev`)
   - `mkdir ~/.<project> && chmod 700 ~/.<project>`
   - `mkdir ~/Applications/<Project>`
4. On laptop: `uv init`, scaffold `app/`, alembic, launchd plists, `deploy/sync.sh`, `deploy/setup-tunnel.sh` (copy from ESPN).
5. Write `~/.<project>/.env` on the Mini (chmod 600); symlink to `~/Applications/<Project>/.env`.
6. `./deploy/sync.sh` to push code, run migrations, restart.
7. `ssh -t mini "cd ~/Applications/<Project> && bash deploy/setup-tunnel.sh <project>.schnetz.us <port>"` to add the public route.
8. `curl https://<project>.schnetz.us/healthz` to verify.
9. Add the database to the central backup: append `<db>:.<project>:14` to `~/.mini/scripts/backup-postgres.sh` `JOBS` array. Trigger once to verify (`launchctl kickstart -k gui/$(id -u)/com.mini.backup-postgres`).
10. Update this MINI_ENV.md with the new row + bump the JOBS list.

---

## Open / verify-on-next-touch

- **Braves DB** — no `braves_prod` exists in the Postgres list. Braves uses its own backup script (`~/Applications/Braves/scripts/backup-mini.sh`) — peek there next time to learn what database/data it actually dumps. Could be DuckDB-only with a Postgres view layer; worth documenting.
- **Health-endpoint convention** — going forward use `/healthz` with both GET and HEAD supported (see "Health endpoints" section above). Older apps (Hearth/`/health`, Headline/`/health`) need retrofitting on next touch; until then, point UptimeRobot at GET (not HEAD) for those.
- **PM2 bootstrap** — resolved: `pm2.schnetzermini.plist` in `~/Library/LaunchAgents/`. Consider checking it into Hearth's repo so a Mini rebuild is reproducible.
- **`.bak` plists** — `com.braves.backend.plist.bak`, `com.portfolio.snapshot.plist.bak`, etc. clutter `~/Library/LaunchAgents/`. Clean up when convenient (some may be stale revisions kept for rollback).
