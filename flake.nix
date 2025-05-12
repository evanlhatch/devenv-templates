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

  outputs = { self, nixpkgs, flake-utils, devenv-sh, uv2nix, crane, fenix, deadnix, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            devenv-sh.overlays.default
          ];
        };
        
        # Step 1: Substitute variables into the script text
        substitutedInitScriptText = pkgs.substituteAll {
          src = ./init-project.sh;
          name = "init-project-text-substituted.sh"; 

          inherit (pkgs) bash; # For #!/usr/bin/env bash in init-project.sh to resolve bash correctly

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
          # No PATH substitution here in the text
        };

        # Step 2: Create an executable script package that runs the substituted script
        # and has the necessary tools in its PATH.
        initProjectAppProgram = pkgs.writeShellScriptBin "init-project-app" ''
          #!${pkgs.bash}/bin/bash
          # This PATH will be available when substitutedInitScriptText (now $1) is executed
          export PATH="${pkgs.lib.makeBinPath [
            pkgs.coreutils 
            pkgs.sd
            pkgs.git
            pkgs.gnugrep 
            pkgs.findutils 
            pkgs.file 
            pkgs.bash 
          ]}:$PATH"
          
          exec "${substitutedInitScriptText}" "$@" # Execute the substituted script text
        '';
        
        test-templates-script = pkgs.writeShellScriptBin "test-templates" ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo "Verifying init-project script..."
          if [ ! -x "${initProjectAppProgram}/bin/init-project-app" ]; then 
            echo "Error: init-project script not found or not executable"
            exit 1
          fi
          echo "init-project script verification passed!"
          exit 0
        '';
        
        appMeta = {
          description = "Generate devenv-based project templates";
          mainProgram = "init-project-app"; # Corresponds to the binary in initProjectAppProgram
          license = pkgs.lib.licenses.mit;
          maintainers = [ pkgs.lib.maintainers.eelcoh ]; 
        };
        
      in {
        packages = {
          default = initProjectAppProgram; 
          init-project = initProjectAppProgram; # The app wrapper is the package
          test-templates = test-templates-script;
        };
        
        apps = {
          init-project = { 
            type = "app"; 
            program = "${initProjectAppProgram}/bin/init-project-app"; 
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
            initProjectAppProgram # For testing the app from the dev shell
            test-templates-script
            pkgs.shellcheck 
          ];
          shellHook = ''
            echo "Welcome to the devenv-templates development environment!"
            echo "Use 'init-project-app <project-type> <project-name>' to test template generation."
            echo "Use 'test-templates' to run template generation tests."
          '';
        };
        
        checks = {
          build-check = self.packages.${system}.default; 
          template-check = pkgs.runCommand "template-check" {
            # Check if initProjectAppProgram is executable
          } ''
            if [ -x "${initProjectAppProgram}/bin/init-project-app" ]; then
              echo "init-project app verification passed!"
              touch $out
            else
              echo "Error: init-project app not found or not executable"
              exit 1
            fi
          '';
        };
      });
}
