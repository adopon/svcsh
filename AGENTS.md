# AGENTS.md

Guidance for AI agents working in this repo.

## What this is

`svcsh` is a **template** for managing Docker Compose services on a home server
from a single entry point. It is not a daemon/UI: it is shell scripts around
`docker compose`, env files, and completions. Instances are clones of this repo;
they keep their own stacks and never commit (see "Instance model" below).

## Entry points

- `svc.sh` — the main command: `svc.sh <action> <stack> [service]`, where
  `<stack>` is a directory under `stacks/` (or `group/stack` when groups are
  used). Actions: `up stop down restart pull logs config ps path edit`.
  `svc.sh --config-root` prints the resolved config root (see below).
- `svc-lib.sh` — sourced by the scripts and completions; resolves the **config
  root** (the directory holding `stacks/`, `global.env`, `ports.env`) and
  provides the record/prompt helpers.
- `manage-service.sh` — scaffolds/removes a stack directory (+ data dir). With
  a terminal on stdin it runs an interactive wizard (image, port mapping
  host:container with the next free host port suggested, env vars, network,
  tunnel reminder) and writes a real compose.yml + .env + .env.example,
  updates ports.env; with non-TTY stdin it falls back to a plain alpine
  scaffold (scripting/CI).
- `install.sh` — shell integration: `svc` on PATH, tab completions, optional
  `COMPOSE_ENV_FILES` hook so plain `docker compose` works inside the repo.
- `completions/` — bash (`svc.bash`), zsh (loads `svc.bash` via bashcompinit),
  fish (`svc.sh.fish`); also the `svcd` helper (cd to stack config/data dir).

## Naming grammar (slash vs space)

`svc <action> <stack> [service]` — three words, two kinds of separator:

- **Slash = directory structure.** A stack is ONE token; the slash is part of
  its name, mirroring the directory: `stacks/immich/` → `svc up immich`,
  `stacks/web/site-a/` → `svc up web/site-a`.
- **Space = compose argument.** The optional third word is a compose service
  *inside* the stack, exactly like `docker compose up <service>`:
  `svc up homelab/media sonarr`.

`svc up group/stack/service` is NEVER valid — a service is not a stack.
Completions implement this: position 1 completes actions, position 2 completes
stack tokens (slash inside), position 3 completes services of the chosen stack.
Groups never nest deeper than one level.

## Layout

```
svc.sh, svc-lib.sh, manage-service.sh, install.sh   scripts (bash)
completions/                            bash/zsh/fish completions + svcd
examples/                               reference examples — NEVER managed by svc.sh
global.env.example                      → copy to <config root>/global.env (gitignored)
ports.env.example                       → copy to <config root>/ports.env (gitignored)
<config root>/stacks/                   user stacks; groups optional (web/, homelab/)
```

## Config root (code vs config)

Scripts and config may live in different places: the checkout is code, the
config root is data. `svc-lib.sh` resolves the config root as, first match wins:

1. `$SVC_CONFIG_DIR` (per-shell override),
2. `~/.config/svcsh/config` (`SVC_CONFIG_DIR=...`), written by `install.sh
   --config-dir` or the first-run prompt,
3. the checkout itself, when it still has `stacks/` (legacy in-repo layout),
4. unresolved → `svc.sh` prompts when both stdin and stdout are TTYs; otherwise
   it errors with a pointer to `SVC_CONFIG_DIR`.

Rules: nothing may hardcode `<checkout>/stacks` or `<checkout>/global.env`.
`SVC_SCRIPT_DIR` (the checkout) and `SVC_ROOT` (the config root) are separate
values — `svc.sh` locates its lib, `manage-service.sh` and the completions via
the checkout, and the stacks/env files via the config root. In
`manage-service.sh` the config root is `CONFIG_BASE` (`$CONFIG_BASE` >
`$SVC_CONFIG_DIR` > resolved > `$SCRIPT_DIR`), while `svc.sh` is invoked as
`$SCRIPT_DIR/svc.sh`, never `$CONFIG_BASE/svc.sh`.

## Rules of the pattern (invariants)

1. **One compose project per directory under `stacks/`** — dir name = stack
   name. A stack may sit directly under `stacks/` (`stacks/immich/` →
   `svc up immich`) or under an optional group dir (`stacks/web/site-a/` →
   `svc up web/site-a`). Groups are purely organizational.
2. **`examples/` is reference-only.** svc.sh/completions must never see it.
   To try an example: `cp -r examples/example-single stacks/`. Never move
   examples back into `stacks/` — the whole point is that template files and
   user stacks cannot collide on an instance (which would break `git pull`).
3. **`compose.yml` never hardcodes host ports or shared paths** — they come
   from `${VARS}` resolved via env files.
4. **Env layering** (later overrides earlier): shell > stack `.env` >
   `ports.env` > `global.env`. `svc.sh` builds `--env-file` flags with
   **absolute** paths to `$SVC_ROOT/global.env` and `$SVC_ROOT/ports.env` (the
   config root, not the checkout), plus the stack's `.env` if present. All three
   are optional: missing files are skipped.
5. **Instance-specific files never enter git**: `global.env`, `ports.env`,
   every `**/.env`. Tracked files are `compose.yml`, `*.env.example`, scripts,
   README, completions.
6. **`manage-service.sh` semantics**: `manage-service.sh <name>` = flat stack
   (default group `homelab`-less); `manage-service.sh web <name>` /
   `manage-service.sh homelab <name>` = grouped. A lone *known group* name
   (`web`/`homelab`) as the single arg means "group, ask for name". Data root
   per group: `WEB_SERVICE_DATA_PATH` for `web`, `HOMELAB_SERVICE_DATA_PATH`
   otherwise (defined in `global.env`). Wizard defaults come from `global.env`
   too: `SVC_NETWORK` (default network new stacks join; composed as
   `${SVC_NETWORK}` via `networks.default.name` when set, literal otherwise),
   `SVC_DEFAULT_GROUP`, `SVC_TUNNEL_DOMAIN` (for Cloudflare ingress reminders).
   `add` is an alias for `create`; wizard mode is gated on `[ -t 0 ]`.
7. **Completions enumerate stacks two levels deep** (flat stack OR group/stack)
   and derive services via `docker compose config --services` from the stack
   dir with the same env flags as svc.sh. They must not hardcode the config
   root: ask `svc.sh --config-root` (see "Config root" above). If stack
   resolution changes, update both bash and fish copies — they must stay in
   sync.
8. **Code and config are resolved separately** (see "Config root"). Nothing may
   assume `stacks/` or the env files are next to the script; the checkout only
   supplies the scripts, the completions and the `*.env.example` templates.

## Conventions

- Shell scripts are bash, `#!/bin/bash`, POSIX-ish; completions are bash + fish.
- All paths in scripts are resolved from the script's own dir
  (`readlink -f "$0"` → the checkout), never `$PWD`. Paths to `stacks/`,
  `global.env` and `ports.env` come from the resolved config root instead
  (`svc-lib.sh`), so code and config may live apart.
- A stack's compose file may be named `compose.yml`, `compose.yaml`,
  `docker-compose.yml` or `docker-compose.yaml` — svc.sh and both completion
  copies accept all four (checked in that order, `compose.yml` first).
- No comments unless they document intent/behavior, not the obvious.
- README.md documents the user-facing pattern; keep it in sync with code
  changes (layout, usage, rules).

## Verification

```bash
bash -n svc.sh svc-lib.sh manage-service.sh install.sh completions/svc.bash
fish -n completions/fish/completions/svc.sh.fish
# completions must list flat + grouped stacks:
bash -c 'source completions/svc.bash; _svc_stacks'
# svc.sh must resolve a stack without instance env files present:
tmp=$(mktemp -d) && cp svc.sh svc-lib.sh "$tmp/" && mkdir -p "$tmp/stacks/x"
printf 'services:\n  x:\n    image: alpine\n' > "$tmp/stacks/x/compose.yml"
(cd "$tmp" && ./svc.sh config x >/dev/null)
# all four compose filenames must resolve (here: compose.yaml):
mkdir -p "$tmp/stacks/y" && printf 'services:\n  y:\n    image: alpine\n' > "$tmp/stacks/y/compose.yaml"
(cd "$tmp" && ./svc.sh config y >/dev/null)
# code and config in separate places:
mkdir -p "$tmp/scripts" "$tmp/config/stacks/z" && cp svc.sh svc-lib.sh "$tmp/scripts/"
printf 'services:\n  z:\n    image: alpine\n' > "$tmp/config/stacks/z/compose.yml"
SVC_CONFIG_DIR="$tmp/config" "$tmp/scripts/svc.sh" config z >/dev/null
# a recorded root is read back from $XDG_CONFIG_HOME/svcsh/config:
(cd "$tmp/scripts" && XDG_CONFIG_HOME="$tmp/xdg" bash -c '. ./svc-lib.sh; svc_write_config_dir "$1"; svc_config_dir' _ "$tmp/config") >/dev/null
# manage-service.sh scaffold smoke test (overrides CONFIG_BASE / *_SERVICE_DATA_PATH):
CONFIG_BASE="$tmp" WEB_SERVICE_DATA_PATH="$tmp/web" HOMELAB_SERVICE_DATA_PATH="$tmp/homelab" bash manage-service.sh create web test >/dev/null
```

## Instance model (how this template is used)

- Instances clone this repo and are expected to stay a **clean mirror**: no
  local commits, `git pull` always fast-forwards. `stacks/`, `global.env`,
  `ports.env`, `**/.env` are untracked/gitignored on instances — and with the
  config root pointed elsewhere (see "Config root") the clone holds no instance
  data at all.
- Instance backups are handled separately (e.g. restic via the user's
  `backrest` tool), not via git.
- Changes to the template are committed here and pushed; instances pull.