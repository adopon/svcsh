#!/bin/bash
base="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
stacks_dir="$base/stacks"
action="$1"

usage() {
  echo "usage: svc.sh <action> <stack> [service]"
  echo "actions: up stop down restart pull logs config ps path edit"
  echo "examples:"
  echo "  svc.sh up media sonarr      # sonarr + its depends_on"
  echo "  svc.sh up media             # whole stack"
  echo "  svc.sh pull media sonarr    # pull image(s) with the env layer loaded"
  echo "  svc.sh config media sonarr  # print resolved config, no side effects"
  echo "  svc.sh path media sonarr    # host data path(s), first is primary"
  echo "  svc.sh edit media sonarr    # open compose.yml at the sonarr section"
}

[ -z "$action" ] && { usage; exit 1; }
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

cd "$stacks_dir/$name" || { echo "no such stack: $name"; exit 1; }

ENV_FLAGS=(--env-file ../../global.env --env-file ../../ports.env)
[ -f .env ] && ENV_FLAGS+=(--env-file .env)

run() { docker compose "${ENV_FLAGS[@]}" "$@"; }

compose_file() {
  if [ -f compose.yml ]; then echo compose.yml; else echo docker-compose.yml; fi
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
