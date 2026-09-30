#!/usr/bin/env bash
#
# Benchmark a COLD `install.sh` — the devbox bootstrap path, not the no-op rerun.
#
# Runs the real installer against a throwaway $HOME and throwaway mise dirs, so
# every submodule clone and tool download happens for real and nothing on this
# machine is touched. Prints install.sh's own per-phase breakdown.
#
# Usage:
#   bench/install-bench.sh                 one cold run
#   bench/install-bench.sh -n 3            three cold runs
#   bench/install-bench.sh --keep-tools    reuse the tool cache between runs
#                                          (isolates clone+stow+resolve from downloads)
#   bench/install-bench.sh -- KEY=VAL ...  extra env for the run, e.g. DOTFILES_ENABLE=work
#
# To measure the box that is actually slow, skip this and time the real thing
# in place:  DOTFILES_TIMING=1 ./install.sh
set -euo pipefail

runs=1 keep_tools=0 extra_env=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n) runs="$2"; shift 2 ;;
    --keep-tools) keep_tools=1; shift ;;
    --) shift; extra_env=("$@"); break ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The sandbox gets a throwaway $HOME, which hides gh's keyring token and drops
# mise to anonymous GitHub API calls — 60/hr per IP, which a handful of cold runs
# will drain, poisoning both the benchmark and every other tool on this network.
# Pass a token through explicitly. Set DOTFILES_BENCH_ANON=1 to measure the
# genuinely unauthenticated path (what a devbox with no token actually hits).
bench_token=""
if [ "${DOTFILES_BENCH_ANON:-0}" = 0 ]; then
  bench_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -z "$bench_token" ] && command -v gh >/dev/null 2>&1; then
    bench_token="$(gh auth token 2>/dev/null || true)"
  fi
  [ -n "$bench_token" ] || echo "warning: no GitHub token; runs will be rate-limited (60/hr)" >&2
fi
root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bench.XXXXXX")"
trap 'rm -rf "$root"' EXIT

# Snapshot the WORKING TREE, not HEAD — the point is to measure edits before
# committing them. Dropping .git/modules along the way means `submodule --init`
# has no local object cache to short-circuit through, so each run re-fetches the
# plugins over the network the way a real bootstrap does.
src="$root/src"
mkdir -p "$src"
tar -C "$repo" -cf - --exclude='./.git/modules' . | tar -C "$src" -xf -
while read -r _ path; do
  if [ -n "$path" ]; then rm -rf "$src/$path"; fi
done < <(git -C "$repo" config -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)

echo "cold install.sh x$runs  (sandbox: $root)"
if [ "${#extra_env[@]}" -gt 0 ]; then
  echo "env: ${extra_env[*]}"
fi

for i in $(seq 1 "$runs"); do
  home="$root/home$i"
  mkdir -p "$home"
  # Fresh copy per run so submodules are re-fetched every time. --keep-tools only
  # shares the mise data/cache dirs, which is what makes downloads free on reruns.
  rm -rf "$root/run"; cp -R "$src" "$root/run"
  if [ "$keep_tools" = 1 ]; then
    mdata="$root/shared-data"; mcache="$root/shared-cache"
  else
    mdata="$home/.local/share/mise"; mcache="$home/.cache/mise"
  fi

  echo "--- run $i ---"
  env -i \
    PATH="$PATH" TERM="${TERM:-dumb}" LANG="${LANG:-C}" \
    HOME="$home" \
    MISE_DATA_DIR="$mdata" MISE_CACHE_DIR="$mcache" MISE_STATE_DIR="$home/.local/state/mise" \
    MISE_CONFIG_DIR="$home/.config/mise" \
    DOTFILES_TIMING=1 DOTFILES_ASYNC_TOOLS=0 \
    ${bench_token:+GITHUB_TOKEN="$bench_token"} \
    ${extra_env[@]+"${extra_env[@]}"} \
    bash "$root/run/install.sh" 2>&1 | grep -E '^(timing|  [a-z_-]+ +[0-9]+ ms|  TOTAL|warning|note)' 
done
