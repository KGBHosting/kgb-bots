#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS="${AMXX_COMPAT_VERSIONS:-1.8.2 1.9 1.10}"

for version in $VERSIONS; do
	printf '\n== AMX Mod X %s ==\n' "$version"
	AMXX_VERSION="$version" "$ROOT_DIR/scripts/build.sh"
done
