#!/usr/bin/env zsh
#
# Benchmark zsh interactive startup time and log the result over time.
#
# Measures `zsh -i -c true` — a full interactive init that sources setup.zsh and
# exits immediately. Lower is better. Uses hyperfine for warmups + statistics,
# so it's the shell-init equivalent of `go test -bench`.
#
# Usage:
#   bench/bench.zsh            run, print result, append a row to results.md
#   bench/bench.zsh --no-log   run and print only (don't touch results.md)
#
# To see WHAT is slow (per-component profile, the `pprof` equivalent), run:
#   ZSH_PROFILE=1 zsh -i -c exit

emulate -L zsh
set -e

if ! command -v hyperfine >/dev/null 2>&1; then
  print -u2 "hyperfine not found — install deps with: brew bundle"
  exit 1
fi

log=1
[[ "$1" == "--no-log" ]] && log=0

here="${${(%):-%x}:A:h}"
results="$here/results.md"

# Identify the config state being measured.
sha="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || print unknown)"
git -C "$here" diff --quiet 2>/dev/null || sha+=" (dirty)"
stamp="$(date '+%Y-%m-%d %H:%M')"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# --shell=none: run `zsh -i -c true` directly instead of via an extra wrapper
# shell. --warmup primes the filesystem/compinit caches so we measure
# steady-state init rather than a cold first run. Run `true` (not `exit`) so the
# measured command's status is deterministically 0 and doesn't depend on whatever
# the rc's last statement happens to leave in $?.
hyperfine --warmup 3 --shell=none --export-markdown "$tmp" 'zsh -i -c true'

(( log )) || exit 0

# Pull the numbers out of hyperfine's markdown table. The data row looks like:
#   | `zsh -i -c exit` | 142.3 ± 4.1 | 137.2 | 151.8 | 1.00 |
row=("${(@s:|:)$(grep '`zsh' "$tmp")}")
mean="${row[3]//[[:space:]]/}"   # e.g. 142.3±4.1
min="${row[4]//[[:space:]]/}"
max="${row[5]//[[:space:]]/}"

if [[ ! -f "$results" ]]; then
  {
    print "# zsh init benchmark"
    print ""
    print "Append a row with \`bench/bench.zsh\`. Measures \`zsh -i -c exit\` (ms, lower is better)."
    print ""
    print "| Date | Commit | Mean [ms] | Min [ms] | Max [ms] |"
    print "|:---|:---|---:|---:|---:|"
  } > "$results"
fi

print "| $stamp | $sha | $mean | $min | $max |" >> "$results"
print "\nLogged to ${results/#$HOME/~}"
