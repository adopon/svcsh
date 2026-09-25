# zsh entry point: load compinit + bashcompinit, then the shared bash completion.
# Source this file, or wire it up once with install-completion.sh.

if ! type compdef >/dev/null 2>&1; then
    autoload -U +X compinit && compinit
fi
autoload -U +X bashcompinit && bashcompinit

_svc_zsh_script="${(%):-%x}"
source "$(cd "$(dirname "$_svc_zsh_script")" && pwd)/svc.bash"
