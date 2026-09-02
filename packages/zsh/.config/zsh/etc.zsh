
# mise first: most of the CLI toolchain below (zoxide, fzf, fd, bat) is a mise
# tool now, and activating puts the real install dirs on PATH so the `command -v`
# probes and init evals don't each re-exec mise through a shim.
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# zoxide (smarter cd)
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# fzf (fuzzy finder) — rebinds Ctrl-R history search, Ctrl-T file paste, Alt-C cd
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"

  # Use fd for the file/dir walkers: respects .gitignore, much faster than the
  # built-in walker, and includes hidden files (minus .git).
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --hidden --strip-cwd-prefix --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'
  fi

  export FZF_DEFAULT_OPTS='--height 40% --layout reverse --border --info inline'
  # Ctrl-T: preview file contents (bat) or dir listing.
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null || ls -la {}'"
  # Alt-C: preview the directory you'd cd into.
  export FZF_ALT_C_OPTS="--preview 'ls -la {} | head -200'"
fi
