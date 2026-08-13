#!/usr/bin/env bash
#
# Dotfiles installer. Symlinks the tracked config into $HOME and wires it into
# ~/.zshrc. Idempotent — safe to re-run.
#
# Two consumers:
#   - Your laptop: run `./install.sh` (or `make install` to also pull brew deps).
#   - Automated bootstrap (e.g. a Coder devbox): clones this repo and runs this
#     script on workspace startup, NON-INTERACTIVELY with no TTY. So the script
#     never prompts and degrades gracefully when tools are missing.
#
# Every directory under packages/ is a stow package whose contents mirror $HOME
# (e.g. packages/zsh/.config/zsh -> ~/.config/zsh). Adding a tool is just
# `mkdir packages/<tool>/...` — this script discovers it automatically, no edit
# needed here.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$REPO_DIR/packages"
cd "$REPO_DIR"

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

# Clone an optional package's submodule. `--checkout` forces it even though the
# submodule is declared `update = none` in .gitmodules (which is what keeps it
# from being fetched on machines that don't opt in) — without it, `git submodule
# update --init` just prints "Skipping submodule" and leaves the path empty.
#
# Submodule URLs are SSH, and some environments can't use SSH at all: a Coder
# workspace has no `ssh` binary, only `coder gitssh`, so the clone dies before it
# reaches GitHub. On failure, retry over HTTPS via a per-invocation insteadOf
# rewrite (.gitconfig uses pushInsteadOf, so HTTPS reads stay authenticated by
# whatever credential helper the box provides). The first attempt's output is held
# back and only printed if the retry fails too, since git's own clone retry is
# loud and looks alarming when the fallback ends up working.
init_submodule() {
  local name="$1" path="packages/$1" log
  log="$(mktemp "${TMPDIR:-/tmp}/dotfiles.XXXXXX")"

  if git submodule update --init --checkout --recursive -- "$path" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi

  local rewrite=() key url hostpath
  while read -r key url; do
    case "$url" in
      git@*:*)
        hostpath="${url#git@}"
        rewrite+=(-c "url.https://${hostpath%%:*}/${hostpath#*:}.insteadOf=$url")
        ;;
    esac
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.url$' || true)

  # GIT_TERMINAL_PROMPT=0: with no credential helper, HTTPS would otherwise sit
  # asking for a username, and this script must never block on a prompt.
  if [ "${#rewrite[@]}" -gt 0 ] \
    && GIT_TERMINAL_PROMPT=0 git "${rewrite[@]}" \
      submodule update --init --checkout --recursive -- "$path" >>"$log" 2>&1; then
    rm -f "$log"
    echo "note: SSH clone of $name failed; fetched it over HTTPS instead."
    return 0
  fi

  cat "$log" >&2
  rm -f "$log"
  return 1
}

if command -v stow >/dev/null 2>&1; then
  # Which optional packages to enable on this machine. DOTFILES_ENABLE is a
  # space- or comma-separated list of package names; empty/unset enables none.
  #
  # Coder workspaces are work machines, so default to the work overlay there and
  # keep the devbox zero-config. This is the ONE place a package name is written
  # down (the discovery loop below stays name-agnostic); an explicit
  # DOTFILES_ENABLE always wins, including `DOTFILES_ENABLE=` to opt back out.
  if [ -z "${DOTFILES_ENABLE+x}" ] && [ "${CODER:-}" = "true" ]; then
    DOTFILES_ENABLE=work
    echo "CODER=true and DOTFILES_ENABLE unset — enabling: $DOTFILES_ENABLE"
  fi

  # Wrapped in spaces so the `case` glob below can match whole names.
  enabled=" ${DOTFILES_ENABLE:-} "
  enabled="${enabled//,/ }"

  # Discover every package under packages/ — still no hardcoded list. A package
  # is OPTIONAL if it contains a `.optional` marker; those are stowed only when
  # named in DOTFILES_ENABLE. An enabled optional package may be backed by a
  # submodule with `update = none`, so we init just that path on demand.
  # Non-optional packages behave exactly as before.
  names=()
  for p in "$PKG_DIR"/*/; do
    name="$(basename "$p")"
    if [ -f "$p/.optional" ]; then
      case "$enabled" in
        *" $name "*) ;;  # enabled: fall through to init + stow
        *) echo "skipping optional package: $name (not in DOTFILES_ENABLE)"; continue ;;
      esac
      if [ -f .gitmodules ] && command -v git >/dev/null 2>&1; then
        init_submodule "$name" \
          || echo "warning: could not init submodule for $name; continuing without it" >&2
      fi
    fi
    names+=("$name")
  done

  # --ignore the marker so `packages/<opt>/.optional` is never linked into $HOME.
  stow --restow --ignore='\.optional' --dir="$PKG_DIR" --target="$HOME" "${names[@]}"
else
  # No stow (e.g. a minimal container image). We deliberately DON'T try to install it
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

# Nothing above loads unless the shell is zsh, and a devbox image often hands you
# bash instead (a Coder workspace did — `source ~/.zshrc` then feeds zsh syntax to
# bash and explodes). Say so rather than switching shells behind your back: the
# durable fix belongs in the image or template, not in $HOME.
case "${SHELL:-}" in
*/zsh) ;;
*)
  echo
  echo "notice: \$SHELL is ${SHELL:-unset}, not zsh — none of the above loads in bash." >&2
  if command -v zsh >/dev/null 2>&1; then
    echo "  Run 'exec zsh' for this session; set zsh as the login shell to make it stick." >&2
  else
    echo "  zsh is not installed on this machine." >&2
  fi
  ;;
esac
