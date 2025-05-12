#!/usr/bin/env bash
set -euo pipefail

# --- Configuration & Helper Functions ---
# (Similar to the previous version of init-project.sh with log_info, log_error, usage)
# Key change: Determine FLAKE_ROOT dynamically assuming this script is run from the flake context
# Or, if `nix run` unpacks the flake, we need to locate the template directories differently.
# For `nix run`, the script is often put into a temp location.
# A robust way is to have the flake output the paths to the template directories,
# and the script (or a wrapper) consumes these.
# Given the setup with `packages.init-script-env`, the script is in the Nix store.
# The source files (templates) are also in the Nix store, referenced by `self`.
# The easiest way if writeShellScriptBin copies the script is to have the flake
# pass the paths to the templates *into* the script text itself during generation.

# This script will be wrapped by `pkgs.writeShellScriptBin` and paths to templates
# will be interpolated directly by Nix. We achieve this by having the `program`
# attribute in `flake.nix` use `pkgs.substituteAll` or by embedding paths
# directly if `self` is accessible.
# For now, let's assume the Flake's `program` attribute will handle path interpolation.
# The version of init-project.sh from the previous "Flake app" response is a good base.
# I will paste that here and highlight key areas to ensure they work with this structure.

# This script is intended to be wrapped by `pkgs.writeShellScriptBin`
# where `templateBasePath`, `templatePythonPath`, `templateRustPath`,
# `inputsNixpkgsUrl`, `inputsDevenvUrl`, etc. are substituted by Nix.

# Example of how it might be called by pkgs.writeShellScriptBin with pkgs.substituteAll
# program = pkgs.substituteAll {
#   src = ./init-project.sh;
#   sd = pkgs.sd;
#   coreutils = pkgs.coreutils;
#   gnugrep = pkgs.gnugrep;
#   findutils = pkgs.findutils;
#   git = pkgs.git;
#   bash = pkgs.bash;
#   isExecutable = true;
#   template_base_path = "${self}/template_base";
#   template_python_path = "${self}/template_python";
#   template_rust_path = "${self}/template_rust";
#   inputs_nixpkgs_url = inputs.nixpkgs.url;
#   inputs_devenv_url = inputs.devenv-sh.url;
#   inputs_flake_utils_url = inputs.flake-utils.url;
#   inputs_uv2nix_url = inputs.uv2nix.url;
#   inputs_uv2nix_rev = inputs.uv2nix.rev;
#   # inputs_ty_source_url = inputs.ty-source.url; # Removed
#   inputs_crane_url = inputs.crane.url;
#   inputs_fenix_url = inputs.fenix.url;
#   generated_project_config_path = generatedProjectConfig; # Path to Nix-generated config
# };

# --- Configuration ---
DEFAULT_PYTHON_VERSION="3.11"
DEFAULT_MANAGE_DEPS_WITH_UV2NIX="false"
DEFAULT_RUST_EDITION="2021" # Or "2024" if applicable

# Path to sd, coreutils, etc., will be available via PATH from the buildEnv
# The template paths will be substituted by Nix when the script is built
readonly BASE_TEMPLATE_DIR="@template_base_path@"
readonly PYTHON_TEMPLATE_DIR="@template_python_path@"
readonly RUST_TEMPLATE_DIR="@template_rust_path@"

# --- Helper Functions ---
log_info() {
  echo "INFO: $1"
}
log_error() {
  echo "ERROR: $1" >&2
  exit 1
}

# --- Argument Parsing ---
# (Same argument parsing as before: $1=PROJECT_TYPE, $2=PROJECT_NAME, then key=value pairs)
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <project-type> <project-name> [python-version=X.Y] [manage-deps-with-uv2nix=true|false] [rust-edition=2021|2024]"
  echo "Example (Python): $0 python my-python-app python-version=3.11 manage-deps-with-uv2nix=true"
  echo "Example (Rust):   $0 rust my-rust-app rust-edition=2021"
  exit 1
fi

PROJECT_TYPE=$1
PROJECT_DIR_NAME=$2 # This can be a relative or absolute path
PROJECT_NAME=$(basename "$PROJECT_DIR_NAME")
shift 2

PYTHON_VERSION=$DEFAULT_PYTHON_VERSION
MANAGE_DEPS_WITH_UV2NIX=$DEFAULT_MANAGE_DEPS_WITH_UV2NIX
RUST_EDITION=$DEFAULT_RUST_EDITION

for arg in "$@"; do
  case $arg in
    python-version=*)
      PYTHON_VERSION="${arg#*=}"
      ;;
    manage-deps-with-uv2nix=*)
      MANAGE_DEPS_WITH_UV2NIX="${arg#*=}"
      ;;
    rust-edition=*)
      RUST_EDITION="${arg#*=}"
      ;;
    *)
      log_error "Unknown argument: $arg"
      ;;
  esac
done

TARGET_DIR="$PROJECT_DIR_NAME" # Use the provided name directly

log_info "Project Type: ${PROJECT_TYPE}"
log_info "Project Name: ${PROJECT_NAME}"
log_info "Target Directory: ${TARGET_DIR}"
# ... (Log Python/Rust specific chosen versions)

# --- Safety Check & Setup ---
if [ -d "$TARGET_DIR" ]; then
  read -r -p "Directory ${TARGET_DIR} already exists. Overwrite? (y/N): " confirmation
  if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    log_info "Aborted."
    exit 0
  fi
  log_info "Removing existing directory: ${TARGET_DIR}"
  rm -rf "${TARGET_DIR}"
fi
mkdir -p "$TARGET_DIR"
# cd "$TARGET_DIR" # Not strictly needed here, operations use $TARGET_DIR path

# --- Copy Files & Create Configs ---
log_info "Copying base template files to ${TARGET_DIR}..."
cp -rT "$BASE_TEMPLATE_DIR/" "$TARGET_DIR/" # -T treats source as a directory
mv "${TARGET_DIR}/.gitignore_template" "${TARGET_DIR}/.gitignore"
mv "${TARGET_DIR}/justfile_template" "${TARGET_DIR}/Justfile"
mv "${TARGET_DIR}/README.md_template" "${TARGET_DIR}/README.md"
# project_config.nix_template is no longer directly moved if we use a pre-generated one.
# If @generated_project_config_path@ is used, we'll cp that.
# Otherwise, the old mv for project_config.nix_template should be removed.
# For now, assume project_config.nix is handled by the cp from @generated_project_config_path@
if [ -f "${TARGET_DIR}/project_config.nix_template" ]; then
  rm "${TARGET_DIR}/project_config.nix_template"
fi 


# 1. Copy pre-generated project_config.nix from flake
log_info "Copying pre-generated project_config.nix template..."
cp "@generated_project_config_path@" "${TARGET_DIR}/project_config.nix"
# Placeholders like {{PROJECT_NAME}} will be replaced by the 'sd' commands later.
log_info "Copied project_config.nix template."

# 2. Create devenv.yaml with pinned inputs from the template flake
log_info "Creating devenv.yaml..."
cat << EOF > "${TARGET_DIR}/devenv.yaml"
# This file pins inputs for devenv.sh if not using a project flake for this.
# It's less critical if the generated project flake.nix pins these.
inputs:
  nixpkgs:
    url: @inputs_nixpkgs_url@
  # The devenv CLI itself is often provided by the project's flake.nix
  # or a global install. Pinning devenv-sh here is an option if not using a project flake.
  # devenv:
  #   url: @inputs_devenv_url@
  #   inputs:
  #     nixpkgs:
  #       follows: nixpkgs
  # If the generated flake.nix doesn't include flake-utils, uv2nix, etc., add them here.
EOF

# 3. Create .envrc for direnv + Flakes
log_info "Creating .envrc..."
cat << EOF > "${TARGET_DIR}/.envrc"
# For nix-direnv to load the flake environment automatically
# Ensures all developers use the same consistent shell.
use flake . --no-pure-eval
EOF

# 4. Create the main project flake.nix (based on a simple template)
log_info "Creating project flake.nix..."
cat << EOF > "${TARGET_DIR}/flake.nix"
{
  description = "A new ${PROJECT_TYPE} project: ${PROJECT_NAME}";

  inputs = {
    nixpkgs.url = "@inputs_nixpkgs_url@";
    flake-utils.url = "@inputs_flake_utils_url@"; # devenv.lib.mkFlake uses this
    devenv-sh.url = "@inputs_devenv_url@";
    devenv-sh.inputs.nixpkgs.follows = "nixpkgs";

    # Conditionally add language-specific inputs based on PROJECT_TYPE
    # (These are used by the devenv modules)
    $(if [ "\$PROJECT_TYPE" == "python" ]; then
      echo \\
    "uv2nix = {\n      url = \"@inputs_uv2nix_url@\";\n      rev = \"@inputs_uv2nix_rev@\";\n      inputs.nixpkgs.follows = \"nixpkgs\";\n    };";
    fi)
    $(if [ "\$PROJECT_TYPE" == "rust" ]; then
      echo \\
    "crane.url = \\"@inputs_crane_url@\\";
    crane.inputs.nixpkgs.follows = \\"nixpkgs\\";
    fenix.url = \\"@inputs_fenix_url@\\";
    fenix.inputs.nixpkgs.follows = \\"nixpkgs\\";";
    fi)
  };

  # Add devenv binary cache for faster builds
  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv-sh, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # overlays = [ devenv-sh.overlays.default ]; # Not needed if using devenv-sh.lib.mkFlake
          config.allowUnfree = true; # Example
        };
      in
      {
        devShells.default = devenv-sh.lib.mkFlake {
          inherit pkgs inputs; # Pass inputs to devenv.nix
          # The devenv.nix file (from template_base) will be used.
          # It reads project_config.nix to load language-specific modules.
        };

        # You can add other flake outputs like packages, apps, checks here
        # packages.default = ...;
        # apps.default = ...;
      }
    );
}
EOF

# --- Language-Specific File Copying & Setup ---
if [ "\$PROJECT_TYPE" == "python" ]; then
  log_info "Copying Python-specific files..."
  # Assuming python_module.nix is the devenv module, pyproject.toml, etc.
  cp -rT "\$PYTHON_TEMPLATE_DIR/" "\$TARGET_DIR/"
  mv "\${TARGET_DIR}/pyproject.toml_template" "\${TARGET_DIR}/pyproject.toml"
  if [ -f "\${TARGET_DIR}/justfile_python_overlay" ]; then
    cat "\${TARGET_DIR}/justfile_python_overlay" >> "\${TARGET_DIR}/Justfile"
    rm "\${TARGET_DIR}/justfile_python_overlay"
  fi
  if [ -f "\${TARGET_DIR}/README_python.md" ]; then
    echo -e "\\n\\n---\\n" >> "\${TARGET_DIR}/README.md"
    cat "\${TARGET_DIR}/README_python.md" >> "\${TARGET_DIR}/README.md"
    rm "\${TARGET_DIR}/README_python.md"
  fi
  if [ -d "\${TARGET_DIR}/.vscode_template" ]; then # if vscode settings are in a dir
    mv "\${TARGET_DIR}/.vscode_template" "\${TARGET_DIR}/.vscode"
  elif [ -f "\${TARGET_DIR}/settings.json_template" ]; then # if it's just the file
    mkdir -p "\${TARGET_DIR}/.vscode"
    mv "\${TARGET_DIR}/settings.json_template" "\${TARGET_DIR}/.vscode/settings.json"
  fi

  # Create placeholder src directory and __init__.py
  PYTHON_PACKAGE_NAME=\$(echo "\$PROJECT_NAME" | sd '-' '_' | tr '[:upper:]' '[:lower:]')
  mkdir -p "\${TARGET_DIR}/src/\${PYTHON_PACKAGE_NAME}"
  touch "\${TARGET_DIR}/src/\${PYTHON_PACKAGE_NAME}/__init__.py"
  echo "print('Hello from \${PYTHON_PACKAGE_NAME}')" > "\${TARGET_DIR}/src/\${PYTHON_PACKAGE_NAME}/main.py"
  # Create basic tests directory
  mkdir -p "\${TARGET_DIR}/tests"
  touch "\${TARGET_DIR}/tests/__init__.py"
  echo "def test_example(): assert True" > "\${TARGET_DIR}/tests/test_example.py"

elif [ "\$PROJECT_TYPE" == "rust" ]; then
  log_info "Copying Rust-specific files..."
  cp -rT "\$RUST_TEMPLATE_DIR/" "\$TARGET_DIR/"
  mv "\${TARGET_DIR}/Cargo.toml_template" "\${TARGET_DIR}/Cargo.toml"
   if [ -f "\${TARGET_DIR}/justfile_rust_overlay" ]; then
    cat "\${TARGET_DIR}/justfile_rust_overlay" >> "\${TARGET_DIR}/Justfile"
    rm "\${TARGET_DIR}/justfile_rust_overlay"
  fi
  if [ -f "\${TARGET_DIR}/README_rust.md" ]; then
    echo -e "\\n\\n---\\n" >> "\${TARGET_DIR}/README.md"
    cat "\${TARGET_DIR}/README_rust.md" >> "\${TARGET_DIR}/README.md"
    rm "\${TARGET_DIR}/README_rust.md"
  fi
   if [ -d "\${TARGET_DIR}/.vscode_template" ]; then
    mv "\${TARGET_DIR}/.vscode_template" "\${TARGET_DIR}/.vscode"
  elif [ -f "\${TARGET_DIR}/settings.json_template" ]; then
    mkdir -p "\${TARGET_DIR}/.vscode"
    mv "\${TARGET_DIR}/settings.json_template" "\${TARGET_DIR}/.vscode/settings.json"
  fi
  # Create basic src/main.rs
  mkdir -p "\${TARGET_DIR}/src"
  echo 'fn main() { println!("Hello, world from {}!", "'"\${PROJECT_NAME}"'"); }' > "\${TARGET_DIR}/src/main.rs"
fi

# --- Placeholder Replacement (using sd) ---
log_info "Replacing placeholders in copied files..."
pushd "\$TARGET_DIR" > /dev/null
  # Common placeholders
  find . -type f -not -path '*/.git/*' -not -name '*.lock' -print0 | while IFS= read -r -d \$'\\0' file; do
    if file -b --mime-type "\$file" | grep -q text; then # Process only text files
      sd '{{PROJECT_NAME}}' "\$PROJECT_NAME" "\$file" || true
      sd '{{PROJECT_TYPE}}' "\$PROJECT_TYPE" "\$file" || true
      PROJECT_NAME_SNAKE_CASE=\$(echo "\$PROJECT_NAME" | sd '-' '_' | tr '[:upper:]' '[:lower:]')
      sd '{{PROJECT_NAME_SNAKE_CASE}}' "\$PROJECT_NAME_SNAKE_CASE" "\$file" || true
      if [ "\$PROJECT_TYPE" == "python" ]; then
        sd '{{PYTHON_VERSION}}' "\$PYTHON_VERSION" "\$file" || true
        PYTHON_VERSION_SHORT_NO_DOT=\$(echo "\$PYTHON_VERSION" | sd '[.]' '')
        sd '{{PYTHON_VERSION_SHORT_NO_DOT}}' "\$PYTHON_VERSION_SHORT_NO_DOT" "\$file" || true
        sd '{{MANAGE_DEPS_WITH_UV2NIX}}' "\$MANAGE_DEPS_WITH_UV2NIX" "\$file" || true
        PYTHON_MAIN_MODULE_PATH="\${PROJECT_NAME_SNAKE_CASE}.main" # Example
        sd '{{PYTHON_MAIN_MODULE_PATH}}' "\$PYTHON_MAIN_MODULE_PATH" "\$file" || true
      elif [ "\$PROJECT_TYPE" == "rust" ]; then
        sd '{{RUST_EDITION}}' "\$RUST_EDITION" "\$file" || true
      fi
    fi
  done
popd > /dev/null

# --- Initialize Git Repository ---
log_info "Initializing Git repository in \${TARGET_DIR}..."
pushd "\$TARGET_DIR" > /dev/null
  git init -b main
  # Add example scripts to be executable if they exist
  if [ -d "example_scripts" ]; then
    chmod +x example_scripts/* || true
  fi
  git add .
  git commit -m "Initial commit: scaffolded \${PROJECT_TYPE} project '\${PROJECT_NAME}' via template"
popd > /dev/null

# --- Final Instructions ---
log_info "✅ Project '\${PROJECT_NAME}' initialized successfully in '\${TARGET_DIR}'!"
echo ""
echo "Next steps:"
echo "  1. cd \\"\${TARGET_DIR}\\""
echo "  2. (If you use direnv and haven't already whitelisted the path) direnv allow"
echo "  3. Review devenv.nix, project_config.nix, and other generated files."
if [ "\$PROJECT_TYPE" == "python" ]; then
  echo "  4. For Python projects, run: devenv script setup-python"
  echo "     (This creates a .venv and installs dependencies using uv)"
  if [ "\$MANAGE_DEPS_WITH_UV2NIX" == "true" ]; then
    echo "  5. Optionally, to generate uv.nix: devenv script generate-uv-nix"
  fi
fi
echo "  6. Start developing! Try 'just --list' or 'devenv script list'."
