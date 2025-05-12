# ~/my-project-templates/template_python/python_devenv_module.nix
{
  pkgs,
  config,
  lib,
  inputs, # Make sure inputs is passed here if you need inputs.ty-source
  ...
}:

let
  projectCfg = config.projectConfig; # From base devenv.nix options
  pythonVersion = projectCfg.pythonVersion or "3.11"; # Default if not set
  manageDepsWithUv2nix = projectCfg.manageDependenciesWithUv2nix or false;

  # Determine Python package and uv package based on version
  pythonPackages = pkgs."python${lib.replaceStrings [ "." ] [ "" ] pythonVersion}Packages";
  pythonInterpreter = pythonPackages.python;
  uvPackage = pkgs.uv;

  # Ty (Type checker) - Prefer from nixpkgs, fallback to source build from flake input
  # This assumes ty-source is an input to the main flake, passed through to here.
  tyFromSource = pkgs.rustPlatform.buildRustPackage {
    pname = "ty-cli-from-source";
    version = "0.1.0-dev"; # Placeholder, ideally use inputs.ty-source.rev
    src = inputs.ty-source; # This needs `inputs` to be in the function signature
    cargoLock.lockFile = "${inputs.ty-source}/Cargo.lock";
    # buildInputs = [ pkgs.openssl pkgs.pkg-config ]; # Example build inputs for Rust if needed
  };
  tyPackage = pkgs.ty or tyFromSource;

in
{
  # Python version and package management
  languages.python = {
    enable = true;
    package = pythonInterpreter;
    version = pythonVersion;
    venv = {
      enable = true; # Creates and manages .venv/
      requirementsFiles = [ "pyproject.toml" ]; # uv uses this to find dependencies
      # Or use requirements.txt: requirementsFile = ./requirements.txt;
      # uv will be used if pyproject.toml or requirements.txt present
    };
  };

  # Packages for the Python environment
  packages = [
    uvPackage # For managing Python packages, venvs
    pythonPackages.pip # Good to have for some operations, though uv is preferred
    pythonPackages.ruff # Linter and formatter
    tyPackage # Type checker
    pythonPackages.debugpy # For VS Code debugging
    pkgs.poetry # If using poetry for dependency management (alternative to uv2nix for lock files)
  ];

  # Conditionally include uv2nix if manageDependenciesWithUv2nix is true
  packages = lib.mkIf manageDepsWithUv2nix [
    inputs.uv2nix.packages.${pkgs.system}.default # uv2nix CLI
  ];

  # Scripts for Python development
  scripts = {
    setup-python = {
      exec = ''
        echo "Setting up Python virtual environment with uv..."
        # Ensure uv is available
        if ! command -v uv &> /dev/null; then
          echo "uv command could not be found. Ensure it is in pkgs in devenv.nix."
          exit 1
        fi

        # Create venv if it doesn't exist
        if [ ! -d .venv ]; then
          echo "Creating virtual environment in ./.venv"
          ${pythonInterpreter}/bin/python -m venv .venv --prompt "({{PROJECT_NAME}})"
        else
          echo "Virtual environment ./.venv already exists."
        fi

        # Install/sync dependencies using uv
        echo "Installing/syncing dependencies from pyproject.toml into ./.venv using uv..."
        # Activate venv for this script part to ensure uv installs into it
        source .venv/bin/activate
        uv pip sync pyproject.toml --python .venv/bin/python
        # Or if you had requirements.txt: uv pip install -r requirements.txt
        deactivate
        echo "✅ Python environment setup complete. Activate with: source .venv/bin/activate"
      '';
      description = "Sets up the Python .venv and installs dependencies using uv.";
    };
    generate-uv-nix = lib.mkIf manageDepsWithUv2nix {
      exec = ''
        echo "Generating uv.nix from pyproject.toml..."
        # Ensure uv2nix is available
        if ! command -v uv2nix &> /dev/null; then
          echo "uv2nix command could not be found. Make sure manageDependenciesWithUv2nix is true and uv2nix is in inputs."
          exit 1
        fi
        uv2nix generate
        echo "✅ uv.nix generated. You might need to add it to your devenv.nix's imports or packages."
      '';
      description = "Generates uv.nix from pyproject.toml using uv2nix.";
    };
    lint = {
      exec = ''
        echo "Running Ruff linter..."
        ruff check .
        echo "Running Ty type checker..."
        ty src
      '';
      description = "Runs Ruff linter and Ty type checker.";
    };
    format = {
      exec = ''
        echo "Running Ruff formatter..."
        ruff format .
      '';
      description = "Formats Python code using Ruff.";
    };
    type-check = {
      exec = ''
        echo "Running Ty type checker..."
        ty src  # Assuming your main source code is in 'src'
      '';
      description = "Runs Ty for static type checking.";
    };
    test = {
      exec = ''
        echo "Running pytest..."
        # Activate venv if it exists and contains pytest, or rely on Nix-provided pytest
        if [ -f .venv/bin/pytest ]; then
            source .venv/bin/activate
            pytest
            deactivate
        elif command -v pytest &> /dev/null; then
            pytest
        else 
            echo "pytest not found in .venv or Nix environment."
            exit 1
        fi
      '';
      description = "Runs Python tests using pytest.";
    };
  };

  # Pre-commit hooks for Python
  pre-commit.hooks = {
    ruff = {
      enable = true;
      entry = "ruff check --fix --exit-non-zero-on-fix";
      types = [ "python" ];
    };
    ruff-format = {
      enable = true;
      entry = "ruff format";
      types = [ "python" ];
    };
    # Ty might be too slow for a pre-commit hook or require specific setup.
    # Consider running it in CI or manually.
    # ty-check = {
    #   enable = true;
    #   entry = "ty src";
    #   types = ["python"];
    #   pass_filenames = false;
    # };
  };

  # VS Code debugger configuration for Python
  # This helps `devenv vscode` setup if not using settings.json directly.
  # languages.python.debugger = {
  #   enable = true;
  #   package = pkgs.pythonPackages.debugpy;
  # };

  # Example of how to configure uv2nix if it's used to generate a Nix expression
  # for dependencies, which can then be imported.
  # This is more advanced if you want to fully Nix-ify Python deps.
  # let
  #   uvNixOutput = if manageDepsWithUv2nix && builtins.pathExists ./uv.nix
  #                 then import ./uv.nix { inherit pkgs; }
  #                 else [];
  # in
  # packages = uvNixOutput ++ [ ... ];

  # Shell entry messages specific to Python
  enterShell = ''
    if ${lib.boolToString manageDepsWithUv2nix}; then
      echo "   - uv2nix is enabled. Run 'devenv script generate-uv-nix' to create/update uv.nix"
    fi
    if [ -d ".venv" ]; then
      echo "💡 Python venv found at ./.venv. Activate with: source .venv/bin/activate"
    else
      echo "💡 No .venv found. Run 'devenv script setup-python' to create it."
    fi
  '';
}
