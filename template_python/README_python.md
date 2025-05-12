## Python Specifics for {{PROJECT_NAME}}

This project uses Python {{PYTHON_VERSION}}.

### Environment Setup

1.  **Initialize the Python Environment (Virtual Environment & Dependencies):**
    ```bash
    just setup
    # OR
    devenv script setup-python
    ```
    This command will:
    - Create a virtual environment in `.venv/` using `uv` (if it doesn't exist).
    - Install dependencies listed in `pyproject.toml` into the `.venv/` using `uv pip sync`.

2.  **Activate the Virtual Environment:**
    ```bash
    source .venv/bin/activate
    ```
    Your shell prompt should change to indicate the active venv.

### Dependency Management

- Dependencies are managed in `pyproject.toml`.
- After adding or updating dependencies in `pyproject.toml`, re-run `just setup` or `devenv script setup-python` to update your `.venv/`.
- If `manageDependenciesWithUv2nix = true;` was chosen during project initialization (see `project_config.nix`):
    - You can generate a `uv.nix` file from `pyproject.toml` for Nix-based dependency management:
      ```bash
      just generate-uv-nix
      # OR
      devenv script generate-uv-nix
      ```
    - This `uv.nix` can then be imported into your `devenv.nix` to provide Python packages directly through Nix, offering more robust reproducibility. (Manual step to integrate `uv.nix` into `devenv.nix` might be needed).

### Key Tools & Tasks

- **`uv`**: Used for creating virtual environments and installing packages. It's a fast alternative to `pip` and `venv`.
- **`ruff`**: For linting and formatting. Integrated into `just lint` and `just format`.
- **`ty`**: For static type checking. Integrated into `just type-check` and part of `just lint`.
- **`pytest`**: For running tests. Use `just test`.

### VS Code Integration

- Recommended VS Code extensions:
    - `ms-python.python` (Pylance for IntelliSense, debugging)
    - `charliermarsh.ruff` (Ruff integration)
- The provided `.vscode/settings.json_template` (copied to `.vscode/settings.json`) configures:
    - Ruff as the default formatter and linter.
    - Python interpreter path to point to the one managed by `devenv` (and potentially the `.venv`).
    - Enables `debugpy` for debugging.
- Ensure your VS Code is using the Python interpreter from the `.venv/` directory once it's created and activated for the best experience with tools like Pylance.

### Running the Application

If your project has a main entry point (e.g., `src/{{PROJECT_NAME_SNAKE_CASE}}/main.py`), you can run it using:
```bash
just run
# or with arguments
just run --some-arg value
```
This uses `uv run` which executes the command within the context of the managed environment.

### Common `just` tasks for Python:

- `just setup`: Create/update `.venv` and install dependencies.
- `just lint`: Run Ruff and Ty.
- `just format`: Format code with Ruff.
- `just type-check`: Run Ty.
- `just test`: Run Pytest.
- `just run`: Run the main application (if configured).
- `just generate-uv-nix`: (If `manageDependenciesWithUv2nix = true`) Generate `uv.nix`.
