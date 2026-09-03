# dotfiles

My personal config, managed with [GNU Stow](https://www.gnu.org/software/stow/).
Currently tracks my zsh setup; structured so more tools can be added later as
their own stow packages.

## Install

Clone anywhere except `~/.config/zsh` itself (that path becomes a symlink into
the repo).

```console
git clone <url> ~/dotfiles
cd ~/dotfiles
make install   # deps + symlink + wire up zsh startup files
```

`make install` runs `brew bundle` (skipped with a notice if brew isn't
installed, e.g. on Linux) then `./install.sh`, which symlinks the config and
runs `mise install`. If you just want the symlinks without touching brew, run
`./install.sh` (or `make stow`) directly.

Most of the CLI toolchain comes from [mise](https://mise.jdx.dev), not brew, so
on Linux `./install.sh` alone is the whole install as long as `mise`, `git`,
`stow` and `zsh` are already there. The Brewfile only covers what mise can't:
`git`, `stow`, `mise` itself, and the macOS casks. The zsh plugins are git
submodules, so they come with the repo (see [Plugins](#plugins)).

Then open a new shell (or `exec zsh`).

Everything in `setup.zsh` is guarded by `command -v` / `[[ -f ]]`, so a machine
missing some of these tools still gets a working shell — it just loses
that tool's integration. Install what your platform has and move on.

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

### Two ways to override

Each of the three zsh startup files ends with two guarded sources, in this order:

1. **The overlay** at `~/.config/zsh-local/<scope>.zsh` — a *shared* layer for
   config that belongs on a whole class of machines (all my work boxes), tracked
   in its own repo.
2. **The local hatch** at `~/.zshrc.local` / `~/.zprofile.local` /
   `~/.zshenv.local` — untracked, one machine only, in no repo at all.

Both no-op when absent, so most machines use neither. The distinction matters:
reach for the overlay when a second machine will want the same thing, and the
hatch when it's a one-off you'd never commit. `.gitconfig` has the same split via
its `~/.config/git/config.local` include.

### The work overlay

The overlay path is just a path, so anything can fill it. Mine is a separate
private repo. `packages/work` carries a `.optional` marker and a submodule (with
`update = none`, so it's never cloned by default) at
`packages/work/.config/zsh-local`, which stows to `~/.config/zsh-local`. It also
ships `.config/mise/conf.d/work.toml`, so enabling it layers work-only mise tools
on top of the base config.

Optional packages are stowed only when named in the `DOTFILES_ENABLE` env var
(space/comma-separated). So a personal machine ignores `work` entirely — never
cloned, never stowed, never an error — while a work machine opts in:

```console
DOTFILES_ENABLE=work ./install.sh   # or: make install-work
```

On a **Coder workspace** you don't need to set anything: `install.sh` enables the
work overlay automatically when `CODER=true`, so pointing Coder's dotfiles module
at this repo is the whole setup. An explicit `DOTFILES_ENABLE` still wins, and
`DOTFILES_ENABLE=` (empty) opts a workspace back out.

The overlay is a private repo and its submodule URL is SSH, so the workspace needs
an SSH key on your GitHub account. Some devboxes can't do SSH at all — a Coder
workspace has no `ssh` binary, only `coder gitssh`, so the clone dies before it
reaches GitHub. When the SSH clone fails, `install.sh` retries over HTTPS with a
per-invocation `insteadOf` rewrite; `.gitconfig` uses `pushInsteadOf` (not
`insteadOf`), so HTTPS reads are left alone and whatever credential helper the box
provides (Coder's external auth, an injected token) can authenticate them. If both
routes fail the clone fails soft — `install.sh` warns and continues, and you get
the base config without the overlay.

The workspace's login shell has to actually be zsh. A devbox image that hands you
bash loads none of this (and `source ~/.zshrc` from bash just spews syntax
errors). `install.sh` says so at the end rather than switching shells for you —
fix it in the image or template (`chsh -s "$(command -v zsh)"`), since nothing
`install.sh` writes to `$HOME` can change which shell the terminal starts.

Because the hooks only care about the path, you can also clone or symlink any
overlay straight to `~/.config/zsh-local` and it loads the same way.

To turn the overlay off on a machine that previously enabled it, unstow the
package explicitly (a plain `./install.sh` only restows the packages it stows,
so it leaves an already-linked optional package in place):

```console
stow --dir=packages --target="$HOME" --delete work
```

The overlay is a normal git repo at its stowed path, so update it in place —
there's no wrapper command for it:

```console
cd ~/.config/zsh-local && git pull
```

## Motivation

I previously used oh-my-zsh, but found it was slowing down my shell init.
This is a heavily pared-down setup with only what I've needed over the years —
simple, fast, and easy to move between machines.

## Layout

Repo root holds tooling that is *not* symlinked into `$HOME`:

- `install.sh` — symlinks packages into `$HOME` and wires zsh's startup files (idempotent).
- `Brewfile` — the few deps mise can't provide: `git`, `stow`, `mise`, and the
  macOS casks. Everything else is a mise tool or a submodule.
- `Makefile` — maintenance commands; run `make` to list them.
- `bench/` — init benchmark script and its results log.

Stow packages live under `packages/` (their contents get symlinked into `$HOME`):

- `packages/zsh/.config/zsh/` — the whole zsh config, symlinked to `~/.config/zsh`:
  - `env.zsh` — sourced from `~/.zshenv` (every shell); `$PATH` and exported env.
  - `profile.zsh` — sourced from `~/.zprofile` (login shells); `$PATH` ordered after Homebrew.
  - `setup.zsh` — sourced from `~/.zshrc` (interactive); prompt, history, keybindings, and sources the rest.
  - `aliases/` — aliases and directory shortcuts.
  - `etc.zsh` — wires up CLI tools (`mise` first, then `zoxide`, `fzf`).
  - `plugins/` — `git.plugin.zsh` is vendored outright; the other three are git
    submodules, see [Plugins](#plugins).
- `packages/mise/.config/mise/conf.d/10-dotfiles.toml` — global
  [mise](https://mise.jdx.dev) tool baseline: language runtimes *and* the CLI
  toolchain (`fzf`, `fd`, `ripgrep`, `bat`, `zoxide`, `gh`, `lazygit`,
  `hyperfine`, `neovim`). Keeping them here rather than in the `Brewfile` is what
  makes them available on the Linux boxes. Update with `mise upgrade`. Lives in
  `conf.d/` rather than `config.toml` so the work overlay can drop a second file
  alongside it and mise merges the two, instead of the two packages fighting over
  one path.
- `packages/nvim/.config/nvim/` — [LazyVim](https://www.lazyvim.org)-based
  Neovim config, symlinked to `~/.config/nvim`. `neovim` itself is a mise tool
  and the nerd font is a cask. There's deliberately no `luarocks`: no plugin here
  needs it (`:checkhealth lazy` confirms), and if one ever does, lazy.nvim's
  default `hererocks = nil` bootstraps its own copy.

## Commands

Run `make` (no args) in the repo to see everything:

```console
make          # list commands
make install       # deps + symlink + wire up zsh startup files
make install-work  # same, including the work overlay
make stow          # symlink + wire up zsh startup files (no brew)
make bench         # benchmark zsh init time, log to bench/results.md
make profile       # per-component init profile (what's slow)
```

## Plugins

`fzf-tab`, `zsh-autosuggestions`, and `zsh-syntax-highlighting` are git
submodules under `packages/zsh/.config/zsh/plugins/`, each pinned to a commit and
cloned shallow. `install.sh` runs `git submodule update --init` (no `--checkout`,
so the `update = none` work overlay is left alone), and `setup.zsh` sources them
straight off that path:

```console
~/.config/zsh/plugins/<name>/<name>.zsh
```

They were brew/apt packages before. Submodules are the better fit for three
reasons: apt doesn't package `fzf-tab` at all, so Linux silently lost it; the
gitlink pins a version, which a `brew upgrade` does not; and it costs nothing at
startup, unlike a plugin manager (`sheldon source` measured ~9.5ms per shell to
emit three `source` lines).

A submodule that was never checked out is silently skipped, so a `git clone`
without `--recursive` still gives you a working shell. Load order is fixed in
`setup.zsh` and the reasoning is commented there — `fzf-tab` before
`zsh-autosuggestions` is the constraint that actually bites.

Bump them with `make update-plugins` (`git submodule update --remote`), then
commit the moved gitlinks. Everything else updates via `mise upgrade`.
