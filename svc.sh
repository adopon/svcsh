#!/bin/bash
SVC_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=svc-lib.sh
. "$SVC_SCRIPT_DIR/svc-lib.sh"
action="$1"

usage() {
  echo "usage: svc.sh <action> <stack> [service]"
  echo "       stack = name, or group/name when using groups (optional)"
  echo "actions: up stop down restart pull logs config ps path edit"
  echo "options: --config-root   print the resolved config root (stacks/, *.env)"
  echo "examples:"
  echo "  svc.sh up media sonarr              # flat stack, no group"
  echo "  svc.sh up homelab/media sonarr      # grouped stack"
  echo "  svc.sh up homelab/media           # whole stack"
  echo "  svc.sh pull homelab/media sonarr  # pull image(s) with the env layer loaded"
  echo "  svc.sh config web/site-a          # print resolved config, no side effects"
  echo "  svc.sh path homelab/media sonarr  # host data path(s), first is primary"
  echo "  svc.sh edit web/site-a            # open compose.yml at the site section"
}

# The stacks and env files live in the config root, which may be outside this
# repo. SVC_SCRIPT_DIR (this checkout) and the config root are resolved
# separately, so scripts and compose files can be kept in different places.
no_config_root() {
  echo "svc.sh: no config root found." >&2
  echo "  Set SVC_CONFIG_DIR to the directory holding stacks/, global.env and" >&2
  echo "  ports.env, or run $SVC_SCRIPT_DIR/install.sh to record it once." >&2
  exit 1
}

case "${action:-}" in
  "")            usage; exit 1 ;;
  -h|--help|help) usage; exit 0 ;;
  --config-root)
    root="$(svc_config_dir)" || root=""
    [ -n "$root" ] || no_config_root
    printf '%s\n' "$root"
    exit 0 ;;
esac

name="$2"
[ -z "$name" ] && { usage; exit 1; }
service="${3:-}"

case "$action" in
  up|stop|down|restart|pull|logs|config|ps|path|edit) ;;
  *) echo "unknown action: $action"; usage; exit 1 ;;
esac

if [ "$action" = "down" ] && [ -n "$service" ]; then
  echo "down is stack-wide; use: svc.sh stop $name $service"
  exit 1
fi

# Resolve once, in the main shell, so the first-run prompt can use the terminal.
SVC_ROOT=""
if ! SVC_ROOT="$(svc_config_dir)"; then
  SVC_ROOT=""
  if svc_prompt_config_dir; then
    SVC_ROOT="$SVC_PROMPTED_CONFIG_DIR"
  fi
fi
[ -n "$SVC_ROOT" ] || no_config_root

stacks_dir="$SVC_ROOT/stacks"

cd "$stacks_dir/$name" || { echo "no such stack: $name"; exit 1; }

ENV_FLAGS=()
[ -f "$SVC_ROOT/global.env" ] && ENV_FLAGS+=(--env-file "$SVC_ROOT/global.env")
[ -f "$SVC_ROOT/ports.env" ] && ENV_FLAGS+=(--env-file "$SVC_ROOT/ports.env")
[ -f .env ] && ENV_FLAGS+=(--env-file .env)

run() { docker compose "${ENV_FLAGS[@]}" "$@"; }

compose_file() {
  if [ -f compose.yml ]; then echo compose.yml
  elif [ -f compose.yaml ]; then echo compose.yaml
  elif [ -f docker-compose.yml ]; then echo docker-compose.yml
  else echo docker-compose.yaml
  fi
}

# svc.sh path <stack>            -> stack config dir
# svc.sh path <stack> <service>  -> host bind sources of that service (one per line)
data_paths() {
  local svc="$1" out
  if [ -z "$svc" ]; then
    printf '%s\n' "$PWD"
    return 0
  fi
  command -v jq >/dev/null || { echo "jq is required for: svc.sh path <stack> <service>" >&2; return 1; }
  out=$(run config --format json 2>/dev/null | jq -r --arg s "$svc" '
    (.services[$s].volumes // [])[]
    | select(.type == "bind")
    | .source')
  if [ -z "$out" ]; then
    echo "no host bind mounts for service '$svc'" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# svc.sh edit <stack> [service] -> open compose.yml in $EDITOR, at the service if given
open_editor() {
  local svc="$1" file line
  local -a editor
  file="$PWD/$(compose_file)"
  read -r -a editor <<< "${EDITOR:-vi}"
  if [ -n "$svc" ]; then
    line=$(grep -n "^  ${svc}:" "$file" | head -n1 | cut -d: -f1)
    [ -n "$line" ] || { echo "no such service in $file: $svc" >&2; exit 1; }
    exec "${editor[@]}" "+$line" "$file"
  fi
  exec "${editor[@]}" "$file"
}

case "$action" in
  up)      if [ -n "$service" ]; then run up -d "$service"; else run up -d; fi ;;
  stop)    if [ -n "$service" ]; then run stop "$service"; else run stop; fi ;;
  down)    run down ;;
  restart) if [ -n "$service" ]; then run restart "$service"; else run restart; fi ;;
  pull)    if [ -n "$service" ]; then run pull "$service"; else run pull; fi ;;
  logs)    if [ -n "$service" ]; then run logs -f "$service"; else run logs -f; fi ;;
  config)  if [ -n "$service" ]; then run config "$service"; else run config; fi ;;
  ps)      if [ -n "$service" ]; then run ps "$service"; else run ps; fi ;;
  path)    data_paths "$service" ;;
  edit)    open_editor "$service" ;;
esac
