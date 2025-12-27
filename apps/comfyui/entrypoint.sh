#!/usr/bin/env bash

set -e

# Validate required environment variables
if [ -z "$CONFIG_DIR" ]; then
    echo "ERROR: CONFIG_DIR is not set"
    exit 1
fi

if [ -z "$MODEL_DIR" ]; then
    echo "ERROR: MODEL_DIR is not set"
    exit 1
fi

# Setup virtual environment with system site-packages (for torch, xformers, etc.)
unset UV_SYSTEM_PYTHON
mkdir -p "${VIRTUAL_ENV}"
uv venv --system-site-packages --link-mode=copy --allow-existing "${VIRTUAL_ENV}"
source "${VIRTUAL_ENV}/bin/activate"
export UV_PROJECT_ENVIRONMENT="${VIRTUAL_ENV}"

# Log PyTorch version
echo "PyTorch: $(python -c "import torch; print(torch.__version__)")"

# Create required directories
mkdir -p "$CONFIG_DIR/custom_nodes"
mkdir -p "$USER_DIR"

# Install ComfyUI-Manager if not present
if [ ! -d "$CONFIG_DIR/custom_nodes/ComfyUI-Manager" ]; then
    echo "Cloning ComfyUI-Manager..."
    git clone --depth 1 --quiet https://github.com/Comfy-Org/ComfyUI-Manager.git "$CONFIG_DIR/custom_nodes/ComfyUI-Manager"
fi

# Create model directories
MODEL_DIRECTORIES=(
    "checkpoints"
    "classifiers"
    "clip"
    "clip_vision"
    "configs"
    "controlnet"
    "diffusers"
    "diffusion_models"
    "embeddings"
    "gligen"
    "hypernetworks"
    "loras"
    "photomaker"
    "style_models"
    "text_encoders"
    "unet"
    "upscale_models"
    "vae"
    "vae_approx"
)
for dir in "${MODEL_DIRECTORIES[@]}"; do
    mkdir -p "$MODEL_DIR/$dir"
done

# Install requirements for custom nodes
shopt -s nullglob
for node_dir in "$CONFIG_DIR/custom_nodes"/*; do
    if [ -f "$node_dir/requirements.txt" ]; then
        node_name="${node_dir##*/}"
        echo "Installing requirements for ${node_name}..."
        uv pip install --requirement "$node_dir/requirements.txt"
    fi
done
shopt -u nullglob

echo "Starting ComfyUI..."
exec "$@"
