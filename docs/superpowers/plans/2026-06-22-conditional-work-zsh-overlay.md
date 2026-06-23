# Conditional Work Zsh Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver work-specific zsh config from a separate private repo, sourced via a generic machine-local overlay, installed only on machines that opt in.

**Architecture:** The base repo's three startup files each source `~/.config/zsh-local/{env,profile,setup}.zsh` if present (generic, knows nothing about "work"). The work content is a git submodule at `packages/work/.config/zsh-local` that stows to that path. Two gates keep it off personal machines: `update = none` in `.gitmodules` (never cloned by the blanket submodule init) and a `.optional` sentinel that `install.sh` only stows when the package name appears in `DOTFILES_ENABLE`.

**Tech Stack:** zsh, GNU Stow, git submodules, bash (`install.sh`), make.

## Global Constraints

- `install.sh` stays idempotent and fully non-interactive; preserve `set -euo pipefail`.
- No hardcoded package names in any script. Packages are discovered by globbing `packages/*`; optional ones are identified by a `.optional` marker.
- Overlay hook lines are appended to the **end** of each base file (after tool-generated lines), matching the repo's existing wiring convention.
- Graceful degradation: a missing overlay file or an unfetchable submodule must no-op, never error.
- Activation signal: `DOTFILES_ENABLE` — a space/comma-separated list of optional package names. Empty/unset enables none.
- Fixed names: overlay path `~/.config/zsh-local`; submodule path `packages/work/.config/zsh-local`, submodule name `work`, `update = none`; sentinel `packages/work/.optional`.
- There is no test suite. Verification is `zsh -n` syntax checks, behavioral one-liners, and `./install.sh` runs (idempotent).
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` and contain no em-dashes or semicolons.

---

### Task 1: Overlay hooks in the three base files

Add a guarded source-if-present line to the end of each base file so a machine-local overlay at `~/.config/zsh-local` is sourced in the matching scope. With no overlay present these no-op.

**Files:**
- Modify: `packages/zsh/.config/zsh/env.zsh` (append at end)
- Modify: `packages/zsh/.config/zsh/profile.zsh` (append at end)
- Modify: `packages/zsh/.config/zsh/setup.zsh` (insert before the final zprof block)

**Interfaces:**
- Produces: the convention that `~/.config/zsh-local/env.zsh`, `~/.config/zsh-local/profile.zsh`, and `~/.config/zsh-local/setup.zsh` are sourced (when present) at the end of their respective scopes. Later tasks deliver files at exactly these paths.

- [ ] **Step 1: Append the env hook to `env.zsh`**

Append to the end of `packages/zsh/.config/zsh/env.zsh`:

```zsh

# Machine-local overlay (e.g. a work-only layer), sourced for every shell if
# present. Absent on machines without an overlay, so this no-ops. Delivered by
# the optional `work` stow package -> ~/.config/zsh-local.
[[ -f ~/.config/zsh-local/env.zsh ]] && source ~/.config/zsh-local/env.zsh
```

- [ ] **Step 2: Append the profile hook to `profile.zsh`**

Append to the end of `packages/zsh/.config/zsh/profile.zsh`:

```zsh

# Machine-local overlay, login-shell scope (PATH ordering relative to Homebrew).
# Sourced if present; no-ops otherwise.
[[ -f ~/.config/zsh-local/profile.zsh ]] && source ~/.config/zsh-local/profile.zsh
```

- [ ] **Step 3: Insert the setup hook into `setup.zsh`**

In `packages/zsh/.config/zsh/setup.zsh`, find the final profiling block:

```zsh
# Profiling output (see the zmodload at the top). Keep this last. Use an `if`
# rather than `[[ ... ]] && zprof`: a false `&&` would make startup exit non-zero
# (it's the last statement), which leaks into the first prompt's $? and breaks
# `zsh -i -c exit` (the bench harness). An `if` with no else returns 0 when false.
if [[ -n "$ZSH_PROFILE" ]]; then zprof; fi
```

Insert immediately **before** that comment:

```zsh
# Machine-local overlay, interactive scope (e.g. work-only aliases and tool
# wiring). Sourced last so it can extend or override the base; absent on
# machines without an overlay, so this no-ops.
[[ -f ~/.config/zsh-local/setup.zsh ]] && source ~/.config/zsh-local/setup.zsh

```

(The zprof block must stay the literal last statement, so the hook goes before it.)

- [ ] **Step 4: Syntax-check all three files**

Run:
```bash
for f in env profile setup; do zsh -n "packages/zsh/.config/zsh/$f.zsh" && echo "$f OK"; done
```
Expected:
```
env OK
profile OK
setup OK
```

- [ ] **Step 5: Verify the hooks no-op when no overlay is present**

Confirm there is no overlay, then start a fresh interactive shell:
```bash
test ! -e ~/.config/zsh-local && echo "no overlay present"
zsh -ic 'echo shell-ok'
```
Expected: prints `no overlay present` then `shell-ok` with no errors. (If `~/.config/zsh-local` already exists from the legacy setup, that is fine; the line still behaves.)

- [ ] **Step 6: Commit**

```bash
git add packages/zsh/.config/zsh/env.zsh packages/zsh/.config/zsh/profile.zsh packages/zsh/.config/zsh/setup.zsh
git commit -m "$(cat <<'EOF'
adds machine-local overlay hooks to the three zsh base files

Sources ~/.config/zsh-local/{env,profile,setup}.zsh if present, in each
matching scope. No-ops on machines without an overlay.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Optional-package support in `install.sh` + `make install-work`

Teach `install.sh` to discover optional packages (those with a `.optional` marker), stow them only when named in `DOTFILES_ENABLE`, init their submodule on demand, and ignore the marker file during stow. Add a `make install-work` convenience target.

**Files:**
- Modify: `install.sh` (the `if command -v stow` block; the blanket submodule init stays as-is)
- Modify: `Makefile` (add `install-work` target and `.PHONY`)

**Interfaces:**
- Consumes: the `~/.config/zsh-local` convention from Task 1 (an enabled overlay package stows there).
- Produces: `DOTFILES_ENABLE="<names>"` activates optional packages; `make install-work` runs `DOTFILES_ENABLE=work ./install.sh`.

- [ ] **Step 1: Replace the stow discovery block in `install.sh`**

Find this block:

```bash
if command -v stow >/dev/null 2>&1; then
  # Discover and stow every package under packages/ — no hardcoded list.
  names=()
  for p in "$PKG_DIR"/*/; do names+=("$(basename "$p")"); done
  stow --restow --dir="$PKG_DIR" --target="$HOME" "${names[@]}"
else
```

Replace it with:

```bash
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
        git submodule update --init --recursive -- "packages/$name" \
          || echo "warning: could not init submodule for $name; continuing without it" >&2
      fi
    fi
    names+=("$name")
  done

  # --ignore the marker so `packages/<opt>/.optional` is never linked into $HOME.
  stow --restow --ignore='\.optional' --dir="$PKG_DIR" --target="$HOME" "${names[@]}"
else
```

(Leave the blanket `git submodule update --init --recursive` near the top of the file unchanged. It will skip `update = none` submodules.)

- [ ] **Step 2: Add the `install-work` target to the `Makefile`**

In `Makefile`, add `install-work` to the `.PHONY` line:

```make
.PHONY: help bench profile install install-work stow update
```

Add the target after the `stow` target:

```make
install-work: ## Symlink config incl. the work overlay (DOTFILES_ENABLE=work)
	DOTFILES_ENABLE=work ./install.sh
```

- [ ] **Step 3: Scaffold a throwaway optional package to test the gate**

```bash
mkdir -p packages/optltest/.config/optltest
touch packages/optltest/.optional
echo '# probe' > packages/optltest/.config/optltest/probe.zsh
```

- [ ] **Step 4: Run install with the package NOT enabled, confirm it is skipped**

Run:
```bash
./install.sh 2>&1 | grep optltest
test ! -e ~/.config/optltest && echo "optltest not stowed (correct)"
test ! -e ~/.optional && echo "marker not leaked to home (correct)"
```
Expected:
```
skipping optional package: optltest (not in DOTFILES_ENABLE)
optltest not stowed (correct)
marker not leaked to home (correct)
```

- [ ] **Step 5: Run install WITH the package enabled, confirm it stows**

Run:
```bash
DOTFILES_ENABLE=optltest ./install.sh >/dev/null
test -f ~/.config/optltest/probe.zsh && echo "optltest stowed (correct)"
test ! -e ~/.optional && echo "marker still not leaked (correct)"
```
Expected:
```
optltest stowed (correct)
marker still not leaked (correct)
```

- [ ] **Step 6: Tear down the scaffold**

```bash
rm -rf ~/.config/optltest packages/optltest
```
Then confirm a clean re-stow with nothing enabled:
```bash
./install.sh >/dev/null && echo "clean restow ok"
```
Expected: `clean restow ok` with no `optltest` lines.

- [ ] **Step 7: Commit `install.sh` and `Makefile` only**

```bash
git add install.sh Makefile
git commit -m "$(cat <<'EOF'
adds optional-package support to install.sh

Packages carrying a .optional marker are stowed only when named in
DOTFILES_ENABLE, and their submodule (if any) is inited on demand. Adds a
make install-work convenience target. Keeps the no-hardcoded-list rule.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Restructure the work repo (`zsh-work-config`)

Reshape the private repo so its root exposes the three overlay entry files and drop its now-redundant self-install framework. This task runs in a clone of `git@github.com:nickzelei/zsh-work-config.git`, not in the dotfiles repo.

**Files (in the work repo):**
- Create: `env.zsh`, `profile.zsh`
- Modify: `setup.zsh`
- Delete: `envvars.zsh`, `Makefile`, `Brewfile`, `bench/`
- Modify: `README.md`
- Keep: `aliases/aliases.zsh`, `etc.zsh`, `.gitignore`

**Interfaces:**
- Produces: a repo whose root, when placed at `~/.config/zsh-local`, satisfies the Task 1 hooks. `setup.zsh` derives `ZSHRC_WORK_DIR` and sources `aliases/aliases.zsh` and `etc.zsh`.

- [ ] **Step 1: Enter a clean clone of the work repo**

```bash
cd ~/.config/zsh-work
git fetch && git status --short
```
Expected: on the default branch, clean tree. (This existing clone becomes the working copy for the restructure.)

- [ ] **Step 2: Create `env.zsh` (non-interactive scope, currently a documented stub)**

Create `env.zsh`:

```zsh
# Work overlay, env scope. Sourced from the base config's env.zsh (which runs in
# ~/.zshenv) for EVERY shell, including non-interactive. Keep it cheap: no
# subprocess spawns. Put work-specific exported env and order-independent $PATH
# entries here. Empty for now; add as needed.
```

- [ ] **Step 3: Create `profile.zsh` (login scope, documented stub)**

Create `profile.zsh`:

```zsh
# Work overlay, login scope. Sourced from the base config's profile.zsh
# (~/.zprofile, after Homebrew's shellenv). Put $PATH entries here when their
# order relative to Homebrew matters. Empty for now; add as needed.
```

- [ ] **Step 4: Rewrite `setup.zsh` (interactive scope)**

Replace `setup.zsh` with:

```zsh
# Work overlay, interactive scope. Sourced LAST from the base config's setup.zsh
# (~/.zshrc), so the base has already set up compinit, history, the prompt,
# keybindings, and plugins. This only adds work-specific interactive bits.
#
# Absolute path to this file's dir, via `%x` (file being sourced); `:A` resolves
# the stow symlink, `:h` takes the directory. A distinct var from the base's
# ZSHRC_CONFIG_DIR so the two layers don't collide.
export ZSHRC_WORK_DIR="${${(%):-%x}:A:h}"

source "$ZSHRC_WORK_DIR/aliases/aliases.zsh"
source "$ZSHRC_WORK_DIR/etc.zsh"
```

(Drops the `envvars.zsh` source and the self-contained zprof harness; profiling is owned by the base config now.)

- [ ] **Step 5: Delete the redundant framework files**

```bash
git rm envvars.zsh Makefile Brewfile
git rm -r bench
```
(Work-specific brew deps are out of scope for this plan. If needed later, add an overlay Brewfile and a parent-side hook; note it and move on.)

- [ ] **Step 6: Rewrite `README.md`**

Replace `README.md` with:

```markdown
# zsh-work-config

A thin, work-specific zsh overlay. Not a standalone config: it loads *after* the
base config (`~/.config/zsh`) and only adds work-specific aliases, env, and tool
wiring. The base provides compinit, history, the prompt, keybindings, plugins.

## How it is loaded

This repo is delivered by my dotfiles as an optional stow package. It is added
there as a git submodule at `packages/work/.config/zsh-local` and stows to
`~/.config/zsh-local`. The base config sources, if present:

- `~/.config/zsh-local/env.zsh`     (every shell)
- `~/.config/zsh-local/profile.zsh` (login shells)
- `~/.config/zsh-local/setup.zsh`   (interactive shells)

Install it on a machine by enabling the package: `DOTFILES_ENABLE=work` when
running the dotfiles installer (e.g. `make install-work`).

The repo can also be cloned/symlinked straight to `~/.config/zsh-local` in any
environment and the base config will pick it up the same way.

## Layout

- `env.zsh`     - work env and PATH (non-interactive safe).
- `profile.zsh` - login-shell PATH ordering relative to Homebrew.
- `setup.zsh`   - entrypoint for interactive bits; sets `$ZSHRC_WORK_DIR`.
- `aliases/aliases.zsh` - work-specific aliases.
- `etc.zsh`     - work-specific CLI tool wiring.
```

- [ ] **Step 7: Syntax-check and commit/push**

```bash
for f in env profile setup; do zsh -n "$f.zsh" && echo "$f OK"; done
git add -A
git commit -m "$(cat <<'EOF'
restructures into a three-scope overlay loaded by the base config

Exposes env.zsh/profile.zsh/setup.zsh at the root so the dotfiles base config
can source each scope from ~/.config/zsh-local. Drops the self-install
framework (Makefile, bench, Brewfile); the parent dotfiles repo owns install.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push
cd -
```
Expected: three `OK` lines, then a successful push.

---

### Task 4: Add the work submodule and sentinel to the dotfiles repo

Wire the restructured private repo into the dotfiles repo as the optional `work` package: a submodule with `update = none` plus the `.optional` marker.

**Files (in the dotfiles repo):**
- Create (submodule): `packages/work/.config/zsh-local`
- Modify: `.gitmodules` (add the `work` submodule with `update = none`)
- Create: `packages/work/.optional`

**Interfaces:**
- Consumes: the optional-package logic from Task 2 and the restructured repo from Task 3.
- Produces: the `work` optional package that stows to `~/.config/zsh-local`.

- [ ] **Step 1: Add the submodule with an explicit name**

```bash
git submodule add --name work git@github.com:nickzelei/zsh-work-config.git packages/work/.config/zsh-local
```
Expected: clones into `packages/work/.config/zsh-local` and writes a `[submodule "work"]` stanza to `.gitmodules`.

- [ ] **Step 2: Set `update = none` on the work submodule**

```bash
git config -f .gitmodules submodule.work.update none
git config -f .gitmodules submodule.work.update
```
Expected: prints `none`. This makes the blanket `git submodule update --init --recursive` skip it on machines that do not opt in.

- [ ] **Step 3: Create the `.optional` marker**

```bash
touch packages/work/.optional
```

- [ ] **Step 4: Verify the gate end to end without enabling**

```bash
./install.sh 2>&1 | grep work
test ! -e ~/.config/zsh-local && echo "work not stowed when disabled (correct)"
```
Expected:
```
skipping optional package: work (not in DOTFILES_ENABLE)
work not stowed when disabled (correct)
```
(If `~/.config/zsh-local` still exists as the legacy real directory, the second check will not print. That gets removed in Task 6; for now confirm only the `skipping` line.)

- [ ] **Step 5: Commit**

```bash
git add .gitmodules packages/work/.optional packages/work/.config/zsh-local
git commit -m "$(cat <<'EOF'
adds the work overlay as an optional submodule package

packages/work is the zsh-work-config repo as a submodule (update = none) plus a
.optional marker, so it is only cloned and stowed when DOTFILES_ENABLE names it.
Stows to ~/.config/zsh-local where the base hooks pick it up.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Document the conventions (`CLAUDE.md`, `README.md`)

Record the optional-package convention, the activation signal, and the overlay mechanism so future edits follow them.

**Files:**
- Modify: `CLAUDE.md` (Architecture and Conventions sections)
- Modify: `README.md` (a short "Work / machine-local overlay" section; match the existing tone and structure)

**Interfaces:**
- Consumes: the finished mechanism from Tasks 1, 2, 4.
- Produces: no code; documentation only.

- [ ] **Step 1: Add an overlay/optional-package subsection to `CLAUDE.md`**

Under the Architecture section, after the "Plugins are git submodules" paragraph, add:

```markdown
**Machine-local overlays (optional packages).** Each of the three zsh base files
ends with a guarded `[[ -f ~/.config/zsh-local/<scope>.zsh ]] && source ...`, so a
machine-local overlay at `~/.config/zsh-local` is sourced in the matching scope and
absent overlays no-op. A package is **optional** if it contains a `.optional`
marker at its root; `install.sh` stows optional packages only when their name
appears in the `DOTFILES_ENABLE` env var (space/comma-separated). The work overlay
is such a package: `packages/work/.config/zsh-local` is the private `zsh-work-config`
repo as a submodule with `update = none` (so the blanket submodule init skips it),
stowing to `~/.config/zsh-local`. Enable it with `DOTFILES_ENABLE=work ./install.sh`
or `make install-work`. The `.optional` marker is kept out of `$HOME` via stow's
`--ignore`.
```

- [ ] **Step 2: Add a Conventions bullet to `CLAUDE.md`**

In the Conventions list, add:

```markdown
- Optional packages carry a `.optional` marker and a submodule with `update = none`; never stow or clone them unless `DOTFILES_ENABLE` names them. Keep the no-hardcoded-list rule: discover by glob + marker, not by name in the script.
```

- [ ] **Step 3: Add a `### Machine-local overlays` section to `README.md`**

Insert this section in `README.md` immediately before the `## Motivation` heading (after the `### Adding another tool` section), matching the README's existing voice:

```markdown
### Machine-local overlays (e.g. work)

Each of the three zsh startup files ends with a guarded source of a machine-local
overlay, so config that only belongs on *some* machines lives outside this repo's
history but still loads cleanly:

```console
[[ -f ~/.config/zsh-local/env.zsh ]]     && source ~/.config/zsh-local/env.zsh
[[ -f ~/.config/zsh-local/profile.zsh ]] && source ~/.config/zsh-local/profile.zsh
[[ -f ~/.config/zsh-local/setup.zsh ]]   && source ~/.config/zsh-local/setup.zsh
```

Nothing there on most machines, so the guards no-op. My work config is a separate
private repo wired in as an *optional* package: `packages/work` carries a
`.optional` marker and a submodule (with `update = none`, so it's never cloned by
default) at `packages/work/.config/zsh-local`, which stows to `~/.config/zsh-local`.

Optional packages are stowed only when named in the `DOTFILES_ENABLE` env var
(space/comma-separated). So a personal machine ignores `work` entirely — never
cloned, never stowed, never an error — while a work machine opts in:

```console
DOTFILES_ENABLE=work ./install.sh   # or: make install-work
```

Because the hooks only care about the path, you can also clone or symlink any
overlay straight to `~/.config/zsh-local` and it loads the same way.
```

- [ ] **Step 4: Verify and commit**

```bash
git add CLAUDE.md README.md
git commit -m "$(cat <<'EOF'
documents the machine-local overlay and optional-package conventions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Activate on the work laptop and migrate off the legacy clone

End-to-end activation: remove the old hardcoded source line, stow with the overlay enabled, verify the work config loads, then delete the legacy clone. This task changes local machine state, not the repo.

**Files:**
- Modify: `~/.zshrc` (remove the legacy `zsh-work` source line)
- Remove: `~/.config/zsh-work` (legacy clone, after verification)

**Interfaces:**
- Consumes: everything from Tasks 1 through 5.

- [ ] **Step 1: Remove the legacy hardcoded source line from `~/.zshrc`**

The line to remove (from `~/.zshrc`, not a tracked file):
```zsh
[[ -f /Users/nick/.config/zsh-work/setup.zsh ]] && source /Users/nick/.config/zsh-work/setup.zsh
```
Verify it is gone:
```bash
grep -n zsh-work ~/.zshrc || echo "legacy line removed"
```
Expected: `legacy line removed`.

- [ ] **Step 2: Clear the legacy real directory so stow can link the overlay**

If `~/.config/zsh-local` exists as a real directory (it should not yet, but check), move it aside. Then install with the work overlay enabled:
```bash
ls -ld ~/.config/zsh-local 2>/dev/null || echo "no pre-existing zsh-local"
make install-work
```
Expected: `install.sh` inits the `work` submodule and stows it. `~/.config/zsh-local` becomes a symlink into `packages/work/.config/zsh-local`.

- [ ] **Step 3: Verify the overlay is linked and sourced**

```bash
readlink ~/.config/zsh-local && test -f ~/.config/zsh-local/setup.zsh && echo "overlay linked"
zsh -ic 'alias tg; whence av; echo overlay-ok'
```
Expected: `overlay linked`, then the `tg` alias definition, the `av` location, and `overlay-ok`, with no errors. (Confirms a known work alias and the `aws-vault` alias resolve, i.e. the overlay's `setup.zsh` ran.)

- [ ] **Step 4: Confirm idempotence and a clean shell**

```bash
make install-work >/dev/null && echo "reinstall idempotent"
exec zsh
```
Expected: `reinstall idempotent`; the new shell starts clean with the work prompt/aliases.

- [ ] **Step 5: Remove the legacy clone**

Once verified:
```bash
rm -rf ~/.config/zsh-work
test ! -e ~/.config/zsh-work && echo "legacy clone removed"
```
Expected: `legacy clone removed`.

- [ ] **Step 6: Verify the personal-machine path still works (regression)**

Confirm a disabled run skips and unstows the overlay cleanly (simulating a personal machine), then re-enable:
```bash
./install.sh 2>&1 | grep work   # expect: skipping optional package: work ...
make install-work >/dev/null && echo "re-enabled"
```
Expected: the `skipping` line on the disabled run, then `re-enabled`. (No commit; this task is machine state only.)

---

## Notes

- **Updating the overlay:** the `work` submodule has `update = none`, so `make update` (which runs `git submodule update --remote --merge`) will not bump it. To ship a work change: commit and push in `zsh-work-config`, then in the dotfiles repo run `git submodule update --remote -- packages/work/.config/zsh-local`, commit the new pointer, and push.
- **Out of scope:** work-specific Homebrew deps (the old overlay `Brewfile`). If needed later, add an overlay `Brewfile` and a parent-side `brew bundle` hook for enabled optional packages.
- **Caveat:** the public dotfiles repo carries a `.gitmodules` entry pointing at a private URL. Cloning is fine; `update = none` plus the `DOTFILES_ENABLE` gate keep it from being fetched unless explicitly enabled.
