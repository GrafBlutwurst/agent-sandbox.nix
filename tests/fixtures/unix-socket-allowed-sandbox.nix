# Test fixture: sandbox with allowUnixSockets = true and UNIX-socket-capable
# clients (socat, python3) in PATH.
#
# `open` selects the network mode, because the flag has to hold up under both
# mechanisms: in filtered mode (allowedDomains set, the default here) the
# AF_UNIX allows are additive over seatbelt's deny-default; in open mode they
# must outrank the blanket (deny network-outbound (remote unix-socket)) by
# last-match. On Linux the mode makes no difference to AF_UNIX — the flag
# controls whether the seccomp filter is applied at all — but building both
# keeps the fixture honest on either platform.
{ pkgs ? import ../pinned-nixpkgs.nix { }, open ? false }:
let
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox ({
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash";
  allowedPackages = [ pkgs.coreutils pkgs.socat pkgs.python3Minimal ];
  allowUnixSockets = true;
} // (if open then { } else { allowedDomains = [ "anthropic.com" ]; }))
