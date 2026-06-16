# Sourced from ~/.zshenv, so this runs for EVERY zsh invocation — interactive
# shells, non-interactive scripts, `ssh host 'cmd'`, cron. Keep it cheap (no
# subprocess spawns) and limit it to environment that non-interactive sessions
# also need. Interactive-only setup lives in setup.zsh; PATH entries whose order
# relative to Homebrew matters live in profile.zsh.

# Dedupe $PATH (and other tied arrays): keep only the first occurrence of each
# entry. Setting the -U attribute here makes it apply to every later PATH change
# (profile.zsh, setup.zsh) for the life of the shell.
typeset -U path PATH

# Go — appended, no ordering concerns.
export PATH="$PATH:$HOME/go/bin"

# local bin (e.g. claude installs here).
export PATH="$HOME/.local/bin:$PATH"

# AWS
export AWS_DEFAULT_REGION=us-west-2
export AWS_PAGER=""

export LESS="-R" # adding -X will prevent the pager from clearing
