#!/bin/bash
# Provisioning-Skript fuer das Vast.ai ComfyUI-Template ("ComfyUI - Mod RAM")
# Wird automatisch beim ERSTEN Boot einer neuen Instanz ausgefuehrt (PROVISIONING_SCRIPT env var).
# Laeuft die Instanz einfach nur stop/start (nicht destroy+neu erstellt), wird dieses
# Skript NICHT erneut ausgefuehrt - das ist beabsichtigt, siehe /.provisioning-Marker
# im image-eigenen Start-Skript.
#
# Voraussetzungen (im Vast-Template bereits gesetzt):
#   - HF_TOKEN als Environment-Variable mit gueltigem Hugging-Face-Token
#   - Zugriff auf beide gated FLUX-Repos unten wurde im HF-Account bereits akzeptiert
#   - COMFYUI_ARGS zeigt bereits auf die /dev/shm-Pfade + --disable-dynamic-vram
#     (dieses Skript muss COMFYUI_ARGS nicht anfassen, nur die Verzeichnisse
#     und Modelle bereitstellen, auf die die Args verweisen)

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
MODELS_DIR="$WORKSPACE/ComfyUI/models"
CUSTOM_NODES_DIR="$WORKSPACE/ComfyUI/custom_nodes"

echo "=== RAM-Output-Verzeichnisse anlegen (sonst crasht ComfyUI beim Start) ==="
mkdir -p /dev/shm/comfy-secure-output /dev/shm/comfy-secure-input

mkdir -p "$MODELS_DIR/diffusion_models" "$MODELS_DIR/clip" "$MODELS_DIR/vae" "$MODELS_DIR/upscale_models"

echo "=== ComfyUI-GGUF Custom Node ==="
if [ ! -d "$CUSTOM_NODES_DIR/ComfyUI-GGUF" ]; then
  git clone --depth 1 https://github.com/city96/ComfyUI-GGUF "$CUSTOM_NODES_DIR/ComfyUI-GGUF"
  pip install --no-cache-dir -r "$CUSTOM_NODES_DIR/ComfyUI-GGUF/requirements.txt" || true
else
  echo "bereits vorhanden, ueberspringe"
fi

echo "=== Hugging Face Login ==="
pip install --no-cache-dir -U "huggingface_hub[cli]" >/dev/null
huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential

echo "=== Text-Encoder (uncensored, q8_0 GGUF) ==="
if [ ! -f "$MODELS_DIR/clip/flux2-klein-9b-uncensored-q8_0.gguf" ]; then
  huggingface-cli download ponpoke/flux2-klein-9b-uncensored-text-encoder \
    flux2-klein-9b-uncensored-q8_0.gguf \
    --local-dir "$MODELS_DIR/clip"
fi

echo "=== FLUX.2-klein-9B Transformer (FP8, 9.43 GB) ==="
if [ ! -f "$MODELS_DIR/diffusion_models/flux-2-klein-9b-fp8.safetensors" ]; then
  huggingface-cli download black-forest-labs/FLUX.2-klein-9b-fp8 \
    flux-2-klein-9b-fp8.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models"
fi

echo "=== VAE (geteilter Decoder fuer alle FLUX.2-Varianten) ==="
if [ ! -f "$MODELS_DIR/vae/full_encoder_small_decoder.safetensors" ]; then
  huggingface-cli download black-forest-labs/FLUX.2-small-decoder \
    full_encoder_small_decoder.safetensors \
    --local-dir "$MODELS_DIR/vae"
fi

echo "=== Upscale-Modell (4x-UltraSharp) ==="
if [ ! -f "$MODELS_DIR/upscale_models/4x-UltraSharp.pth" ]; then
  huggingface-cli download uwg/upscaler \
    ESRGAN/4x-UltraSharp.pth \
    --local-dir "$MODELS_DIR/upscale_models"
  mv "$MODELS_DIR/upscale_models/ESRGAN/4x-UltraSharp.pth" "$MODELS_DIR/upscale_models/" 2>/dev/null || true
  rmdir "$MODELS_DIR/upscale_models/ESRGAN" 2>/dev/null || true
fi

echo "=== Provisioning abgeschlossen ==="
