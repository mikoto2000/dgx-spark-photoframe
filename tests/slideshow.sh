#!/bin/bash
# Exercise the unchanged playlist and mpv launch sections with fixture paths.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/photos/sub" "$root/bin"
touch "$root/photos/a photo.JPG" "$root/photos/sub/b.webp" "$root/photos/ignored.txt"
sed -n '/^find \/photos/,/^# mpv を起動し/{ /^# mpv を起動し/d; p; }' entrypoint.sh |
    sed "s|/tmp/photos.m3u|$root/playlist|g; s|/photos|$root/photos|g" > "$root/playlist.sh"
bash "$root/playlist.sh"
[[ $(wc -l < "$root/playlist") == 2 ]]
grep -Fx "$root/photos/a photo.JPG" "$root/playlist"
grep -Fx "$root/photos/sub/b.webp" "$root/playlist"
cat > "$root/bin/mpv" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$MPV_ARGS"
EOF
chmod +x "$root/bin/mpv"
sed -n '/^exec mpv/,$p' entrypoint.sh > "$root/launch.sh"
export PATH="$root/bin:$PATH" MPV_ARGS="$root/args"
export device=/dev/dri/photoframe connector=Unknown-9 PHOTO_ROTATE=90 PHOTO_DURATION=23
bash "$root/launch.sh"
for arg in --vo=drm --drm-device=/dev/dri/photoframe --drm-connector=Unknown-9 --video-rotate=90 --image-display-duration=23 --shuffle --loop-playlist=inf --playlist=/tmp/photos.m3u; do
    grep -Fx -- "$arg" "$root/args"
done
rm "$root/photos/a photo.JPG" "$root/photos/sub/b.webp"
if bash "$root/playlist.sh"; then echo 'Empty playlist should fail' >&2; exit 1; fi
echo 'Slideshow fixture checks passed.'
