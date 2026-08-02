# Example: a dev shell with a sandboxed Claude Code binary that can use Nix
# (nix build/run/develop) inside the sandbox.

# Usage:
#   export CLAUDE_CODE_OAUTH_TOKEN="<your_token_here>"
#   nix-shell shells/claude-nix.shell.nix
let
  pkgs = import <nixpkgs> {
    config.allowUnfreePredicate = pkg: pkgs.lib.getName pkg == "claude-code";
  };
  agent-sandbox =
    import (fetchTarball "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz")
      {
        pkgs = pkgs;
      };
  claude-sandboxed = agent-sandbox.mkSandbox {
    pkg = pkgs.claude-code;
    binName = "claude";
    outName = "claude-sandboxed";
    allowedPackages = agent-sandbox.commonTools;
    allowNix = true;
    rwDirs = [
      "$HOME/.claude"
      # Client state. Without these, every invocation re-fetches the
      # flake registry and re-downloads tarballs.
      "$HOME/.cache/nix"
      "$HOME/.config/nix"
      "$HOME/.local/share/nix"
    ];
    # Bind your host gitconfig read-only for git identity (recommended).
    # Set user.name / user.email on the host first, then uncomment:
    # roFiles = [ "$HOME/.config/git/config" ];
    # (Alternative: set GIT_AUTHOR_* / GIT_COMMITTER_* in env. See README.)
    env = {
      CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
      GITHUB_TOKEN = "$GITHUB_TOKEN";
      CLAUDE_CONFIG_DIR = "$HOME/.claude";
      # Enable the flake CLI here
      NIX_CONFIG = "experimental-features = nix-command flakes";
    };
    allowedDomains = {
      "anthropic.com" = "*";
      "claude.com" = "*";
      "github.com" = [
        "GET"
        "HEAD"
      ];
      "raw.githubusercontent.com" = [
        "GET"
        "HEAD"
      ];
      "api.github.com" = [
        "GET"
        "HEAD"
      ];
      "channels.nixos.org" = [
        "GET"
        "HEAD"
      ];
      "cache.nixos.org" = [
        "GET"
        "HEAD"
      ];
    };
  };
in
pkgs.mkShell { packages = [ claude-sandboxed ]; }
