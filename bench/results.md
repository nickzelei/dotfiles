# zsh init benchmark

Append a row with `bench/bench.zsh`. Measures `zsh -i -c exit` (ms, lower is better).

| Date | Commit | Mean [ms] | Min [ms] | Max [ms] |
|:---|:---|---:|---:|---:|
| 2026-06-08 20:42 | 0f47e1e | 87.6±3.1 | 84.4 | 93.7 |
| 2026-06-10 10:41 | ef6727f | 82.1±1.3 | 79.7 | 84.9 |
| 2026-06-15 18:15 | bbe5d97 (dirty) | 83.0±1.1 | 80.8 | 86.0 |
| 2026-06-15 18:16 | 4d0323f | 78.6±0.9 | 77.3 | 80.6 |
| 2026-06-15 18:23 | 0c9abb5 | 77.8±1.3 | 75.8 | 82.5 |
