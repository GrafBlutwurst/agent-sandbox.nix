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
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED_FILTERED=$(build_fixture unix-socket-allowed-sandbox.nix)
SANDBOXED_OPEN=$(build_fixture unix-socket-allowed-sandbox.nix --arg open true)

# Host-side python3 from nixpkgs, for the UNIX-socket listener below.
# /usr/bin/python3 on macOS is a Command Line Tools stub that isn't safe
# to depend on in CI; nix-provided python3 is reproducible.
HOST_PYTHON3=$(build_host_pkg python3Minimal)/bin/python3

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/unix-socket-allowed.XXXXXX")

# Launch from TESTDIR so the launch directory — the CWD the seatbelt scope
# covers — is a scratch directory rather than the repo.
run_filtered() {
	(cd "$TESTDIR" && "$SANDBOXED_FILTERED/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
}
run_open() {
	(cd "$TESTDIR" && "$SANDBOXED_OPEN/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
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

# Host listener OUTSIDE the writable-dir scope. /private/tmp is deliberate:
# its directory is in the seatbelt file allow set (file-read/write for
# /private/tmp) but not in the unix-socket scope, so a successful connect()
# would mean the socket rules leak beyond CWD + rwDirs.
SOCK_DIR=$(mktemp -d "/private/tmp/sandbox-unix-allowed.XXXXXX")
SOCK_PATH="$SOCK_DIR/listener.sock"

LISTENER_PID=""
cleanup() {
	if [ -n "$LISTENER_PID" ]; then
		kill "$LISTENER_PID" 2>/dev/null || true
		wait "$LISTENER_PID" 2>/dev/null || true
	fi
	rm -rf "$SOCK_DIR" "$TESTDIR"
}
trap cleanup EXIT

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
' "$SOCK_PATH" >"$TESTDIR/listener.log" 2>&1 &
LISTENER_PID=$!

for _ in $(seq 1 50); do
	[ -S "$SOCK_PATH" ] && break
	sleep 0.1
done
if [ ! -S "$SOCK_PATH" ]; then
	echo "ERROR: host listener never bound $SOCK_PATH" >&2
	exit 1
fi

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

print_results
exit_status
