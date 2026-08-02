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
              allowUnfreePredicate = pkg: pkgs.lib.getName pkg == "github-copilot-cli";
            };
          };
          sbx = agent-sandbox.lib.${system};
          copilot-sandboxed = sbx.mkSandbox {
            pkg = pkgs.github-copilot-cli;
            binName = "copilot";
            outName = "copilot-sandboxed"; # or whatever alias you'd like
            allowedPackages = sbx.commonTools;
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
              # Pass secrets as shell variable references (e.g. "$TOKEN"), not
              # via builtins.getEnv, so they expand at runtime and stay out of
              # the /nix/store.
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
        {
          default = pkgs.mkShell { packages = [ copilot-sandboxed ]; };
        }
      );
    };
}
