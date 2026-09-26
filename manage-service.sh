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

# --- ARGUMENT PARSING ---
MODE=""
GROUP=""
SERVICE_NAME=""
KNOWN_GROUPS="web homelab"

case "${1:-}" in
    create|add)      MODE="create"; shift ;;
    remove|rm|-r|--remove) MODE="remove"; shift ;;
    "") : ;; # no args -> interactive below
    *) MODE="create" ;; # first arg handled below (group or name)
esac

if [[ -n "${1:-}" ]]; then
    # Two args = <group> <name>. One arg = <name> unless it is a known group
    # (then the name is asked interactively). Groups are optional: with no
    # group the stack is created directly under stacks/.
    if [[ -n "${2:-}" ]]; then
        GROUP="$1"; shift
    elif [[ " $KNOWN_GROUPS " == *" $1 "* ]] && [[ ! -f "$CONFIG_BASE/stacks/$1/compose.yml" ]]; then
        GROUP="$1"; shift
    fi
fi
if [[ -n "${1:-}" ]]; then
    SERVICE_NAME="$1"; shift
fi

if [[ -z "$MODE" ]]; then
    read -r -p "What do you want to do? [c]reate / [r]emove: " action
    case "$action" in
        r|R|remove|rm) MODE="remove" ;;
        *)             MODE="create" ;;
    esac
fi

if [[ -z "$GROUP" ]]; then
    read -r -p "Group (empty for no group)${SVC_DEFAULT_GROUP:+ [$SVC_DEFAULT_GROUP]}: " GROUP
    GROUP="${GROUP:-$SVC_DEFAULT_GROUP}"
fi

if [[ -z "$SERVICE_NAME" ]]; then
    read -r -p "Service name: " SERVICE_NAME
fi

# Validate names (only letters, numbers, dash, underscore)
if [[ -n "$GROUP" && ! "$GROUP" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid group '$GROUP'. Use only letters, numbers, '-' or '_'."
    exit 1
fi
if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid service name '$SERVICE_NAME'. Use only letters, numbers, '-' or '_'."
    exit 1
fi

# Per-group data root: web sites live under WEB_SERVICE_DATA_PATH, everything
# else (including flat stacks) under HOMELAB_SERVICE_DATA_PATH (see global.env).
case "$GROUP" in
    web) DATA_BASE="${DATA_BASE:-${WEB_SERVICE_DATA_PATH:-${HOMELAB_SERVICE_DATA_PATH:-$CONFIG_BASE}}}" ;;
    *)   DATA_BASE="${DATA_BASE:-${HOMELAB_SERVICE_DATA_PATH:-$CONFIG_BASE}}" ;;
esac
DATA_PATH_VAR="HOMELAB_SERVICE_DATA_PATH"
[[ "$GROUP" == "web" ]] && DATA_PATH_VAR="WEB_SERVICE_DATA_PATH"

CONFIG_DIR="$CONFIG_BASE/stacks${GROUP:+/$GROUP}/$SERVICE_NAME"
DATA_DIR="$DATA_BASE/$SERVICE_NAME"
STACK_LABEL="${GROUP:+$GROUP/}$SERVICE_NAME"

remove_service() {
    if [[ ! -d "$CONFIG_DIR" && ! -d "$DATA_DIR" ]]; then
        echo "Error: No service '$SERVICE_NAME' found (checked $CONFIG_DIR and $DATA_DIR)."
        return 1
    fi

    # Stop the container(s) through svc.sh so global.env/ports.env/.env are loaded
    if command -v docker &>/dev/null && [[ -x "$CONFIG_BASE/svc.sh" ]]; then
        echo "Stopping containers for '$STACK_LABEL'..."
        "$CONFIG_BASE/svc.sh" down "$STACK_LABEL" 2>/dev/null || \
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

# Wizard defaults from global.env (instance config)
NETWORK="${SVC_NETWORK:-homelab-network}"
TUNNEL_DOMAIN="${SVC_TUNNEL_DOMAIN:-}"
# Env var names must not contain dashes: my-app -> MY_APP_PORT
PORT_VAR="$(echo "$SERVICE_NAME" | tr '[:lower:]-' '[:upper:]_')_PORT"

# Next free host port in the given range, scanning ports.env.
next_free_port() {
    local lo="$1" hi="$2" max
    max="$(awk -F= -v lo="$lo" -v hi="$hi" \
        '/^[A-Z_][A-Z0-9_]*=[0-9]+$/ { p=$2+0; if (p>=lo && p<=hi && p>max) max=p }
         END { print max+0 }' "$CONFIG_BASE/ports.env" 2>/dev/null)"
    [[ "$max" -lt "$lo" ]] && max="$lo"
    echo "$max"
}

# Append VAR=value under the first range header matching the marker.
insert_port() {
    local line="$1" marker="$2" file="$CONFIG_BASE/ports.env"
    awk -v line="$line" -v m="$marker" '
        $0 ~ m && !done { print; print line; done=1; next }
        { print }
        END { if (!done) print line }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Run the interactive scaffold wizard (stdin is a terminal).
wizard_create() {
    local IMAGE CONTAINER_PORTS HOST_PORT KV
    local EXPOSE_PORT=false NETWORK_REF="$NETWORK"
    local -a ENV_PAIRS=() ENV_LINES=()

    read -r -p "Image: " IMAGE
    [[ -z "$IMAGE" ]] && { echo "Error: image is required."; exit 1; }

    read -r -p "Container port(s), comma-separated (empty = internal only): " CONTAINER_PORTS

    if [[ -n "$CONTAINER_PORTS" ]]; then
        local range_start=3000
        [[ "$GROUP" == "web" ]] && range_start=2800
        local suggested
        suggested="$(next_free_port "$range_start" $((range_start+99)))"
        read -r -p "Host port [$suggested]: " HOST_PORT
        HOST_PORT="${HOST_PORT:-$suggested}"
        EXPOSE_PORT=true
    fi

    while true; do
        read -r -p "Extra env var (K=V, empty to finish): " KV
        [[ -z "$KV" ]] && break
        ENV_PAIRS+=("$KV")
        ENV_LINES+=("      ${KV%%=*}: \${${KV%%=*}}")
    done

    read -r -p "Join network $NETWORK? [Y/n]: " JOIN_NET
    # Compose interpolates ${SVC_NETWORK} only when global.env defines it;
    # otherwise the resolved name is written literally.
    if [[ -n "${SVC_NETWORK:-}" ]]; then
        NETWORK_REF='${SVC_NETWORK}'
    else
        [[ "$JOIN_NET" =~ ^[Nn]$ ]] && NETWORK_REF=""
    fi

    cat > "$CONFIG_DIR/compose.yml" <<EOF
# Compose file for: $STACK_LABEL
#
#   Config dir: $CONFIG_DIR
#   Data dir:   $DATA_DIR
services:
  $SERVICE_NAME:
    image: $IMAGE
    container_name: $SERVICE_NAME
    restart: unless-stopped
    environment:
      TZ: \${TZ}
$(printf '%s\n' "${ENV_LINES[@]}")
EOF
    if [[ "$EXPOSE_PORT" == true ]]; then
        cat >> "$CONFIG_DIR/compose.yml" <<EOF
    ports:
      - "\${$PORT_VAR}:${CONTAINER_PORTS%%,*}"
EOF
    fi
    cat >> "$CONFIG_DIR/compose.yml" <<EOF
    volumes:
      - \${$DATA_PATH_VAR}/$SERVICE_NAME:/data
EOF
    if [[ -n "$NETWORK_REF" ]]; then
        cat >> "$CONFIG_DIR/compose.yml" <<EOF
    networks:
      - default

networks:
  default:
    name: $NETWORK_REF
    external: true
EOF
    fi

    if [[ ${#ENV_PAIRS[@]} -gt 0 ]]; then
        local pair
        for pair in "${ENV_PAIRS[@]}"; do
            printf '%s\n' "$pair" >> "$CONFIG_DIR/.env"
            printf '%s=\n' "${pair%%=*}" >> "$CONFIG_DIR/.env.example"
        done
    fi

    echo "-----------------------------------------------"
    echo "Created service '$STACK_LABEL':"
    echo "  Config: $CONFIG_DIR/compose.yml"
    echo "  Data:   $DATA_DIR"
    echo ""

    if [[ "$EXPOSE_PORT" == true ]]; then
        if [[ ! -f "$CONFIG_BASE/ports.env" && -f "$CONFIG_BASE/ports.env.example" ]]; then
            cp "$CONFIG_BASE/ports.env.example" "$CONFIG_BASE/ports.env"
        fi
        if [[ -f "$CONFIG_BASE/ports.env" ]]; then
            local marker="# 3000s"
            [[ "$GROUP" == "web" ]] && marker="# 2800s"
            insert_port "$PORT_VAR=$HOST_PORT" "$marker"
            echo "  Ports:  $PORT_VAR=$HOST_PORT -> $CONFIG_BASE/ports.env"
        else
            echo "  Ports:  add '$PORT_VAR=$HOST_PORT' to $CONFIG_BASE/ports.env"
        fi
    fi

    read -r -p "Add Cloudflare tunnel ingress? [y/N]: " TUNNEL
    if [[ "$TUNNEL" =~ ^[Yy]$ ]]; then
        local hostname first_port
        first_port="${CONTAINER_PORTS%%,*}"
        if [[ -n "$TUNNEL_DOMAIN" ]]; then
            hostname="$SERVICE_NAME.$TUNNEL_DOMAIN"
            echo "  Tunnel: add ingress in the Cloudflare dashboard:"
            echo "          $hostname -> http://$SERVICE_NAME:$first_port"
        else
            echo "  Tunnel: add the ingress in the Cloudflare dashboard"
            echo "          (<hostname> -> http://$SERVICE_NAME:$first_port)"
        fi
    fi

    echo ""
    if [[ -x "$CONFIG_BASE/svc.sh" ]] && "$CONFIG_BASE/svc.sh" config "$STACK_LABEL" >/dev/null 2>&1; then
        echo "  Config check: OK — ./svc.sh up $STACK_LABEL"
    else
        echo "  Config check: review $CONFIG_DIR/compose.yml, then ./svc.sh up $STACK_LABEL"
    fi
    echo "-----------------------------------------------"
}

if [[ -t 0 ]]; then
    wizard_create
    exit 0
fi

# Non-interactive: plain alpine scaffold.
cat > "$CONFIG_DIR/compose.yml" <<EOF
# Compose file for: $STACK_LABEL
#
#   Config dir: $CONFIG_DIR   (persistent, survives reboots)
#   Data dir:   $DATA_DIR     (bind-mount target for service data)
#
# Shared vars come from the repo's global.env, host ports from ports.env
# (add a \${$PORT_VAR} entry there).
#
# Start:   ./svc.sh up $STACK_LABEL   (from the repo root)
# Logs:    ./svc.sh logs $STACK_LABEL
# Stop:    ./svc.sh stop $STACK_LABEL
services:
  $SERVICE_NAME:
    image: alpine:latest
    container_name: $SERVICE_NAME
    restart: unless-stopped
    # Uncomment to mount persistent storage into the container:
    # volumes:
    #   - \${$DATA_PATH_VAR}/$SERVICE_NAME:/data
    # Uncomment to expose a port (host side comes from ports.env):
    # ports:
    #   - "\${$PORT_VAR}:80"
EOF

echo "-----------------------------------------------"
echo "Created service '$STACK_LABEL':"
echo "  Config: $CONFIG_DIR/compose.yml"
echo "  Data:   $DATA_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit $CONFIG_DIR/compose.yml (image, ports, volumes)"
echo "  2. Add a <NAME>_PORT var to $CONFIG_BASE/ports.env if you expose a port"
echo "  3. ./svc.sh up $STACK_LABEL    (from the repo root)"
echo "-----------------------------------------------"
