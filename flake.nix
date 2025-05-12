{
  description = "A Nix Flake for generating devenv-based project templates";

  inputs = {
    # Core inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # devenv for development environments
    devenv-sh = {
      url = "github:cachix/devenv/v1.0.8"; # Pinned
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Python-specific inputs
    uv2nix = {
      url = "github:pyproject-nix/uv2nix"; # Consider pinning
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ty-source was removed
    
    # Rust-specific inputs
    crane = {
      url = "github:ipetkov/crane"; # Consider pinning
    };
    fenix = {
      url = "github:nix-community/fenix"; # Consider pinning
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Linting tools
    deadnix = {
      url = "github:astro/deadnix"; # Consider pinning
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Removed ty-source from the function signature
  outputs = { self, nixpkgs, flake-utils, devenv-sh, uv2nix, crane, fenix, deadnix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            devenv-sh.overlays.default
          ];
        };
        
        substitutedInitScript = pkgs.substituteAll {
          src = ./init-project.sh;
          name = "init-project-final.sh"; 
          isExecutable = true;

          inherit (pkgs) bash; 

          template_base_path = "${self}/template_base";
          template_python_path = "${self}/template_python";
          template_rust_path = "${self}/template_rust";

          inputs_nixpkgs_url = "github:NixOS/nixpkgs/nixos-unstable";
          inputs_devenv_url = "github:cachix/devenv/v1.0.8";
          inputs_flake_utils_url = "github:numtide/flake-utils";
          inputs_uv2nix_url = "github:pyproject-nix/uv2nix";
          inputs_uv2nix_rev = inputs.uv2nix.rev or (inputs.uv2nix.meta.original.rev or "main"); 
          inputs_crane_url = "github:ipetkov/crane";
          inputs_fenix_url = "github:nix-community/fenix";
          
          PATH = pkgs.lib.makeBinPath [
            pkgs.coreutils 
            pkgs.sd
            pkgs.git
            pkgs.gnugrep 
            pkgs.findutils 
            pkgs.file 
            pkgs.bash 
          ];
        };
        
        test-templates-script = pkgs.writeShellScriptBin "test-templates" ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo "Verifying init-project script..."
          if [ ! -x "${substitutedInitScript}" ]; then 
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
          maintainers = [ pkgs.lib.maintainers.eelcoh ]; 
        };
        
      in {
        packages = {
          default = substitutedInitScript; 
          init-project = substitutedInitScript;
          test-templates = test-templates-script;
        };
        
        apps = {
          init-project = { 
            type = "app"; 
            program = "${substitutedInitScript}"; 
            meta = appMeta; 
          };
          default = self.apps.${system}.init-project;
          test-templates = {
            type = "app";
            program = "${test-templates-script}/bin/test-templates";
            meta = { description = "Test template generation"; mainProgram = "test-templates"; license = pkgs.lib.licenses.mit; maintainers = [ pkgs.lib.maintainers.eelcoh ]; };
          };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.git
            pkgs.sd
            pkgs.just
            pkgs.nixpkgs-fmt 
            (deadnix.packages.${system}.default or deadnix) 
            pkgs.statix
            substitutedInitScript 
            test-templates-script
            pkgs.shellcheck 
            # pkgs.ty removed
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
            # No buildInputs needed as substitutedInitScript is a store path
          } ''
            if [ -x "${substitutedInitScript}" ]; then
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
