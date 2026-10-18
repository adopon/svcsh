# Bash completion + `svcd` helper for svc.sh.
# Source this file, or wire it up once with install.sh.
# zsh users: source svc.zsh instead (it loads this file via bashcompinit).

if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_svc_script="${(%):-%x}"'
else
    _svc_script="${BASH_SOURCE[0]}"
fi
_svc_script_dir="$(cd "$(dirname "$(readlink -f "$_svc_script")")/.." && pwd)"

# Stacks and env files live in the config root, which may be outside this
# checkout. svc.sh owns the lookup (env > recorded > in-repo), so ask it rather
# than duplicating the rules here.
_svc_config_dir() {
    local dir
    dir="$("$_svc_script_dir/svc.sh" --config-root 2>/dev/null)"
    if [ -n "$dir" ]; then
        printf '%s\n' "$dir"
    else
        printf '%s\n' "$_svc_script_dir"
    fi
}

_has_compose() {
    [ -f "$1/compose.yml" ] || [ -f "$1/compose.yaml" ] || \
    [ -f "$1/docker-compose.yml" ] || [ -f "$1/docker-compose.yaml" ]
}

# List stacks as group/stack (or plain name for flat stacks directly under
# stacks/ — groups are optional).
_svc_stacks() {
    local stacks_dir
    stacks_dir="$(_svc_config_dir)/stacks"
    [ -d "$stacks_dir" ] || return 0
    local g d name
    for g in "$stacks_dir"/*/; do
        [ -d "$g" ] || continue
        name="${g%/}"
        if _has_compose "$name"; then
            echo "${name#"$stacks_dir/"}"
            continue
        fi
        for d in "$g"*/; do
            _has_compose "$d" || continue
            d="${d%/}"
            echo "${d#"$stacks_dir/"}"
        done
    done
}

_svc_services() {
    local stack="$1" root dir
    root="$(_svc_config_dir)"
    dir="$root/stacks/$stack"
    if [ -d "$dir" ] && _has_compose "$dir"; then
        (
            cd "$dir" || exit 1
            flags=()
            [ -f "$root/global.env" ] && flags+=(--env-file "$root/global.env")
            [ -f "$root/ports.env" ] && flags+=(--env-file "$root/ports.env")
            [ -f .env ] && flags+=(--env-file .env)
            docker compose "${flags[@]}" config --services 2>/dev/null
        )
    fi
}

_svc_completion() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"
    case "$COMP_CWORD" in
      1) COMPREPLY=( $(compgen -W "up stop down restart pull logs config ps path edit" -- "$cur") ) ;;
      2) COMPREPLY=( $(compgen -W "$(_svc_stacks)" -- "$cur") ) ;;
      3) COMPREPLY=( $(compgen -W "$(_svc_services "${COMP_WORDS[2]}")" -- "$cur") ) ;;
    esac
}

_svcd_completion() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"
    case "$COMP_CWORD" in
      1) COMPREPLY=( $(compgen -W "$(_svc_stacks)" -- "$cur") ) ;;
      2) COMPREPLY=( $(compgen -W "$(_svc_services "${COMP_WORDS[1]}")" -- "$cur") ) ;;
    esac
}

# cd to the config root, a stack's config dir, or a service's primary host data
# dir:
#   svcd                  -> config root (where stacks/ + env files live)
#   svcd homelab/media    -> <config root>/stacks/homelab/media
#   svcd homelab/media sonarr -> first bind mount of sonarr
svcd() {
    if [ "$#" -eq 0 ]; then
        cd "$(_svc_config_dir)" || return 1
        return 0
    fi
    local target
    target="$("$_svc_script_dir/svc.sh" path "$@" | head -n1)" || return 1
    [ -n "$target" ] && cd "$target"
}

complete -F _svc_completion svc.sh
complete -F _svc_completion ./svc.sh
complete -F _svc_completion svc
complete -F _svcd_completion svcd
