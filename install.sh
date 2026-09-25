#!/bin/bash
# Shell integration for this repo: `svc` on PATH, tab-completion and the `svcd`
# helper. Optionally also makes plain `docker compose` work while inside the repo.
# Idempotent; undo with --remove.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
MARK_BEGIN="# >>> homelab svc.sh shell integration >>>"
MARK_END="# <<< homelab svc.sh shell integration <<<"
FISH_MARKER="# managed by homelab svc.sh shell integration"
BASH_HOOK_MARKER="_svc_compose_env"
FISH_HOOK_MARKER="__svc_compose_env"

usage() {
    cat <<EOF
usage: install.sh [shell] [--compose-env|--no-compose-env] [--remove]

Adds (or removes) a managed block that:
  - puts \`svc\` on PATH
  - loads completions for svc/svcd + the svcd helper

The optional compose-env hook exports COMPOSE_ENV_FILES while your shell is
inside the repo, so plain \`docker compose up\` works from any stack directory.
It installs a shell hook (bash PROMPT_COMMAND / zsh chpwd / fish PWD event).
When run interactively you are asked once; on re-runs your current choice is
kept. Use the flags to decide non-interactively.

Supported shells: bash, zsh, fish (default: detect from \$SHELL).

  ./install.sh                    # detect shell, ask about the hook
  ./install.sh bash               # block in ~/.bashrc
  ./install.sh zsh                # block in ~/.zshrc (or \$ZDOTDIR/.zshrc)
  ./install.sh fish               # files in ~/.config/fish/{completions,functions}
  ./install.sh --compose-env      # also enable plain-compose fallback
  ./install.sh --no-compose-env   # ensure it stays disabled
  ./install.sh --remove           # remove for the selected/detected shell
EOF
}

shell=""
remove=0
compose_env=""   # "" = ask (interactive) / keep current; 1 = yes; 0 = no
for arg in "$@"; do
    case "$arg" in
        --remove|-r)       remove=1 ;;
        --compose-env)     compose_env=1 ;;
        --no-compose-env)  compose_env=0 ;;
        bash|zsh|fish)     shell="$arg" ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; usage; exit 1 ;;
    esac
done

if [ -z "$shell" ]; then
    shell="$(basename "${SHELL:-bash}")"
fi

case "$shell" in
    bash) rc="$HOME/.bashrc";             source_file="$REPO_DIR/completions/svc.bash"; hook_marker="$BASH_HOOK_MARKER" ;;
    zsh)  rc="${ZDOTDIR:-$HOME}/.zshrc";  source_file="$REPO_DIR/completions/svc.zsh";  hook_marker="$BASH_HOOK_MARKER" ;;
    fish) rc="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"; hook_marker="$FISH_HOOK_MARKER" ;;
    *)    echo "unsupported shell: $shell (supported: bash, zsh, fish)" >&2; exit 1 ;;
esac

# Current state: is the hook present in the rc right now?
current=0
if [ -f "$rc" ] && grep -qF "$hook_marker" "$rc"; then
    current=1
fi

if [ "$remove" -eq 0 ] && [ -z "$compose_env" ]; then
    if [ -t 0 ]; then
        if [ "$current" -eq 1 ]; then
            read -r -p "Keep plain 'docker compose' working inside the repo (COMPOSE_ENV_FILES hook)? [Y/n] " answer || answer=""
            case "$answer" in [Nn]*) compose_env=0 ;; *) compose_env=1 ;; esac
        else
            read -r -p "Also make plain 'docker compose' work inside the repo (COMPOSE_ENV_FILES hook)? [y/N] " answer || answer=""
            case "$answer" in [Yy]*) compose_env=1 ;; *) compose_env=0 ;; esac
        fi
    else
        compose_env="$current"
    fi
fi

emit_bash_hook() {
    cat <<'EOF'
_svc_compose_env() {
    local _svc_env
    case "$PWD" in
        "@REPO_DIR@"|"@REPO_DIR@"/*)
            _svc_env=""
            [ -f "@REPO_DIR@/global.env" ] && _svc_env="@REPO_DIR@/global.env"
            [ -f "@REPO_DIR@/ports.env" ] && _svc_env="${_svc_env:+$_svc_env,}@REPO_DIR@/ports.env"
            [ -f "$PWD/.env" ] && _svc_env="${_svc_env:+$_svc_env,}$PWD/.env"
            if [ -n "$_svc_env" ]; then
                export COMPOSE_ENV_FILES="$_svc_env" _SVC_COMPOSE_ENV=1
            else
                unset COMPOSE_ENV_FILES _SVC_COMPOSE_ENV
            fi ;;
        *)
            if [ -n "${_SVC_COMPOSE_ENV:-}" ]; then
                unset COMPOSE_ENV_FILES _SVC_COMPOSE_ENV
            fi ;;
    esac
    return 0
}
EOF
}

emit_fish_hook() {
    cat <<'EOF'

function __svc_compose_env --on-variable PWD --description 'homelab: COMPOSE_ENV_FILES inside the services repo'
    if test "$PWD" = "@REPO_DIR@"; or string match -q "@REPO_DIR@/*" "$PWD"
        set -l files
        test -f "@REPO_DIR@/global.env"; and set files $files "@REPO_DIR@/global.env"
        test -f "@REPO_DIR@/ports.env"; and set files $files "@REPO_DIR@/ports.env"
        test -f "$PWD/.env"; and set files $files "$PWD/.env"
        if test (count $files) -gt 0
            set -gx COMPOSE_ENV_FILES (string join , $files)
            set -g _SVC_COMPOSE_ENV 1
        else
            set -e COMPOSE_ENV_FILES
            set -e _SVC_COMPOSE_ENV
        end
    else if set -q _SVC_COMPOSE_ENV
        set -e COMPOSE_ENV_FILES
        set -e _SVC_COMPOSE_ENV
    end
end
__svc_compose_env
EOF
}

install_fish() {
    local fish_config="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
    local files=(completions/svc.sh.fish completions/svc.fish completions/svcd.fish functions/svcd.fish)
    local cfg="$rc"

    if [ "$remove" -eq 1 ]; then
        local removed=0 f
        for f in "${files[@]}"; do
            if [ -f "$fish_config/$f" ] && grep -qF "$FISH_MARKER" "$fish_config/$f"; then
                rm -f "$fish_config/$f"
                removed=1
            fi
        done
        if [ -f "$cfg" ] && grep -qF "$MARK_BEGIN" "$cfg"; then
            sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$cfg"
            removed=1
        fi
        if [ "$removed" -eq 1 ]; then
            echo "Removed fish integration from $fish_config"
        else
            echo "No managed fish integration found in $fish_config"
        fi
        return 0
    fi

    mkdir -p "$fish_config/completions" "$fish_config/functions"
    local f
    for f in "${files[@]}"; do
        sed "s|@REPO_DIR@|$REPO_DIR|g" "$REPO_DIR/completions/fish/$f" > "$fish_config/$f"
    done

    # fish only autoloads completions for commands it can resolve, so source the
    # file explicitly to cover invocations like ./svc.sh.
    [ -f "$cfg" ] || : > "$cfg"
    if grep -qF "$MARK_BEGIN" "$cfg"; then
        sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$cfg"
    fi
    {
        echo "$MARK_BEGIN"
        echo "if not contains \"$REPO_DIR/bin\" \$PATH"
        echo "    set -gx PATH \"$REPO_DIR/bin\" \$PATH"
        echo "end"
        if [ "$compose_env" -eq 1 ]; then
            emit_fish_hook | sed "s|@REPO_DIR@|$REPO_DIR|g"
        fi
        echo "source \"$fish_config/completions/svc.sh.fish\""
        echo "$MARK_END"
    } >> "$cfg"

    if [ "$compose_env" -eq 1 ]; then
        echo "Installed fish integration in $fish_config (PATH + completions + compose env)"
    else
        echo "Installed fish integration in $fish_config (PATH + completions)"
    fi
    command -v fish >/dev/null || echo "note: fish is not in PATH; files were installed anyway"
    echo "Open a new fish session to pick it up."
}

if [ "$shell" = "fish" ]; then
    install_fish
    exit 0
fi

if [ ! -f "$rc" ]; then
    read -r -p "$rc does not exist. Create it? [y/N] " answer || answer=""
    case "$answer" in
        [Yy]*) : > "$rc" ;;
        *)     echo "aborted."; exit 1 ;;
    esac
fi

# Remove an existing managed block (if any)
found=0
if grep -qF "$MARK_BEGIN" "$rc"; then
    sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$rc"
    found=1
fi

if [ "$remove" -eq 1 ]; then
    if [ "$found" -eq 1 ]; then
        echo "Removed managed integration block from $rc"
    else
        echo "No managed integration block found in $rc"
    fi
    exit 0
fi

cp -n "$rc" "$rc.homelab.bak" 2>/dev/null || true

path_line="case \":\$PATH:\" in *\":$REPO_DIR/bin:\"*) ;; *) export PATH=\"$REPO_DIR/bin:\$PATH\" ;; esac"

hook_activation=""
if [ "$compose_env" -eq 1 ]; then
    case "$shell" in
        bash) hook_activation='PROMPT_COMMAND="_svc_compose_env${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
_svc_compose_env' ;;
        zsh)  hook_activation='autoload -U add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _svc_compose_env
_svc_compose_env' ;;
    esac
fi

{
    echo "$MARK_BEGIN"
    echo "$path_line"
    if [ "$compose_env" -eq 1 ]; then
        emit_bash_hook | sed "s|@REPO_DIR@|$REPO_DIR|g"
        echo "$hook_activation"
    fi
    echo "source \"$source_file\""
    echo "$MARK_END"
} >> "$rc"

if [ "$compose_env" -eq 1 ]; then
    echo "Installed shell integration for '$shell' in $rc (PATH + completions + compose env)"
else
    echo "Installed shell integration for '$shell' in $rc (PATH + completions)"
fi
echo "Reload with: source \"$rc\"  (or open a new shell)"
