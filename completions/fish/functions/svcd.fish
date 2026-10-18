# managed by homelab svc.sh shell integration
function svcd --description 'cd to the services config root / stack config / service data'
    set -l repo '@REPO_DIR@'
    if not test -d $repo
        if set -q svc_repo
            set repo $svc_repo
        else
            echo "svcd: run install.sh, or set -U svc_repo /path/to/svcsh" >&2
            return 1
        end
    end
    if test (count $argv) -eq 0
        set -l root (command $repo/svc.sh --config-root 2>/dev/null)
        test -n "$root"; or set root $repo
        cd $root; or return 1
        return 0
    end
    set -l target (command $repo/svc.sh path $argv | head -n1)
    test -n "$target"; and cd $target
end
