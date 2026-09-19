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

: "${HF_TOKEN:?HF_TOKEN ist nicht gesetzt}"

echo "=== RAM-Verzeichnisse anlegen (sonst crasht ComfyUI beim Start) ==="
# Alle vier Pfade aus COMFYUI_ARGS. /dev/shm ist nach stop/start leer und dieses
# Skript laeuft dann NICHT erneut - deshalb legt zusaetzlich die --onstart-cmd
# die Verzeichnisse bei jedem Boot an. Hier nur als Absicherung fuer den ersten Boot.
mkdir -p -m 700 /dev/shm/comfy-secure-output /dev/shm/comfy-secure-input \
  /dev/shm/comfy-secure-temp /dev/shm/comfy-secure-user /dev/shm/tmp

mkdir -p "$MODELS_DIR/diffusion_models" "$MODELS_DIR/clip" "$MODELS_DIR/vae" "$MODELS_DIR/upscale_models"

echo "=== ComfyUI-GGUF Custom Node ==="
# WICHTIG: venv aktivieren, sonst installiert pip in die falsche Umgebung -
# ComfyUI selbst aktiviert /venv/main beim Start (siehe comfyui.sh), das
# Provisioning laeuft aber in einem anderen Kontext ohne aktiviertes venv.
. /venv/main/bin/activate
if [ ! -d "$CUSTOM_NODES_DIR/ComfyUI-GGUF" ]; then
  git clone --depth 1 https://github.com/city96/ComfyUI-GGUF "$CUSTOM_NODES_DIR/ComfyUI-GGUF"
fi
pip install --no-cache-dir -r "$CUSTOM_NODES_DIR/ComfyUI-GGUF/requirements.txt"

echo "=== Hugging Face CLI ==="
# Kein "hf auth login": das wuerde den Token nach ~/.cache/huggingface/token und
# (mit --add-to-git-credential) im Klartext nach ~/.git-credentials auf die Disk
# schreiben. "hf download" liest HF_TOKEN direkt aus der Umgebung.
pip install --no-cache-dir -U huggingface_hub >/dev/null

echo "=== Text-Encoder (uncensored, q8_0 GGUF) ==="
if [ ! -f "$MODELS_DIR/clip/flux2-klein-9b-uncensored-q8_0.gguf" ]; then
  hf download ponpoke/flux2-klein-9b-uncensored-text-encoder \
    flux2-klein-9b-uncensored-q8_0.gguf \
    --local-dir "$MODELS_DIR/clip"
fi

echo "=== FLUX.2-klein-9B Transformer (FP8, 9.43 GB) ==="
if [ ! -f "$MODELS_DIR/diffusion_models/flux-2-klein-9b-fp8.safetensors" ]; then
  hf download black-forest-labs/FLUX.2-klein-9b-fp8 \
    flux-2-klein-9b-fp8.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models"
fi

echo "=== VAE (geteilter Decoder fuer alle FLUX.2-Varianten) ==="
if [ ! -f "$MODELS_DIR/vae/full_encoder_small_decoder.safetensors" ]; then
  hf download black-forest-labs/FLUX.2-small-decoder \
    full_encoder_small_decoder.safetensors \
    --local-dir "$MODELS_DIR/vae"
fi

echo "=== Upscale-Modell (4x-UltraSharp) ==="
if [ ! -f "$MODELS_DIR/upscale_models/4x-UltraSharp.pth" ]; then
  hf download uwg/upscaler \
    ESRGAN/4x-UltraSharp.pth \
    --local-dir "$MODELS_DIR/upscale_models"
  mv "$MODELS_DIR/upscale_models/ESRGAN/4x-UltraSharp.pth" "$MODELS_DIR/upscale_models/" 2>/dev/null || true
  rmdir "$MODELS_DIR/upscale_models/ESRGAN" 2>/dev/null || true
fi

echo "=== Provisioning abgeschlossen ==="
