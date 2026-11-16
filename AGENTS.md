# AGENTS.md

Hands-on build of a WoW 3.3.5a (WotLK) private server: AzerothCore + mod-playerbots, sized for ~10 real players + 50+ bots. This repo holds the compose override, docs, and config references only — the server source is cloned and its Docker images built in a separate working directory.

## How it is wired

Canonical layout — one base dir (default `$HOME/WotLK`, flag `--base-dir` / env `WOTLK_BASE_DIR`) owns both pieces:
```
$HOME/WotLK/
├── azerothcore-wotlk/   # source clone; its docker-compose.yml is the compose BASE and the launch cwd
└── runtime/             # conf, db, data, logs, db.password, generated docker-compose.modules.yml
```

- Server source: clone `mod-playerbots/azerothcore-wotlk` branch **`Playerbot`** (NOT upstream AzerothCore master) into `<base-dir>/azerothcore-wotlk`, then clone the modules listed in `docs/server.md` into its `modules/` dir. Build there: `DOCKER_IMAGE_TAG=<tag> docker compose build`.
- `docker compose up` runs from **the clone dir**, project name pinned via `COMPOSE_PROJECT_NAME=wotlk`. The compose stack = clone's `docker-compose.yml` (base) merged with this repo's `docker-compose.override.yml` (+ generated modules file when `--modules-dir` is used), chained through the `COMPOSE_FILE` env var that `start-server.sh` prints. Services use prebuilt/built images `acore/ac-wotlk-{db-import,worldserver,authserver,client-data}:${DOCKER_IMAGE_TAG}` (default tag `master`).
- Local customization lives **only in this repo's `docker-compose.override.yml`** (mysql.cnf mount + per-service `mem_limit` — pure deltas, never restate base config); upstream service definitions stay untouched and refresh with `git pull` in the clone. MySQL tuning lives in `conf/mysql.cnf` → `ac-database:/etc/mysql/conf.d/custom.cnf:ro`, path overridable via `$MYSQL_CNF` (exported by `start-server.sh` to `$RUNTIME_DIR/conf/mysql.cnf`); apply with `docker compose up -d ac-database`, then bring world/auth back up.
- **Host RAM is dominated by a local LLM (~100G); the WoW server must stay within ~20G.** Memory limits (`mem_limit`, env-overridable like `DOCKER_WORLD_MEM_LIMIT`): db 6g (must stay > `innodb_buffer_pool_size` = 4g in mysql.cnf), world 8g, auth 512m, db-import 1g, client-data-init 256m, tools 4g (run that profile with the LLM unloaded). If world/auth restart-loop after load, check `docker inspect --format '{{.State.OOMKilled}}'` before debugging anything else.
- `docs/server.md` is the authoritative module set & build flow; `docs/client.md` covers client setup (downloads, LAA patch, zhCN locale, Project Reforged HD patches, addons, realmlist).
- Laptop → Strix Halo PC code sync: `bash sync-to-pc.sh --target-ip <ip> [--port <n>] [--folder <path>] [--dry-run]` (one-way rsync; excludes `.git`, `opencode.json*`, `.DS_Store`; never touches the PC's `$HOME/WotLK/runtime`). On the PC follow up with `start-server.sh --refresh-conf`. Git remote (`origin`, GitHub) is the durable path; the sync script is for fast test iteration.

## Starting the server

1. `bash start-server.sh [--base-dir <dir>] [--image-tag <tag>] [--runtime-dir <dir>] [--azerothcore-dir <dir>] [--db-password-file <file>] [--compose-file <file>] [--modules-dir <dir>] [--refresh-conf]` — bootstrap only: validates the clone exists at `<base-dir>/azerothcore-wotlk` (prints the exact `git clone` command if not), creates `<base-dir>/runtime/{conf,db,data,logs}`, prompts to copy repo `conf/*` templates into `$RUNTIME_DIR/conf/` (first time only; existing files are never overwritten, no-TTY defaults to copy), generates `$RUNTIME_DIR/db.password` if missing. Explicit `--runtime-dir`/`--azerothcore-dir` win over the `--base-dir` derivation. `--refresh-conf` skips the prompt and force-syncs runtime conf from the repo (repo wins, recursive) — use it after every `git pull`/`rsync` that changed `conf/`, otherwise runtime copies go stale silently. `--modules-dir <path>` bind-mounts a local modules dir to `ac-worldserver:/azerothcore/modules` by generating `$RUNTIME_DIR/docker-compose.modules.yml` and appending it last to `COMPOSE_FILE` (compose merges `volumes` additively); without the option no modules file is generated and nothing is mounted there. It does **not** launch the server — it prints an `export ...` block (incl. `COMPOSE_PROJECT_NAME=wotlk` and the `COMPOSE_FILE` chain) plus `cd <azerothcore-dir> && docker compose up -d` to paste. `--compose-file` replaces the base compose file (the repo's `docker-compose.override.yml` is still merged on top).
2. Run that printed block (from anywhere — all paths in it are absolute). `COMPOSE_FILE`/`COMPOSE_PROJECT_NAME` being exported means bare `docker compose ps|attach|down` also work in that shell. Defaults in the base compose (`./env/dist/...`, password `password`) are wrong for this setup — the env exports are required. Compose reads `$RUNTIME_DIR/conf/env.ac` via `env_file` for worldserver/authserver; without it compose fails. Do not leave a stray `.env` with `DOCKER_*` values in the clone dir — compose auto-loads it (exported shell vars win, but it's a footgun).

## Gotchas

- One-time cutover (first launch after the clone-base/`wotlk`-project change): take the old stack down first — `docker compose -f <old-repo>/docker-compose.yml down` while it still has the old file, or `docker compose -p Build-Own-WotLK-Server down` afterwards — because its pinned `container_name: ac-*` would collide with the new `wotlk` project. Move an existing clone to `<base-dir>/azerothcore-wotlk` if it lives elsewhere. Nothing is lost: all state is bind-mounted under `$RUNTIME_DIR`.
- Layout defaults derive from the base dir (`$HOME/WotLK`): clone at `<base-dir>/azerothcore-wotlk`, runtime at `<base-dir>/runtime` — **not** the repo's `conf/` dir (the latter only holds templates: `env.ac`, `env.docker`).
- The `tools` compose profile (map extraction) now works, since the compose base file lives inside the clone and its `build.context: .` resolves there — run `docker compose --profile tools ...` with the `COMPOSE_FILE` chain exported. Usually unneeded: `ac-client-data-init` populates the client-data volume with maps.
- MySQL 8.4 container `ac-database`; databases: `acore_auth`, `acore_world`, `acore_characters`, `acore_playerbots`. First boot runs `ac-db-import`, which is slow — world/auth wait on it.
- Ports: 3724 auth, 8085 world, 7878 SOAP (RAS console).
- Docker daemon often needs an HTTP proxy set via systemd to pull packages during image builds (recipe in `docs/server.md`).
- `opencode.jsonc` is gitignored on purpose (local model/provider config).
