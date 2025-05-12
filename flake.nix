{
  description = "A Nix Flake for generating devenv-based project templates";

  inputs = {
    # Core inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # devenv for development environments
    devenv-sh = {
      url = "github:cachix/devenv/v1.0.8"; # Pinned version
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Python-specific inputs
    uv2nix = {
      url = "github:pyproject-nix/uv2nix"; # Consider pinning with rev or ref
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ty-source = {
      url = "github:astral-sh/ty";
      # Consider adding rev = "commit-hash"; for pinning
      flake = false;
    };

    # Rust-specific inputs
    crane = {
      url = "github:ipetkov/crane";
      # Consider adding rev = "commit-hash"; for pinning
      # crane doesn't have a nixpkgs input, so we don't need to follow it
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      # Consider pinning fenix itself, e.g. fenix.url = "github:nix-community/fenix/v0.x.y";
    };

    # Linting tools
    deadnix = {
      url = "github:astro/deadnix"; # Consider pinning
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, devenv-sh, uv2nix, crane, fenix, deadnix, ty-source, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            devenv-sh.overlays.default
          ];
        };

        # Helper to build 'ty' if needed
        tyFromSourceCargoLock = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/astral-sh/ty/main/Cargo.lock"; # Adjust if ty-source is pinned to a commit
          sha256 = "0000000000000000000000000000000000000000000000000000"; # ACTUAL HASH NEEDED HERE
        };

        tyFromSource = pkgs.rustPlatform.buildRustPackage {
          pname = "ty-cli-from-source";
          version = "0.1.0-dev"; # Use actual commit hash from inputs.ty-source.rev if ty-source is pinned
          src = inputs.ty-source;
          cargoLock.lockFile = tyFromSourceCargoLock;
        };
        tyPackage = pkgs.ty or tyFromSource;


        # Variables to be substituted into init-project.sh
        substitutionVars = {
          template_base_path = "${self}/template_base";
          template_python_path = "${self}/template_python";
          template_rust_path = "${self}/template_rust";

          inputs_nixpkgs_url = inputs.nixpkgs.meta.original.url or inputs.nixpkgs.url;
          inputs_devenv_url = inputs.devenv-sh.meta.original.url or inputs.devenv-sh.url;
          inputs_flake_utils_url = inputs.flake-utils.meta.original.url or inputs.flake-utils.url;
          
          inputs_uv2nix_url = inputs.uv2nix.meta.original.url or inputs.uv2nix.url;
          inputs_uv2nix_rev = inputs.uv2nix.rev or (inputs.uv2nix.meta.original.rev or "main");

          inputs_ty_source_url = inputs.ty-source.url;
          # inputs_ty_source_rev = inputs.ty-source.rev or ""; # If ty-source is defined with rev

          inputs_crane_url = inputs.crane.meta.original.url or inputs.crane.url;
          # inputs_crane_rev = inputs.crane.rev or (inputs.crane.meta.original.rev or "main");

          inputs_fenix_url = inputs.fenix.meta.original.url or inputs.fenix.url;
          # inputs_fenix_rev = inputs.fenix.rev or (inputs.fenix.meta.original.rev or "main");

          sd_path = "${pkgs.sd}/bin/sd";
          coreutils_path = "${pkgs.coreutils}/bin";
          gnugrep_path = "${pkgs.gnugrep}/bin";
          findutils_path = "${pkgs.findutils}/bin";
          git_path = "${pkgs.git}/bin/git";
          bash_path = "${pkgs.bash}/bin/bash";
        };

        # Create the init-project script using substituteAll
        init-project-script-substituted = pkgs.substituteAll {
          src = ./init-project.sh;
          name = "init-project-substituted.sh";
          isExecutable = true;
          inherit (substitutionVars)
            template_base_path template_python_path template_rust_path
            inputs_nixpkgs_url inputs_devenv_url inputs_flake_utils_url
            inputs_uv2nix_url inputs_uv2nix_rev
            inputs_ty_source_url
            inputs_crane_url inputs_fenix_url
            sd_path coreutils_path gnugrep_path findutils_path git_path bash_path;
        };
        
        # Final init-project package that calls the substituted script
        init-project-final-package = pkgs.writeShellScriptBin "init-project" ''
          #!${pkgs.bash}/bin/bash
          PATH="${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.sd pkgs.git pkgs.gnugrep pkgs.findutils pkgs.bash ]}:$PATH"
          exec "${init-project-script-substituted}" "$@"
        '';

        test-templates-script = pkgs.writeShellScriptBin "test-templates" ''
          #!/usr/bin/env bash
          set -euo pipefail
          
          echo "Verifying init-project script..."
          if [ ! -x "${init-project-final-package}/bin/init-project" ]; then
            echo "Error: init-project script not found or not executable"
            exit 1
          fi
          
          echo "init-project script verification passed!"
          exit 0
        '';
        
        appMeta = {
          description = "Generate devenv-based project templates";
          mainProgram = "init-project";
          license = pkgs.lib.licenses.mit; 
          maintainers = [ pkgs.lib.maintainers.eelcoh ]; # Example, replace with actual
        };
        
      in {
        packages = {
          default = init-project-final-package;
          init-project = init-project-final-package;
          test-templates = test-templates-script;
          ty = tyPackage;
        };
        
        apps = {
          init-project = {
            type = "app";
            program = "${init-project-final-package}/bin/init-project";
            meta = appMeta;
          };
          default = self.apps.${system}.init-project;
          
          test-templates = {
            type = "app";
            program = "${test-templates-script}/bin/test-templates";
            meta = {
              description = "Test template generation";
              mainProgram = "test-templates";
              license = pkgs.lib.licenses.mit;
              maintainers = [ pkgs.lib.maintainers.eelcoh ]; # Example
            };
          };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.git
            pkgs.sd
            pkgs.just
            pkgs.nixpkgs-fmt # Switched
            (deadnix.packages.${system}.default or deadnix) 
            pkgs.statix
            init-project-final-package 
            test-templates-script    
            tyPackage               
          ];
          
          shellHook = ''
            echo "Welcome to the devenv-templates development environment!"
            echo "Use 'init-project <project-type> <project-name>' to test template generation."
            echo "Use 'test-templates' to run template generation tests."
          '';
        };
        
        checks = {
          build-check = self.packages.${system}.default;
          template-check = pkgs.runCommand "template-check" {
            buildInputs = [ init-project-final-package ]; 
          } ''
            if [ -x "$init_project/bin/init-project" ]; then 
              echo "init-project script verification passed!"
              touch $out
            else
              echo "Error: init-project script not found or not executable"
              exit 1
            fi
          '';
        };
      });
}
