
起動後JupyterLabのターミナルで以下を貼り付け（一括追加）
```bash
# リポジトリをクローン
cd /workspace
git clone https://github.com/yukisub1234-dot/Runpod.git
cd Runpod

# 環境変数が見えているか確認(トークンの中身は表示しない)
echo "CIVITAI_TOKEN: ${CIVITAI_TOKEN:+設定済み}"
echo "HF_TOKEN: ${HF_TOKEN:+設定済み}"

# 実行
python3 download_all.py --config wan22-lightweight-fast --workers 2
```

起動後JupyterLabのターミナルで以下を貼り付け（個別追加）
```bash
# Civitaiから1個追加
python3 download_all.py --add \
  --source civitai \
  --target 2342652 \
  --file xxxx_lora.safetensors \
  --type lora \
  --rename-to my_lora.safetensors

# Hugging Faceから1個追加
python3 download_all.py --add \
  --source hf \
  --target Comfy-Org/Wan_2.2_ComfyUI_Repackaged \
  --file split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors \
  --type diffusion
```

# ComfyUI Model Downloader

RunPod公式テンプレート **「ComfyUI - CUDA 13」**(`github.com/runpod-workers/comfyui-base`)向けに、Civitai / Hugging Face からモデル(チェックポイント・LoRA・VAE・テキストエンコーダーなど)を目的別プリセットで一括ダウンロードするスクリプトです。

## 対応テンプレート

| 項目 | 値 |
|---|---|
| テンプレート | ComfyUI - CUDA 13 |
| ComfyUIインストール先 | `/workspace/runpod-slim/ComfyUI` |
| カスタム起動引数 | `/workspace/runpod-slim/comfyui_args.txt` |
| プリインストール済みカスタムノード | ComfyUI-Manager / ComfyUI-KJNodes / Civicomfy / ComfyUI-RunpodDirect |

`COMFYUI_ROOT` のデフォルト値はこのテンプレートの構成に合わせて `/workspace/runpod-slim/ComfyUI` になっています。別テンプレートを使う場合は環境変数で上書きしてください。

## 特徴

- **目的別プリセット**: 「軽量高速」「高品質」「長尺」など用途ごとにファイルセットをまとめて一括インストール
- **並列ダウンロード**: `ThreadPoolExecutor` により複数モデルを同時取得(大容量モデルはOOM対策で並列数を抑制)
- **SHA256検証**: ダウンロード後のファイル整合性をチェックサムで確認
- **重複ダウンロード防止**: 同一セッション内の二重処理をロックでブロック、既存ファイルは自動スキップ
- **ページキャッシュ解放**: RunPodのcgroupメモリ制限によるOOMを回避
- **Network Volume対応**: `/workspace` が永続ボリュームかを自動判定し、Pod再作成時の無駄な再ダウンロードを防止
- **単体追加モード**: `--add` でJSON編集なしに1個だけ追加ダウンロード
- **設定の外部化**: ダウンロード対象は `configs/*.json` で管理(コード変更不要)
- **自動リトライ**: 一時的なネットワークエラーに対して再試行

## ディレクトリ構成

```
.
├── download_all.py                    # ダウンロード実行スクリプト
├── configs/                            # 用途別プリセット
│   ├── wan22-lightweight-fast.json      # 軽量高速: Wan2.2 TI2V-5B
│   ├── wan22-high-quality.json          # 高品質: Wan2.2 T2V/I2V-A14B(MoE, fp8)
│   ├── wan22-long-duration.json         # 長尺: I2V-A14B + SVI v2.0 Pro LoRA
│   ├── realistic.json                   # 例: 写実系チェックポイント
│   └── style-loras.json                 # 例: スタイルLoRAセット
└── README.md
```

`configs/` 以下に用途ごとのJSONを好きなだけ追加し、実行時に `--config` でどれを使うか指定します。

## Wan2.2 目的別プリセット

| プリセット | 中身 | 特徴 | VRAM目安 |
|---|---|---|---|
| `wan22-lightweight-fast` | TI2V-5B(単一モデル・fp16) | T2V/I2V両対応、720p@24fps。速度優先 | 約24GB |
| `wan22-high-quality` | T2V-A14B + I2V-A14B(MoE高/低ノイズ・fp8_scaled) | 映画的な質感・複雑な動きに強いMoE構成 | 約24GB(fp8) |
| `wan22-long-duration` | I2V-A14B(Kijai/KJ形式fp8) + SVI v2.0 Pro LoRA + LightX2V | セグメントを連結し60秒程度までのシームレスな動画(SVI方式) | 約24GB |
| `wan22-latent-continuation` | Fun VACE-A14B(fp8_scaled) | 潜在空間(Latent)を直接引き継いで動画の続きを生成。ネイティブノードのみ、追加LoRA不要 | 約24GB |
| `wan22-speed-boost-loras` | LightX2V 4-stepディスティルLoRA(T2V/I2V, High/Low) | `wan22-high-quality`に重ねて3〜4倍高速化するアドオン | 数百MB |

**注意点**:
- `wan22-high-quality` と `wan22-long-duration` はMoE構成(High-Noise/Low-Noiseの2モデル切替)のため、KSampler(Advanced)を2回使うワークフローが必要です(公式テンプレート「Wan2.2 14B T2V/I2V」で対応)。
- `wan22-long-duration` のdiffusionモデルは**ネイティブComfyUI形式ではなく**、`ComfyUI-KJNodes`の`DiffusionModelLoaderKJ`ノード専用形式(Kijaiリポジトリ配布)です。ノード自体はこのテンプレートにプリインストール済みです。
- fp8_scaledはfp16よりVRAM消費を抑えつつ品質劣化を最小化した形式です。さらに高品質を求める場合はfp16版に差し替え可能ですが、必要VRAMが大幅に増えます(A14Bのfp16は80GB級GPU相当)。

### 長尺動画の2つの方式の違い

| 方式 | プリセット | 仕組み | 長所 | 短所 |
|---|---|---|---|---|
| SVI(画像アンカー方式) | `wan22-long-duration` | セグメント末尾をVAEデコードした画像を次のI2V入力に使う | 導入実績が多く安定 | VAEデコード/再エンコードを繰り返すため微小な劣化が蓄積しうる |
| Latent直接結合方式 | `wan22-latent-continuation` | セグメント末尾の潜在表現(latent)をVAEを介さず直接次のコンテキストに渡す | 圧縮劣化が起きにくい。追加LoRA不要 | VACEモデル自体の学習傾向に品質が左右される。ワークフロー構築がやや複雑 |

どちらもComfyUI標準の`TrimVideoLatent`ノードで潜在系列の長さを調整しながら複数セグメントを繋ぎます。まずは`wan22-latent-continuation`(ネイティブノードのみ)を試し、動きの一貫性が物足りない場合に`wan22-long-duration`(SVI)を試す、という順番がおすすめです。

## 高速化のオプション(品質への影響で2段階)

**① 本当に無劣化な高速化(推奨・まず試す)**

推論カーネルの最適化で、出力はほぼ変わらず速度だけ向上します。`/workspace/runpod-slim/comfyui_args.txt` に追記してComfyUIを再起動してください。

```
--use-sage-attention
--fast
```

- `--use-sage-attention`: Attentionの計算を高速なカーネルに置き換え(要`sageattention`パッケージ、ComfyUI-Managerからインストール可)
- `--fast`: fp8行列演算の高速パスを有効化(対応GPUのみ)

**② トレードオフのある高速化(LightX2V 4-stepディスティルLoRA)**

`wan22-speed-boost-loras` で導入できます。20ステップ→6ステップ程度まで削減し3〜4倍高速化しますが、ComfyOrg公式ブログでも「動きのダイナミズムがわずかに低下する場合がある」と明言されているとおり、完全な無劣化ではありません。まず①を試し、それでも遅い場合にLoRAの強度を1.0→0.7程度に下げながら試すのがおすすめです。

## ワークフロー(JSON)の一括ダウンロード

`type: "workflow"` と `source: "url"` を使うと、Civitai/HF以外の任意のURL(GitHub添付ファイル、raw.githubusercontent.com など)から直接ワークフローJSONをダウンロードし、ComfyUIの `user/default/workflows/` に配置できます。モデルと違い数十KB〜数MB程度なので、通常のモデル用サイズチェックとは別の緩い基準(かつJSONとして正しくパースできるか)で検証されます。

`configs/*.json` に含める場合:

```json
{
  "source": "url",
  "url": "https://github.com/user-attachments/files/xxxxxxx/example_workflow.json",
  "file": "example_workflow.json",
  "type": "workflow"
}
```

コマンド一発(単体追加モード)でも可能です:

```bash
python3 download_all.py --add \
  --source url \
  --url "https://github.com/user-attachments/files/24359648/wan22_SVI_Pro_native_example_KJ.json" \
  --file wan22_svi_pro.json \
  --type workflow
```

### SVI v2.0 Pro ワークフロー(長尺動画生成)の入手例

`wan22-long-duration` のモデルに対応する公式サンプルワークフローは、KJ(Kijai)氏がGitHub上で配布しています。上記のworkflow type経由で直接ダウンロードできます。

- ワークフロー本体(JSON): https://github.com/user-attachments/files/24359648/wan22_SVI_Pro_native_example_KJ.json
- より高機能な派生版(セグメントごとのLoRA切替・保存/再開対応、v3.0): https://civitai.com/models/2368359/long-videos-with-full-control-wan-22-i2v-svi-2-pro-individual-lora-multiple-reference-images-and-more

不足しているカスタムノードが赤く表示された場合は、ComfyUI-Managerの「Install Missing Custom Nodes」で解決してください。

ダウンロードしたファイルは種類に応じて `COMFYUI_ROOT` 配下の各サブディレクトリに自動配置されます。

| type          | 配置先                              |
|---------------|--------------------------------------|
| `checkpoint`  | `models/checkpoints`                 |
| `lora`        | `models/loras`                       |
| `vae`         | `models/vae`                         |
| `clip`        | `models/text_encoders`               |
| `diffusion`   | `models/diffusion_models`            |
| `upscale`     | `models/upscale_models`              |
| `controlnet`  | `models/controlnet`                  |
| `workflow`    | `user/default/workflows`             |

## セットアップ

### 1. 環境変数の設定

RunPodのPod設定画面の **Environment Variables**、またはターミナルで以下を設定します。

```bash
export CIVITAI_TOKEN="your_civitai_api_token"
export HF_TOKEN="your_huggingface_token"
export COMFYUI_ROOT="/workspace/runpod-slim/ComfyUI"   # 省略時のデフォルト値(新テンプレート用)
```

- `CIVITAI_TOKEN`: [Civitai Account Settings](https://civitai.com/user/account) から発行
- `HF_TOKEN`: [Hugging Face Settings > Access Tokens](https://huggingface.co/settings/tokens) から発行(read権限で可)

### 2. リポジトリの取得

```bash
cd /workspace
git clone https://github.com/<your-username>/<your-repo>.git
cd <your-repo>
```

### 3. プリセット(configs/*.json)の編集・追加

用途ごとにファイルを分けます。「軽量高速」「高品質」「長尺」のように目的別に分類すると管理しやすくなります。

```
configs/
├── wan22-lightweight-fast.json   # 軽量高速: Wan2.2 TI2V-5B
├── wan22-high-quality.json       # 高品質: Wan2.2 T2V/I2V-A14B(MoE)
├── wan22-long-duration.json      # 長尺: I2V-A14B + SVI v2.0 Pro
├── realistic.json                # 写実系チェックポイント
└── style-loras.json              # スタイルLoRA詰め合わせ
```

各ファイルの中身は以下の形式です。

```json
{
  "_description": "このプリセットの説明(--list実行時に表示されます)",
  "models": [
    {
      "source": "civitai",
      "target": "モデルID",
      "file": "任意のファイル名.safetensors",
      "type": "checkpoint",
      "sha256": ""
    },
    {
      "source": "hf",
      "target": "リポジトリ名(例: Comfy-Org/xxx)",
      "file": "リポジトリ内のファイルパス",
      "type": "vae",
      "sha256": ""
    }
  ]
}
```

| フィールド     | 必須 | 説明                                                                 |
|----------------|------|----------------------------------------------------------------------|
| `source`       | ✅   | `civitai` または `hf`                                               |
| `target`       | ✅   | CivitaiのモデルID、またはHFのリポジトリ名                            |
| `file`         | ✅   | ダウンロードするファイル名(HFの場合はリポジトリ内パス)               |
| `type`         | ✅   | 保存先ディレクトリの種類(上表参照)                                   |
| `rename_to`    | 任意 | 保存後にリネームしたい場合のファイル名                               |
| `sha256`       | 任意 | 整合性検証用のハッシュ値。モデル配布ページに記載があれば設定推奨      |
| `path`         | 任意 | `type` が未定義の場合の保存先を直接指定                              |

CivitaiのハッシュはモデルページのFile欄、HFのハッシュはファイル詳細(SHA256列)で確認できます。

## 実行方法

### 起動後にモデルを1個だけ追加したい場合

`configs/*.json` を編集・再実行する代わりに、コマンドラインだけで1件だけ追加ダウンロードできます。まとめてDLし直すよりOOMのリスクも小さくなります。

```bash
# Civitaiから1個追加
python3 download_all.py --add \
  --source civitai \
  --target 2342652 \
  --file paizuri_lora.safetensors \
  --type lora \
  --rename-to my_lora.safetensors

# Hugging Faceから1個追加
python3 download_all.py --add \
  --source hf \
  --target Comfy-Org/Wan_2.2_ComfyUI_Repackaged \
  --file split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors \
  --type diffusion

# 任意のURLからワークフローJSONを1個追加
python3 download_all.py --add \
  --source url \
  --url "https://github.com/user-attachments/files/24359648/wan22_SVI_Pro_native_example_KJ.json" \
  --file wan22_svi_pro.json \
  --type workflow
```

| オプション      | 必須 | 説明                                                   |
|-----------------|------|--------------------------------------------------------|
| `--add`         | ✅   | 単体ダウンロードモードを有効化                          |
| `--source`      | ✅   | `civitai` / `hf` / `url`(任意の直リンク)                |
| `--target`      | ✅※  | CivitaiのモデルID、またはHFのリポジトリ名(`--source url`では不要) |
| `--url`         | ✅※  | ダウンロード元URL(`--source url` の場合のみ必須)        |
| `--file`        | ✅   | ファイル名(HFの場合はリポジトリ内パス)                  |
| `--type`        | 任意 | 保存先タイプ(デフォルト: `checkpoint`。`workflow`も指定可) |
| `--rename-to`   | 任意 | 保存後のリネーム先ファイル名                             |
| `--sha256`      | 任意 | 整合性検証用のハッシュ値                                 |

### プリセット一覧の確認

```bash
python3 download_all.py --list
```

```
📂 利用可能なプリセット (./configs):

  - realistic            写実系チェックポイントとアップスケーラーのセット  (2 モデル)
  - style-loras          スタイル系LoRAのセット  (2 モデル)
  - wan22-lightweight-fast  軽量・高速セット: Wan2.2 TI2V-5B  (3 モデル)
  - wan22-high-quality     高品質セット: Wan2.2 T2V/I2V-A14B(MoE)  (6 モデル)
  - wan22-long-duration    長尺セット: I2V-A14B + SVI v2.0 Pro  (6 モデル)
```

### ターミナルから実行(推奨)

`--config` にはプリセット名(拡張子省略可)、または任意のパスを指定できます。

```bash
# configs/wan22-lightweight-fast.json を使う場合(名前だけでOK)
python3 download_all.py --config wan22-lightweight-fast --workers 2

# 拡張子付きでも可
python3 download_all.py --config wan22-high-quality.json --workers 1

# configs/ 以外の場所にあるJSONを直接指定する場合
python3 download_all.py --config /workspace/custom/my-list.json --workers 3
```

| オプション   | デフォルト     | 説明                                                        |
|--------------|----------------|---------------------------------------------------------------|
| `--config`   | `models.json`  | プリセット名 または 設定ファイルのパス                        |
| `--workers`  | `3`            | 並列ダウンロード数                                            |
| `--list`     | -              | `configs/` 内の利用可能なプリセット一覧を表示して終了          |

### バックグラウンド実行(大容量モデル・長時間DL向け)

JupyterLabやSSHセッションが切れてもダウンロードを継続させたい場合:

```bash
nohup python3 download_all.py --config wan22-lightweight-fast --workers 2 > download.log 2>&1 &
tail -f download.log   # 進捗確認(Ctrl+Cで監視終了、DLは継続)
```

### JupyterLabのノートブックセルから

```python
import os
print("CIVITAI_TOKEN:", "設定済み" if os.environ.get("CIVITAI_TOKEN") else "未設定")
print("HF_TOKEN:", "設定済み" if os.environ.get("HF_TOKEN") else "未設定")
```

```python
!python3 download_all.py --list
!python3 download_all.py --config wan22-lightweight-fast --workers 2
```

## 出力例

```
✅ /workspace は独立したボリューム(Network Volume想定)です。Pod再起動後もモデルは保持されます。

📋 3 件のモデルを最大 3 並列でダウンロードします

🚀 開始: [CIVITAI] (checkpoint) realistic_checkpoint.safetensors -> realistic_checkpoint.safetensors
🚀 開始: [HF] (vae) split_files/vae/wan_2.1_vae.safetensors -> wan_2.1_vae.safetensors
✅ 完了: realistic_checkpoint.safetensors
✅ 完了: wan_2.1_vae.safetensors

============================================================
📊 ダウンロード結果サマリー
============================================================
  ✅ 成功: realistic_checkpoint.safetensors
  ✅ 成功: wan_2.1_vae.safetensors
============================================================
✨ すべて正常に完了しました。
```

## トラブルシューティング

| 症状                              | 原因・対処                                                                 |
|-----------------------------------|------------------------------------------------------------------------------|
| `❌ HTMLが返却されています`        | トークンが無効/期限切れ、または非公開モデルへのアクセス権限がない            |
| `❌ ハッシュ不一致`                | モデルが更新された、またはダウンロードが破損している。再実行してみてください |
| `⚠️ Network Volumeが未接続の可能性` | `/workspace` がPersistent Volumeにマウントされているか、RunPodのPod設定を確認 |
| ダウンロードが途中で止まる          | `nohup` を使ったバックグラウンド実行に切り替える                             |
| `WARN: triggered memory limits (OOM)` でコンテナが落ちる | RAM(VRAMではない)の枯渇。大容量モデルの並列DL+検証でページキャッシュが増加し、cgroupのメモリ制限に抵触するのが典型的な原因。`--workers 1` に下げて再実行するか、Podのシステムメモリ割当が大きいプランに変更する |

## セキュリティに関する注意

- トークンは環境変数管理とし、`models.json` やコード内にハードコードしないでください
- `.gitignore` に以下を含めることを推奨します

```
*.safetensors
*.ckpt
*.pt
.env
download.log
```

## ライセンス

ダウンロードするモデル自体のライセンス・利用規約は、各配布元(Civitai / Hugging Face)のページで個別にご確認ください。
