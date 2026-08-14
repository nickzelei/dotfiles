
# Terraform and Terragrunt
alias tff="terraform fmt --recursive"
alias tg="terragrunt"
alias tgp="terragrunt plan"
alias tga="terragrunt apply"
alias tgf="terragrunt hclfmt"
alias tfclean="rm -rf .terraform .terraform.lock.hcl backend.tf providers.tf"


function kubectl() {
    if ! type __start_kubectl >/dev/null 2>&1; then
        source <(command kubectl completion zsh)
    fi

    command kubectl "$@"
}

# etc
alias av="aws-vault"
alias k="kubectl"

alias gmt="go mod tidy"

alias kctx='kubectx'

alias brewup='brew update && brew upgrade && brew autoremove && brew cleanup'

# claude
alias clauded="claude --dangerously-skip-permissions"
# a Coder workspace is disposable, so skipping permissions there is the default
[[ "${CODER:-}" == "true" ]] && alias claude="claude --allow-dangerously-skip-permissions"

docker_rmi() {
    docker rmi -f $(docker images -aq)
}

# git
alias nzm="git fetch && git checkout master && git reset --hard origin/master"
alias nzmm="git fetch && git checkout main && git reset --hard origin/main"
alias gmcsg="gcmsg" # I keep typoing this
alias gcsmg="gcmsg" # I keep typoing this too

source "$ZSHRC_CONFIG_DIR/aliases/directories.zsh"
