# Conditional work zsh overlay

**Date:** 2026-06-22
**Status:** Approved design, pending implementation plan

## Problem

The dotfiles repo is used across personal and work machines. Work-specific zsh
config currently lives in a separate private repo (`zsh-work-config`), cloned to
`~/.config/zsh-work` (an old pre-stow clone of this repo) and sourced via a raw,
hardcoded line in `~/.zshrc`:

```zsh
[[ -f /Users/nick/.config/zsh-work/setup.zsh ]] && source /Users/nick/.config/zsh-work/setup.zsh
```

Problems with the status quo:

- The source line lives in the home `~/.zshrc`, untracked and not created by
  `install.sh`. A fresh work machine doesn't get it.
- Only `setup.zsh` (interactive scope) is wired. The work config touches all
  three scopes (env, login PATH ordering, interactive) but the env/profile
  scopes aren't sourced at all.
- The work content must be tracked, but must NOT leak into the personal repo's
  history, and must NOT be cloned or cause errors on a personal machine.

## Goals

- Track work-specific zsh config in its own private repo.
- Wire it in idiomatically, covering all three startup scopes
  (`env.zsh` / `profile.zsh` / `setup.zsh`).
- Conditional install: on a personal machine the work overlay is **never
  cloned, never stowed, and never errors**. On a work machine it is cloned,
  stowed, and sourced automatically.
- Preserve the repo's existing invariants: graceful degradation, no interactive
  prompts in `install.sh`, and no hardcoded package names in any script.
- Work cleanly with Coder/Ona-style bootstrap (clone repo URL + run install
  script).

## Non-goals

- Putting work config in this (potentially public) repo's own history.
- A second `install.sh` / `install-work.sh`. One install script handles both.
- Detecting "work machine" by hostname, git email, or other heuristics. The
  signal is explicit (see Activation).

## Design

Two independent pieces: a **generic overlay mechanism** in the base repo that
knows nothing about "work," and the **work content** delivered as a conditional
submodule + stow package.

### 1. Overlay mechanism (base repo)

Append one guarded source-if-present line to the **end** of each of the three
base files. The end matches the repo's existing "source after tool-generated
lines" convention.

```zsh
# end of packages/zsh/.config/zsh/env.zsh
[[ -f ~/.config/zsh-local/env.zsh ]] && source ~/.config/zsh-local/env.zsh

# end of packages/zsh/.config/zsh/profile.zsh
[[ -f ~/.config/zsh-local/profile.zsh ]] && source ~/.config/zsh-local/profile.zsh

# end of packages/zsh/.config/zsh/setup.zsh
[[ -f ~/.config/zsh-local/setup.zsh ]] && source ~/.config/zsh-local/setup.zsh
```

These lines are tracked, so every machine gets them automatically and they never
need editing. Each base file sources its scope-matching counterpart, so:

- `env.zsh` (sourced from `~/.zshenv`) sources the overlay's env in every shell,
  including non-interactive.
- `profile.zsh` (sourced from `~/.zprofile`) sources the overlay's login-time
  PATH ordering.
- `setup.zsh` (sourced from `~/.zshrc`) sources the overlay's interactive setup.

On a machine with no overlay, `~/.config/zsh-local/*` does not exist and every
guard no-ops. Pure graceful degradation, matching the existing plugin-sourcing
pattern.

The mechanism is generic: the path is `~/.config/zsh-local`, with no reference
to "work." A different machine could provide a different overlay at the same
path.

### 2. Work content (conditional submodule + stow package)

The private repo `git@github.com:nickzelei/zsh-work-config.git` is added as a
git submodule at:

```
packages/work/.config/zsh-local
```

`packages/work` is a normal stow package. When stowed it links
`~/.config/zsh-local` -> the submodule contents, which is exactly where the
overlay hooks look. This mirrors how the zsh plugins are already submodules
under a stow package.

The private repo is restructured so its **root** holds the three overlay entry
files plus its supporting files:

```
env.zsh          # exported env / PATH for non-interactive shells (from today's envvars.zsh)
profile.zsh      # login-time PATH ordering relative to Homebrew (may be minimal/empty)
setup.zsh        # interactive: sources aliases/, etc.zsh
aliases/
etc.zsh
README.md
```

It stops being a mini-framework: its own `Makefile`, `bench/`, and any
self-install logic are removed, since the parent repo owns install. The existing
`ZSHRC_WORK_DIR` derivation via `${${(%):-%x}:A:h}` still resolves correctly
through the stow symlink (`:A` resolves symlinks).

### 3. Conditional gating (two gates)

**Gate A — don't clone.** In `.gitmodules`, the work submodule is declared with
`update = none`:

```
[submodule "work"]
    path = packages/work/.config/zsh-local
    url = git@github.com:nickzelei/zsh-work-config.git
    update = none
```

The existing `git submodule update --init --recursive` in `install.sh` then
skips it by default. A personal machine never fetches it, so there is no clone
and no auth error. (The plugin submodules have no `update` key and continue to
init normally.)

**Gate B — don't stow.** A package declares itself optional with a `.optional`
sentinel file at its root:

```
packages/work/.optional      # tracked in the PARENT repo, alongside .config/zsh-local
```

`install.sh` stows every package under `packages/*` as today, except packages
carrying `.optional`, which are stowed only when enabled for this machine.

### 4. Activation

A machine declares which optional packages to enable via the `DOTFILES_ENABLE`
environment variable: a space- or comma-separated list of package names.

```sh
DOTFILES_ENABLE="work"
```

Unset or empty -> no optional packages are enabled. The script reads the *set of
names* from the signal and matches against discovered optional packages, so
there are still **no package names hardcoded in any script**.

The variable must be present at install time:

- **Laptop:** run `DOTFILES_ENABLE=work make install` (or export it in the
  machine's persistent environment). An optional convenience target
  `make install-work` wraps `DOTFILES_ENABLE=work ./install.sh`.
- **Coder/Ona:** set `DOTFILES_ENABLE=work` in the workspace environment (e.g.
  Terraform `env`), so the standard install run picks it up.

### 5. `install.sh` changes

All changes preserve `set -euo pipefail`, non-interactive operation, and the
no-hardcoded-list rule.

1. Parse `DOTFILES_ENABLE` (commas -> spaces) into a lookup-able set.
2. In the package-discovery loop: for each `packages/*`, if it contains
   `.optional` and its name is not in the enable set, `continue` (skip both the
   submodule init and the stow).
3. For an enabled optional package, init just its submodule path before adding
   it to the stow list:
   ```sh
   git submodule update --init --recursive -- "packages/$name" \
     || echo "warning: could not init submodule for $name; skipping" >&2
   ```
4. Add `--ignore='\.optional'` to the `stow` invocation so the sentinel file is
   never linked into `$HOME` as `~/.optional`.

The no-stow fallback branch (`ln -s` of the zsh package only) is unchanged;
optional packages require stow and are simply not handled there.

### 6. Bootstrap flows

- **Personal laptop:** `make install` with `DOTFILES_ENABLE` unset. Blanket
  submodule init skips work (`update = none`); the glob skips `packages/work`
  (`.optional`, not enabled); zsh hooks find no `~/.config/zsh-local` and no-op.
  Nothing cloned, nothing errored.
- **Work laptop:** `DOTFILES_ENABLE=work make install`. The work submodule is
  explicitly inited, `packages/work` is stowed to `~/.config/zsh-local`, hooks
  fire.
- **Coder/Ona work workspace:** point the dotfiles module at this repo URL with
  `DOTFILES_ENABLE=work` in the workspace env. The module clones the repo and
  runs `install.sh` (auto-detected, or via `post_clone_script`), which inits the
  submodule (workspace git must have access to the private repo) and stows it.
- **Coder/Ona neutral workspace:** same repo URL, `DOTFILES_ENABLE` unset ->
  behaves like a personal machine.

### 7. Updating the overlay

Submodules pin a commit, so shipping a work change is two steps: commit in the
work repo, then bump the pointer in this repo. The existing `make update`
(`git submodule update --remote` style) bumps submodules to upstream and picks
up the overlay automatically.

## Migration

1. **Work repo (`zsh-work-config`):** restructure root to expose
   `env.zsh` / `profile.zsh` / `setup.zsh`; fold `envvars.zsh` into `env.zsh`;
   keep `aliases/` and `etc.zsh`; remove framework cruft (`Makefile`, `bench/`,
   self-install). Commit and push.
2. **Dotfiles repo:** add the three overlay hooks; add the submodule at
   `packages/work/.config/zsh-local` with `update = none`; add
   `packages/work/.optional`; update `install.sh` per section 5; update
   `CLAUDE.md` and `README.md` to document the optional-package convention and
   the overlay mechanism.
3. **Work laptop:** remove the hardcoded `zsh-work` source line from `~/.zshrc`;
   run `DOTFILES_ENABLE=work make install`; `exec zsh`; verify work aliases/env
   load.
4. Once verified, delete the old `~/.config/zsh-work` clone (its content now
   lives in the submodule).

## Verification

- **Personal simulation:** with `DOTFILES_ENABLE` unset, run `./install.sh`.
  Confirm the work submodule is not cloned, no error is raised,
  `~/.config/zsh-local` does not exist, and `exec zsh` starts cleanly.
- **Work simulation:** with `DOTFILES_ENABLE=work`, run `./install.sh`. Confirm
  the submodule is checked out, `~/.config/zsh-local/setup.zsh` exists and is
  sourced, and a known work alias/env var is present in a new shell.
- **Idempotence:** re-run install in both modes; no duplicate source lines, no
  errors.
- **Init time:** `make bench` shows no meaningful regression (hooks are three
  guarded `[[ -f ]]` tests).

## Caveats

- The public dotfiles repo carries a `.gitmodules` entry pointing at a private
  URL. Cloning the repo is fine; the `update = none` flag plus the install-time
  gate mean the private submodule is never fetched unless explicitly enabled.
- `DOTFILES_ENABLE` must be in the environment at install time. It is not set by
  the dotfiles themselves (that would be a chicken/egg), so on a laptop it must
  be passed to the install command or set in the machine's persistent env.
