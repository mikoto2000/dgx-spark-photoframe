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
DRM_DEVICE=/dev/dri/by-path/...
DRM_CONNECTOR=auto
DRM_MONITOR_EDID_SHA256=
PHOTO_DURATION=15
PHOTO_ROTATE=0
```

## DRM Device

`card0` / `card1` は起動時のドライバやデバイスの列挙順によって変化することがあります。
ホストでは物理接続経路を表す永続パスを推奨します。

```bash
ls -l /dev/dri/by-path/
```

表示された `*-card` のパスをそのまま設定してください。`*-render` は使用しません。

```dotenv
DRM_DEVICE=/dev/dri/by-path/...
DRM_CONNECTOR=auto
DRM_MONITOR_EDID_SHA256=
```

`...` は実際の `platform-...-card` または `pci-...-card` に置き換えてください。
経路をコードへ固定していません。`DRM_DEVICE=/dev/dri/card1` も利用できますが、
再起動後の安定性は保証できません。

Compose はホストのデバイスをコンテナの `/dev/dri/photoframe` へマッピングします。
mpv は常にこの固定パスを使用します。起動時に character device の存在、読み書き権限、
open の成功を確認します。DRM master / KMS の取得可否は mpv の起動結果で確認してください。

## DRM Connector

`Unknown-4` 等の connector 名も再起動で変化することがあるため、
`DRM_CONNECTOR=auto` を推奨します。デバイスの major/minor 番号と
sysfs の `card*/dev` を照合して現在の card を識別し、その card の connector だけを調べます。
ホストの `/sys` を `/host-sys:ro` へマウントして、`class/drm` の相対 symlink と
`devices` 配下の参照先をまとめて保持します。クラスディレクトリだけのマウントでは
リンク先を参照できない可能性があります。

選択ルール:

- `auto` 以外の明示 connector 名は、そのまま mpv に渡します。EDID 指定は使用しません。
- `auto` + EDID hash は、connected かつ hash が一致する connector が1件の場合だけ選択します。
- `auto` + hash 未指定は、対象 device の connected connector がちょうど1件の場合だけ選択します。
- connected が0件、複数件、hash が不一致、または同じ EDID が複数件ならエラー終了します。
- disconnected connector は選択しません。EDID 指定時の空・取得不能な EDID は理由を stderr に記録して候補から除外します。
- EDID を使用しない1件の自動選択では、EDID を取得できなくても選択できます。

複数モニタ時は `DRM_MONITOR_EDID_SHA256` を設定してください。
同じ EDID を返すモニタを区別できない場合は明示 connector 名が必要です。

接続状態と EDID hash の確認:

```bash
grep -H '^connected$' /sys/class/drm/card*-*/status
for f in /sys/class/drm/card*-*/edid; do
  hash=$(cat "$f" | sha256sum) || continue
  hash=${hash%% *}
  [ "$hash" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ] || echo "$hash $f"
done
```

sysfs はサイズ0でもデータを返す場合があるため、実際に読み取って空データを除外します。
対象モニタの64桁 hash を DRM_MONITOR_EDID_SHA256 に設定してください。
EDID はモニタ・接続機器・ファームウェアの変更で変わる可能性があります。

明示指定も引き続き利用できます:

```dotenv
DRM_CONNECTOR=Unknown-4
```

## Verification

Bash と coreutils を使用した fixture テスト:

```bash
bash tests/drm-selection.sh
bash tests/slideshow.sh
bash -n entrypoint.sh drm-selection.sh
```

DGX Spark 実機で設定とマッピングを確認します:

```bash
docker compose config
docker compose up -d --build
docker compose logs --tail=100
docker compose exec photoframe bash -c 'stat -Lc "%t:%T %n" /dev/dri/photoframe; ls -l /host-sys/class/drm; cat /host-sys/class/drm/card*/dev'
```

ログの Detected DRM card / Detected connector / EDID SHA256 と表示先を確認します。
再起動後も同じモニタに表示されることを確認してください。起動前にモニタを接続します。
起動後の抜き差しで connector は再解決しません。必要ならコンテナを再作成してください。
物理接続経路が変わった場合は DRM_DEVICE の更新が必要です。

sysfs のデバイス番号は [Linux kernel の説明](https://www.kernel.org/doc/html/latest/filesystems/sysfs.html)、
デバイスマッピングは [Docker Compose の仕様](https://docs.docker.com/reference/compose-file/services/#devices) を参照してください。

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

ホストの永続 DRM device パス。DRM Device を参照。

```dotenv
DRM_DEVICE=/dev/dri/by-path/...
```

### `DRM_CONNECTOR`

auto または明示 connector 名。DRM_MONITOR_EDID_SHA256 による指定方法は DRM Connector を参照。

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
DRM_DEVICE=/dev/dri/by-path/...
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

