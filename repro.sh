#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
BIN_PATH="$BUILD_DIR/rocksdb-cpp-repro"
DB_PATH="$ROOT_DIR/db"

RUNS="${RUNS:-30}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-10}"
READY_GRACE_SECONDS="${READY_GRACE_SECONDS:-1}"
SHUTDOWN_MODE="${SHUTDOWN_MODE:-kill}"
REQUIRE_SIGTRAP_MIN="${REQUIRE_SIGTRAP_MIN:-0}"
REQUIRE_SIGTRAP_MAX="${REQUIRE_SIGTRAP_MAX:-}"

echo "[repro] root: $ROOT_DIR"
echo "[repro] runs: $RUNS"
echo "[repro] start-timeout-seconds: $START_TIMEOUT_SECONDS"
echo "[repro] shutdown-mode: $SHUTDOWN_MODE"
echo "[repro] require-sigtrap-min: $REQUIRE_SIGTRAP_MIN"
echo "[repro] require-sigtrap-max: ${REQUIRE_SIGTRAP_MAX:-<none>}"

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G Ninja
cmake --build "$BUILD_DIR"

echo "[repro] clearing database directory before first run"
rm -rf "$DB_PATH"
mkdir -p "$DB_PATH"

ok_count=0
sigtrap_count=0
timeout_count=0
other_fail_count=0
killed_count=0

WAIT_CODE=0

wait_status() {
	local pid="$1"
	set +e
	wait "$pid"
	WAIT_CODE=$?
	set -e
}

for run in $(seq 1 "$RUNS"); do
	log_path="$ROOT_DIR/run-$run.log"
	: >"$log_path"

	status=0
	started=0

	REPRO_DB_PATH="$DB_PATH" "$BIN_PATH" >"$log_path" 2>&1 &
	pid=$!

	for _ in $(seq 1 $((START_TIMEOUT_SECONDS * 10))); do
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi

		if grep -q "READY" "$log_path"; then
			started=1
			break
		fi

		sleep 0.1
	done

	if kill -0 "$pid" 2>/dev/null; then
		if [[ "$started" -eq 1 ]]; then
			sleep "$READY_GRACE_SECONDS"
			if [[ "$SHUTDOWN_MODE" == "graceful" ]]; then
				kill -INT "$pid" 2>/dev/null || true
			else
				kill -KILL "$pid" 2>/dev/null || true
			fi
			wait_status "$pid"
			status="$WAIT_CODE"
		else
			kill -KILL "$pid" 2>/dev/null || true
			wait_status "$pid"
			status="$WAIT_CODE"
		fi
	else
		wait_status "$pid"
		status="$WAIT_CODE"
	fi

	case "$status" in
	0)
		ok_count=$((ok_count + 1))
		result="ok"
		;;
	133)
		sigtrap_count=$((sigtrap_count + 1))
		result="sigtrap"
		;;
	137)
		if [[ "$SHUTDOWN_MODE" == "kill" && "$started" -eq 1 ]]; then
			killed_count=$((killed_count + 1))
			result="killed"
		else
			timeout_count=$((timeout_count + 1))
			result="timeout"
		fi
		;;
	*)
		other_fail_count=$((other_fail_count + 1))
		result="exit-$status"
		;;
	esac

	echo "RUN $run: result=$result status=$status started=$started log=$log_path"

	if [[ "$status" -ne 0 ]]; then
		echo "[repro] tail(run=$run)"
		tail -n 8 "$log_path" || true
	fi
done

echo
echo "[repro] summary"
echo "  ok=$ok_count"
echo "  sigtrap=$sigtrap_count"
echo "  killed=$killed_count"
echo "  timeout=$timeout_count"
echo "  other_fail=$other_fail_count"

if ((sigtrap_count < REQUIRE_SIGTRAP_MIN)); then
	echo "[repro] expected at least $REQUIRE_SIGTRAP_MIN sigtrap events, got $sigtrap_count"
	exit 2
fi

if [[ -n "$REQUIRE_SIGTRAP_MAX" ]] && ((sigtrap_count > REQUIRE_SIGTRAP_MAX)); then
	echo "[repro] expected at most $REQUIRE_SIGTRAP_MAX sigtrap events, got $sigtrap_count"
	exit 3
fi
