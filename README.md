# dotfiles

My personal config, managed with [GNU Stow](https://www.gnu.org/software/stow/).
Currently tracks my zsh setup; structured so more tools can be added later as
their own stow packages.

## Install

Clone anywhere except `~/.config/zsh` itself (that path becomes a symlink into
the repo).

```console
git clone --recurse-submodules <url> ~/dotfiles
cd ~/dotfiles
make install   # brew deps + symlink + wire up zsh startup files
```

`make install` runs `brew bundle` then `./install.sh`. If you just want the
symlinks without touching brew, run `./install.sh` (or `make stow`) directly.

Then open a new shell (or `exec zsh`).

### How the linking works

Every directory under `packages/` is a [stow](https://www.gnu.org/software/stow/)
package whose contents mirror `$HOME`. The `zsh` package contains
`packages/zsh/.config/zsh/...`, so stowing it creates:

```
~/.config/zsh -> ~/dotfiles/packages/zsh/.config/zsh
```

`install.sh` discovers every package under `packages/` automatically (no
hardcoded list) and appends a guarded source line to each of zsh's startup
files, mirroring zsh's startup model so non-interactive shells get the env too:

```console
~/.zshenv   <- [[ -f ~/.config/zsh/env.zsh ]]     && source ~/.config/zsh/env.zsh
~/.zprofile <- [[ -f ~/.config/zsh/profile.zsh ]] && source ~/.config/zsh/profile.zsh
~/.zshrc    <- [[ -f ~/.config/zsh/setup.zsh ]]   && source ~/.config/zsh/setup.zsh
```

`env.zsh` runs for **every** invocation (interactive shells, scripts,
`ssh host 'cmd'`, cron), so order-independent `$PATH` and exported env live
there. `profile.zsh` runs for login shells after Homebrew's `shellenv`, for the
few `$PATH` entries whose order relative to Homebrew matters (e.g. openssl).
`setup.zsh` is interactive-only: prompt, plugins, keybindings.

The lines are appended to the *end* of each home file, so they run after any
tool-generated lines already there (Homebrew `shellenv`, rustup's cargo env,
OrbStack). The `[[ -f ... ]]` guard means your shell still starts cleanly if the
repo is ever moved or removed, instead of erroring on every prompt.

If `stow` isn't installed (e.g. a minimal image), `install.sh` doesn't try to
install it — it falls back to linking the `zsh` package directly with `ln -s`
so you always get a working shell, and prints which other packages it skipped.

### Adding another tool

No script edits — just create a package mirroring where the tool reads from in
`$HOME`, move the real config in, and re-run:

```console
mkdir -p packages/git
mv ~/.gitconfig packages/git/.gitconfig     # move, don't copy
make stow                                    # picks up the new package
git add -A && git commit -m "track gitconfig"
```

Mirror the *full* path under `$HOME` inside the package, e.g.
`packages/ghostty/.config/ghostty/config` → `~/.config/ghostty/config`. Move
(don't copy) the original — stow refuses to clobber a real file that's still in
place, which is its way of telling you to move it into the package first.

## Motivation

I previously used oh-my-zsh, but found it was slowing down my shell init.
This is a heavily pared-down setup with only what I've needed over the years —
simple, fast, and easy to move between machines.

## Layout

Repo root holds tooling that is *not* symlinked into `$HOME`:

- `install.sh` — symlinks packages into `$HOME` and wires zsh's startup files (idempotent).
- `Brewfile` — brew deps (`fzf`, `fd`, `ripgrep`, `stow`, `zoxide`, `mise`, …).
- `Makefile` — maintenance commands; run `make` to list them.
- `bench/` — init benchmark script and its results log.

Stow packages live under `packages/` (their contents get symlinked into `$HOME`):

- `packages/zsh/.config/zsh/` — the whole zsh config, symlinked to `~/.config/zsh`:
  - `env.zsh` — sourced from `~/.zshenv` (every shell); `$PATH` and exported env.
  - `profile.zsh` — sourced from `~/.zprofile` (login shells); `$PATH` ordered after Homebrew.
  - `setup.zsh` — sourced from `~/.zshrc` (interactive); prompt, history, keybindings, and sources the rest.
  - `aliases/` — aliases and directory shortcuts.
  - `etc.zsh` — wires up CLI tools (`zoxide`, `mise`, `fzf`).
  - `lib/git.zsh` — git helper functions.
  - `plugins/` — the vendored `git` plugin plus zsh plugin submodules.
- `packages/mise/.config/mise/config.toml` — global [mise](https://mise.jdx.dev)
  tool config, symlinked to mise's default `~/.config/mise/config.toml` so the
  tool baseline is tracked in the repo.

## Commands

Run `make` (no args) in the repo to see everything:

```console
make          # list commands
make install  # brew deps + symlink + wire up zsh startup files
make stow     # symlink + wire up zsh startup files (no brew)
make bench    # benchmark zsh init time, log to bench/results.md
make profile  # per-component init profile (what's slow)
make update   # update plugin submodules
```

## Plugins

`zsh-autosuggestions` and `zsh-syntax-highlighting` are git submodules under
`packages/zsh/.config/zsh/plugins/`, conditionally sourced in `setup.zsh`. `install.sh`
checks them out for you. If you cloned without `--recurse-submodules`:

```console
git submodule update --init --recursive
```

To update them to their latest upstream:

```console
make update
```

`fzf-tab` is installed via Homebrew (in the `Brewfile`) and sourced from there.
