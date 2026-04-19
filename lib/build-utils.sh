#!/usr/bin/env bash
# lib/build-utils.sh

needs_build() {
  local container=$1
  local registry=$2

  if [ -z "$container" ] || [ -z "$registry" ]; then
    echo "Usage: needs_build <container> <registry>" >&2
    return 1
  fi

  local image="${registry}/${container}:latest"

  local current_hash
  current_hash=$(find "${container}" -type f | sort \
    | xargs sha256sum | sha256sum | awk '{print $1}')

  local last_hash
  last_hash=$(skopeo inspect --format '{{ index .Labels "build.source.hash" }}' "docker://${image}" 2>/dev/null || true)
  if [ -z "$last_hash" ] || [ "$last_hash" = "<no value>" ]; then
    last_hash="none"
  fi

  if [ "$current_hash" = "$last_hash" ]; then
    echo "[${container}] No changes detected, skipping build."
    return 1
  fi

  export BUILD_HASH="$current_hash"
  return 0
}

do_build() {
  local container=$1
  local registry=$2
  local image="${registry}/${container}:latest"

  echo "[${container}] Building..."
  docker build \
    --label "build.source.hash=${BUILD_HASH}" \
    -t "${image}" \
    "${container}/"
}

do_push() {
  local container=$1
  local registry=$2
  local image="${registry}/${container}:latest"

  echo "[${container}] Pushing..."
  docker push "${image}"
}
