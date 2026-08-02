{
  inputs.agent-sandbox.url = "github:archie-judd/agent-sandbox.nix";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, agent-sandbox, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            system = system;
            config = {
              allowUnfreePredicate = pkg: pkgs.lib.getName pkg == "claude-code";
            };
          };
          sbx = agent-sandbox.lib.${system};
          claude-sandboxed = sbx.mkSandbox {
            pkg = pkgs.claude-code;
            binName = "claude";
            outName = "claude-sandboxed"; # or whatever alias you'd like
            allowedPackages = sbx.commonTools;
            rwDirs = [ "$HOME/.claude" ];
            rwFiles = [ ];
            # Bind your host gitconfig read-only for git identity (recommended).
            # Set user.name / user.email on the host first, then uncomment:
            # roFiles = [ "$HOME/.config/git/config" ];
            # (Alternative: set GIT_AUTHOR_* / GIT_COMMITTER_* in env. See README.)
            env = {
              # Pass secrets as shell variable references (e.g. "$TOKEN"), not
              # via builtins.getEnv, so they expand at runtime and stay out of
              # the /nix/store.
              CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
              GITHUB_TOKEN = "$GITHUB_TOKEN";
              CLAUDE_CONFIG_DIR = "$HOME/.claude";
            };
            allowedDomains = {
              "anthropic.com" = "*";
              "claude.com" = "*";
              "raw.githubusercontent.com" = [
                "GET"
                "HEAD"
              ];
              "api.github.com" = [
                "GET"
                "HEAD"
              ];
            };
          };
        in
        {
          default = pkgs.mkShell { packages = [ claude-sandboxed ]; };
        }
      );
    };
}
