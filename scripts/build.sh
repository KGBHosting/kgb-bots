#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMXX_URL="${AMXX_URL:-https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.2-dev-hg34-base.tar.gz}"
AMXX_SHA256="${AMXX_SHA256:-8a8293df0f9cc4ab1f2040b60e7cbd5ac86ee95c0fda2d40b344f12ed18bc5cc}"
AMXX_CACHE_DIR="$ROOT_DIR/.ci/amxx"
AMXX_ARCHIVE="$AMXX_CACHE_DIR/amxmodx-base.tar.gz"
AMXX_ARCHIVE_NAME="$(basename "$AMXX_ARCHIVE")"
AMXX_REPO_DIR="$AMXX_CACHE_DIR/addons/amxmodx/scripting"

mkdir -p "$ROOT_DIR/compiled"

verify_archive()
{
	if command -v sha256sum >/dev/null 2>&1; then
		(
			cd "$AMXX_CACHE_DIR"
			printf '%s  %s\n' "$AMXX_SHA256" "$AMXX_ARCHIVE_NAME" | sha256sum --check -
		)
		return
	fi

	if command -v shasum >/dev/null 2>&1; then
		actual_sha="$(shasum -a 256 "$AMXX_ARCHIVE" | awk '{print $1}')"

		if [[ "$actual_sha" == "$AMXX_SHA256" ]]; then
			printf '.ci/amxx/%s: OK\n' "$AMXX_ARCHIVE_NAME"
			return
		fi

		printf 'Checksum mismatch for .ci/amxx/%s\nexpected: %s\nactual:   %s\n' "$AMXX_ARCHIVE_NAME" "$AMXX_SHA256" "$actual_sha" >&2
		exit 1
	fi

	printf 'Missing checksum tool: install sha256sum or shasum.\n' >&2
	exit 1
}

ensure_amxx()
{
	if [[ -n "${AMXX_DIR:-}" ]]; then
		return
	fi

	mkdir -p "$AMXX_CACHE_DIR"

	if [[ ! -x "$AMXX_REPO_DIR/amxxpc" ]]; then
		curl --fail --location --show-error --silent "$AMXX_URL" --output "$AMXX_ARCHIVE"
		verify_archive
		tar -xzf "$AMXX_ARCHIVE" -C "$AMXX_CACHE_DIR"
	fi

	AMXX_DIR="$AMXX_REPO_DIR"
}

ensure_amxx

test -x "$AMXX_DIR/amxxpc"
test -f "$AMXX_DIR/include/amxmodx.inc"
test -f "$AMXX_DIR/include/amxmisc.inc"
test -f "$AMXX_DIR/include/cstrike.inc"
test -f "$AMXX_DIR/include/fakemeta.inc"

docker run --rm --platform linux/386 \
	-v "$ROOT_DIR:/work" \
	-v "$AMXX_DIR:/amxx:ro" \
	-e LD_LIBRARY_PATH=/amxx \
	-w /work \
	debian:bookworm \
	/amxx/amxxpc src/kgbbots.sma -i/amxx/include -ocompiled/kgbbots.amxx
