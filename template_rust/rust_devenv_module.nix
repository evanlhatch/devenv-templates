# ~/my-project-templates/template_rust/rust_devenv_module.nix
{
  pkgs,
  config,
  lib,
  inputs, # Ensure inputs is available for fenix, crane
  ...
}:

let
  projectCfg = config.projectConfig; # From base devenv.nix options
  rustEdition = projectCfg.rustEdition or "2021";
  # rustChannel = projectCfg.rustChannel or "stable"; # Or use fenix default

  # Fenix for Rust toolchains
  # You can specify a channel (stable, beta, nightly) or a specific version
  fenixToolchain = inputs.fenix.packages.${pkgs.system}.complete.withComponents [
    "cargo"
    "clippy"
    "rust-src"
    "rustc"
    "rustfmt"
    # "rust-analyzer" # rust-analyzer is often better installed via its own extension
  ];

  # Crane for Cargo builds (optional, but good for caching)
  # craneLib = inputs.crane.lib.${pkgs.system};

in
{
  # Rust language support with Fenix toolchain
  languages.rust = {
    enable = true;
    # package = fenixToolchain; # devenv uses rust-overlay by default, or can be set
    # toolchain = fenixToolchain; # If devenv has a specific option for fenix
    # Instead of above, we add fenixToolchain to pkgs directly
  };

  packages = [
    fenixToolchain # This makes cargo, rustc, etc., available
    pkgs.rust-analyzer-nightly # Or pkgs.rust-analyzer, if preferred and up-to-date
    pkgs.cargo-edit # For `cargo add/rm/upgrade`
    pkgs.cargo-watch # For `cargo watch`
    pkgs.bacon # Enhanced `cargo watch` for tests
    pkgs.cargo-audit # For auditing dependencies for security vulnerabilities
    pkgs.cargo-outdated # For checking for outdated dependencies
    pkgs.cargo-expand # To expand macros
    pkgs.clippy # Already included via fenixToolchain.complete but explicit doesn't hurt
    pkgs.rustfmt # Already included via fenixToolchain.complete

    # QoL CLI tools often used in Rust dev (some might be in base devenv.nix too)
    pkgs.ripgrep
    pkgs.fd-find # aliased to fd
    pkgs.eza # ls replacement
    pkgs.bat # cat replacement
    pkgs.zellij # Terminal multiplexer
    pkgs.git-cliff # Changelog generator
  ];

  # Environment variables for Rust
  env = {
    RUST_EDITION = rustEdition;
    # RUST_BACKTRACE = "1"; # Or "full" for more detailed backtraces
    # CARGO_TARGET_DIR = "target_devenv"; # To keep target dir separate if needed
    # For rust-analyzer to find the rust-src component from fenix
    RUST_SRC_PATH = "${fenixToolchain}/lib/rustlib/src/rust/library";
  };

  # Scripts for Rust development
  scripts = {
    build = {
      exec = "cargo build";
      description = "Build the Rust project.";
    };
    build-release = {
      exec = "cargo build --release";
      description = "Build the Rust project in release mode.";
    };
    run = {
      exec = "cargo run";
      description = "Build and run the Rust project.";
    };
    run-release = {
      exec = "cargo run --release";
      description = "Build and run the Rust project in release mode.";
    };
    test = {
      exec = "cargo test";
      description = "Run Rust tests.";
    };
    fmt = {
      exec = "cargo fmt";
      description = "Format Rust code.";
    };
    clippy = {
      exec = "cargo clippy --all-targets --all-features -- -D warnings";
      description = "Run Clippy linter with strict warnings.";
    };
    lint = { # Alias for clippy for consistency with Python
      exec = "devenv script clippy";
      description = "Lint Rust code using Clippy.";
    };
    watch-test = {
      exec = "cargo watch -x test";
      description = "Watch for changes and run tests.";
    };
    bacon-test = {
      exec = "bacon test"; # Bacon provides a better UI for `cargo watch -x test`
      description = "Run tests with bacon for a better watching experience.";
    };
    audit = {
      exec = "cargo audit";
      description = "Audit dependencies for security vulnerabilities.";
    };
    check-outdated = {
      exec = "cargo outdated";
      description = "Check for outdated dependencies.";
    };
    update-deps = {
      exec = "cargo update";
      description = "Update dependencies as per Cargo.lock.";
    };
    clean = {
      exec = "cargo clean";
      description = "Clean build artifacts.";
    };
  };

  # Pre-commit hooks for Rust
  pre-commit.hooks = {
    cargo-fmt = {
      enable = true;
      entry = "cargo fmt --all"; # Ensures all workspace members are formatted
      types = [ "rust" ];
    };
    cargo-clippy = {
      enable = true;
      entry = "cargo clippy --all-targets --all-features -- -D warnings";
      types = [ "rust" ];
      pass_filenames = false; # Clippy runs on the whole project
    };
    # cargo-check = { enable = true; entry = "cargo check"; types = ["rust"]; pass_filenames = false; };
  };

  # Additional settings for rust-analyzer if needed directly in devenv.nix
  # (though typically configured via .vscode/settings.json or coc-settings.json)
  # languages.rust.rust-analyzer.config = {
  #   checkOnSave.command = "clippy";
  #   "procMacro.enable" = true;
  # };

  enterShell = ''
    echo "   - Rust Edition: ${rustEdition}"
    # echo "   - Rust Channel: ${rustChannel} (via Fenix)"
    echo "   - To use rust-analyzer, ensure you have the extension installed in your IDE."
    echo "     It should pick up the toolchain from the environment (RUST_SRC_PATH is set)."
  '';
}
