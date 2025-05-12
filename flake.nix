
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
    ty-source = {
      url = "github:astral-sh/ty";
      rev = "81c2bf20a8995337d799953f9003cfabd860b943"; # Pinned ty-source
      flake = false;
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

  outputs = { self, nixpkgs, flake-utils, devenv-sh, uv2nix, crane, fenix, deadnix, ty-source, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            devenv-sh.overlays.default
          ];
        };

        # Helper to build 'ty' if needed from pinned source
        tyFromSource = pkgs.rustPlatform.buildRustPackage {
          pname = "ty-cli-from-source";
          version = "git-${inputs.ty-source.shortRev or "unknown"}"; # Version from shortRev
          src = inputs.ty-source;
          cargoLock.lockFile = "${inputs.ty-source}/Cargo.lock"; # Use Cargo.lock from src
          # Add necessary buildInputs for ty if any, e.g.:
          # buildInputs = [ pkgs.openssl pkgs.pkg-config ]; 
        };
        # Prefer ty from nixpkgs if it exists and is recent enough, otherwise try building from source.
        tyPackage = pkgs.ty or tyFromSource;
        
        # Create the init-project script with variable substitution (current method using runCommand + sed)
        init-project-script = pkgs.runCommand "init-project.sh" {
          src = ./init-project.sh;
          nativeBuildInputs = [ pkgs.gnused pkgs.makeWrapper ]; # makeWrapper for wrapProgram
          
          # Template paths
          template_base_path = "${self}/template_base";
          template_python_path = "${self}/template_python";
          template_rust_path = "${self}/template_rust";
          
          # Input URLs for generated projects - Pass pinned versions where possible
          inputs_nixpkgs_url = inputs.nixpkgs.meta.original.url or inputs.nixpkgs.url;
          inputs_devenv_url = inputs.devenv-sh.meta.original.url or inputs.devenv-sh.url;
          inputs_flake_utils_url = inputs.flake-utils.meta.original.url or inputs.flake-utils.url;
          
          inputs_uv2nix_url = inputs.uv2nix.meta.original.url or inputs.uv2nix.url;
          inputs_uv2nix_rev = inputs.uv2nix.rev or (inputs.uv2nix.meta.original.rev or "main");
          
          # For ty-source, pass the pinned URL and REV if defined
          inputs_ty_source_url = inputs.ty-source.url; # This will be github:astral-sh/ty
          # If init-project.sh is updated to use rev for ty-source:
          # inputs_ty_source_rev = inputs.ty-source.rev or ""; 
          
          inputs_crane_url = inputs.crane.meta.original.url or inputs.crane.url;
          inputs_fenix_url = inputs.fenix.meta.original.url or inputs.fenix.url;
          
          # Tool paths for sed replacement in script (if script uses @tool_name@)
          # Alternatively, wrapProgram (as currently done) is better.
          sd_tool_path = "${pkgs.sd}/bin/sd"; # Renamed to avoid conflict if script also uses 'sd' var
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
          
          # Replace template paths
          sed -i "s|@template_base_path@|$template_base_path|g" $out/bin/init-project.sh
          sed -i "s|@template_python_path@|$template_python_path|g" $out/bin/init-project.sh
          sed -i "s|@template_rust_path@|$template_rust_path|g" $out/bin/init-project.sh
          
          # Replace input URLs (ensure init-project.sh expects these exact @variable@ names)
          sed -i "s|@inputs_nixpkgs_url@|$inputs_nixpkgs_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_devenv_url@|$inputs_devenv_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_flake_utils_url@|$inputs_flake_utils_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_uv2nix_url@|$inputs_uv2nix_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_uv2nix_rev@|$inputs_uv2nix_rev|g" $out/bin/init-project.sh
          sed -i "s|@inputs_ty_source_url@|$inputs_ty_source_url|g" $out/bin/init-project.sh
          # If passing ty_source_rev:
          # sed -i "s|@inputs_ty_source_rev@|$inputs_ty_source_rev|g" $out/bin/init-project.sh
          sed -i "s|@inputs_crane_url@|$inputs_crane_url|g" $out/bin/init-project.sh
          sed -i "s|@inputs_fenix_url@|$inputs_fenix_url|g" $out/bin/init-project.sh
          
          # Replace tool paths if script uses @tool_name@ placeholders for them
          # This is an alternative to wrapProgram if script expects to find tools via these vars.
          # sed -i "s|@sd@|$sd_tool_path|g" $out/bin/init-project.sh 
          # sed -i "s|@git@|$git_tool_path|g" $out/bin/init-project.sh
          # etc.

          # Add tools to PATH for the execution of init-project.sh
          # This is crucial if the script calls commands like `git`, `sd`, `cp` directly.
          wrapProgram $out/bin/init-project.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.sd
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.findutils
              pkgs.git
              pkgs.bash # Bash is usually found via shebang, but good to ensure
              pkgs.file # Used by init-project.sh
            ]}
        '';
        
        init-project-package = pkgs.writeShellScriptBin "init-project" ''
          exec ${init-project-script}/bin/init-project.sh "$@"
        '';
        
        test-templates-script = pkgs.writeShellScriptBin "test-templates" ''
          #!/usr/bin/env bash
          set -euo pipefail
          echo "Verifying init-project script..."
          if [ ! -x "${init-project-package}/bin/init-project" ]; then # Check final package
            echo "Error: init-project script not found or not executable"
            exit 1
          fi
          echo "init-project script verification passed!"
          exit 0
        '';
        
        appMeta = {
          description = "Generate devenv-based project templates";
          mainProgram = "init-project";
          license = pkgs.lib.licenses.mit; # Assuming MIT
          maintainers = [ pkgs.lib.maintainers.eelcoh ]; # Replace with actual maintainer
        };
        
      in {
        packages = {
          default = init-project-package;
          init-project = init-project-package; # Alias for clarity
          test-templates = test-templates-script;
          ty = tyPackage; # Expose the ty package
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
            pkgs.nixpkgs-fmt # Switched to nixpkgs-fmt
            (deadnix.packages.${system}.default or deadnix) # Robust deadnix access
            pkgs.statix
            init-project-package # For testing init-project from shell
            test-templates-script # For running tests from shell
            tyPackage # Make ty available in the template dev shell
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
            buildInputs = [ init-project-package ]; # Check the final packaged script
          } ''
            # $init_project_package/bin/init-project should be the path
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
