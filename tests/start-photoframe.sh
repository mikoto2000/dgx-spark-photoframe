#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir "$root/bin"
export PATH="$root/bin:$PATH" CALLS="$root/calls"
export TEST_DEVICE="$root/by path/card"
mkdir -p "${TEST_DEVICE%/*}"

cat > "$root/bin/docker" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
    'compose config --environment')
        printf 'DRM_DEVICE=%s\n' "$TEST_DEVICE"
        ;;
    'compose up -d --no-build')
        [[ -c $TEST_DEVICE ]]
        ;;
    *)
        exit 1
        ;;
esac
EOF
# Publish the path when the wait loop first sleeps.
cat > "$root/bin/sleep" <<'EOF'
#!/bin/bash
ln -s /dev/null "$TEST_DEVICE"
EOF
chmod +x "$root/bin/"*

if DRM_DEVICE_WAIT_SECONDS=0 bash scripts/start-photoframe.sh 2>"$root/error"; then
    echo 'Expected the missing device to time out' >&2
    exit 1
fi
grep -F "Timed out waiting for DRM device: $TEST_DEVICE" "$root/error"
[[ $(cat "$CALLS") == 'compose config --environment' ]]

: > "$CALLS"
DRM_DEVICE_WAIT_SECONDS=5 bash scripts/start-photoframe.sh
[[ $(cat "$CALLS") == $'compose config --environment\ncompose up -d --no-build' ]]
echo 'DRM device wait checks passed.'
