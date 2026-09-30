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

# Opt-in phase timing: DOTFILES_TIMING=1 prints a per-phase breakdown at the end.
# The cost this measures is network latency on the bootstrapping box, which does
# not reproduce on a laptop, so the timer has to ship with the script.
_probe="$(date +%s%3N 2>/dev/null || true)"
if [ -n "${EPOCHREALTIME:-}" ]; then
  _now_ms() { local t="${EPOCHREALTIME/,/.}" f; f="${t#*.}000"; echo $(( ${t%.*} * 1000 + 10#${f:0:3} )); }
elif [ -n "$_probe" ] && [ -z "${_probe//[0-9]/}" ]; then
  _now_ms() { date +%s%3N; }
else
  _now_ms() { echo $(( $(date +%s) * 1000 )); }
fi

_phase_name=""; _phase_start=0; _phase_log=""; _run_start="$(_now_ms)"

# Close the running phase (if any) and start one named "$1". `phase` with no
# argument just closes the last one.
phase() {
  [ -n "${DOTFILES_TIMING:-}" ] || return 0
  local n; n="$(_now_ms)"
  if [ -n "$_phase_name" ]; then
    _phase_log+="$(printf '  %-24s %6d ms' "$_phase_name" "$(( n - _phase_start ))")"$'\n'
  fi
  _phase_name="${1:-}"; _phase_start="$n"
}

phase_report() {
  [ -n "${DOTFILES_TIMING:-}" ] || return 0
  phase
  printf '\ntiming (DOTFILES_TIMING=1)\n%s  %-24s %6d ms\n' \
    "$_phase_log" TOTAL "$(( $(_now_ms) - _run_start ))"
}

mkdir -p "$HOME/.config"

# Keep ~/.config occupied by something stow doesn't own. Stow's unstow pass (which
# --restow runs first) deletes a target directory once it's empty, so on a $HOME
# where ~/.config holds nothing but stowed symlinks it RMDIRs the directory, tries
# to fold ~/.config itself into whichever package it reaches next, then aborts the
# whole run with "unstow_contents() called with invalid target: .config" — before
# any of the wiring below happens. A real subdirectory prevents both the RMDIR and
# the fold. git/ is the natural resident: no package owns it and .gitconfig already
# includes ~/.config/git/config.local from there.
mkdir -p "$HOME/.config/git"

# If ~/.config/zsh already exists as a real directory (not a symlink), bail
# loudly instead of nesting a link inside it. A stale symlink (ours, maybe
# pointing at an old path) is fine — we drop it below before relinking.
zdir="$HOME/.config/zsh"
if [ -e "$zdir" ] && [ ! -L "$zdir" ]; then
  echo "error: $zdir exists and is not a symlink. Move or remove it, then re-run." >&2
  exit 1
fi

# Drop the link only if it's stale (dangling, or pointing at an older repo path);
# stow relinks it below. -ef compares device+inode through the link, so a dangling
# link counts as stale. A correct link is left alone rather than churned.
if [ -L "$zdir" ] && [ ! "$zdir/setup.zsh" -ef "$PKG_DIR/zsh/.config/zsh/setup.zsh" ]; then
  rm -f "$zdir"
fi

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

# Populate the non-optional submodules (the zsh plugins under
# packages/zsh/.config/zsh/plugins/). No `--checkout` here, deliberately: a plain
# `--init` honours the `update = none` on the work overlay, so this fills in the
# plugins without dragging in a private repo this machine may not be able to
# reach. GIT_TERMINAL_PROMPT=0 keeps a stray credential helper from blocking.
# Non-fatal — a shell missing a plugin is fine, a bootstrap that dies is not.
phase submodules
if [ -f .gitmodules ] && command -v git >/dev/null 2>&1; then
  # --jobs: three independent clones, so this is latency-bound, not bandwidth-bound.
  GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive --jobs 4 \
    || echo "warning: could not init submodules; some zsh plugins will be missing." >&2
fi

phase stow
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
  stow --restow --ignore='\.optional' --ignore='^mise\.lock$' \
    --dir="$PKG_DIR" --target="$HOME" "${names[@]}"
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

# Install the mise tool baseline (conf.d/10-dotfiles.toml, linked above). Most of
# the CLI toolchain lives there rather than the Brewfile, so this is what gets
# fzf/rg/fd/nvim onto a box with no brew. Non-fatal: a failed download must not
# take the shell setup down with it, and `mise install` never prompts.
phase github-token
# Give mise a GitHub token if we can find one. Without it every "latest" resolves
# against the anonymous API — 60 requests/hour shared by egress IP, which a whole
# devbox fleet behind one NAT exhausts easily; the symptom is a slow install that
# degrades into 403s. The lockfile below removes most of these calls, but the work
# overlay's tools aren't in it, so a token still helps.
#
# DEVCONTAINER_GITHUB_TOKEN is the Coder devbox source: grow-workspace's
# coder_agent sets it from data.coder_external_auth.github for devcontainer
# builds, which puts a per-user token in this script's environment for free. It is
# preferred over asking the coder CLI (a round trip) and over `gh auth token`,
# which is useless here twice over: gh is itself a mise tool that this run is about
# to install, and the template's gh-auth.sh races us anyway (coder_script has no
# ordering — every run_on_start script shares one errgroup).
#
# Every probe is best-effort and must not block. `coder` prints a login URL rather
# than a token when the provider isn't linked, so validate the shape before use.
if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
  tok="${DEVCONTAINER_GITHUB_TOKEN:-}"
  if [ -z "$tok" ] && [ -n "${CODER_AGENT_URL:-}" ] && command -v coder >/dev/null 2>&1; then
    tok="$(coder external-auth access-token github 2>/dev/null || true)"
  fi
  if [ -z "$tok" ] && command -v gh >/dev/null 2>&1; then
    tok="$(gh auth token 2>/dev/null || true)"
  fi
  # A URL (the coder failure mode) or any other junk has characters a token doesn't.
  case "$tok" in *[!A-Za-z0-9_.-]*|"") tok="" ;; esac
  if [ -n "$tok" ]; then
    export GITHUB_TOKEN="$tok"
    echo "using a GitHub token for tool resolution (5000 req/hr instead of 60)."
  else
    echo "note: no GitHub token found; mise will resolve tools anonymously (60 req/hr)."
  fi
fi

phase mise-lock
# Seed mise's lockfile so a fresh box installs pinned versions straight from the
# recorded URLs+checksums instead of resolving "latest" against the GitHub API
# once per tool — that resolution is a serial round trip each and dominates
# bootstrap on a high-latency link.
#
# COPIED, not stowed: mise rewrites the lockfile in place whenever it installs a
# tool that isn't in it (the work overlay's aws-cli, direnv). A symlink would push
# those edits back into the tracked repo, leaving every devbox with a dirty file
# that the next startup's `git pull` refuses to overwrite. Refresh with
# `make update-tools`. Not `locked = true` anywhere: that turns an unlocked tool
# into a hard failure, which is exactly the work overlay's tools.
if [ -f "$REPO_DIR/mise.lock" ]; then
  mise_lock="$HOME/.config/mise/mise.lock"
  mkdir -p "$(dirname "$mise_lock")"
  # A symlink here would be one into this repo, and mise rewrites the lockfile in
  # place on every install — the edits would land on tracked content and the next
  # bootstrap's `git pull` would refuse to run. Replace it with a real file.
  if [ -L "$mise_lock" ]; then rm -f "$mise_lock"; fi
  if [ ! -f "$mise_lock" ] || [ "$REPO_DIR/mise.lock" -nt "$mise_lock" ]; then
    cp "$REPO_DIR/mise.lock" "$mise_lock"
    chmod u+w "$mise_lock"
  fi
fi

phase mise-install
if command -v mise >/dev/null 2>&1; then
  # The downloads are the bulk of bootstrap wall time and nothing needed at the
  # first prompt depends on them, so detach on a devbox and let the shell come up
  # while they land. DOTFILES_ASYNC_TOOLS=1/0 overrides in either direction; a
  # laptop stays synchronous so `make install` still means "tools are ready".
  if [ -z "${DOTFILES_ASYNC_TOOLS+x}" ] && [ "${CODER:-}" = "true" ]; then
    DOTFILES_ASYNC_TOOLS=1
  fi
  if [ "${DOTFILES_ASYNC_TOOLS:-0}" != 0 ]; then
    tools_log="${TMPDIR:-/tmp}/dotfiles-mise-install.log"
    nohup mise install >"$tools_log" 2>&1 &
    echo "mise install detached (pid $!); progress: tail -f $tools_log"
  else
    mise install || echo "warning: 'mise install' failed; some tools will be missing." >&2
  fi
else
  echo "mise not found — skipping tool install (see https://mise.jdx.dev)." >&2
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

phase wire
wire "$HOME/.zshenv"   env.zsh
wire "$HOME/.zprofile" profile.zsh
wire "$HOME/.zshrc"    setup.zsh

phase_report

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
