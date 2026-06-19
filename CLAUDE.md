# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). The README is detailed — read it for install/usage. This file captures the structural invariants worth knowing before editing.

## Commands

```console
make          # list commands (self-documenting via `## ` comments in Makefile)
make install  # brew bundle, then ./install.sh
make stow     # ./install.sh only — symlink + wire startup files, no brew
make bench    # benchmark zsh init time, appends a row to bench/results.md
make profile  # per-component init profile (ZSH_PROFILE=1 zsh -i -c exit)
make update   # update plugin submodules to latest upstream
```

There is no test suite or linter. The way to verify a change is `make stow` (idempotent) then `exec zsh`, or `make bench`/`make profile` for init-time impact.

## Architecture

**Stow packages.** Every directory under `packages/` is a stow package whose internal layout mirrors `$HOME`. `packages/zsh/.config/zsh/...` stows to `~/.config/zsh/...`. `install.sh` discovers packages automatically by globbing `packages/*/` — **there is no hardcoded package list anywhere**, so adding a tool is purely `mkdir packages/<tool>/<path-under-home>` + move the real config in + `make stow`. Do not add package names to any script.

**zsh startup split.** The config is deliberately split across three files matching zsh's own startup model, so non-interactive shells (scripts, `ssh host cmd`, cron) still get env. `install.sh`'s `wire()` appends a guarded `[[ -f ... ]] && source ...` line to each home file:
- `env.zsh` → `~/.zshenv` — runs for **every** invocation. Order-independent `$PATH` and exported env only.
- `profile.zsh` → `~/.zprofile` — login shells, after Homebrew's `shellenv`. For `$PATH` entries whose order *relative to Homebrew* matters.
- `setup.zsh` → `~/.zshrc` — interactive only. Prompt, history, keybindings; sources `etc.zsh`, `aliases/`, `lib/`, `plugins/`.

When adding shell config, put it in the file matching its scope. Lines are appended to the **end** of home files so they run after tool-generated lines (Homebrew, rustup, OrbStack).

**Graceful degradation.** `install.sh` is built to run non-interactively with no TTY (Ona clones the repo and runs it on startup). It never prompts. If `stow` is missing it falls back to `ln -s` for the `zsh` package only (guaranteeing a working shell) and skips the rest with a notice — it deliberately does *not* try to install stow. Preserve this: no interactive prompts, degrade rather than fail.

**Plugins are git submodules.** `zsh-autosuggestions` and `zsh-syntax-highlighting` live under `packages/zsh/.config/zsh/plugins/` as submodules (see `.gitmodules`), conditionally sourced in `setup.zsh`. `fzf-tab` is installed via Homebrew (`Brewfile`) instead. `install.sh` runs `git submodule update --init --recursive`; `make update` bumps them to upstream.

## Conventions

- `install.sh` must stay idempotent — `wire()` greps before appending; stow uses `--restow`.
- Brew dependencies belong in `Brewfile`, not in any script.
- When tracking a new config, **move** (not copy) the original out of `$HOME` — stow refuses to clobber a real file in place.
