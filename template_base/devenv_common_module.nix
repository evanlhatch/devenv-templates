# ~/my-project-templates/template_base/devenv_common_module.nix
{ pkgs, config, lib, ... }:
{
  packages = [
    pkgs.nil # Nix Language Server for IDEs
    pkgs.infisical # Infisical CLI for secrets management
    pkgs.shellcheck # For linting shell scripts (used by hooks and devenv test)
  ];

  # Enable devenv to load .env files (for INFISICAL_TOKEN, etc.)
  # direnv itself will also pick up .env if present. This makes devenv explicitly aware.
  dotenv.enable = true;

  # Attempt to inject Infisical secrets into the shell
  enterShell = ''
    # Infisical secrets injection
    if command -v infisical &> /dev/null; then
      if [ -n "$INFISICAL_TOKEN" ] && [ -n "$INFISICAL_PROJECT_ID" ]; then
        echo "Attempting to fetch secrets from Infisical for project $INFISICAL_PROJECT_ID (env: $INFISICAL_ENVIRONMENT)..."
        if eval "$(infisical export --format=shell)"; then
          echo "🗝️ Infisical secrets exported into the current shell environment."
        else
          echo "⚠️ Warning: Failed to export secrets from Infisical. Check token/config in .env"
        fi
      else
        echo "💡 Infisical: Set INFISICAL_TOKEN, INFISICAL_PROJECT_ID, INFISICAL_ENVIRONMENT in a .env file to load secrets."
      fi
    else
      echo "⚠️ Infisical CLI not found in PATH. Secrets will not be loaded automatically."
    fi
  '';

  # Common pre-commit hooks
  pre-commit.hooks = {
    nixpkgs-fmt = { enable = true; }; # Format Nix files
    # statix = { enable = true; entry = "statix check"; }; # Lint Nix files (can be slow)
  };
}
