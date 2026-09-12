# dgx-spark-photoframe

DGX Spark を LLM サーバーとして運用しながら、接続した USB-C モニタをデジタルフォトフレームとして利用するための Docker 構成です。

デスクトップ環境やブラウザは使用せず、`mpv` から Linux DRM/KMS へ直接描画します。

```text
DGX Spark
├─ LLM Server
│   └─ vLLM / llama.cpp / etc.
│
└─ dgx-spark-photoframe
    └─ mpv
        └─ DRM/KMS
            └─ USB-C DisplayPort
                └─ Monitor
```

## Features

* Docker Compose で起動
* X11 / Wayland / GNOME 不要
* USB-C DisplayPort 接続のモニタへ直接表示
* JPEG / PNG / WebP 対応
* サブディレクトリ内の画像も表示
* スライドショー表示
* 表示間隔を環境変数で変更可能
* 画像の回転角度を環境変数で変更可能
* 写真ディレクトリを任意のホストパスからマウント可能
* DRM device / connector を環境変数で指定可能

## Requirements

* NVIDIA DGX Spark
* Ubuntu / DGX OS
* Docker Engine
* Docker Compose
* DRM/KMS が有効になっていること
* USB-C DisplayPort Alt Mode 対応モニタおよびケーブル

## Setup

### 1. Repository

```bash
git clone https://github.com/mikoto2000/dgx-spark-photoframe.git
cd dgx-spark-photoframe
```

### 2. Environment Variables

`.env.example` を `.env` にコピーします。

```bash
cp .env.example .env
```

環境に合わせて `.env` を編集します。

例:

```dotenv
PHOTO_DIR=/home/mikoto/photos
DRM_DEVICE=/dev/dri/card1
DRM_CONNECTOR=DP-1
PHOTO_DURATION=15
PHOTO_ROTATE=0
```

## DRM Device

使用可能な DRM device は次のコマンドで確認できます。

```bash
ls -l /dev/dri/
```

例:

```text
by-path
card1
renderD128
```

この場合:

```dotenv
DRM_DEVICE=/dev/dri/card1
```

を指定します。

`card0` や `card1` は環境や起動状態によって変化する可能性があるため、固定値とは限りません。

## DRM Connector

接続中の connector は次のコマンドで確認できます。

```bash
grep -H connected /sys/class/drm/card*-*/status
```

または `mpv` から直接確認できます。

```bash
mpv \
  --vo=drm \
  --drm-device=/dev/dri/card1 \
  --drm-connector=help
```

DGX Spark の USB-C DisplayPort 接続では、connector が `DP-1` のような名前ではなく、次のように認識される場合があります。

```text
HDMI-A-1 (disconnected)
Unknown-2 (disconnected)
Unknown-3 (disconnected)
Unknown-4 (connected)
Unknown-5 (disconnected)
```

この場合:

```dotenv
DRM_CONNECTOR=Unknown-4
```

を指定します。

## Photos

`.env` の `PHOTO_DIR` に指定したディレクトリへ画像を配置します。

例:

```text
~/photos/
├── 001.jpg
├── 002.jpg
├── 006/
│   ├── photo01.jpg
│   └── photo02.jpg
└── 010/
    └── photo03.webp
```

対応形式:

* `.jpg`
* `.jpeg`
* `.png`
* `.webp`

## Start

ビルドして起動します。

```bash
docker compose up -d --build
```

ログを確認する場合:

```bash
docker compose logs -f
```

停止:

```bash
docker compose down
```

## Configuration

### `PHOTO_DIR`

ホスト側の写真ディレクトリ。

```dotenv
PHOTO_DIR=/home/mikoto/photos
```

コンテナ内では `/photos` として読み取り専用でマウントされます。

### `DRM_DEVICE`

使用する DRM device。

```dotenv
DRM_DEVICE=/dev/dri/card1
```

### `DRM_CONNECTOR`

画像を表示するモニタの DRM connector。

```dotenv
DRM_CONNECTOR=Unknown-4
```

### `PHOTO_DURATION`

1枚の画像を表示する秒数。

```dotenv
PHOTO_DURATION=15
```

### `PHOTO_ROTATE`

画像の回転角度。

```dotenv
PHOTO_ROTATE=0
```

指定可能な値:

```text
0
90
180
270
```

モニタを縦置きする場合は、例えば:

```dotenv
PHOTO_ROTATE=90
```

とします。

## Copy Photos with rsync

WSL などのローカル環境から DGX Spark へ写真をコピーする場合:

```bash
rsync -avh --progress \
  /mnt/d/picture/ \
  mikoto@<dgx-spark-host>:~/photos/
```

ローカル側で削除したファイルもリモート側から削除して完全同期する場合:

```bash
rsync -avh --delete --progress \
  /mnt/d/picture/ \
  mikoto@<dgx-spark-host>:~/photos/
```

`--delete` はリモート側のファイルも削除するため注意してください。

## Troubleshooting

### `/dev/dri/card0: no such file or directory`

実際に存在する DRM device を確認してください。

```bash
ls -l /dev/dri/
```

例えば `card1` が存在する場合:

```dotenv
DRM_DEVICE=/dev/dri/card1
```

とします。

### `No connector with name ... found`

指定している `DRM_CONNECTOR` が実際の connector 名と一致していません。

確認:

```bash
mpv \
  --vo=drm \
  --drm-device=/dev/dri/card1 \
  --drm-connector=help
```

`connected` となっている connector を指定してください。

例:

```text
Unknown-4 (connected)
```

```dotenv
DRM_CONNECTOR=Unknown-4
```

### `VT_GETMODE failed: Inappropriate ioctl for device`

Docker コンテナ内では Linux VT を直接操作できないため、この警告が表示されることがあります。

```text
VT_GETMODE failed: Inappropriate ioctl for device
Failed to set up VT switcher.
Terminal switching will be unavailable.
```

DRM/KMS による表示自体が正常に動作していれば、この警告は無視できます。

### USB-C モニタが認識されない

まず DRM connector が生成されているか確認します。

```bash
ls -l /sys/class/drm
```

`card*-DP-*`、`card*-HDMI-*`、`card*-Unknown-*` などが存在しない場合は、NVIDIA DRM の modeset 設定を確認してください。

```bash
cat /sys/module/nvidia_drm/parameters/modeset
```

通常は:

```text
Y
```

である必要があります。

さらに:

```bash
grep -R "nvidia-drm.*modeset" \
  /etc/modprobe.d \
  /usr/lib/modprobe.d \
  2>/dev/null
```

を実行し、

```text
options nvidia-drm modeset=0
```

が設定されていないか確認してください。

DGX Spark / DGX OS の一部環境では `nvidia-drm modeset=0` により DRM connector が生成されず、HDMI や USB-C DisplayPort の画面出力が利用できなくなる場合があります。

`options nvidia-drm modeset=0` が設定されている場合は、NVIDIA の `nvidia-drm-options-modeset0` パッケージが原因のことがあります。

パッケージを削除してから再起動してください。

```bash
sudo apt purge nvidia-drm-options-modeset0
sudo poweroff
```

再起動後もモニタが認識されない場合は、GX10 の電源ケーブルを抜いて 1 分程度待ってから電源を入れ直してください。

## Architecture

このプロジェクトでは NVIDIA Container Toolkit や CUDA を使用していません。

フォトフレーム用コンテナが必要とするのは主に:

```text
/dev/dri/card*
```

へのアクセスです。

そのため、LLM 推論用コンテナとは独立して動作できます。

```text
DGX Spark
│
├─ vLLM Container
│   └─ CUDA / GB10
│
└─ Photo Frame Container
    └─ DRM/KMS
        └─ USB-C Monitor
```

## License

このソフトウェアは MIT ライセンスの下で提供されます。詳細については [LICENSE](./LICENSE) ファイルを参照してください。

