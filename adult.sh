cat << 'EOF' > download_all.py
import os
import sys
import subprocess

# ====================================================================
# 1. 秘密鍵（環境変数）からトークンを自動取得
# ====================================================================
CIVITAI_TOKEN = os.environ.get("CIVITAI_TOKEN", "")
HF_TOKEN = os.environ.get("HF_TOKEN", "")

COMFYUI_ROOT = "/workspace/ComfyUI"

# ====================================================================
# 種類に応じたディレクトリの定義（マッピング）
# ====================================================================
DIR_MAPPING = {
    "diffusion": f"{COMFYUI_ROOT}/models/diffusion_models",
    "checkpoint": f"{COMFYUI_ROOT}/models/checkpoints",
    "lora": f"{COMFYUI_ROOT}/models/loras",
    "clip": f"{COMFYUI_ROOT}/models/text_encoders",         
    "vae": f"{COMFYUI_ROOT}/models/vae",                   
}

# ====================================================================
# 2. ダウンロードしたいファイルのリスト
# ====================================================================
DOWNLOAD_LIST = [
    {
        "source": "civitai",
        "target": "2342652", 
        "file": "paizuri_lora.safetensors",
        "type": "lora",
        "rename_to": "paizuri.safetensors"
    },
    {
        "source": "civitai",
        "target": "2504591", 
        "file": "onani_lora.safetensors",
        "type": "lora",
        "rename_to": "onani.safetensors"
    },
    {
        "source": "civitai",
        "target": "2235288", 
        "file": "blowjob_lora.safetensors",
        "type": "lora",
        "rename_to": "blowjob.safetensors"
    },
    {
        "source": "civitai",
        "target": "1602715", 
        "file": "bukkake_lora.safetensors",
        "type": "lora",
        "rename_to": "bukkake.safetensors"
    },
    {
        "source": "civitai",
        "target": "2210320", 
        "file": "paimomi_lora.safetensors",
        "type": "lora",
        "rename_to": "paimomi.safetensors"
    },
    {
        "source": "hf",
        "target": "NSFW-API/NSFW-Wan-UMT5-XXL",
        "file": "nsfw_wan_umt5-xxl_fp8_scaled.safetensors",
        "type": "clip"
    },
]

# ====================================================================
# 3. 自動判別・ダウンロード処理ロジック
# ====================================================================
def ensure_dependencies(source):
    if source == "hf":
        try:
            import hf_transfer
        except ImportError:
            print("📦 Hugging Face 用の高速化ライブラリをインストール中...")
            subprocess.run([sys.executable, "-m", "pip", "install", "-U", "hf_transfer"], check=True)

def download_item(item):
    source = item["source"].lower().strip()
    target = item["target"].strip()
    filename = item["file"].strip()
    rename_to = item.get("rename_to")
    
    file_type = item.get("type", "").lower().strip()
    if file_type in DIR_MAPPING:
        save_dir = DIR_MAPPING[file_type]
    else:
        save_dir = item.get("path", f"{COMFYUI_ROOT}/models/checkpoints").strip()

    os.makedirs(save_dir, exist_ok=True)
    print(f"\n🚀 スタート: [{source.upper()}] ({file_type}) -> {filename}")

    # ----------------------------------------------------------------
    # Civitai の処理 (wget 安定モード)
    # ----------------------------------------------------------------
    if source == "civitai":
        url = f"https://civitai.com/api/download/models/{target}"
        if CIVITAI_TOKEN:
            url += f"?token={CIVITAI_TOKEN}"
        
        save_path = os.path.join(save_dir, filename)
        
        cmd = [
            "wget", 
            "--no-check-certificate",
            "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64)", 
            "-O", save_path, 
            url
        ]
        
        print(f"📥 実行コマンド: {' '.join(cmd)}")
        subprocess.run(cmd)
        
        # HTML誤取得チェック
        if os.path.exists(save_path) and os.path.getsize(save_path) < 50000:
            with open(save_path, 'r', errors='ignore') as f:
                if "html" in f.read(500).lower():
                    print(f"❌ エラー: {filename} がログイン画面に弾かれました。CIVITAI_TOKEN が必要です。")
                    return

    # ----------------------------------------------------------------
    # Hugging Face の処理 (2026年最新仕様: 正しい位置引数に修正)
    # ----------------------------------------------------------------
    elif source == "hf":
        ensure_dependencies("hf")
        
        env = os.environ.copy()
        if HF_TOKEN:
            env["HF_TOKEN"] = HF_TOKEN
            
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
            
        # 引数の順番を修正: [REPO_ID] [FILENAMES] --local-dir [DIR]
        cmd = [
            "hf", "download",
            target,
            filename,
            "--local-dir", save_dir
        ]
        
        print(f"📥 実行コマンド: {' '.join(cmd)}")
        subprocess.run(cmd, env=env)
                
    else:
        print(f"❌ 不明なソースタイプです: {source}")
        return

    # ----------------------------------------------------------------
    # [共通処理] ダウンロード後の自動リネーム
    # ----------------------------------------------------------------
    if rename_to:
        old_path = os.path.join(save_dir, filename)
        new_path = os.path.join(save_dir, rename_to.strip())
        if os.path.exists(old_path):
            os.rename(old_path, new_path)
            print(f"🔄 リネーム完了: {filename} -> {rename_to}")
        else:
            print(f"⚠️ リネーム対象のファイルが見つかりません: {old_path}")

if __name__ == "__main__":
    if not CIVITAI_TOKEN:
        print("⚠️ 【重要】CIVITAI_TOKEN が未設定です。LoRAのダウンロードは高確率で失敗します。")
    for item in DOWNLOAD_LIST:
        try:
            download_item(item)
        except Exception as e:
            print(f"💥 ダウンロードエラー: {e}")
    print("\n✨ 処理が完了しました。")
EOF

# スクリプトの実行
python download_all.py
