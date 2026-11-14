#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

timeout=${DRM_DEVICE_WAIT_SECONDS:-60}
if [[ ! $timeout =~ ^(0|[1-9][0-9]{0,3})$ ]]; then
    echo 'DRM_DEVICE_WAIT_SECONDS must be an integer from 0 to 9999.' >&2
    exit 1
fi

# Use the same interpolation (including shell overrides and .env) as Compose.
environment=$(docker compose config --environment)
device=
while IFS= read -r line; do
    if [[ $line == DRM_DEVICE=* ]]; then
        device=${line#DRM_DEVICE=}
        break
    fi
done <<< "$environment"
if [[ -z $device || $device != /* ]]; then
    echo 'Set DRM_DEVICE to an absolute host DRM device path.' >&2
    exit 1
fi

deadline=$((SECONDS + timeout))
until [[ -c $device ]]; do
    if (( SECONDS >= deadline )); then
        echo "Timed out waiting for DRM device: $device" >&2
        exit 1
    fi
    sleep 1
done

exec docker compose up -d --no-build
