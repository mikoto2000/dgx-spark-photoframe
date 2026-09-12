#!/bin/bash

# コマンド実行時にエラーが発生したら即終了する。
# 未定義変数の参照や、パイプ途中のコマンド失敗もエラーとして扱う。
set -euo pipefail

# /photos 配下から表示対象の画像ファイルを検索し、
# mpv 用のプレイリストを生成する。
#
# 対象形式:
# - JPEG
# - PNG
# - WebP
#
# ファイル名に空白などが含まれていても扱えるよう、
# find では NULL 区切りで取得している。
find /photos \
  -type f \
  \( \
    -iname '*.jpg' -o \
    -iname '*.jpeg' -o \
    -iname '*.png' -o \
    -iname '*.webp' \
  \) \
  -print0 \
  | sort -z \
  | tr '\0' '\n' \
  > /tmp/photos.m3u

# 表示対象の画像が1枚も存在しない場合は、
# mpv を起動せずエラー終了する。
if [ ! -s /tmp/photos.m3u ]; then
  echo "表示可能な画像が /photos に存在しません。" >&2
  exit 1
fi

# mpv を起動し、DRM/KMS を利用して
# デスクトップ環境を介さずモニタへ直接描画する。
#
# DRM_CONNECTOR:
#   使用する DRM connector。
#   例: DP-1
#   未指定の場合は DP-1。
#
# PHOTO_DURATION:
#   1枚の写真を表示する秒数。
#   未指定の場合は15秒。
#
# PHOTO_ROTATE:
#   写真を回転して表示する角度。
#   0 / 90 / 180 / 270 を想定。
#   未指定の場合は0度。
#
# --loop-playlist=inf:
#   最後の写真まで表示したら先頭へ戻り、
#   スライドショーを無限に繰り返す。
#
# exec を使用することで mpv 自体をコンテナの PID 1 とし、
# docker stop などのシグナルを直接受信できるようにする。
exec mpv \
  --vo=drm \
  --drm-device="${DRM_DEVICE:-/dev/dri/card1}" \
  --drm-connector="${DRM_CONNECTOR:-DP-1}" \
  --drm-mode=preferred \
  --video-rotate="${PHOTO_ROTATE:-0}" \
  --profile=sw-fast \
  --fullscreen \
  --no-audio \
  --shuffle \
  --image-display-duration="${PHOTO_DURATION:-15}" \
  --loop-playlist=inf \
  --playlist=/tmp/photos.m3u
