# Example: a dev shell with a sandboxed Copilot binary.
# Copy this into your project and adjust as needed.
#
# Usage:
#   export GITHUB_TOKEN="your_token_here"
#   nix-shell shells/copilot.shell.nix
let
  pkgs = import <nixpkgs> {
    config.allowUnfreePredicate = pkg: pkgs.lib.getName pkg == "github-copilot-cli";
  };
  agent-sandbox =
    import (fetchTarball "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz")
      {
        pkgs = pkgs;
      };
  copilot-sandboxed = agent-sandbox.mkSandbox {
    pkg = pkgs.github-copilot-cli;
    binName = "copilot";
    outName = "copilot-sandboxed";
    allowedPackages = agent-sandbox.commonTools;
    rwDirs = [
      "$HOME/.config/github-copilot"
      "$HOME/.copilot"
    ];
    rwFiles = [ ];
    # Bind your host gitconfig read-only for git identity (recommended).
    # Set user.name / user.email on the host first, then uncomment:
    # roFiles = [ "$HOME/.config/git/config" ];
    # (Alternative: set GIT_AUTHOR_* / GIT_COMMITTER_* in env. See README.)
    env = {
      GITHUB_TOKEN = "$GITHUB_TOKEN";
    };
    allowedDomains = {
      "githubcopilot.com" = "*";
      "github.com" = "*";
      "githubusercontent.com" = [
        "GET"
        "HEAD"
      ];
    };

  };

in
pkgs.mkShell { packages = [ copilot-sandboxed ]; }
