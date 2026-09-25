# managed by homelab svc.sh shell integration
function svcd --description 'cd to homelab services root / stack config / service data'
    set -l repo '@REPO_DIR@'
    if not test -d $repo
        if set -q svc_repo
            set repo $svc_repo
        else
            echo "svcd: run install-completion.sh, or set -U svc_repo /path/to/services" >&2
            return 1
        end
    end
    if test (count $argv) -eq 0
        cd $repo; or return 1
        return 0
    end
    set -l target (command $repo/svc.sh path $argv | head -n1)
    test -n "$target"; and cd $target
end
