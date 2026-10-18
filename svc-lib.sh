#!/bin/bash
# Shared config-root resolution for svc.sh, manage-service.sh, install.sh and the
# completions. Source it, do not execute it.
#
# The "config root" is the directory holding stacks/, global.env and ports.env.
# It does not have to be this repo: keep the scripts anywhere (e.g. ~/scripts) and
# the compose files elsewhere (e.g. /srv/services). Lookup order, first match wins:
#
#   1. $SVC_CONFIG_DIR         per-shell / per-invocation override
#   2. ~/.config/svcsh/config  recorded by install.sh or the first-run prompt
#   3. this repo, when it still has stacks/   legacy in-repo layout
#   4. unresolved              caller decides (svc.sh prompts, then errors)

if [ -z "${SVC_SCRIPT_DIR:-}" ]; then
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        SVC_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
    elif [ -n "${ZSH_VERSION:-}" ]; then
        eval 'SVC_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${(%):-%x}")")" && pwd)"'
    fi
fi

# Where a recorded config root is kept (survives re-cloning the scripts).
svc_config_file() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/svcsh/config"
}

# Print the resolved config root. Returns 1 when nothing is configured.
svc_config_dir() {
    local file value
    if [ -n "${SVC_CONFIG_DIR:-}" ]; then
        printf '%s\n' "$SVC_CONFIG_DIR"
        return 0
    fi
    file="$(svc_config_file)"
    if [ -f "$file" ]; then
        value="$(sed -n 's/^[[:space:]]*SVC_CONFIG_DIR[[:space:]]*=[[:space:]]*//p' "$file" | tail -n1)"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        case "$value" in
            "~/"*) value="$HOME/${value#\~/}" ;;
        esac
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    fi
    if [ -n "${SVC_SCRIPT_DIR:-}" ] && [ -d "$SVC_SCRIPT_DIR/stacks" ]; then
        printf '%s\n' "$SVC_SCRIPT_DIR"
        return 0
    fi
    return 1
}

# Record a config root for future shells.
svc_write_config_dir() {
    local dir="$1" file
    file="$(svc_config_file)"
    mkdir -p "$(dirname "$file")" || return 1
    {
        echo "# Written by svcsh. The config root holds stacks/, global.env and"
        echo "# ports.env, and may live outside the svcsh checkout."
        printf 'SVC_CONFIG_DIR=%s\n' "$dir"
    } > "$file"
}

# Ask for a config root on the terminal and record it. Sets SVC_PROMPTED_CONFIG_DIR.
#
# Call this directly (never in $(...)), and only when the shell owns the terminal:
# both stdin and stdout must be TTYs, so a piped invocation or a completion
# subshell gets the "no config root" error instead of a hanging prompt.
svc_prompt_config_dir() {
    local dir default="${SVC_SCRIPT_DIR:-$PWD}"
    [ -t 0 ] && [ -t 1 ] || return 1
    printf 'Where do your compose files live? (the directory holding stacks/, global.env and ports.env)\n' >&2
    read -r -p "  config root [$default]: " dir || return 1
    dir="${dir:-$default}"
    case "$dir" in
        "~/"*) dir="$HOME/${dir#\~/}" ;;
    esac
    svc_write_config_dir "$dir" || return 1
    printf 'Recorded config root in %s\n' "$(svc_config_file)" >&2
    SVC_PROMPTED_CONFIG_DIR="$dir"
}
