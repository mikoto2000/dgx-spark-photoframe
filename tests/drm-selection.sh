#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ./drm-selection.sh
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/card7" "$root/card8"
printf '226:7\n' > "$root/card7/dev"
printf '226:8\n' > "$root/card8/dev"
connector() {
    mkdir -p "$root/$1"
    printf '%s\n' "$2" > "$root/$1/status"
    printf '%s' "$3" > "$root/$1/edid"
}
pass=0
expect() {
    local expected=$1; shift
    local actual
    actual=$("$@")
    [[ $actual == "$expected" ]] || { echo "Expected $expected, got $actual" >&2; exit 1; }
    pass=$((pass + 1))
}
fails() {
    local message=$1; shift
    if "$@" > "$root/out" 2> "$root/error"; then echo 'Expected failure' >&2; exit 1; fi
    grep -q "$message" "$root/error"
    pass=$((pass + 1))
}
expect card7 drm_card_for_id "$root" 226:7
fails 'Cannot identify' drm_card_for_id "$root" 226:9
expect Unknown-4 drm_resolve_connector "$root" card7 Unknown-4 ignored
fails 'No connected' drm_resolve_connector "$root" card7 auto ''
connector card7-Unknown-4 connected monitor-a
connector card8-DP-1 connected other-device
connector card7-DP-2 disconnected monitor-b
expect Unknown-4 drm_resolve_connector "$root" card7 auto ''
hash=$(printf monitor-a | sha256sum); hash=${hash%% *}
expect Unknown-4 drm_resolve_connector "$root" card7 auto "$hash"
disconnected_hash=$(printf monitor-b | sha256sum); disconnected_hash=${disconnected_hash%% *}
fails 'No connected.*matching' drm_resolve_connector "$root" card7 auto "$disconnected_hash"
fails 'No connected.*matching' drm_resolve_connector "$root" card7 auto "$(printf '%064d' 0)"
connector card7-DP-3 connected monitor-b
fails 'Multiple connected' drm_resolve_connector "$root" card7 auto ''
expect Unknown-4 drm_resolve_connector "$root" card7 auto "$hash"
connector card7-DP-3 connected ''
expect Unknown-4 drm_resolve_connector "$root" card7 auto "$hash"
rm "$root/card7-Unknown-4/edid"
fails 'No connected.*matching' drm_resolve_connector "$root" card7 auto "$hash"
printf monitor-a > "$root/card7-Unknown-4/edid"
printf monitor-a > "$root/card7-DP-3/edid"
fails 'Multiple connected' drm_resolve_connector "$root" card7 auto "$hash"
fails 'Invalid EDID' drm_resolve_connector "$root" card7 auto invalid
mkdir -p "$root/card9"
printf '226:9\n' > "$root/card9/dev"
connector card9-DP-1 connected ''
expect DP-1 drm_resolve_connector "$root" card9 auto ''
fails 'No connected.*matching' drm_resolve_connector "$root" card9 auto "$hash"
echo "$pass DRM selection checks passed."
