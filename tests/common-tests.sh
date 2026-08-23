#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_DIRECTORY

# shellcheck source=../lib/common.sh
source "${PROJECT_DIRECTORY}/lib/common.sh"

assert_equal() {
    local expected="$1"
    local actual="$2"
    local description="$3"

    if [[ "${actual}" != "${expected}" ]]; then
        printf 'FAIL: %s: expected %q, got %q\n' \
            "${description}" \
            "${expected}" \
            "${actual}" >&2
        exit 1
    fi
}

assert_equal \
    "100 0" \
    "$(decode_volume_property 'q 25700')" \
    "legacy stereo volume"

assert_equal \
    "100 1" \
    "$(decode_volume_property 'q 58596')" \
    "legacy muted stereo volume"

assert_equal \
    "100 0" \
    "$(decode_volume_property 'ay 2 100 100')" \
    "array stereo volume"

assert_equal \
    "100 1" \
    "$(decode_volume_property 'ay 2 228 228')" \
    "array muted stereo volume"

assert_equal \
    "75 0" \
    "$(decode_volume_property 'ay 1 75')" \
    "array mono volume"

if decode_volume_property 'invalid value' >/dev/null 2>&1; then
    printf 'FAIL: invalid volume property was accepted.\n' >&2
    exit 1
fi

printf 'Common helper tests passed.\n'
