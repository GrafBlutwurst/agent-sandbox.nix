#!/usr/bin/env bash
# Test: with allowUnixSockets = true, AF_UNIX sockets work inside the
# directories the sandbox can write (here: the launch directory), and host
# sockets outside those directories stay unreachable.
#
# Both network modes are exercised, because the allows work by different
# mechanisms: in filtered mode they are additive over seatbelt's deny-default;
# in open mode they must outrank the blanket
# (deny network-outbound (remote unix-socket)) by last-match. The flag-off
# behaviour is covered by test-unix-socket-egress-denied.sh.
#
# A third variant declares a read-only directory nested inside the launch
# dir, and asserts the socket scope excludes it: the enclosing subpath allow
# must not let the sandbox bind or connect there (the issue #84 interaction —
# its file-write fix would not cover socket operations).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED_FILTERED=$(build_fixture unix-socket-allowed-sandbox.nix)
SANDBOXED_OPEN=$(build_fixture unix-socket-allowed-sandbox.nix --arg open true)
SANDBOXED_NESTED=$(build_fixture unix-socket-allowed-sandbox.nix --arg nestedRoDir true)

# Host-side python3 from nixpkgs, for the UNIX-socket listeners below.
# /usr/bin/python3 on macOS is a Command Line Tools stub that isn't safe
# to depend on in CI; nix-provided python3 is reproducible.
HOST_PYTHON3=$(build_host_pkg python3Minimal)/bin/python3

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/unix-socket-allowed.XXXXXX")
# The declared "$PWD/nested-ro" roDir must exist before any nested launch.
mkdir -p "$TESTDIR/nested-ro"

# Launch from TESTDIR so the launch directory — the CWD the seatbelt scope
# covers — is a scratch directory rather than the repo.
run_filtered() {
	(cd "$TESTDIR" && "$SANDBOXED_FILTERED/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
}
run_open() {
	(cd "$TESTDIR" && "$SANDBOXED_OPEN/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
}
run_nested() {
	(cd "$TESTDIR" && "$SANDBOXED_NESTED/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
}

# bind(), listen(), connect() and a byte each way, all on a socket in the CWD.
# One process plays both ends: the assertion is about the seatbelt rules, not
# about concurrency.
IN_CWD_CHECK='python3 -c "
import socket, os
path = \"check.sock\"
try:
    os.unlink(path)
except FileNotFoundError:
    pass
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(1)
cli = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
cli.connect(path)
conn, _ = srv.accept()
cli.sendall(b\"x\")
assert conn.recv(1) == b\"x\"
"'

LISTENER_PIDS=""
cleanup() {
	if [ -n "$LISTENER_PIDS" ]; then
		# shellcheck disable=SC2086 # word-splitting the pid list is the point
		kill $LISTENER_PIDS 2>/dev/null || true
		# shellcheck disable=SC2086
		wait $LISTENER_PIDS 2>/dev/null || true
	fi
	rm -rf "$SOCK_DIR" "$TESTDIR"
}
trap cleanup EXIT

# start_listener <socket-path> <logfile> — a host-side (unsandboxed)
# UNIX-socket listener that actually accept()s, so a successful connect()
# would observably complete, not just queue in the kernel backlog.
start_listener() {
	local sock_path="$1" logfile="$2"
	"$HOST_PYTHON3" -c '
import socket, sys, signal, threading
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(128)
sys.stdout.write("READY\n"); sys.stdout.flush()
def loop():
    while True:
        try:
            c, _ = s.accept()
            c.close()
        except Exception:
            break
threading.Thread(target=loop, daemon=True).start()
signal.pause()
' "$sock_path" >"$logfile" 2>&1 &
	LISTENER_PIDS="$LISTENER_PIDS $!"
	local _i
	for _i in $(seq 1 50); do
		[ -S "$sock_path" ] && return 0
		sleep 0.1
	done
	echo "ERROR: host listener never bound $sock_path" >&2
	cat "$logfile" >&2 || true
	return 1
}

# Host listener OUTSIDE the writable-dir scope. /private/tmp is deliberate:
# its directory is in the seatbelt file allow set (file-read/write for
# /private/tmp) but not in the unix-socket scope, so a successful connect()
# would mean the socket rules leak beyond CWD + rwDirs.
SOCK_DIR=$(mktemp -d "/private/tmp/sandbox-unix-allowed.XXXXXX")
SOCK_PATH="$SOCK_DIR/listener.sock"
start_listener "$SOCK_PATH" "$TESTDIR/listener-outside.log"

# Host listener INSIDE the nested roDir, for the nested-scope assertions.
NESTED_SOCK="$TESTDIR/nested-ro/listener.sock"
start_listener "$NESTED_SOCK" "$TESTDIR/listener-nested.log"

echo "=== UNIX sockets allowed in writable dirs (Darwin) ==="
echo "TESTDIR=$TESTDIR"
echo "SOCK_PATH=$SOCK_PATH"
echo

expect_ok run_filtered "socat binary is available inside the sandbox" "command -v socat"

expect_ok run_filtered "filtered: bind+connect a socket in CWD" "$IN_CWD_CHECK"
expect_ok run_open "open: bind+connect a socket in CWD" "$IN_CWD_CHECK"

# The scope must not leak: a host socket outside CWD + rwDirs stays denied
# even with the flag on. printf sends a byte so socat really connect()s.
expect_fail run_filtered "filtered: cannot connect() to host socket outside scope" \
	"printf x | socat -t 1 - UNIX-CONNECT:'$SOCK_PATH'"
expect_fail run_open "open: cannot connect() to host socket outside scope" \
	"printf x | socat -t 1 - UNIX-CONNECT:'$SOCK_PATH'"

# A declared read-only directory nested inside the CWD is denied back out of
# the enclosing subpath allow — while the rest of the CWD keeps working.
expect_ok run_nested "nested roDir declared: bind+connect in CWD still works" "$IN_CWD_CHECK"
expect_fail run_nested "cannot bind() inside a nested roDir" 'python3 -c "
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(\"nested-ro/deny.sock\")
"'
expect_fail run_nested "cannot connect() to a socket inside a nested roDir" \
	"printf x | socat -t 1 - UNIX-CONNECT:'$NESTED_SOCK'"

print_results
exit_status
