#!/usr/bin/env bash
# Build + push the multi-arch image as :latest and :<VERSION> to Docker Hub.
# Sets VERSION/BUILD_DATE itself from the VERSION file, so a fresh shell can't fall
# back to the bake `latest` default and push an unversioned image.
#   Usage: ./push.sh [extra docker buildx bake args]
set -euo pipefail
cd "$(dirname "$0")"

BUILDER=mclaude-builder

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "push.sh: VERSION file must hold a Claude Code release (x.y.z), got '$VERSION'" >&2
  exit 1
fi
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export VERSION BUILD_DATE

# We build FROM unimock/mclaude:<VERSION>; it must be published first.
if ! docker buildx imagetools inspect "unimock/mclaude:${VERSION}" >/dev/null 2>&1; then
  echo "push.sh: base image unimock/mclaude:${VERSION} not found in the registry, push it first" >&2
  exit 1
fi

# Multi-platform builds need a docker-container builder.
docker buildx inspect "$BUILDER" >/dev/null 2>&1 || \
  docker buildx create --name "$BUILDER" --driver docker-container --bootstrap >/dev/null

# Refuse to push unless bake really resolved the versioned tag.
if ! docker buildx bake --builder "$BUILDER" --print release 2>/dev/null | grep -q "\"unimock/mclaude-docker:${VERSION}\""; then
  echo "push.sh: bake did not resolve tag unimock/mclaude-docker:${VERSION}, aborting" >&2
  exit 1
fi

echo "Pushing unimock/mclaude-docker:${VERSION} + :latest (build date ${BUILD_DATE})"
docker buildx bake --builder "$BUILDER" --push release "$@"
