# RocksDB C++ Startup Crash Repro

Minimal C++ repro for startup failures while opening a local RocksDB instance.

The test repeatedly reopens one DB path with `OptimisticTransactionDB::Open`,
writes data,
prints `READY`,
then force-stops the process.

## Run

| Environment | Command |
| --- | --- |
| Nix | `nix develop --command ./repro.sh` |
| Non-Nix | `./repro.sh` |

## Output classes

| Class | Meaning |
| --- | --- |
| `ok` | Clean exit |
| `sigtrap` | Exit status `133` |
| `timeout` | `READY` not reached before timeout |
| `other_fail` | Any other non-zero failure |

## Common knobs

| Variable | Default | Purpose |
| --- | --- | --- |
| `RUNS` | `60` | Number of restart cycles |
| `START_TIMEOUT_SECONDS` | `10` | Max wait for `READY` |
| `READY_GRACE_SECONDS` | `0.2` | Delay before shutdown after `READY` |
| `SHUTDOWN_MODE` | `kill` | `kill` or `graceful` shutdown |
| `REPRO_WRITE_COUNT` | `20000` | Writes before `READY` |

## Reproduction matrix (macOS arm64)

| nixpkgs set | RocksDB source/version | Outcome |
| --- | --- | --- |
| unstable | packaged `10.9.1` | reproduces (`sigtrap` after first kill cycle) |
| unstable | local checkout `11.1.0` | reproduces (`sigtrap` after first kill cycle) |
| `24.11` | packaged `9.7.3` | no repro (`sigtrap=0`, `killed` only) |
| `24.11` | local checkout `11.1.0` | no repro (`sigtrap=0`, `killed` only) |

## Dependency/toolchain delta (unstable vs 24.11)

| Component | unstable | `24.11` |
| --- | --- | --- |
| Clang | `21.1.8` | `16.0.6` |
| Packaged RocksDB | `10.9.1` | `9.7.3` |
| Snappy | `1.2.2` | `1.2.1` |
| Zstd | `1.5.7` | `1.5.6` |

## Crash context (macOS)

| Source | Observation |
| --- | --- |
| Local runs (`RUNS=60`, `SHUTDOWN_MODE=kill`) | `sigtrap=59` after the first forced kill |
| `.ips` fault stacks | Recovery/open path includes `DBImpl::ProcessLogFiles`, `DBImpl::WriteLevel0TableForRecovery`, `TableCache::FindTable` |

## CI snapshot

Workflow: `Repro (Nix Devshell)`

| Runner | Result |
| --- | --- |
| `macos-14` (`darwin-aarch64`) | First run reaches `READY`, subsequent runs fail before `READY` |
| `ubuntu-24.04` (`linux-x86_64`) | All runs reach `READY` |

## Artifacts

| Path | Description |
| --- | --- |
| `run-<n>.log` | Per-run log |
| `db/` | RocksDB files used across restarts |
