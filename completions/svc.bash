# Bash completion + `svcd` helper for svc.sh.
# Source this file, or wire it up once with install-completion.sh.
# zsh users: source svc.zsh instead (it loads this file via bashcompinit).

if [ -n "${ZSH_VERSION:-}" ]; then
    eval '_svc_script="${(%):-%x}"'
else
    _svc_script="${BASH_SOURCE[0]}"
fi
_svc_dir="$(cd "$(dirname "$(readlink -f "$_svc_script")")/.." && pwd)"

_svc_stacks() {
    find "$_svc_dir" -maxdepth 1 -mindepth 1 -type d ! -name '.*' | while read -r d; do
        [ -f "$d/compose.yml" ] || [ -f "$d/docker-compose.yml" ] || continue
        basename "$d"
    done
}

_svc_services() {
    local stack="$1" dir
    dir="$_svc_dir/$stack"
    if [ -d "$dir" ] && { [ -f "$dir/compose.yml" ] || [ -f "$dir/docker-compose.yml" ]; }; then
        (
            cd "$dir" || exit 1
            flags=(--env-file ../global.env --env-file ../ports.env)
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
#   svcd                 -> <repo>
#   svcd media           -> <repo>/media
#   svcd media sonarr    -> first bind mount of sonarr
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
