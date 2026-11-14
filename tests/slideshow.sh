#!/bin/bash
# Run the image's normal entrypoint with a synthetic DRM device and sysfs.
set -euo pipefail
image=${1:-photoframe-test}
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
sys="$root/sys"
mkdir -p "$root/bin" "$root/photos/sub" "$sys/class/drm" \
    "$sys/devices/"{card42,card42-Unknown-4,card42-DP-2}
for entry in card42 card42-Unknown-4 card42-DP-2; do
    ln -s "../../devices/$entry" "$sys/class/drm/$entry"
done
printf '1:3\n' > "$sys/devices/card42/dev"  # Linux /dev/null
printf 'unknown\n' > "$sys/devices/card42-Unknown-4/status"
: > "$sys/devices/card42-Unknown-4/edid"
printf 'connected\n' > "$sys/devices/card42-DP-2/status"
printf 'other-monitor' > "$sys/devices/card42-DP-2/edid"

# Three small, valid 16x16 images so the installed mpv can decode the playlist.
base64 -d > "$root/photos/a photo.JPG" <<'EOF'
/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzU4LjU0LjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAQABADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAFF/f//Z
EOF
base64 -d > "$root/photos/b.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAACXBIWXMAAAABAAAAAQBPJcTWAAAAF0lEQVR4nGP4y8BAEiJN9aiGUQ1DSgMAfsz9ATa/hGgAAAAASUVORK5CYII=
EOF
base64 -d > "$root/photos/sub/c.webp" <<'EOF'
UklGRjwAAABXRUJQVlA4IDAAAADQAQCdASoQABAAAgA0JaACdLoB+AADsAD+8Oj3/yC5YXXI1/8gP+QH/ID/+PIAAAA=
EOF
touch "$root/photos/ignored.txt"
mkdir -p "$root/photos/"$'album\n/tmp'
cp "$root/photos/a photo.JPG" "$root/photos/"$'album\n/tmp/other.png\ncover.jpg'
cp "$root/photos/sub/c.webp" "$root/photos/"$'carriage\rreturn.webp'

cat > "$root/bin/drm-probe" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ $1 == /dev/dri/photoframe ]]
connector="$DRM_SYSFS_ROOT/card42-Unknown-4"
printf 'connected\n' > "$connector/status"
printf 'test-monitor' > "$connector/edid"
EOF
cat > "$root/bin/mpv" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" > /fixture/args
cp /tmp/photos.m3u /fixture/playlist
# Use the real decoder and playlist parser without a physical KMS display.
exec /usr/bin/mpv --no-config --vo=null --no-audio --image-display-duration=0.05 \
    --term-playing-msg='Playing fixture: ${filename}' --playlist=/tmp/photos.m3u
EOF
chmod +x "$root/bin/"*

run_slideshow() {
    docker run --rm --network none --device /dev/null:/dev/dri/photoframe \
        --mount "type=bind,source=$root,target=/fixture" \
        --mount "type=bind,source=$root/photos,target=/photos,readonly" \
        --env PATH=/fixture/bin:/usr/local/bin:/usr/bin:/bin \
        --env DRM_SYSFS_ROOT=/fixture/sys/class/drm \
        "$@" "$image"
}

hash=$(printf 'test-monitor' | sha256sum)
run_slideshow --env DRM_MONITOR_EDID_SHA256="${hash%% *}" \
    --env PHOTO_ROTATE=90 --env PHOTO_DURATION=23 2>&1 | tee "$root/auto.log"
grep -Fx 'Detected DRM card: card42' "$root/auto.log"
grep -Fx 'Detected connector: Unknown-4' "$root/auto.log"
for arg in --vo=drm --drm-device=/dev/dri/photoframe --drm-connector=Unknown-4 \
    --video-rotate=90 --image-display-duration=23 --shuffle --loop-playlist=inf \
    --playlist=/tmp/photos.m3u; do
    grep -Fx -- "$arg" "$root/args"
done
[[ $(wc -l < "$root/playlist") == 3 ]]
[[ $(grep -cF 'Skipping photo path containing CR or LF:' "$root/auto.log") == 2 ]]
for path in '/photos/a photo.JPG' /photos/b.png /photos/sub/c.webp; do
    grep -Fx "$path" "$root/playlist"
    grep -F "Playing fixture: ${path##*/}" "$root/auto.log"
done

run_slideshow --env DRM_CONNECTOR=DP-6 --env DRM_SYSFS_ROOT=/nonexistent \
    --env DRM_MONITOR_EDID_SHA256=ignored
grep -Fx -- '--drm-connector=DP-6' "$root/args"

rm "$root/photos/a photo.JPG" "$root/photos/b.png" "$root/photos/sub/c.webp" "$root/args"
if output=$(run_slideshow --env DRM_CONNECTOR=DP-6 2>&1); then
    echo 'Expected the empty playlist to fail' >&2
    exit 1
fi
grep -F '表示可能な画像が /photos に存在しません。' <<< "$output"
[[ ! -e $root/args ]]
echo 'Slideshow entrypoint checks passed.'
