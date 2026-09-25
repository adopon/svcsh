# Bash completion + `svcd` helper for svc.sh.
# Source this file, or wire it up once with install.sh.
# zsh users: source svc.zsh instead (it loads this file via bashcompinit).

if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_svc_script="${(%):-%x}"'
else
    _svc_script="${BASH_SOURCE[0]}"
fi
_svc_dir="$(cd "$(dirname "$(readlink -f "$_svc_script")")/.." && pwd)"

# List stacks as group/stack (or plain name for flat stacks directly under
# stacks/ — groups are optional).
_svc_stacks() {
    [ -d "$_svc_dir/stacks" ] || return 0
    local g d name
    for g in "$_svc_dir/stacks"/*/; do
        [ -d "$g" ] || continue
        name="${g%/}"
        if [ -f "$name/compose.yml" ] || [ -f "$name/docker-compose.yml" ]; then
            echo "${name#"$_svc_dir/stacks/"}"
            continue
        fi
        for d in "$g"*/; do
            [ -f "$d/compose.yml" ] || [ -f "$d/docker-compose.yml" ] || continue
            d="${d%/}"
            echo "${d#"$_svc_dir/stacks/"}"
        done
    done
}

_svc_services() {
    local stack="$1" dir
    dir="$_svc_dir/stacks/$stack"
    if [ -d "$dir" ] && { [ -f "$dir/compose.yml" ] || [ -f "$dir/docker-compose.yml" ]; }; then
        (
            cd "$dir" || exit 1
            flags=(--env-file "$_svc_dir/global.env" --env-file "$_svc_dir/ports.env")
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

# cd to the repo root, a stack's config dir, or a service's primary host data dir:
#   svcd                  -> <repo>
#   svcd homelab/media    -> <repo>/stacks/homelab/media
#   svcd homelab/media sonarr -> first bind mount of sonarr
svcd() {
    if [ "$#" -eq 0 ]; then
        cd "$_svc_dir" || return 1
        return 0
    fi
    local target
    target="$("$_svc_dir/svc.sh" path "$@" | head -n1)" || return 1
    [ -n "$target" ] && cd "$target"
}

complete -F _svc_completion svc.sh
complete -F _svc_completion ./svc.sh
complete -F _svc_completion svc
complete -F _svcd_completion svcd
