ARG VERSION="v0.6.0"
ARG PYTHON_VERSION="3.12"
ARG TORCH_CUDA="cu128"
ARG BASE_IMAGE="ghcr.io/arsac/cuda-ml"

# =============================================================================
# Builder stage - uses devel base image with CUDA compiler and build tools
# =============================================================================
FROM ${BASE_IMAGE}:devel AS builder

ARG VERSION
ARG TORCH_CUDA
ARG PYTHON_VERSION

# Clone ComfyUI and install requirements
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --branch ${VERSION} --quiet \
    https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    rm -rf /app/.git && \
    echo "Installed torch version:" && \
    python -c "import torch; print(torch.__version__)"

# Build Hunyuan3D extensions from source
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git /tmp/hunyuan3d && \
    cd /tmp/hunyuan3d && \
    git sparse-checkout set hy3dgen/texgen/custom_rasterizer hy3dgen/texgen/differentiable_renderer && \
    # Build custom_rasterizer
    cd /tmp/hunyuan3d/hy3dgen/texgen/custom_rasterizer && \
    python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    # Build mesh_processor (differentiable_renderer)
    cd /tmp/hunyuan3d/hy3dgen/texgen/differentiable_renderer && \
    python setup.py build_ext --inplace && \
    cp -r mesh_processor* /usr/local/lib/python${PYTHON_VERSION}/dist-packages/ && \
    # Clean up build artifacts
    rm -rf /tmp/hunyuan3d && \
    echo "custom_rasterizer and mesh_processor installed"

# Install diso (Differentiable Marching Cubes) for Hunyuan3D dmc algorithm
# Build from source with FORCE_CUDA=1 since no GPU available during build
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --recursive https://github.com/SarahWeiii/diso.git /tmp/diso && \
    cd /tmp/diso && \
    FORCE_CUDA=1 python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    rm -rf /tmp/diso && \
    echo "diso installed (import test skipped - requires GPU)"

# Update constraints file with new packages
RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|tokenizers|accelerate|sageattention|custom-rasterizer)==" \
    > /app/constraints.txt && \
    echo "Generated constraints:" && cat /app/constraints.txt

# Cleanup to reduce image size
RUN find /usr/local/lib/python${PYTHON_VERSION} -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -type d -name 'tests' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -type d -name 'test' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -type d -name 'docs' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -name '*.pyc' -delete 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -name '*.so' -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    rm -rf /tmp/* /var/tmp/*

# =============================================================================
# Runtime stage - use runtime base image with app-specific additions
# =============================================================================
FROM ${BASE_IMAGE}:runtime

ARG PYTHON_VERSION

ENV UV_CONSTRAINT=/app/constraints.txt \
    PIP_CONSTRAINT=/app/constraints.txt

# Copy app-specific Python packages (Hunyuan3D extensions, diso, ComfyUI deps)
COPY --from=builder /usr/local/lib/python${PYTHON_VERSION}/dist-packages /usr/local/lib/python${PYTHON_VERSION}/dist-packages

# Copy ComfyUI
COPY --from=builder /app /app

# Copy configuration files
COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh

USER root
RUN chmod +x /entrypoint.sh && \
    # Create directories and symlinks
    mkdir -p /config /config/user /config/custom_nodes /config/.venv /config/web /input /output /models && \
    chmod -R 755 /config /input /output /models && \
    ln -sf /config/web /app/web

# Environment variables
ENV CONFIG_DIR=/config \
    USER_DIR=/config/user \
    MODEL_DIR=/models \
    WORKFLOWS_DIR=/config/workflows \
    OUTPUT_DIR=/output \
    INPUT_DIR=/input \
    VIRTUAL_ENV=/config/.venv \
    HOME="/config"

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config", "/models", "/input", "/output"]

EXPOSE 8188
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

CMD ["python", "/app/main.py", \
    "--listen", "0.0.0.0", "--port", "8188", \
    "--multi-user", \
    "--base-directory", "/config", \
    "--user-directory", "/config/user", \
    "--input-directory", "/input", \
    "--output-directory", "/output", \
    "--temp-directory", "/tmp", \
    "--extra-model-paths-config", "/app/extra_model_paths.yaml", \
    "--use-sage-attention"]
