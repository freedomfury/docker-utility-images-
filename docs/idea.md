# Docker Utility Images — GitHub Actions CI/CD Design

## Overview

Monorepo for building, scanning, and publishing utility Docker containers via GitHub Actions. Migrated from Harness CI/CD.

## Repository Structure

```
/
├── hello-a/                  # Placeholder container
├── hello-b/                  # Placeholder container
├── hello-c/                  # Placeholder container
├── lib/
│   └── build-utils.sh        # Shared bash functions: needs_build, do_build, do_push
├── bin/                      # Standalone scripts (check-matrix.sh removed — replaced by dynamic matrix)
├── .github/
│   └── workflows/
│       ├── pr.yml            # PR validation — lint only
│       ├── main.yml          # Push to main — lint, build-if-changed, scan, SBOM, push, release
│       └── scheduled.yml     # Weekly rebuild — unconditional build, scan, SBOM, push
└── docs/
    └── idea.md               # This file
```

### Conventions

- Every folder at the repo root that is not `lib`, `bin`, `.github`, `.git`, `docs`, or `exports` is a container.
- Each container folder contains at minimum a `Dockerfile`.
- `lib/` holds shared bash functions sourced by pipeline steps.
- The matrix is generated dynamically by scanning the repo root — no hardcoded list.

---

## Workflows

### PR Workflow (`pr.yml`)

Triggers on `pull_request` to any branch. **Lint only — no build, no push.**

**Jobs:**
1. `discover` — scans root dirs, excludes non-container folders, outputs JSON matrix
2. `lint` (matrix: container) — depends on `discover`
   - Shellcheck: `shellcheck lib/build-utils.sh`
   - Hadolint: `hadolint <container>/Dockerfile`

---

### Main Workflow (`main.yml`)

Triggers on `push` to `main`. **Lint → build-if-changed → scan → SBOM → push → release.**

**Jobs:**
1. `discover` — dynamic matrix generation
2. `lint` (matrix: container) — shellcheck + hadolint
3. `build-and-push` (matrix: container, needs: lint)
   - Install skopeo
   - **Build If Changed** — sources `lib/build-utils.sh`, calls `needs_build()` which hashes the container folder and compares against the `build.source.hash` Docker label on the registry image via Skopeo. Builds with `do_build()` only if changed.
   - **Smoke Test** *(not yet implemented — add when containers become real workloads)* — if built: `docker run --rm <image>` and assert exit code 0. For long-running services: run detached, hit a health endpoint, then stop. Lives between Build and Trivy scan, gated on `BUILD_NEEDED == 'true'`.
   - **Trivy Scan** — if built: `trivy image --format json --output trivy-report-<container>.json`
   - **SBOM** — if built: `trivy image --format cyclonedx --output sbom-<container>.cdx.json`
   - **Docker Push** — if built: `do_push()` from `build-utils.sh`
   - **Upload artifacts** — Trivy report + SBOM uploaded via `actions/upload-artifact`
4. `release` (needs: all build-and-push jobs)
   - Downloads all artifacts
   - Creates date-based tag: `v<YYYY.MM.DD>` (e.g. `v2026.04.20`)
   - Cuts a GitHub Release with all Trivy reports and SBOMs attached as release assets

**Per-container release assets:**
```
trivy-report-hello-a.json    ← vulnerability scan
sbom-hello-a.cdx.json        ← CycloneDX SBOM (contents of that image only)
trivy-report-hello-b.json
sbom-hello-b.cdx.json
...
```

---

### Scheduled Workflow (`scheduled.yml`)

Triggers on cron `0 2 * * 1` (Monday 02:00 UTC). **Unconditional rebuild, scan, SBOM, push of all containers** to pick up base image security patches.

**Jobs:**
1. `discover` — dynamic matrix generation
2. `rebuild` (matrix: container)
   - Unconditional build (computes hash, calls `do_build()` directly)
   - Trivy scan + SBOM (always runs)
   - Docker push (always runs)
   - Upload artifacts

---

## Dynamic Matrix Discovery

All three workflows use the same pattern. A `discover` job scans the repo root:

```bash
EXCLUDED=".git .github lib bin docs exports"
dirs=()
for d in */; do
  name="${d%/}"
  skip=false
  for ex in $EXCLUDED; do [ "$name" = "$ex" ] && skip=true; done
  $skip || dirs+=("$name")
done
echo "matrix=$(jq -cn '$ARGS.positional' --args "${dirs[@]}")" >> "$GITHUB_OUTPUT"
```

Downstream jobs consume it:
```yaml
strategy:
  matrix:
    container: ${{ fromJson(needs.discover.outputs.matrix) }}
```

Adding a new container folder is zero-config — no workflow edits needed.

---

## Hash-Based Change Detection

Registry-native, CI-agnostic — no dependency on git diff.

1. Hash all files in the container folder: `find <dir> -type f | sort | xargs sha256sum | sha256sum`
2. Bake the hash into the image as a Docker label: `build.source.hash=<hash>`
3. On next run, Skopeo inspects the registry image label without pulling layers
4. If hashes match → skip. If they differ (or image doesn't exist) → build.

Implemented in `lib/build-utils.sh` (`needs_build`, `do_build`, `do_push`). The function is CI-agnostic — it does not reference any GitHub Actions primitives.

---

## GitHub Secrets & Variables

### Repository Secrets
| Secret | Description |
|---|---|
| `DOCKER_HUB_TOKEN` | Docker Hub access token for push |
| `MINIO_PASS` | *(kept for local reference — not used in workflows)* |

### Repository Variables
| Variable | Value | Description |
|---|---|---|
| `DOCKER_USERNAME` | `freedomfury` | Docker Hub namespace |

> MinIO is **not used** in GitHub Actions workflows. Trivy reports and SBOMs are stored as GitHub Release assets and workflow run artifacts (`actions/upload-artifact`, 90-day retention).

---

## Variable Mapping (Harness → GitHub Actions)

| Harness | GitHub Actions | Type |
|---|---|---|
| `<+matrix.container>` | `${{ matrix.container }}` | Matrix value |
| `<+variable.dockeruser>` | `${{ vars.DOCKER_USERNAME }}` | Repo variable |
| `<+secrets.getValue("docker-hub-token")>` | `${{ secrets.DOCKER_HUB_TOKEN }}` | Repo secret |
| `${HARNESS_WORKSPACE}/build-state.env` | `$GITHUB_ENV` | Built-in |
| Harness delegate | `runs-on: ubuntu-latest` | Runner |
| Harness template (Stage/StepGroup) | Inline steps (optimize later) | — |

---

## Adding a New Container

1. Create a folder at the repo root with a `Dockerfile`.
2. Open a PR — lint runs automatically against the new Dockerfile.
3. Merge to main — the new container is built, scanned, pushed, and included in the release.

No matrix list to update. No guard script to maintain.

---

## Prerequisites

Before running workflows, ensure the following exist on `freedomfury/docker-utility-images-`:

- **Secrets:** `DOCKER_HUB_TOKEN`
- **Variables:** `DOCKER_USERNAME`

## Dependencies

| Tool | How it runs | Purpose |
|---|---|---|
| Docker CLI | Pre-installed on `ubuntu-latest` | Build and push images |
| Skopeo | `apt-get install -y skopeo` | Inspect registry labels without pulling |
| Hadolint | `apt-get install -y hadolint` | Dockerfile linting |
| Shellcheck | Pre-installed on `ubuntu-latest` | Bash script linting |
| Trivy | `aquasec/trivy` action or binary | Vulnerability scan + SBOM |
