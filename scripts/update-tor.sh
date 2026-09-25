#!/bin/bash
# Update the Dockerfile (and README example) to the latest stable Tor release
# published on dist.torproject.org. Only moves forward: never downgrades.
#
# Prints the new version on stdout when an update was applied, nothing otherwise.
set -euo pipefail

DIST_URL="${DIST_URL:-https://dist.torproject.org}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/Dockerfile"
README="$REPO_ROOT/README.md"

current="$(sed -n 's/^ARG VERSION=//p' "$DOCKERFILE")"
if [ -z "$current" ]; then
    echo "Could not read current version from $DOCKERFILE" >&2
    exit 1
fi

# Stable releases only: four numeric components, no -alpha/-rc suffix.
latest="$(curl -fsSL "$DIST_URL/" |
    grep -oE 'tor-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz"' |
    sed -E 's/^tor-(.*)\.tar\.gz"$/\1/' |
    sort -uV | tail -n 1)"
if [ -z "$latest" ]; then
    echo "Could not determine latest Tor release from $DIST_URL" >&2
    exit 1
fi

echo "Current: $current, latest stable: $latest" >&2

newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)"
if [ "$latest" = "$current" ] || [ "$newest" != "$latest" ]; then
    echo "Already up to date" >&2
    exit 0
fi

sha256="$(curl -fsSL "$DIST_URL/tor-$latest.tar.gz.sha256sum" | awk '{print $1}')"
if ! [[ "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Invalid sha256 for tor-$latest: '$sha256'" >&2
    exit 1
fi
# The checksum file itself is GPG-verified during the image build.

sed -i \
    -e "s/^ARG VERSION=.*/ARG VERSION=$latest/" \
    -e "s/^ARG TOR_TARBALL_SHA256=.*/ARG TOR_TARBALL_SHA256=$sha256/" \
    "$DOCKERFILE"
sed -i -E "s/(docker-tor:)$(printf '%s' "$current" | sed 's/\./\\./g')\b/\1$latest/g" "$README"

echo "$latest"
