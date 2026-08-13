# Sourced from ~/.zprofile (login shells), AFTER Homebrew's shellenv has run.
# Put PATH entries here when their ORDER relative to Homebrew matters: on macOS
# /etc/zprofile runs path_helper (which reorders PATH) and Homebrew's shellenv
# runs in ~/.zprofile, so sourcing this last keeps our overrides in front.
# Order-independent env belongs in env.zsh so non-interactive shells get it too.

# Prefer Homebrew's openssl@3 over the system/symlinked one. Must come before the
# default Homebrew bin, hence here (after brew shellenv) rather than env.zsh. The
# guard matters on Linux: unset $HOMEBREW_PREFIX would prepend a bogus
# /opt/openssl@3/bin that `typeset -U path` can't dedupe away.
[[ -n "$HOMEBREW_PREFIX" ]] && export PATH="$HOMEBREW_PREFIX/opt/openssl@3/bin:$PATH"

# Machine-local overlay, login-shell scope (PATH ordering relative to Homebrew).
# Sourced if present; no-ops otherwise.
[[ -f ~/.config/zsh-local/profile.zsh ]] && source ~/.config/zsh-local/profile.zsh

# Untracked, this-machine-only escape hatch (see env.zsh).
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
