#!/usr/bin/env bash
#
# Dotfiles installer. Symlinks the tracked config into $HOME and wires it into
# ~/.zshrc. Idempotent — safe to re-run.
#
# Two consumers:
#   - Your laptop: run `./install.sh` (or `make install` to also pull brew deps).
#   - Ona: clones this repo to ~/dotfiles and runs this script automatically on
#     environment startup. Ona runs it NON-INTERACTIVELY with no TTY, so this
#     script never prompts and degrades gracefully when tools are missing.
#     See https://ona.com/docs/ona/configuration/dotfiles/overview
#
# Every directory under packages/ is a stow package whose contents mirror $HOME
# (e.g. packages/zsh/.config/zsh -> ~/.config/zsh). Adding a tool is just
# `mkdir packages/<tool>/...` — this script discovers it automatically, no edit
# needed here.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$REPO_DIR/packages"
cd "$REPO_DIR"

# Plugins are git submodules; the zsh config sources them, so make sure they're
# checked out. Skips cleanly if the repo was cloned with --recurse-submodules.
if [ -f .gitmodules ] && command -v git >/dev/null 2>&1; then
  git submodule update --init --recursive
fi

mkdir -p "$HOME/.config"

# If ~/.config/zsh already exists as a real directory (not a symlink), bail
# loudly instead of nesting a link inside it. A stale symlink (ours, maybe
# pointing at an old path) is fine — we drop it below before relinking.
zdir="$HOME/.config/zsh"
if [ -e "$zdir" ] && [ ! -L "$zdir" ]; then
  echo "error: $zdir exists and is not a symlink. Move or remove it, then re-run." >&2
  exit 1
fi
[ -L "$zdir" ] && rm -f "$zdir"

if command -v stow >/dev/null 2>&1; then
  # Which optional packages to enable on this machine. DOTFILES_ENABLE is a
  # space- or comma-separated list of package names; empty/unset enables none.
  # Wrapped in spaces so the `case` glob below can match whole names.
  enabled=" ${DOTFILES_ENABLE:-} "
  enabled="${enabled//,/ }"

  # Discover every package under packages/ — still no hardcoded list. A package
  # is OPTIONAL if it contains a `.optional` marker; those are stowed only when
  # named in DOTFILES_ENABLE. An enabled optional package may be backed by a
  # submodule with `update = none` (so the blanket init above skipped it), so we
  # init just that path on demand. Non-optional packages behave exactly as before.
  names=()
  for p in "$PKG_DIR"/*/; do
    name="$(basename "$p")"
    if [ -f "$p/.optional" ]; then
      case "$enabled" in
        *" $name "*) ;;  # enabled: fall through to init + stow
        *) echo "skipping optional package: $name (not in DOTFILES_ENABLE)"; continue ;;
      esac
      if [ -f .gitmodules ] && command -v git >/dev/null 2>&1; then
        # --checkout forces the clone even though the submodule is declared
        # `update = none` in .gitmodules (which is what keeps the blanket init
        # above from fetching it on machines that don't opt in). Without it,
        # `git submodule update --init` just prints "Skipping submodule" and
        # leaves the path empty, so an enabled overlay would never materialize.
        git submodule update --init --checkout --recursive -- "packages/$name" \
          || echo "warning: could not init submodule for $name; continuing without it" >&2
      fi
    fi
    names+=("$name")
  done

  # --ignore the marker so `packages/<opt>/.optional` is never linked into $HOME.
  stow --restow --ignore='\.optional' --dir="$PKG_DIR" --target="$HOME" "${names[@]}"
else
  # No stow (e.g. a minimal Ona image). We deliberately DON'T try to install it
  # — that's the fragile, cross-distro part. Instead guarantee the one thing
  # that must always work: a usable shell. Link the zsh package directly and
  # skip the rest with a notice.
  echo "stow not found — linking the zsh package only (others need stow)." >&2
  ln -sfn "$PKG_DIR/zsh/.config/zsh" "$zdir"
  for p in "$PKG_DIR"/*/; do
    name="$(basename "$p")"
    [ "$name" = zsh ] || echo "  skipped (needs stow): $name" >&2
  done
fi

# Wire a tracked config file into a home startup file with a guarded source line
# (so the shell still starts if the repo is moved/removed). Idempotent: only
# appends if absent. Appends to the END so it runs after any tool-generated lines
# already in the home file (Homebrew shellenv, rustup's cargo env, OrbStack).
#
# The split mirrors zsh's startup model so non-interactive shells get the env too:
#   ~/.zshenv   <- env.zsh     (every invocation: PATH, exported env)
#   ~/.zprofile <- profile.zsh (login shells: PATH ordered after Homebrew)
#   ~/.zshrc    <- setup.zsh   (interactive: prompt, plugins, keybindings)
wire() {
  home_file="$1"; tracked="$2"
  if [ ! -f "$home_file" ] || ! grep -qF "config/zsh/$tracked" "$home_file"; then
    printf '\n[[ -f ~/.config/zsh/%s ]] && source ~/.config/zsh/%s\n' "$tracked" "$tracked" >> "$home_file"
    echo "Wired $tracked into $home_file."
  else
    echo "$home_file already sources $tracked; left it alone."
  fi
}

wire "$HOME/.zshenv"   env.zsh
wire "$HOME/.zprofile" profile.zsh
wire "$HOME/.zshrc"    setup.zsh

echo "Done. Open a new shell (or 'exec zsh') to pick up the config."
