#!/usr/bin/env bash
#
# Cut a release: build & push the multi-arch image to Docker Hub, then stamp the
# version (the VERSION file) into the `mclaude` launcher (sole update vehicle for
# wrapper users).
#
# Usage: bump the VERSION file, then:
#   ./release.sh
# Afterwards, commit and tag, e.g.
#   git commit -am "release $(cat VERSION)" && git tag "v$(cat VERSION)"
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=unimock/mclaude
BUILDER=mclaude-builder

VERSION="$(cat VERSION)"
case "$VERSION" in
  ""|*+*|*[[:space:]]*)
    echo "ERROR: VERSION '$VERSION' must be a SemVer without '+' (e.g. 0.2.0)." >&2
    exit 1 ;;
esac

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export VERSION BUILD_DATE

echo "Releasing ${IMAGE}:${VERSION} + :latest"
if [ -t 0 ]; then
  printf 'Build and PUSH to Docker Hub? [y/N] '
  read -r ans
  case "$ans" in y|Y|yes) ;; *) echo "Aborted."; exit 1 ;; esac
fi

# Ensure a docker-container builder exists for multi-platform builds.
docker buildx inspect "$BUILDER" >/dev/null 2>&1 || \
  docker buildx create --name "$BUILDER" --driver docker-container --bootstrap >/dev/null

# Tags, build args and platforms all come from docker-compose.yml.
docker buildx bake --builder "$BUILDER" --push

# Stamp the launcher so wrapper users get this version when they redeploy it.
sed -i "s/^MCLAUDE_VERSION=.*/MCLAUDE_VERSION=\"${VERSION}\"/" mclaude

cat <<EOF

Pushed ${IMAGE}:${VERSION} and :latest.
Stamped mclaude -> ${VERSION}.
Next:  git commit -am "release ${VERSION}" && git tag "v${VERSION}"
EOF
