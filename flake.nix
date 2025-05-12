{
  description = "A Nix Flake for generating devenv-based project templates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Inputs that the *generated project's flake.nix* will reference.
    # We define them here so the init script can pin them in the generated devenv.yaml.
    devenv-sh.url = "github:cachix/devenv/v1.0.8"; # Check for latest stable devenv release
    devenv-sh.inputs.nixpkgs.follows = "nixpkgs";

    # For Python template
    uv2nix.url = "github:astral-sh/uv2nix"; # For uv.nix generation
    ty-source.url = "github:astral-sh/ty"; # Source for 'ty' if not in nixpkgs yet
    ty-source.flake = false; # Assuming it's not a flake, adjust if it is

    # For Rust template
    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, devenv-sh, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devenv-sh.overlays.default ]; # Make devenv CLI available
        };

        # Helper to build 'ty' if needed (placeholder, real build might be complex)
        # Ideally, 'ty' becomes available in nixpkgs quickly.
        tyFromSource = pkgs.rustPlatform.buildRustPackage {
          pname = "ty-cli-from-source";
          version = "0.1.0-dev"; # Use actual commit hash from inputs.ty-source.rev
          src = inputs.ty-source;
          cargoLock.lockFile = "${inputs.ty-source}/Cargo.lock"; # Ensure Cargo.lock exists at this path in the source
          # buildInputs = [ pkgs.openssl pkgs.pkg-config ]; # Example build inputs
        };
        # Prefer ty from nixpkgs if it exists and is recent enough, otherwise try building.
        tyPackage = pkgs.ty or tyFromSource;

      in
      {
        # The Flake App for project initialization
        apps.init-project = {
          type = "app";
          program = "\${self.packages.\${system}.init-script-env}/bin/init-project";
        };
        apps.default = self.apps.\${system}.init-project; # Alias

        # Environment that provides the init-project script and its dependencies
        packages.init-script-env = pkgs.buildEnv {
          name = "init-script-environment";
          paths = [
            (pkgs.writeShellScriptBin "init-project" (builtins.readFile ./init-project.sh))
            pkgs.sd # For search-replace in template files
            pkgs.git # For initializing git repo in new project
            pkgs.coreutils # For basic commands like basename, mkdir, cp, cat
            pkgs.gnugrep # For grep in scripts
            pkgs.findutils # For find in scripts
          ];
        };

        # Development shell for working *on this template repository itself*
        devShells.default = pkgs.devenv.lib.mkShell { # Using devenv for the template repo's dev env
          inherit inputs pkgs;
          modules = [{
            packages = [
              pkgs.sd
              pkgs.shellcheck
              pkgs.editorconfig-checker
              pkgs.nixpkgs-fmt # To format Nix files in this template repo
              pkgs.just # If you use a justfile for managing the template repo
            ];
            pre-commit.hooks = {
              shellcheck.enable = true;
              editorconfig-checker.enable = true;
              nixpkgs-fmt.enable = true;
            };
          }];
        };

        # Expose paths to template parts for the init-script
        # The init-script.sh should use these paths, interpolated by Nix.
        # However, writeShellScriptBin doesn't interpolate flake attributes directly.
        # Instead, the init-project.sh will need to determine FLAKE_ROOT.
        # For simplicity in the script, we can rely on it finding template dirs relative to itself.

        # Formatter for this template repository's Nix files
        formatter = pkgs.nixpkgs-fmt;

        # Make ty available if someone wants to test it from this flake
        packages.ty = tyPackage;
      }
    );
}
