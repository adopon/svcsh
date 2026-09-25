#!/bin/bash

# --- CONFIGURATION ---
# Repo root = directory this script lives in (override with CONFIG_BASE / DATA_BASE)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG_BASE="${CONFIG_BASE:-$SCRIPT_DIR}"

# Shared paths (SSD_PATH, HOMELAB_SERVICE_DATA_PATH, ...)
if [[ -f "$CONFIG_BASE/global.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$CONFIG_BASE/global.env"
    set +a
fi
DATA_BASE="${DATA_BASE:-${HOMELAB_SERVICE_DATA_PATH:-$CONFIG_BASE}}"

# --- ARGUMENT PARSING ---
MODE=""
SERVICE_NAME=""

case "${1:-}" in
    create)          MODE="create"; shift ;;
    remove|rm|-r|--remove) MODE="remove"; shift ;;
    "") : ;; # no args -> interactive below
    *) MODE="create"; SERVICE_NAME="$1"; shift ;;
esac

if [[ -z "$MODE" ]]; then
    read -r -p "What do you want to do? [c]reate / [r]emove: " action
    case "$action" in
        r|R|remove|rm) MODE="remove" ;;
        *)             MODE="create" ;;
    esac
fi

if [[ -z "$SERVICE_NAME" ]]; then
    read -r -p "Service name: " SERVICE_NAME
fi

# Validate service name (only letters, numbers, dash, underscore)
if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid service name '$SERVICE_NAME'. Use only letters, numbers, '-' or '_'."
    exit 1
fi

CONFIG_DIR="$CONFIG_BASE/stacks/$SERVICE_NAME"
DATA_DIR="$DATA_BASE/$SERVICE_NAME"

remove_service() {
    if [[ ! -d "$CONFIG_DIR" && ! -d "$DATA_DIR" ]]; then
        echo "Error: No service '$SERVICE_NAME' found (checked $CONFIG_DIR and $DATA_DIR)."
        return 1
    fi

    # Stop the container(s) through svc.sh so global.env/ports.env/.env are loaded
    if command -v docker &>/dev/null && [[ -x "$CONFIG_BASE/svc.sh" ]]; then
        echo "Stopping containers for '$SERVICE_NAME'..."
        "$CONFIG_BASE/svc.sh" down "$SERVICE_NAME" 2>/dev/null || \
            echo "Warning: could not stop containers (running anyway?)."
    fi

    read -r -p "Delete '$SERVICE_NAME' permanently? Config: $CONFIG_DIR, Data: $DATA_DIR [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR" "$DATA_DIR"
        echo "Removed service '$SERVICE_NAME'."
    else
        echo "Aborted. Service '$SERVICE_NAME' was not removed."
    fi
}

if [[ "$MODE" == "remove" ]]; then
    remove_service
    exit 0
fi

# --- CREATE ---
if [ -d "$CONFIG_DIR" ]; then
    echo "Error: $CONFIG_DIR already exists."
    read -r -p "Remove it instead? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        remove_service
    fi
    exit 0
fi

if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
    echo "Error: Cannot create $CONFIG_DIR"
    exit 1
fi

if ! mkdir -p "$DATA_DIR" 2>/dev/null; then
    echo "Error: Cannot create $DATA_DIR (is the SSD mounted?)"
    rmdir "$CONFIG_DIR" 2>/dev/null
    exit 1
fi

# Keep the data dir visible in git if the services repo tracks configs
touch "$DATA_DIR/.gitkeep"

cat > "$CONFIG_DIR/compose.yml" <<EOF
# Compose file for: $SERVICE_NAME
#
#   Config dir: $CONFIG_DIR   (persistent, survives reboots)
#   Data dir:   $DATA_DIR     (bind-mount target for service data)
#
# Shared vars come from ../../global.env, host ports from ../../ports.env
# (add a \${$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]')_PORT} entry there).
#
# Start:   ./svc.sh up $SERVICE_NAME        (from the repo root)
# Logs:    ./svc.sh logs $SERVICE_NAME
# Stop:    ./svc.sh stop $SERVICE_NAME
services:
  $SERVICE_NAME:
    image: alpine:latest
    container_name: $SERVICE_NAME
    restart: unless-stopped
    # Uncomment to mount persistent storage into the container:
    # volumes:
    #   - \${HOMELAB_SERVICE_DATA_PATH}/$SERVICE_NAME:/data
    # Uncomment to expose a port (host side comes from ../../ports.env):
    # ports:
    #   - "\${$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]')_PORT}:80"
EOF

echo "-----------------------------------------------"
echo "Created service '$SERVICE_NAME':"
echo "  Config: $CONFIG_DIR/compose.yml"
echo "  Data:   $DATA_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit $CONFIG_DIR/compose.yml (image, ports, volumes)"
echo "  2. Add a <NAME>_PORT var to $CONFIG_BASE/ports.env if you expose a port"
echo "  3. ./svc.sh up $SERVICE_NAME    (from the repo root)"
echo "-----------------------------------------------"
