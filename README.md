# ci-rust

Shared CI/CD pipeline for Rust CLI tools published under [x71c9](https://github.com/x71c9).

Provides four reusable GitHub Actions workflows and a set of developer scripts. Projects consume these via thin caller files — no pipeline logic lives in the project repo.

---

## Workflows

### `pr-validation.yml`

Triggered on every pull request to `master`. Runs two parallel jobs:

- **Validate PR Title** — enforces [conventional commit](https://www.conventionalcommits.org/) format (`feat:`, `fix:`, `chore!:`, etc.). The PR title becomes the squash commit message and drives automatic version bumping.
- **Run Tests** — `cargo build`, `cargo test`, `cargo fmt --check`, `cargo clippy -D warnings`.

Both jobs must be green before a merge is allowed (enforced via branch protection).

### `release-on-merge.yml`

Triggered when a PR is merged to `master`. Determines the semver bump from the PR title (`feat!` → major, `feat` → minor, everything else → patch), runs `cargo release`, publishes to [crates.io](https://crates.io), creates a git tag, then fans out to `build-release.yml`.

### `build-release.yml`

Builds binaries for four targets:

| Target | Runner |
|---|---|
| `aarch64-apple-darwin` | `macos-latest` (native) |
| `x86_64-apple-darwin` | `macos-latest` (native) |
| `x86_64-unknown-linux-gnu` | `ubuntu-latest` via `cross` |
| `aarch64-unknown-linux-gnu` | `ubuntu-latest` via `cross` |

Creates a GitHub Release with all four tarballs, triggers a Homebrew tap update via `repository_dispatch`, then fans out to `update-packages.yml`.

### `update-packages.yml`

Updates three package repositories in parallel after a release:

- **AUR** (`<name>` source package + `<name>-bin` binary package) — creates the AUR repo on first publish if it doesn't exist yet.
- **NUR** (`x71c9/nur-packages`) — scaffolds `pkgs/<name>/default.nix` on first publish, registers the package in the root `default.nix`, and updates `version`, source `hash`, and `Cargo.lock` on every release.

---

## Required secrets

Configure these in each consuming project's repository secrets:

| Secret | Used by |
|---|---|
| `BYPASS_BRANCH_RULE_PAT` | `release-on-merge` — pushes the version bump commit through branch protection |
| `CARGO_REGISTRY_TOKEN` | `release-on-merge` — publishes to crates.io |
| `HOMEBREW_PAT` | `build-release` — triggers the Homebrew tap update |
| `AUR_SECRET_KEY` | `update-packages` — SSH private key registered with AUR |
| `NUR_PAT` | `update-packages` — GitHub PAT with write access to `x71c9/nur-packages` |

---

## Using in a project

Add two files to your project's `.github/workflows/`. No other pipeline files are needed.

### `.github/workflows/pr-validation.yml`

```yaml
---
name: PR Validation
on:
  pull_request:
    branches: [master]
    types: [opened, synchronize, edited]
permissions:
  contents: read
  pull-requests: write
jobs:
  validate:
    uses: x71c9/ci-rust/.github/workflows/pr-validation.yml@master
    with:
      extra_apt_packages: ""   # e.g. "libxcb1-dev libwayland-dev"
```

### `.github/workflows/release-on-merge.yml`

```yaml
---
name: Release on PR Merge
on:
  pull_request:
    types: [closed]
    branches: [master]
permissions:
  contents: write
jobs:
  release:
    uses: x71c9/ci-rust/.github/workflows/release-on-merge.yml@master
    with:
      crate_name: my-crate          # name in Cargo.toml (may differ from binary)
      binary_name: my-tool          # actual binary name
      pkgdesc: "Short description of the tool"
      # aur_depends: "'glibc'"      # default; add extra deps if needed
      # nur_build_inputs: ""        # nixpkgs attrs for buildInputs, e.g. "libxcb"
      # extra_apt_packages: ""      # apt packages for the release runner
      # macos_extra_brew: ""        # e.g. "--cask xquartz"
      # macos_extra_env: ""         # e.g. "LIBRARY_PATH=/opt/X11/lib PKG_CONFIG_PATH=/opt/X11/lib/pkgconfig"
      # has_shell_completions: false
      # completion_subcommand: "completion"
    secrets: inherit
```

### One-time setup

Run once after cloning to install the git pre-commit hook (enforces `rustfmt` on staged files before committing):

```sh
./scripts/install-hooks.sh
```

Run once after creating the GitHub repo to configure branch protection:

```sh
./scripts/setup-branch-protection.sh
```

---

## Scripts

| Script | Purpose |
|---|---|
| `scripts/install-hooks.sh` | Points git at `scripts/hooks/` via `core.hooksPath` |
| `scripts/hooks/pre-commit` | Runs `rustfmt --check` on staged `.rs` files before each commit |
| `scripts/setup-branch-protection.sh` | Configures required status checks on `master` via the GitHub API |
| `scripts/fetch-rebase.sh` | Fetches `origin/master` (with tags) and rebases the current branch |

Copy the `scripts/` directory into your project repo and run `install-hooks.sh` once.

---

## Installing packages

Once a project is published through this pipeline, it is available on multiple platforms.

### Cargo

```sh
cargo install <crate-name>
```

### Homebrew (macOS / Linux)

```sh
brew tap x71c9/x71c9
brew install <name>
```

### Arch Linux — AUR (source build)

Compiles from source. Using any AUR helper:

```sh
paru -S <name>
# or
yay -S <name>
```

Or manually:

```sh
git clone https://aur.archlinux.org/<name>.git
cd <name>
makepkg -si
```

### Arch Linux — AUR (pre-built binary)

Installs the pre-built binary from the GitHub Release. Faster than the source build and provides the same binary. Conflicts with the source package — install one or the other.

```sh
paru -S <name>-bin
# or
yay -S <name>-bin
```

Both AUR packages (`<name>` and `<name>-bin`) are created automatically on first release — no manual AUR setup required.

### NixOS / Nix

Add the NUR overlay to your configuration, then:

```nix
# configuration.nix or home.nix
environment.systemPackages = [
  nur.repos.x71c9.<name>
];
```

Or try it without installing:

```sh
nix-shell -p nur.repos.x71c9.<name>
```
