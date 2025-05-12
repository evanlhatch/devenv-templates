## Rust Specifics for {{PROJECT_NAME}}

This project uses Rust with edition `{{RUST_EDITION}}`.

### Toolchain

- The Rust toolchain (compiler, Cargo, clippy, rustfmt) is provided by **Fenix** through Nix, ensuring a consistent version defined in the template's `flake.nix` and `rust_devenv_module.nix`.
- **`rust-analyzer`** is also included in the devenv environment. You should install the `rust-analyzer` extension in your IDE (e.g., VS Code). It will use the toolchain from the environment.

### Key Tools & Tasks

- **`cargo`**: The Rust package manager and build tool.
- **`clippy`**: Rust linter for catching common mistakes and improving code quality. Run with `just clippy` or `just lint`.
- **`rustfmt`**: Rust code formatter. Run with `just fmt` or `just format`.
- **`cargo-edit`**: Allows easy modification of `Cargo.toml` (e.g., `cargo add <crate>`).
- **`cargo-watch`**: Watches for file changes and re-runs commands (e.g., `just watch-test`).
- **`bacon`**: An enhanced version of `cargo watch` for a better testing feedback loop. Use `just bacon`.
- **`cargo-audit`**: Checks for security vulnerabilities in dependencies. Run with `just audit`.
- **`cargo-outdated`**: Checks for outdated dependencies. Run with `just check-outdated`.

### VS Code Integration

- **Recommended Extension**: `rust-lang.rust-analyzer`.
- The provided `.vscode/settings.json_template` (copied to `.vscode/settings.json`) configures:
    - `rust-analyzer` as the preferred tool for Rust support.
    - Formatting on save using `rustfmt`.
    - Clippy checks on save.
- Ensure the `rust-analyzer` extension is installed in VS Code. It should automatically detect and use the Rust toolchain provided by the `devenv` environment.

### Building the Project

- Debug build: `just build` (or `cargo build`)
- Release build: `just build-release` (or `cargo build --release`)

### Running the Project

- Debug: `just run` (or `cargo run`)
- Release: `just run-release` (or `cargo run --release`)

### Testing

- Run tests: `just test` (or `cargo test`)
- Watch tests with `cargo-watch`: `just watch-test`
- Watch tests with `bacon`: `just bacon` (or `just bacon-test`)

### Common `just` tasks for Rust:

- `just build` / `just build-release`
- `just run` / `just run-release`
- `just test`
- `just fmt` (or `just format`)
- `just clippy` (or `just lint`)
- `just watch-test` (uses `cargo watch`)
- `just bacon` (uses `bacon` for better test watching)
- `just audit`
- `just check-outdated` (or `just outdated`)
- `just update-deps`
- `just clean`
