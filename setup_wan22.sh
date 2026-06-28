#!/bin/bash
set -euo pipefail

# ==============================================================================
# 【基本設定】
# テンプレート: ComfyUI - CUDA 12.8 (runpod-workers/comfyui-base)
# ==============================================================================
RUNPOD_SLIM_DIR="/workspace/runpod-slim"
COMFYUI_DIR="${RUNPOD_SLIM_DIR}/ComfyUI"
COMFYUI_ARGS_FILE="${RUNPOD_SLIM_DIR}/comfyui_args.txt"
BASE_DIR="${COMFYUI_DIR}/models"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
PLUGIN_DIR="${CUSTOM_NODES_DIR}/ComfyUI-WanVideoWrapper"
COMFYUI_LOG="/tmp/comfyui_setup.log"

# ==============================================================================
# 【Python環境の設定】★重要修正：独自の.venvを排除し、コンテナ純正の最適化環境を使用
# ==============================================================================
# テンプレート側に最初から最高水準のCUDA12.8対応環境が入っているため、それをそのまま使用します。
PYTHON_EXEC="python3"
PIP_CMD="pip"

# もし過去の汚染された古い独自仮想環境が存在する場合は、衝突を防ぐため自動で物理削除
if [ -d "${COMFYUI_DIR}/.venv-cu128" ]; then
    echo "🧹 過去の不要な仮想環境(.venv-cu128)を自動クリーンアップ中..."
    rm -rf "${COMFYUI_DIR}/.venv-cu128"
fi

export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_XET_HIGH_PERFORMANCE=1

echo "=================================================="
echo "🚀 Wan 2.2 セットアップスクリプト（コンテナ純正・完全最適化版）"
echo "=================================================="

# ==============================================================================
# 【Step 1】ComfyUI-Manager の起動時チェックを無効化（維持）
# ==============================================================================
echo "📋 [Step 1/5] ComfyUI-Manager の設定を書き込み中..."
MANAGER_CONFIG_DIR="${COMFYUI_DIR}/user/__manager"
MANAGER_CONFIG="${MANAGER_CONFIG_DIR}/config.ini"
mkdir -p "$MANAGER_CONFIG_DIR"

cat > "$MANAGER_CONFIG" << 'MANAGER_CONF'
[default]
skip_update_check = true
update_check = none
network_mode = local
fetch_custom_node_list = false
skip_migration = true
MANAGER_CONF

# ==============================================================================
# 【Step 2】起動引数の設定 ★重要修正：124GiB RAMを活かした完全VRAM防御・プレビュー無効化
# ------------------------------------------------------------------------------
# 変更前: 曖昧なFP8引数、またはlowvramの不足によるサンプリング時の即死
# 変更後: --lowvramで124GiBのRAMを退避所に活用、--preview-method noneで計算負荷の極小化
# ==============================================================================
echo ""
echo "⚙️  [Step 2/5] 起動引数を設定中（124GiB RAM最適化・VRAM防御モード）..."
cat > "$COMFYUI_ARGS_FILE" << 'ARGS'
--fp8_e4m3fn-unet
--fp8_e4m3fn-text-enc
--lowvram
--use-pytorch-cross-attention
--preview-method none
ARGS
echo "  -> ✅ 設定完了: ${COMFYUI_ARGS_FILE}"

# ==============================================================================
# 【Step 3】パッケージのインストール ★重要修正：純正環境へのクリーンな追加
# ==============================================================================
echo ""
echo "🔌 [Step 3/5] パッケージのインストール中..."

# コンテナに事前インストールされている強力なシステムベースに、不足パッケージだけをクリーンにマージ
echo "  -> 依存ライブラリをインストール中 (詳細ログは /tmp/pip_install.log)..."
if [ ! -d "$PLUGIN_DIR" ]; then
    mkdir -p "$CUSTOM_NODES_DIR"
    git clone --depth=1 https://github.com/Kijai/ComfyUI-WanVideoWrapper.git "$PLUGIN_DIR"
    $PIP_CMD install --no-cache-dir "huggingface_hub[hf_transfer]" accelerate -r "${PLUGIN_DIR}/requirements.txt" > /tmp/pip_install.log 2>&1
else
    $PIP_CMD install --no-cache-dir "huggingface_hub[hf_transfer]" accelerate > /tmp/pip_install.log 2>&1
fi
echo "  -> ✅ パッケージのインストール完了"

# ==============================================================================
# 【Step 4】ComfyUI を新しい引数で再起動（維持）
# ==============================================================================
echo ""
echo "🔄 [Step 4/5] ComfyUI を再起動中..."
COMFYUI_PIDS=$(pgrep -f "python.*main\.py" 2>/dev/null || true)
if [ -n "$COMFYUI_PIDS" ]; then
    echo "$COMFYUI_PIDS" | xargs kill -9 2>/dev/null || true
    sleep 2
fi

FIXED_ARGS="--listen 0.0.0.0 --port 8188 --enable-cors-header"
EXTRA_ARGS=$(grep -v '^\s*#' "$COMFYUI_ARGS_FILE" | grep -v '^\s*$' | tr '\n' ' ')
ALL_ARGS="${FIXED_ARGS} ${EXTRA_ARGS}"

cd "$COMFYUI_DIR"
$PYTHON_EXEC main.py $ALL_ARGS >"$COMFYUI_LOG" 2>&1 &
COMFYUI_PID=$!

# ==============================================================================
# 【Step 5】モデルのダウンロード（維持）
# ==============================================================================
echo ""
echo "📦 [Step 5/5] モデルを並列ダウンロード中..."
PIDS=()

download_and_rename() {
    local repo_id="$1" local hf_file_path="$2" local target_sub_dir="$3" local final_file_name="$4"
    local full_target_dir="${BASE_DIR}/${target_sub_dir}"
    local final_path="${full_target_dir}/${final_file_name}"

    mkdir -p "${full_target_dir}"
    if [ -f "${final_path}" ]; then return 0; fi

    local safe_name; safe_name=$(echo "${target_sub_dir}_${final_file_name}" | tr '/' '_')
    local log_file="/tmp/hf_dl_${safe_name}.log"

    {
        local tmp_dir; tmp_dir=$(mktemp -d)
        if ! hf download "${repo_id}" "${hf_file_path}" --local-dir "${tmp_dir}"; then
            echo "❌ ERROR: ${hf_file_path} ダウンロード失敗" >&2; rm -rf "${tmp_dir}"; exit 1
        fi
        local orig_file_name="${hf_file_path##*/}"
        local downloaded_file; downloaded_file=$(find "${tmp_dir}" -type f -name "${orig_file_name}" | head -n 1)
        mv -f "${downloaded_file}" "${final_path}"
        rm -rf "${tmp_dir}"
    } >"${log_file}" 2>&1 &
    PIDS+=($!)
}

wait_and_check() {
    local status=0
    for pid in "${PIDS[@]}"; do wait "$pid" || status=1; done
    PIDS=(); return $status
}

download_and_rename "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/vae/wan_2.1_vae.safetensors" "vae" "vae.safetensors"
download_and_rename "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/text_encoders/umt5_xxl_fp16.safetensors" "text_encoders" "text_encoder.safetensors"
download_and_rename "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" "loras" "lora_low.safetensors"
download_and_rename "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" "split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" "loras" "lora_high.safetensors"
download_and_rename "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" "split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors" "diffusion_models" "model_low_noise.safetensors"
download_and_rename "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" "split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors" "diffusion_models" "model_high_noise.safetensors"

if ! wait_and_check; then exit 1; fi
find "$BASE_DIR" -mindepth 1 -type d -empty -delete

# ==============================================================================
# 【完了】ComfyUI の起動確認（維持）
# ==============================================================================
echo ""
echo "⏳ ComfyUI の起動確認中（最大60秒）..."
LAUNCHED=false
for i in $(seq 1 60); do
    if ! kill -0 "$COMFYUI_PID" 2>/dev/null; then
        echo "❌ ComfyUI が予期せず終了しました。直近のログ:"
        tail -n 30 "$COMFYUI_LOG" || true
        exit 1
    fi
    if curl -sf "http://localhost:8188" >/dev/null 2>&1; then
        LAUNCHED=true
        echo "  -> ✅ ${i} 秒で起動完了"
        break
    fi
    sleep 1
done

echo "=================================================="
if $LAUNCHED; then echo "🎉 完了！テンプレート純正の最適化環境で起動しました。"; else echo "⚠️ 起動タイムアウト"; fi
echo "=================================================="
