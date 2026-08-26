#!/usr/bin/env bash
# Test: with allowUnixSockets = true, no seccomp filter is applied on Linux,
# so AF_UNIX sockets work wherever the mount namespace makes their path
# visible and writable — here, the launch directory. The default (flag off)
# is covered by test-unix-socket-default-deny.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(build_fixture unix-socket-allowed-sandbox.nix)

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/unix-socket-allowed.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT

# Launch from TESTDIR so the socket lands in a scratch launch directory
# rather than the repo.
run() {
	(cd "$TESTDIR" && "$SANDBOXED/bin/sandboxed-bash" --norc --noprofile -c "$1") >/dev/null 2>&1
}

echo "=== UNIX sockets allowed with allowUnixSockets (Linux) ==="
echo

expect_ok run "python3 is available inside the sandbox" "command -v python3"

# bind(), listen(), connect() and a byte each way, all on a socket in the
# CWD. One process plays both ends: the assertion is about the seccomp
# filter's absence, not about concurrency.
expect_ok run "bind+connect a socket in CWD" 'python3 -c "
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

expect_ok run "socketpair(AF_UNIX) works" 'python3 -c "
import socket
a, b = socket.socketpair()
a.sendall(b\"x\")
assert b.recv(1) == b\"x\"
"'

print_results
exit_status
