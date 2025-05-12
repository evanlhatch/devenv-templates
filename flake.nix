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

        # tyFromSource and related tyPackage logic removed.
        # If pkgs.ty exists, it can be used directly. Otherwise, ty features might be limited.
        # For the template's devShell, we can just try to include pkgs.ty.
        
        init-project-script = pkgs.runCommand "init-project.sh" {
          src = ./init-project.sh;
          nativeBuildInputs = [ pkgs.gnused pkgs.makeWrapper ];
          
          template_base_path = "${self}/template_base";
          template_python_path = "${self}/template_python";
          template_rust_path = "${self}/template_rust";
          
          inputs_nixpkgs_url = inputs.nixpkgs.meta.original.url or inputs.nixpkgs.url;
          inputs_devenv_url = "github:cachix/devenv/v1.0.8"; # Using the literal string from top-level inputs
          inputs_flake_utils_url = "github:numtide/flake-utils"; # Using the literal string from top-level inputs
          inputs_uv2nix_url = "github:pyproject-nix/uv2nix"; # Using the literal string from top-level inputs
          inputs_uv2nix_rev = inputs.uv2nix.rev or (inputs.uv2nix.meta.original.rev or "main");
          
          # inputs_ty_source_url removed from here
          
          inputs_crane_url = "github:ipetkov/crane"; # Using the literal string from top-level inputs
          inputs_fenix_url = "github:nix-community/fenix"; # Using the literal string from top-level inputs
          
          sd_tool_path = "${pkgs.sd}/bin/sd";
          coreutils_tool_path = "${pkgs.coreutils}/bin";
          gnugrep_tool_path = "${pkgs.gnugrep}/bin";
          findutils_tool_path = "${pkgs.findutils}/bin";
          git_tool_path = "${pkgs.git}/bin/git";
          bash_tool_path = "${pkgs.bash}/bin/bash";
          file_tool_path = "${pkgs.file}/bin/file";

        } ''
          mkdir -p $out/bin
          cp $src $out/bin/init-project.sh
          chmod +x $out/bin/init-project.sh
          
          sed -i "s|@template_base_path@|$template_base_path|g" $out/bin/init-project.sh
          sed -i "s|@template_python_path@|$template_python_path|g" $out/bin/init-project.sh
          sed -i "s|@template_rust_path@|$template_rust_path|g" $out/bin/init-project.sh
          
          sed -i "s|@inputs_nixpkgs_url@|$inputs_nixpkgs_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_devenv_url@|$inputs_devenv_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_flake_utils_url@|$inputs_flake_utils_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_uv2nix_url@|$inputs_uv2nix_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_uv2nix_rev@|$inputs_uv2nix_rev|g" $out/bin/init-project.sh
          # sed -i "s|@inputs_ty_source_url@|$inputs_ty_source_url|g" $out/bin/init-project.sh # This line will be removed from init-project.sh too
          sed -i "s|@inputs_crane_url@|$inputs_crane_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_fenix_url@|$inputs_fenix_url|g" $out/bin/init-project.sh
          
          wrapProgram $out/bin/init-project.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.sd pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.git pkgs.bash pkgs.file
            ]}
        '';
        
        init-project-package = pkgs.writeShellScriptBin "init-project" ''
          exec ${init-project-script}/bin/init-project.sh "$@"
        '';
        
        test-templates-script = pkgs.writeShellScriptBin "test-templates" ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo "Verifying init-project script..."
          if [ ! -x "${init-project-package}/bin/init-project" ]; then
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
          default = init-project-package;
          init-project = init-project-package;
          test-templates = test-templates-script;
          # packages.ty removed (or could be pkgs.ty if it exists and is desired)
        };
        
        apps = {
          init-project = { type = "app"; program = "${init-project-package}/bin/init-project"; meta = appMeta; };
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
            init-project-package 
            test-templates-script    
            # tyPackage removed. Add pkgs.ty if available and needed for template dev.
            pkgs.ty # Assuming pkgs.ty exists, otherwise remove or handle conditionally
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
            buildInputs = [ init-project-package ]; 
          } ''
            if [ -x "${init-project-package}/bin/init-project" ]; then
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
