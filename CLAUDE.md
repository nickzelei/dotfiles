# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). The README is detailed — read it for install/usage. This file captures the structural invariants worth knowing before editing.

## Commands

```console
make          # list commands (self-documenting via `## ` comments in Makefile)
make install  # brew bundle (skipped if no brew), then ./install.sh
make stow     # ./install.sh only — symlink + wire startup files, no brew
make bench    # benchmark zsh init time, appends a row to bench/results.md
make bench-install # cold install.sh against a throwaway $HOME (devbox bootstrap path)
make profile  # per-component init profile (ZSH_PROFILE=1 zsh -i -c exit)
make update-tools  # regenerate mise.lock
```

There is no test suite or linter. The way to verify a change is `make stow` (idempotent) then `exec zsh`, or `make bench`/`make profile` for init-time impact.

## Architecture

**Stow packages.** Every directory under `packages/` is a stow package whose internal layout mirrors `$HOME`. `packages/zsh/.config/zsh/...` stows to `~/.config/zsh/...`. `install.sh` discovers packages automatically by globbing `packages/*/` — **there is no hardcoded package list anywhere**, so adding a tool is purely `mkdir packages/<tool>/<path-under-home>` + move the real config in + `make stow`. Do not add package names to any script.

**zsh startup split.** The config is deliberately split across three files matching zsh's own startup model, so non-interactive shells (scripts, `ssh host cmd`, cron) still get env. `install.sh`'s `wire()` appends a guarded `[[ -f ... ]] && source ...` line to each home file:
- `env.zsh` → `~/.zshenv` — runs for **every** invocation. Order-independent `$PATH` and exported env only.
- `profile.zsh` → `~/.zprofile` — login shells, after Homebrew's `shellenv`. For `$PATH` entries whose order *relative to Homebrew* matters.
- `setup.zsh` → `~/.zshrc` — interactive only. Prompt, history, keybindings; sources `etc.zsh`, `aliases/`, and plugins.

When adding shell config, put it in the file matching its scope. Lines are appended to the **end** of home files so they run after tool-generated lines (Homebrew, rustup, OrbStack).

**Graceful degradation.** `install.sh` is built to run non-interactively with no TTY (an automated bootstrap like a Coder devbox clones the repo and runs it on startup). It never prompts. If `stow` is missing it falls back to `ln -s` for the `zsh` package only (guaranteeing a working shell) and skips the rest with a notice — it deliberately does *not* try to install stow. Preserve this: no interactive prompts, degrade rather than fail.

**Plugins are git submodules.** `fzf-tab`, `zsh-autosuggestions`, and `zsh-syntax-highlighting` live under `packages/zsh/.config/zsh/plugins/` as shallow submodules pinned to a commit, and `setup.zsh` sources `plugins/<name>/<name>.zsh` off the stowed path through the `_source_plugin` helper (guarded, so an un-checked-out submodule is skipped rather than fatal). They used to be brew/apt packages; that was reverted because apt has no `fzf-tab` package, so Linux silently lost it. Do not reintroduce a package-manager probe, and do not add a plugin manager — `sheldon` was measured at ~9.5ms per shell to emit three `source` lines that are free to hardcode. `install.sh` populates them with a plain `git submodule update --init`: **no `--checkout`**, which is what keeps the `update = none` work overlay from being dragged in. `plugins/git/git.plugin.zsh` is vendored outright.

**Plugin load order.** `fzf-tab` must precede `zsh-autosuggestions` — it copies the completion widget on load and must see the unwrapped one (`fzf-tab.zsh:382`). `zsh-syntax-highlighting` last is precautionary only: on zsh >= 5.9 it hooks `zle-line-pre-redraw` and stubs out `_zsh_highlight_bind_widgets` entirely, so it no longer rebinds widgets. Keep the order anyway for older zsh.

**Two override layers.** Each of the three zsh base files ends with two guarded sources, in order: the **overlay** (`~/.config/zsh-local/<scope>.zsh`, a shared layer for a class of machines, delivered by a stow package) then the **local hatch** (`~/.zshenv.local` / `~/.zprofile.local` / `~/.zshrc.local`, untracked, one machine). Both no-op when absent. Keep them distinct — the overlay is committed somewhere, the hatch never is. `.gitconfig`'s `~/.config/git/config.local` include is the same idea.

**Optional packages.** A package is **optional** if it contains a `.optional` marker at its root; `install.sh` stows optional packages only when their name appears in the `DOTFILES_ENABLE` env var (space/comma-separated). The work overlay is such a package: `packages/work/.config/zsh-local` is the private `zsh-work-config` repo as a submodule with `update = none` (so it's never cloned unless opted in), stowing to `~/.config/zsh-local`; `install.sh` forces it with `--checkout` when enabled. `packages/work` also ships a `mise/conf.d/work.toml` that layers on the base mise config. Enable with `DOTFILES_ENABLE=work ./install.sh` or `make install-work`. The `.optional` marker is kept out of `$HOME` via stow's `--ignore`.

**The one hardcoded package name.** `install.sh` defaults `DOTFILES_ENABLE=work` when `CODER=true` and the var is *unset*, so Coder devboxes need no configuration. This is a deliberate, single-line exception to the no-hardcoded-names rule and it is scoped to activation only — the discovery loop below it stays name-agnostic. Don't extend it into a lookup table of packages, and don't "fix" it by putting names in the loop. The unset-vs-empty distinction (`${VAR+x}`) is load-bearing: `DOTFILES_ENABLE=` must be able to opt a workspace out.

**Bootstrap speed.** `install.sh` carries opt-in phase timing (`DOTFILES_TIMING=1`
prints a per-phase table); `bench/install-bench.sh` drives a cold run against a
throwaway `$HOME`. The harness snapshots the **working tree**, not HEAD, and drops
`.git/modules` so submodules re-fetch over the network — it also injects a GitHub
token, because a sandbox `$HOME` hides `gh`'s keyring and a few anonymous runs will
drain the 60/hr limit for the whole egress IP. Three things were slow and are now
fixed; don't undo them:

- Submodule clones run with `--jobs 4` (three independent clones, latency-bound).
- `mise install` detaches when `CODER=true` (`DOTFILES_ASYNC_TOOLS` overrides
  either way). Nothing needed at the first prompt depends on those downloads.
- `install.sh` probes for a GitHub token before mise runs. Unauthenticated tool
  resolution is 60 requests/hour **per egress IP**, which a devbox fleet shares.
  On a Coder box the token is already in the environment as
  `DEVCONTAINER_GITHUB_TOKEN` (grow-workspace's `coder_agent` sets it from
  `data.coder_external_auth.github`), so that is checked before shelling out to
  the `coder` CLI. `gh auth token` is last and is effectively laptop-only: `gh` is
  itself a mise tool this run installs, and the template's `gh-auth.sh` races us
  because `coder_script` has no ordering — every `run_on_start` script shares one
  errgroup.

**The mise lockfile.** `mise.lock` at the repo root pins versions, URLs and
checksums for every platform, so a fresh box downloads directly instead of
resolving `latest` against the GitHub API once per tool. Three invariants:

- It is **copied** into `~/.config/mise/mise.lock`, never stowed, and `install.sh`
  deletes a symlink found at that path first. mise rewrites the lockfile in place
  whenever it installs a tool that isn't in it (the work overlay's `aws-cli`,
  `direnv`), so a symlink would push those edits onto tracked content and the next
  bootstrap's `git pull` would refuse to run. `stow --ignore='^mise\.lock$'` backs
  this up.
- **Never set `locked = true`.** It turns "tool absent from the lockfile" into a
  hard failure, which is exactly the work overlay. The lockfile is honoured
  without it; unlocked tools just resolve normally.
- `make update-tools` regenerates it from the base config in an isolated
  `MISE_CONFIG_DIR`/`MISE_DATA_DIR`, so work tools never leak into the tracked file
  and the pins come from upstream rather than whatever is installed locally.

**neovim uses the aqua backend.** It is spelled `"aqua:neovim/neovim"` in
`10-dotfiles.toml`, not `neovim`, because the registry default is a vfox Lua plugin
that makes its own unauthenticated GitHub API calls — it ignores mise's token and
records no URL in `mise.lock`, so it was the first thing to 403 on a rate-limited
box. Don't "simplify" it back to `neovim`.

## Conventions

- `install.sh` must stay idempotent — `wire()` greps before appending; stow uses `--restow`.
- Brew dependencies belong in `Brewfile`, not in any script. It is down to `git`, `stow`, `mise` and the casks — reach for a mise tool or a submodule before adding to it.
- No `luarocks`. `:checkhealth lazy` reports no plugin requires it, and lazy.nvim's `hererocks = nil` default bootstraps its own if one ever does.
- When tracking a new config, **move** (not copy) the original out of `$HOME` — stow refuses to clobber a real file in place.
- Optional packages carry a `.optional` marker and a submodule with `update = none`; never stow or clone them unless `DOTFILES_ENABLE` names them. Keep the no-hardcoded-list rule: discover by glob + marker, not by name in the script.
