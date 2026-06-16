# Profiling: `ZSH_PROFILE=1 zsh -i -c exit` prints a per-component timing table
# (via zsh/zprof) so you can see what's slow. No-op when ZSH_PROFILE is unset.
# Must load before the code being profiled, so keep it first.
[[ -n "$ZSH_PROFILE" ]] && zmodload zsh/zprof

# Basic zsh config
# Initialize completions. compinit normally re-runs its security audit
# (compaudit) on every startup, which is the bulk of init time. Instead, do the
# full rebuild + audit only when the dump is missing or older than 24h;
# otherwise load the cached dump and skip the audit with -C.
#
# NB: this uses an array glob, not `[[ -n ~/.zcompdump(#q...) ]]` — filename
# generation doesn't happen inside [[ ]], so that common idiom silently always
# takes the slow path.
autoload -Uz compinit
# Array glob (filename generation happens here, unlike inside [[ ]]): non-empty
# only when ~/.zcompdump exists and was modified less than 24h ago.
_fresh_zcompdump=( ${HOME}/.zcompdump(Nmh-24) )
if (( $#_fresh_zcompdump )); then
  compinit -C   # dump is fresh: trust it, skip the audit
else
  compinit      # missing or >24h old: rebuild dump and run the audit
fi
unset _fresh_zcompdump
zstyle ':completion:*' menu select # Enable menu selection for completion
# autoload the hook utility
autoload -Uz add-zsh-hook

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

autoload -Uz colors && colors
PS1="%B%{$fg[blue]%}%n@%m%{$reset_color%}:%{$fg[cyan]%}%~%{$reset_color%}$ %b"

### Search history with arrow keys
autoload -Uz up-line-or-beginning-search
autoload -Uz down-line-or-beginning-search
zle -N up-line-or-beginning-search # Register up-line-or-beginning-search as a zle widget
zle -N down-line-or-beginning-search # Register down-line-or-beginning-search as a zle widget

bindkey '^[[A' up-line-or-beginning-search    # Up arrow for history search
bindkey '^[[B' down-line-or-beginning-search  # Down arrow for history search
### End of search history with arrow keys

# Disable terminal flow control (XON/XOFF) so Ctrl-S/Ctrl-Q aren't swallowed by
# the tty. Frees Ctrl-S for forward history search and stops Ctrl-S from
# "freezing" the terminal (resumable only via Ctrl-Q).
stty -ixon

# Git integration in prompt
autoload -Uz vcs_info # Load version control info
add-zsh-hook precmd vcs_info # Update vcs_info before each command
zstyle ':vcs_info:git:*' formats ' (%b)' # Format for git branch
setopt PROMPT_SUBST # Enable prompt string expansion

# commented line includes directory, second one doesn't
# PS1='%B%{$fg[cyan]%}%~%{$fg[green]%}${vcs_info_msg_0_}%{$reset_color%} ➜ %b'
PS1='%B%{$fg[green]%}${vcs_info_msg_0_}%{$reset_color%} ➜ %b'

# Absolute path to this repo, derived from setup.zsh's own location so nothing
# is hardcoded to ~/.zshrc-config. `%x` is the file currently being sourced;
# `:A` makes it absolute (resolving symlinks), `:h` takes the directory.
# Exported so the sub-files sourced below can reference it too.
export ZSHRC_CONFIG_DIR="${${(%):-%x}:A:h}"

# Interactive-only environment. Tells gpg which terminal to prompt on; $(tty) is
# meaningless (and forks a process) in non-interactive shells, so this stays out
# of env.zsh. Order-independent env lives in env.zsh, ordered PATH in profile.zsh.
export GPG_TTY=$(tty)

source "$ZSHRC_CONFIG_DIR/aliases/aliases.zsh"
source "$ZSHRC_CONFIG_DIR/etc.zsh"

# Plugins

source "$ZSHRC_CONFIG_DIR/plugins/git/git.plugin.zsh"

# fzf-tab (brew): replaces the completion menu with an fzf picker. Must load
# after compinit/compdef-using plugins but BEFORE zsh-autosuggestions and
# zsh-syntax-highlighting, since it wraps the completion widget.
if [[ -f "$HOMEBREW_PREFIX/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" ]]; then
  source "$HOMEBREW_PREFIX/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"

  # Preview directory contents when completing `cd`.
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -la $realpath'
fi

# Must be installed last
[[ -f "$ZSHRC_CONFIG_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" ]] && \
  source "$ZSHRC_CONFIG_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
# Must be installed last
[[ -f "$ZSHRC_CONFIG_DIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh" ]] && \
  source "$ZSHRC_CONFIG_DIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"

# Set the terminal window/tab title to the current directory
function _set_terminal_title() { print -Pn "\e]0;%1~\a" }
add-zsh-hook precmd _set_terminal_title

# Profiling output (see the zmodload at the top). Keep this last. Use an `if`
# rather than `[[ ... ]] && zprof`: a false `&&` would make startup exit non-zero
# (it's the last statement), which leaks into the first prompt's $? and breaks
# `zsh -i -c exit` (the bench harness). An `if` with no else returns 0 when false.
if [[ -n "$ZSH_PROFILE" ]]; then zprof; fi
