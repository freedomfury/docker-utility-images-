#!/usr/bin/env bash
# bin/check-matrix.sh

MATRIX_LIST=("hello-a" "hello-b" "hello-c")
EXCLUDED=("lib" "bin" ".harness" ".git" "docs")
MISSING=()

for dir in */; do
  container=$(basename "$dir")

  # Skip known non-container directories
  if [[ " ${EXCLUDED[*]} " =~ " ${container} " ]]; then
    continue
  fi

  # Check if it is in the matrix
  if [[ ! " ${MATRIX_LIST[*]} " =~ " ${container} " ]]; then
    MISSING+=("$container")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: The following container folders are not declared in the pipeline matrix:"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
  done
  echo ""
  echo "Add them to the matrix in pr-pipeline.yaml and main-pipeline.yaml before merging."
  exit 1
fi

echo "Matrix check passed. All container folders are accounted for."
