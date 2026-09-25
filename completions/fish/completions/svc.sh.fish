# managed by homelab svc.sh shell integration
# Fish completions for svc.sh and svcd.
# Install: copy to ~/.config/fish/completions/svc.sh.fish (install-completion.sh
# does this and substitutes @REPO_DIR@).
set -g __svc_dir '@REPO_DIR@'
if not test -d $__svc_dir; and set -q svc_repo
    set -g __svc_dir $svc_repo
end

function __svc_stacks
    for d in $__svc_dir/*/
        if test -f $d/compose.yml -o -f $d/docker-compose.yml
            basename $d
        end
    end
end

function __svc_services --argument-names stack
    set -l dir $__svc_dir/$stack
    test -f $dir/compose.yml -o -f $dir/docker-compose.yml; or return
    pushd $dir; or return
    set -l flags --env-file ../global.env --env-file ../ports.env
    test -f .env; and set flags $flags --env-file .env
    docker compose $flags config --services 2>/dev/null
    popd
end

function __svc_complete_services
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 3; or return
    __svc_services $tokens[3]
end

function __svcd_complete_services
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; or return
    __svc_services $tokens[2]
end

set -l actions up stop down restart pull logs config ps path edit

for cmd in svc svc.sh ./svc.sh
    complete -c $cmd -f -n "not __fish_seen_subcommand_from $actions" -a "$actions"
    complete -c $cmd -f -n "__fish_seen_subcommand_from $actions; and test (count (commandline -opc)) -lt 3" -a '(__svc_stacks)'
    complete -c $cmd -f -n "__fish_seen_subcommand_from up stop restart pull logs config ps path edit; and test (count (commandline -opc)) -ge 3" -a '(__svc_complete_services)'
end

complete -c svcd -f -n 'test (count (commandline -opc)) -lt 2' -a '(__svc_stacks)'
complete -c svcd -f -n 'test (count (commandline -opc)) -ge 2' -a '(__svcd_complete_services)'
