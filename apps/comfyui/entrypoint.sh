#!/usr/bin/env bash

set -e

unset UV_SYSTEM_PYTHON

mkdir -p "${VIRTUAL_ENV}"
uv venv --system-site-packages --link-mode=copy --allow-existing "${VIRTUAL_ENV}"

# Activate virtual environment
source "${VIRTUAL_ENV}/bin/activate"

# Set UV to use the active virtual environment
export UV_PROJECT_ENVIRONMENT="${VIRTUAL_ENV}"

# Get current PyTorch version and ensure it's CUDA 12.8
CURRENT_TORCH_VERSION=$(python -c "import torch; print(torch.__version__)")
echo "System PyTorch: $CURRENT_TORCH_VERSION"

# Creates the directories for the models inside the mounted host volume
if [ ! -d "$CONFIG_DIR" ]; then
    echo "CONFIG_DIR is not set. Please set it to the ComfyUI base directory."
    exit 1
fi

#  If /custom/custom_nodes does not exist, create it
if [ ! -d "$CONFIG_DIR/custom_nodes" ]; then
    echo "Creating /custom/custom_nodes directory..."
    mkdir -p "$CONFIG_DIR/custom_nodes"
fi

if [ ! -d "$CONFIG_DIR/custom_nodes/ComfyUI-Manager" ]; then
    echo "Cloning ComfyUI-Manager into custom_nodes..."
    git clone --depth 1 --quiet https://github.com/Comfy-Org/ComfyUI-Manager.git "$CONFIG_DIR/custom_nodes/ComfyUI-Manager"
fi

if [ ! -d "$USER_DIR" ]; then
    mkdir -p "$USER_DIR"
fi

echo "Creating directories for models..."
MODEL_DIRECTORIES=(
    "checkpoints"
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
for MODEL_DIRECTORY in ${MODEL_DIRECTORIES[@]}; do
    mkdir -p $MODEL_DIR/$MODEL_DIRECTORY
done

echo "Installing requirements for custom nodes..."
for CUSTOM_NODE_DIRECTORY in $CONFIG_DIR/custom_nodes/*;
do
    if [ -f "$CUSTOM_NODE_DIRECTORY/requirements.txt" ];
    then
        CUSTOM_NODE_NAME=${CUSTOM_NODE_DIRECTORY##*/}
        CUSTOM_NODE_NAME=${CUSTOM_NODE_NAME//[-_]/ }
        echo "Installing requirements for $CUSTOM_NODE_NAME..."
        uv pip install --requirement "$CUSTOM_NODE_DIRECTORY/requirements.txt"
    fi
done

echo "Starting ComfyUI..."
"$@"
