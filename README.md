# Docker Utility Images

Monorepo for building, scanning, and publishing utility Docker containers via Harness CI/CD pipelines.

## Repository Structure

```
/
├── hello-a/                  # Placeholder container (to be replaced)
├── hello-b/                  # Placeholder container (to be replaced)
├── hello-c/                  # Placeholder container (to be replaced)
├── lib/
│   └── build-utils.sh        # Shared bash functions (needs_build, do_build, do_push)
├── bin/
│   └── check-matrix.sh       # Matrix guard — fails if a container folder is missing from pipelines
├── .harness/
│   └── orgs/default/projects/default_project/
│       ├── pipelines/
│       │   ├── pr-pipeline.yaml         # PR validation — lint only
│       │   ├── main-pipeline.yaml       # Merge to main — lint, build, scan, push
│       │   └── scheduled-pipeline.yaml  # Weekly rebuild — unconditional build, scan, push
│       └── templates/
│           ├── lint-build-stage.yaml    # Reusable lint stage (shellcheck + hadolint)
│           └── trivy-scan-upload.yaml   # Reusable Trivy scan + MinIO upload step group
└── docs/
```

### Conventions

- Every folder at the root that is not `lib`, `bin`, `.harness`, `.git`, or `docs` is a container.
- Each container folder contains at minimum a `Dockerfile`.
- `lib/` holds shared bash functions sourced by pipeline steps.
- `bin/` holds standalone scripts executed directly by pipelines.

## Pipelines

### PR Pipeline

Runs on pull requests. **Lint only — no build, no push.**

1. **Matrix Check** — verifies every container folder is in the pipeline matrix.
2. **Shellcheck** — lints `lib/build-utils.sh` and `bin/check-matrix.sh`.
3. **Hadolint** — lints each container's Dockerfile.

### Main Pipeline

Runs on merge to `main`. **Lint, then build/scan/push only if content changed.**

1. **Lint stage** — same as PR (matrix check, shellcheck, hadolint).
2. **Build If Changed** — hashes the container folder, compares against the registry label via Skopeo. Builds only if changed.
3. **Trivy Scan** — scans the built image, uploads JSON report to MinIO with a 7-day presigned URL.
4. **Push** — pushes to Docker Hub if a build occurred.

### Scheduled Pipeline

Runs weekly (Monday 02:00 UTC). **Unconditional rebuild, scan, and push of all containers** to pick up base image security patches.

## Hash-Based Change Detection

Change detection is registry-native and CI-agnostic — no dependency on git diff or Harness path filters.

1. Hash all files in the container folder: `find <dir> -type f | sort | xargs sha256sum | sha256sum`
2. Bake the hash into the image as a Docker label: `build.source.hash=<hash>`
3. On next run, Skopeo inspects the registry image label without pulling layers.
4. If hashes match, skip. If they differ (or the image doesn't exist yet), build.

## Adding a New Container

1. Create a folder at the repo root with a `Dockerfile`.
2. Add the folder name to the matrix list in all three pipeline YAMLs.
3. Add it to `MATRIX_LIST` in `bin/check-matrix.sh`.
4. Open a PR — the matrix guard will verify coverage.

If step 2 or 3 is forgotten, `check-matrix.sh` fails the pipeline with a clear error.

## Environment Variable Convention

All JEXL expressions (Harness runtime values) are bound in the `envVariables` section of each step. Bash command blocks contain zero JEXL. Variables use the `HA_` prefix (Harness Automation) to own the namespace:

| Variable | Source |
|---|---|
| `HA_CONTAINER` | `<+matrix.container>` |
| `HA_DOCKER_USERNAME` | `<+project.variables.dockeruser>` |
| `HA_DOCKER_HUB_TOKEN` | `<+secrets.getValue("docker-hub-token")>` |
| `HA_MINIO_URL` | `<+project.variables.miniourl>` |
| `HA_MINIO_USER` | `<+project.variables.miniouser>` |
| `HA_MINIO_PASS` | `<+secrets.getValue("minio-pass")>` |

## Template Design

Templates are pure functions — they declare explicit inputs and never reference project variables directly. Callers own the variable bindings:

```yaml
# Caller passes project variables as template inputs
templateInputs:
  spec:
    inputs:
      - name: docker_username
        value: <+project.variables.dockeruser>
```

## Prerequisites

Before running pipelines, ensure the following exist in Harness:

- **Secrets:** `docker-hub-token`, `minio-pass`
- **Project variables:** `dockeruser`, `miniourl`, `miniouser`
- **Connector:** `docker-default` (Docker Hub)
- **Delegate:** `image-flow-delegate`

## Dependencies

| Tool | Image | Purpose |
|---|---|---|
| Docker CLI | `docker:27-cli` | Build and push images |
| Skopeo | (via `build-utils.sh`) | Inspect registry labels without pulling |
| Hadolint | `hadolint/hadolint:latest` | Dockerfile linting |
| Shellcheck | `koalaman/shellcheck-alpine:stable` | Bash script linting |
| Trivy | `aquasec/trivy:latest` | Container vulnerability scanning |
| MinIO Client | `minio/mc:latest` | Upload scan reports |
