# Docker Utility Images

Monorepo for building, scanning, and publishing utility Docker containers via GitHub Actions.

## Repository Structure

```
/
├── hello-a/                  # Placeholder container (to be replaced)
├── hello-b/                  # Placeholder container (to be replaced)
├── hello-c/                  # Placeholder container (to be replaced)
├── lib/
│   └── build-utils.sh        # Shared bash functions (needs_build, do_build, do_push)
├── .github/
│   └── workflows/
│       ├── pr.yml            # PR validation — lint only
│       ├── main.yml          # Push to main — lint, build-if-changed, scan, SBOM, push, release
│       └── scheduled.yml     # Weekly rebuild — unconditional build, scan, SBOM, push
└── docs/
    └── idea.md               # Design document
```

### Conventions

- Every folder at the repo root that is not `lib`, `bin`, `.github`, `.git`, `docs`, or `exports` is a container.
- Each container folder contains at minimum a `Dockerfile`.
- `lib/` holds shared bash functions sourced by workflow steps.
- The matrix is generated dynamically by scanning the repo root — no hardcoded list to maintain.

## Workflows

### PR Workflow

Runs on pull requests. **Lint only — no build, no push.**

1. **Discover** — scans root dirs dynamically and builds the container matrix.
2. **Shellcheck** — lints `lib/build-utils.sh`.
3. **Hadolint** — lints each container's Dockerfile.

### Main Workflow

Runs on push to `main`. **Lint → build-if-changed → scan → SBOM → push → release.**

1. **Discover** — dynamic matrix generation.
2. **Lint** — shellcheck + hadolint per container.
3. **Build If Changed** — hashes the container folder, compares against the registry label via Skopeo. Builds only if changed.
4. **Trivy Scan** — scans the built image, outputs JSON report.
5. **SBOM** — generates a CycloneDX SBOM for the built image.
6. **Push** — pushes to Docker Hub if a build occurred.
7. **Release** — once all matrix jobs succeed, creates a date-stamped GitHub Release (`v2026.04.20-1430`) with all Trivy reports and SBOMs attached as assets.

### Scheduled Workflow

Runs weekly (Monday 02:00 UTC). **Unconditional rebuild, scan, SBOM, and push of all containers** to pick up base image security patches. Supports `workflow_dispatch` for manual testing.

## Hash-Based Change Detection

Change detection is registry-native and CI-agnostic — no dependency on git diff.

1. Hash all files in the container folder: `find <dir> -type f | sort | xargs sha256sum | sha256sum`
2. Bake the hash into the image as a Docker label: `build.source.hash=<hash>`
3. On next run, Skopeo inspects the registry image label without pulling layers.
4. If hashes match, skip. If they differ (or the image doesn't exist yet), build.

## Adding a New Container

1. Create a folder at the repo root with a `Dockerfile`.
2. Open a PR — lint runs automatically against the new Dockerfile.
3. Merge to main — the new container is built, scanned, pushed, and included in the release.

No matrix list to update. No guard script to maintain.

## Prerequisites

Before running workflows, ensure the following exist on the repository:

- **Secrets:** `DOCKER_HUB_TOKEN`
- **Variables:** `DOCKER_USERNAME` (set to your Docker Hub namespace)

## Dependencies

| Tool | How it runs | Purpose |
|---|---|---|
| Docker CLI | Pre-installed on `ubuntu-latest` | Build and push images |
| Skopeo | `apt-get install -y skopeo` | Inspect registry labels without pulling |
| Hadolint | Downloaded at runtime | Dockerfile linting |
| Shellcheck | Pre-installed on `ubuntu-latest` | Bash script linting |
| Trivy | `aquasecurity/trivy-action` | Vulnerability scan + CycloneDX SBOM |
