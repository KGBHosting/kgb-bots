#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMXX_VERSION="${AMXX_VERSION:-1.8.2}"
DOCKER_IMAGE="${DOCKER_IMAGE:-debian:bookworm}"

case "$AMXX_VERSION" in
	1.8 | 1.8.2)
		AMXX_VERSION="1.8.2"
		AMXX_URL="${AMXX_URL:-https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.2-dev-hg34-base.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-8a8293df0f9cc4ab1f2040b60e7cbd5ac86ee95c0fda2d40b344f12ed18bc5cc}"
		;;
	1.9)
		AMXX_URL="${AMXX_URL:-https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5303-base-linux.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-1ed6898ced2c1fcf225c288b94effc19917e987b284e42911587738ee3c93699}"
		;;
	1.10)
		AMXX_URL="${AMXX_URL:-https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5479/amxmodx-1.10.0-git5479-base-linux.tar.gz}"
		AMXX_SHA256="${AMXX_SHA256:-425b53256dbad0ddaeb7935f771d07d85b6c146ed7d1e72d815221042030602d}"
		;;
	*)
		printf 'Unsupported AMXX_VERSION: %s\n' "$AMXX_VERSION" >&2
		printf 'Supported values: 1.8.2, 1.9, 1.10\n' >&2
		exit 1
		;;
esac

AMXX_ARCHIVE_NAME="${AMXX_URL##*/}"
AMXX_CACHE_DIR="$ROOT_DIR/.ci/amxx/$AMXX_VERSION"
AMXX_ARCHIVE="$ROOT_DIR/.ci/downloads/$AMXX_VERSION/$AMXX_ARCHIVE_NAME"
DEFAULT_AMXX_DIR="$AMXX_CACHE_DIR/addons/amxmodx/scripting"
AMXX_DIR="${AMXX_DIR:-$DEFAULT_AMXX_DIR}"

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

verify_archive() {
	test -f "$AMXX_ARCHIVE" && test "$(hash_file "$AMXX_ARCHIVE")" = "$AMXX_SHA256"
}

ensure_amxx() {
	if test -x "$AMXX_DIR/amxxpc" \
		&& test -f "$AMXX_DIR/include/amxmodx.inc" \
		&& test -f "$AMXX_DIR/include/amxmisc.inc" \
		&& test -f "$AMXX_DIR/include/cstrike.inc" \
		&& test -f "$AMXX_DIR/include/fakemeta.inc"; then
		return
	fi

	if test "$AMXX_DIR" != "$DEFAULT_AMXX_DIR"; then
		printf 'AMXX_DIR is missing the required compiler files: %s\n' "$AMXX_DIR" >&2
		exit 1
	fi

	mkdir -p "$(dirname "$AMXX_ARCHIVE")"

	if ! verify_archive; then
		curl --fail --location --show-error --silent "$AMXX_URL" --output "$AMXX_ARCHIVE"
	fi

	if ! verify_archive; then
		printf 'AMX Mod X archive checksum did not match expected SHA-256.\n' >&2
		exit 1
	fi

	rm -rf "$AMXX_CACHE_DIR"
	mkdir -p "$AMXX_CACHE_DIR"
	tar -xzf "$AMXX_ARCHIVE" -C "$AMXX_CACHE_DIR"

	if ! test -x "$AMXX_DIR/amxxpc"; then
		printf 'AMX Mod X compiler was not found after extraction.\n' >&2
		exit 1
	fi
}

if ! command -v docker >/dev/null 2>&1; then
	printf 'Docker is required to compile the 32-bit AMX Mod X plugin.\n' >&2
	exit 1
fi

ensure_amxx
mkdir -p "$ROOT_DIR/compiled"
printf 'Compiling with AMX Mod X %s\n' "$AMXX_VERSION"

docker run --rm --pull=missing --platform linux/386 --network none \
	-v "$ROOT_DIR:/work" \
	-v "$AMXX_DIR:/amxx:ro" \
	-e LD_LIBRARY_PATH=/amxx \
	-w /work \
	"$DOCKER_IMAGE" \
	/amxx/amxxpc src/kgbbots.sma -i/amxx/include -ocompiled/kgbbots.amxx
