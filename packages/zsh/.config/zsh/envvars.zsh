# Dedupe $PATH (and other tied arrays): keep only the first occurrence of each
# entry. Without this, every new interactive shell re-prepends the paths below
# and $PATH grows with duplicates.
typeset -U path PATH

# Go
# export GOPRIVATE=github.com/nucleuscloud/*
export PATH="$PATH:$HOME/go/bin"

# AWS
export AWS_DEFAULT_REGION=us-west-2
export AWS_PAGER=""

# openssl
export PATH="$HOMEBREW_PREFIX/opt/openssl@3/bin:$PATH"

# rust
export PATH="$HOME/.cargo/bin:$PATH"

export LESS="-R" # adding -X will prevent the pager from clearing

# local bin for claude access
export PATH="$HOME/.local/bin:$PATH"

# Sets up GPG
export GPG_TTY=$(tty)
