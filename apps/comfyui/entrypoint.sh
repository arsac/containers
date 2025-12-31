#!/usr/bin/env bash

set -e

# Validate required environment variables
: "${CONFIG_DIR:?ERROR: CONFIG_DIR is not set}"
: "${MODEL_DIR:?ERROR: MODEL_DIR is not set}"
: "${VIRTUAL_ENV:?ERROR: VIRTUAL_ENV is not set}"

# Check write permissions on mounted directories
check_writable() {
    if [ ! -w "$1" ]; then
        echo "ERROR: $1 is not writable by UID $(id -u)"
        echo "Fix: chown -R $(id -u):$(id -g) $1"
        return 1
    fi
}

if ! check_writable "$CONFIG_DIR"; then
    exit 1
fi

# Create required directories
mkdir -p "$CONFIG_DIR/custom_nodes" "$USER_DIR"

# Symlink /config/models -> /models so custom nodes using $HOME/models work correctly
if [ -d "$CONFIG_DIR/models" ] && [ ! -L "$CONFIG_DIR/models" ]; then
    echo "Warning: $CONFIG_DIR/models exists as a directory, not creating symlink"
    echo "Consider moving contents to $MODEL_DIR and removing $CONFIG_DIR/models"
else
    ln -sfn "$MODEL_DIR" "$CONFIG_DIR/models"
fi

# Create/reuse venv with system site-packages (inherits torch, etc.)
uv venv --system-site-packages --link-mode=copy --allow-existing "$VIRTUAL_ENV"
source "$VIRTUAL_ENV/bin/activate"

# Install uv into venv so ComfyUI-Manager can use it
VENV_SITE=$(python -c "import sysconfig; print(sysconfig.get_path('purelib'))")
uv pip install --quiet --no-index --find-links="$VENV_SITE" uv 2>/dev/null || true

# Ensure torch libraries are in library path
TORCH_LIB=$(python -c "import torch; print(torch.__path__[0])")/lib
export LD_LIBRARY_PATH="${TORCH_LIB}:${LD_LIBRARY_PATH:-}"

# Log PyTorch version and constraints
echo "PyTorch: $(python -c "import torch; print(torch.__version__)")"
echo "Constraints: ${UV_CONSTRAINT:-none}"

# Verify Hunyuan3D extensions
python -c "import custom_rasterizer" && echo "Hunyuan3D: custom_rasterizer OK" || echo "Hunyuan3D: custom_rasterizer FAILED"
python -c "import mesh_processor" && echo "Hunyuan3D: mesh_processor OK" || echo "Hunyuan3D: mesh_processor FAILED"
python -c "from diso import DiffDMC" && echo "Hunyuan3D: diso (dmc) OK" || echo "Hunyuan3D: diso (dmc) FAILED"

# Install ComfyUI-Manager if not present
if [ ! -d "$CONFIG_DIR/custom_nodes/ComfyUI-Manager" ]; then
    echo "Cloning ComfyUI-Manager..."
    git clone --depth 1 --quiet https://github.com/Comfy-Org/ComfyUI-Manager.git "$CONFIG_DIR/custom_nodes/ComfyUI-Manager"
fi

# Configure ComfyUI-Manager to use uv
CM_CONFIG_DIR="$USER_DIR/__manager"
mkdir -p "$CM_CONFIG_DIR"
if [ ! -f "$CM_CONFIG_DIR/config.ini" ]; then
    cat > "$CM_CONFIG_DIR/config.ini" << 'EOF'
[default]
use_uv = True
security_level = weak
file_logging = False
EOF
    echo "Created ComfyUI-Manager config with uv enabled"
fi

# Create model directories
MODEL_DIRECTORIES=(
    "checkpoints"
    "classifiers"
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
    "upscale_models"
    "latent_upscale_models"
    "vae"
    "vae_approx"
    "model_patches"
    "audio_encoders"
)
for dir in "${MODEL_DIRECTORIES[@]}"; do
    mkdir -p "$MODEL_DIR/$dir"
done

# Migrate legacy model folders to new locations
migrate_folder() {
    local src="$1"
    local dest="$2"
    if [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
        echo "Migrating $src -> $dest"
        mkdir -p "$dest"
        for file in "$src"/*; do
            [ -e "$file" ] || continue
            basename="${file##*/}"
            if [ ! -e "$dest/$basename" ]; then
                # Move file to destination
                mv "$file" "$dest/"
            else
                # File exists in both places - remove source duplicate
                echo "  Removing duplicate $basename (already in destination)"
                rm -f "$file"
            fi
        done
        # Remove source directory if empty
        rmdir "$src" 2>/dev/null && echo "  Removed empty $src" || true
    fi
}

migrate_folder "$MODEL_DIR/clip" "$MODEL_DIR/text_encoders"
migrate_folder "$MODEL_DIR/unet" "$MODEL_DIR/diffusion_models"

# Install requirements for custom nodes
# UV_CONSTRAINT/PIP_CONSTRAINT prevent torch ecosystem packages from being changed
shopt -s nullglob
for node_dir in "$CONFIG_DIR/custom_nodes"/*; do
    if [ -f "$node_dir/requirements.txt" ]; then
        node_name="${node_dir##*/}"
        echo "Installing requirements for ${node_name}..."
        uv pip install --index-strategy unsafe-best-match --requirement "$node_dir/requirements.txt" || echo "Warning: Some packages failed to install for ${node_name}"
    fi
done
shopt -u nullglob

echo "Starting ComfyUI..."
exec "$@"
