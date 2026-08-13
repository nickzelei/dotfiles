# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). The README is detailed — read it for install/usage. This file captures the structural invariants worth knowing before editing.

## Commands

```console
make          # list commands (self-documenting via `## ` comments in Makefile)
make install  # brew bundle (skipped if no brew), then ./install.sh
make stow     # ./install.sh only — symlink + wire startup files, no brew
make bench    # benchmark zsh init time, appends a row to bench/results.md
make profile  # per-component init profile (ZSH_PROFILE=1 zsh -i -c exit)
```

There is no test suite or linter. The way to verify a change is `make stow` (idempotent) then `exec zsh`, or `make bench`/`make profile` for init-time impact.

## Architecture

**Stow packages.** Every directory under `packages/` is a stow package whose internal layout mirrors `$HOME`. `packages/zsh/.config/zsh/...` stows to `~/.config/zsh/...`. `install.sh` discovers packages automatically by globbing `packages/*/` — **there is no hardcoded package list anywhere**, so adding a tool is purely `mkdir packages/<tool>/<path-under-home>` + move the real config in + `make stow`. Do not add package names to any script.

**zsh startup split.** The config is deliberately split across three files matching zsh's own startup model, so non-interactive shells (scripts, `ssh host cmd`, cron) still get env. `install.sh`'s `wire()` appends a guarded `[[ -f ... ]] && source ...` line to each home file:
- `env.zsh` → `~/.zshenv` — runs for **every** invocation. Order-independent `$PATH` and exported env only.
- `profile.zsh` → `~/.zprofile` — login shells, after Homebrew's `shellenv`. For `$PATH` entries whose order *relative to Homebrew* matters.
- `setup.zsh` → `~/.zshrc` — interactive only. Prompt, history, keybindings; sources `etc.zsh`, `aliases/`, and plugins.

When adding shell config, put it in the file matching its scope. Lines are appended to the **end** of home files so they run after tool-generated lines (Homebrew, rustup, OrbStack).

**Graceful degradation.** `install.sh` is built to run non-interactively with no TTY (Ona clones the repo and runs it on startup). It never prompts. If `stow` is missing it falls back to `ln -s` for the `zsh` package only (guaranteeing a working shell) and skips the rest with a notice — it deliberately does *not* try to install stow. Preserve this: no interactive prompts, degrade rather than fail.

**Plugins come from the system package manager.** `fzf-tab`, `zsh-autosuggestions`, and `zsh-syntax-highlighting` are installed by brew (`Brewfile`) or apt, never vendored or submoduled. All three land at `<prefix>/share/<name>/<name>.zsh`, so `setup.zsh` sources them through one `_source_plugin` helper that tries `$HOMEBREW_PREFIX/share` then `/usr/share` and no-ops if neither exists. Load order is load-bearing: `fzf-tab` after compinit, then autosuggestions, then syntax-highlighting last. The only vendored plugin is `plugins/git/git.plugin.zsh`. The `work` overlay is the sole remaining submodule.

**Two override layers.** Each of the three zsh base files ends with two guarded sources, in order: the **overlay** (`~/.config/zsh-local/<scope>.zsh`, a shared layer for a class of machines, delivered by a stow package) then the **local hatch** (`~/.zshenv.local` / `~/.zprofile.local` / `~/.zshrc.local`, untracked, one machine). Both no-op when absent. Keep them distinct — the overlay is committed somewhere, the hatch never is. `.gitconfig`'s `~/.config/git/config.local` include is the same idea.

**Optional packages.** A package is **optional** if it contains a `.optional` marker at its root; `install.sh` stows optional packages only when their name appears in the `DOTFILES_ENABLE` env var (space/comma-separated). The work overlay is such a package: `packages/work/.config/zsh-local` is the private `zsh-work-config` repo as a submodule with `update = none` (so it's never cloned unless opted in), stowing to `~/.config/zsh-local`; `install.sh` forces it with `--checkout` when enabled. `packages/work` also ships a `mise/conf.d/work.toml` that layers on the base mise config. Enable with `DOTFILES_ENABLE=work ./install.sh` or `make install-work`. The `.optional` marker is kept out of `$HOME` via stow's `--ignore`.

## Conventions

- `install.sh` must stay idempotent — `wire()` greps before appending; stow uses `--restow`.
- Brew dependencies belong in `Brewfile`, not in any script.
- When tracking a new config, **move** (not copy) the original out of `$HOME` — stow refuses to clobber a real file in place.
- Optional packages carry a `.optional` marker and a submodule with `update = none`; never stow or clone them unless `DOTFILES_ENABLE` names them. Keep the no-hardcoded-list rule: discover by glob + marker, not by name in the script.
