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

# mise-managed tools for NON-interactive shells (`ssh host cmd`, cron, scripts);
# interactive shells get the real bin dirs from `mise activate` in etc.zsh.
# APPENDED, not prepended, and that ordering is load-bearing: a shim is a mise
# re-exec (~20ms) rather than the binary, and zsh SCRIPTS source ~/.zshenv too —
# so a front-of-PATH shims dir gets inherited by any shell they spawn, where it
# wins over mise's own bin dirs and taxes every tool call during init. At the
# back it's a pure fallback, only reached when nothing else provides the tool.
_mise_shims="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
[[ -d "$_mise_shims" ]] && export PATH="$PATH:$_mise_shims"
unset _mise_shims

# local bin (e.g. claude installs here).
export PATH="$HOME/.local/bin:$PATH"

# AWS
export AWS_PAGER=""

export LESS="-R" # adding -X will prevent the pager from clearing

# Machine-local overlay (e.g. a work-only layer), sourced for every shell if
# present. Absent on machines without an overlay, so this no-ops. Delivered by
# the optional `work` stow package -> ~/.config/zsh-local.
[[ -f ~/.config/zsh-local/env.zsh ]] && source ~/.config/zsh-local/env.zsh

# Untracked, this-machine-only escape hatch. The overlay above is a stowed
# package (shared across machines that enable it); this is for one-off local
# tweaks that belong in no repo.
[[ -f ~/.zshenv.local ]] && source ~/.zshenv.local
