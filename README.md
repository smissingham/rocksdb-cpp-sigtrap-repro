# RocksDB C++ Startup Crash Repro

Minimal C++ repro for intermittent process death while opening a local RocksDB instance.

This mirrors the SurrealDB-based reproducer,
but removes SurrealDB and exercises RocksDB directly via `OptimisticTransactionDB::Open`.

## What this does

- Reuses one local DB path across repeated process start/stop cycles.
- Opens RocksDB in each run,
  performs a write burst,
  prints `READY`,
  then the runner stops the process (default `SIGKILL` for stronger recovery-path stress).
- Classifies per-run outcomes:
  - `ok` (clean exit)
  - `sigtrap` (status `133`)
  - `timeout`
  - `other_fail`

## Local run (Nix)

```bash
nix develop --command ./repro.sh
```

## Local run (without Nix)

Requirements:

- CMake
- Ninja
- pkg-config
- RocksDB development headers/libs

Then run:

```bash
./repro.sh
```

## Useful knobs

```bash
RUNS=100 START_TIMEOUT_SECONDS=10 READY_GRACE_SECONDS=1 ./repro.sh

RUNS=100 SHUTDOWN_MODE=graceful ./repro.sh

REPRO_WRITE_COUNT=50000 RUNS=60 ./repro.sh

REQUIRE_SIGTRAP_MIN=1 RUNS=20 ./repro.sh
```

## Artifacts

The script writes:

- `run-<n>.log` per iteration
- `db/` for RocksDB files

## Current local result (macOS arm64)

Using:

```bash
RUNS=60 READY_GRACE_SECONDS=0.2 SHUTDOWN_MODE=kill nix develop --command ./repro.sh
```

Observed:

- `sigtrap=59` (after first forced-kill run)
- faulting stacks in macOS `.ips` reports consistently show RocksDB recovery paths,
  including `DBImpl::ProcessLogFiles`,
  `DBImpl::WriteLevel0TableForRecovery`,
  and `TableCache::FindTable`.

## Reproduction matrix (macOS arm64)

- `nixpkgs unstable` + packaged RocksDB `10.9.1`:
  reproduces (`sigtrap` after first kill cycle).
- `nixpkgs unstable` + local RocksDB `11.1.0`:
  reproduces (`sigtrap` after first kill cycle).
- `nixpkgs 24.11` + packaged RocksDB `9.7.3`:
  does not reproduce (`killed` only, `sigtrap=0`).
- `nixpkgs 24.11` + local RocksDB `11.1.0`:
  does not reproduce (`killed` only, `sigtrap=0`).

Observed toolchain/dependency deltas between those two nixpkgs sets:

- Clang: unstable `21.1.8` vs `24.11` `16.0.6`
- RocksDB package: unstable `10.9.1` vs `24.11` `9.7.3`
- Snappy: unstable `1.2.2` vs `24.11` `1.2.1`
- Zstd: unstable `1.5.7` vs `24.11` `1.5.6`

## CI result (GitHub Actions)

Workflow: `Repro (Nix Devshell)`

- `macos-14` (`darwin-aarch64`): only the first run reaches `READY`,
  subsequent runs fail before `READY`.
- `ubuntu-24.04` (`linux-x86_64`): all runs reach `READY`.

You can inspect the latest run with:

```bash
gh run list --repo smissingham/rocksdb-cpp-sigtrap-repro --workflow "Repro (Nix Devshell)" --limit 1
gh run watch <run-id> --repo smissingham/rocksdb-cpp-sigtrap-repro
```
