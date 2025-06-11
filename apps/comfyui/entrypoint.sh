#!/bin/bash
set -e

# Activate virtual environment
source /app/.venv/bin/activate




# Creates the directories for the models inside the mounted host volume
if [ -z "$COMFY_HOME" ]; then
    echo "COMFY_HOME is not set. Please set it to the ComfyUI home directory."
    exit 1
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

echo "Creating symlink for ComfyUI Manager..."
rm --force $COMFY_HOME/custom_nodes/ComfyUI-Manager
ln -s \
    $COMFYUI_MANAGER_HOME \
    $COMFY_HOME/custom_nodes/ComfyUI-Manager

echo "Installing requirements for custom nodes..."
for CUSTOM_NODE_DIRECTORY in $COMFY_HOME/custom_nodes/*;
do
    if [ "$CUSTOM_NODE_DIRECTORY" != "$COMFY_HOME/custom_nodes/ComfyUI-Manager" ];
    then
        if [ -f "$CUSTOM_NODE_DIRECTORY/requirements.txt" ];
        then
            CUSTOM_NODE_NAME=${CUSTOM_NODE_DIRECTORY##*/}
            CUSTOM_NODE_NAME=${CUSTOM_NODE_NAME//[-_]/ }
            echo "Installing requirements for $CUSTOM_NODE_NAME..."
            uv pip install --requirement "$CUSTOM_NODE_DIRECTORY/requirements.txt"
        fi
    fi
done

"$@"
