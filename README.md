# homelab-template

> **DISCLAIMER** Bulk of this repo code is written with AI tools.
> By no means `svcsh` is not production ready or tested extensively.
> Main purpose was to build simple template for managing homelab docker 
> compose files with clear and easy to use pattern, that gives 
> just enough flexibility to navigate and control all services from single
> entry point svc.sh, separate config files from data (optionally) and
> version control config changes. 

A minimal, terminal-first pattern for organizing Docker Compose services on a home
server: one directory per service or stack, shared values in `global.env`, every
host port in `ports.env`, and one wrapper (`svc.sh`) that injects the right env
files. No UI/daemon layer required — just SSH and compose files.

This repo is a **template**: it contains only the structure and two example stacks.
Copy it, add your own services, and keep your real values out of git.

## Layout

```
.
├── svc.sh                 # entrypoint: svc.sh <action> <stack> [service]
├── bin/svc                # `svc` wrapper (added to PATH by install.sh)
├── completions/           # bash/zsh/fish completions + svcd helper
├── install.sh             # shell integration: PATH + completions + compose env
├── manage-service.sh      # scaffold/remove a service directory
├── global.env.example     # copy to global.env; shared paths + identity
├── ports.env              # every host port, grouped by range
└── stacks/                # one directory per stack (groups are optional)
    ├── web/               # optional group: sites you host (self or clients)
    │   └── example-site/  # example: reverse-proxied site
    └── homelab/           # optional group: plain services (media, apps, infra)
        ├── example-single/    # example: one-service stack
        └── example-stack/     # example: multi-service stack (depends_on)
```

Your instance will look the same, plus one directory per stack under `stacks/`,
each with a real `.env` next to its `compose.yml`.

**Groups are optional.** They exist only to separate purposes (e.g. `web` = hosted
sites, `homelab` = plain services). If you don't need that separation, put stacks
directly under `stacks/` (e.g. `stacks/immich/`) and call
`./svc.sh up immich` — everything works the same, you just omit the group.

## Rules of the pattern

1. **One compose project per directory under `stacks/`** — the directory name is
   the stack name you pass to `svc.sh`. A stack may live directly under
   `stacks/` (e.g. `stacks/immich/` → `svc.sh up immich`) or under an optional
   group directory (e.g. `stacks/web/site-a/` → `svc.sh up web/site-a`) that
   separates purposes like hosted sites from plain services.
2. **Services that depend on each other share a stack directory** (app + db,
   downloader + indexer + media server, ...) so `depends_on` works and they start
   together. Independent services get their own directory.
3. **`compose.yml` never hardcodes host ports or shared paths** — it references
   `${VARS}` resolved from the central files.
4. **`global.env`** — shared, machine-specific values (drive paths, PUID/PGID, TZ).
   Each group gets its own data root (`HOMELAB_SERVICE_DATA_PATH`,
   `WEB_SERVICE_DATA_PATH`). Not committed: copy from `global.env.example`.
5. **`ports.env`** — the single source of truth for host ports, grouped into fixed
   numeric ranges per category. New services take a free number in the matching
   range, so collisions are visible at a glance.
6. **Per-service `.env`** — only secrets/config unique to that service. Never ports
   or shared paths. Not committed: copy from the service's `.env.example`.
7. **Use `svc`/`svc.sh` as the entrypoint.** Compose does not search parent
   directories, so plain `docker compose up` only works inside a stack when the
   compose-env hook from `install.sh` is active (answer yes to the prompt or pass
   `--compose-env`) — it exports `COMPOSE_ENV_FILES` while your shell is in the repo.

## Env layering

`svc.sh` invokes compose with all three layers (paths are absolute, so this works
from any depth):

```
docker compose --env-file <repo>/global.env --env-file <repo>/ports.env --env-file .env ...
```

Later files override earlier ones, so precedence is:
shell > service `.env` > `ports.env` > `global.env`.

Compose expands `${VAR}` inside env files, which is why `global.env` can derive its
paths from drive roots:

```env
SSD_PATH=/mnt/ssd
HOMELAB_SERVICE_DATA_PATH=${SSD_PATH}/services/homelab
```

Requires a recent Docker Compose v2 (multiple `--env-file` and `COMPOSE_ENV_FILES`
need >= 2.24).

## Port ranges

Keep `ports.env` grouped so the number tells you what it is:

```
2800s  web sites (group: web, direct ports)
3000s  web UIs / dashboards
3100s  media
3200s  apps / automation
3400s  documents
3500s  productivity
3600s  files / storage
3700s  infrastructure
```

Only the host side uses a variable:

```yaml
ports:
  - "${MYAPP_PORT}:8080"
```

Ports that must keep their real default (DNS 53, VPN 51820, reverse proxy 80/443,
torrent peer port 6881, ...) are documented exceptions in `ports.env`.

## Usage

```bash
./svc.sh up homelab/example-stack            # whole stack
./svc.sh up homelab/example-stack app        # one service + its depends_on
./svc.sh config web/example-site             # print resolved config, no side effects
./svc.sh logs homelab/example-stack app
./svc.sh stop homelab/example-stack app      # stop one service (down is stack-wide)
./svc.sh down homelab/example-stack
./svc.sh pull homelab/example-stack app      # pull image(s) with the env layer loaded
./svc.sh path homelab/example-stack app      # host data path(s) for app (first is primary)
./svc.sh edit web/example-site               # open compose.yml at the site section

./manage-service.sh web mysite               # scaffold a new web site (group)
./manage-service.sh immich                   # scaffold a stack without a group
./manage-service.sh homelab myapp            # scaffold into the homelab group
```

`install.sh` puts the `svc` command on PATH and wires tab-completion
(action -> stack -> service) plus the `svcd` helper that cd's straight to a
config or data directory (needs `jq`). It asks once whether to also export
`COMPOSE_ENV_FILES` while your shell is inside the repo, so plain
`docker compose up` can keep working from any stack directory (that mode adds a
small shell hook: bash `PROMPT_COMMAND` / zsh `chpwd` / fish PWD event). bash,
zsh and fish are supported:

```bash
./install.sh                    # detect shell, asks about the compose-env hook
./install.sh fish               # or force bash / zsh / fish
./install.sh --compose-env      # enable the hook without asking (for scripts)
./install.sh --no-compose-env   # ensure it stays off
./install.sh --remove

svc up homelab/example-stack  # `svc` works from anywhere after install.sh
svcd                      # cd to the services repo root
svcd homelab/example-stack # cd to the stack's config dir
svcd homelab/example-stack app    # cd to app's primary data dir
```

Without installing, use `./svc.sh ...` from the repo. Manual completion setup:
`source completions/svc.bash` (bash), `source completions/svc.zsh` (zsh); fish
files live under `completions/fish/`.

## New server setup

```bash
git clone <this repo> ~/services/homelab && cd ~/services/homelab
cp global.env.example global.env                 # set drive paths, PUID/PGID, TZ
cp stacks/homelab/example-single/.env.example stacks/homelab/example-single/.env
docker network create homelab-network            # external network stacks join
./install.sh                                     # optional: `svc` on PATH + completions
./svc.sh up homelab/example-single
```

Hardware-specific lines in compose files (`/dev/dri`, `/opt/vc/lib`,
`/etc/sane.d/...`, extra external networks) are expected to be tailored per host.

## Secrets

`.gitignore` excludes `global.env` and every `.env`; only `compose.yml`, scripts,
and `*.env.example` belong in git. To offer this as a starting point for others,
mark the repo as a template on GitHub (Settings -> Template repository) so copies
don't share history.

## AI assistance

Everything in this repository was created with AI assistance (OpenCode) at the
direction of a human maintainer: the scripts (`svc.sh`, `manage-service.sh`,
`install-completion.sh`), the `completions/` files and this README. The compose
examples and layout are derived from a real homelab. Review before relying on it.
