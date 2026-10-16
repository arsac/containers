ARG VERSION="v1.9.1"
ARG CUDA_VERSION="12.8.0"

FROM swaggerapi/swagger-ui:v5.9.1 AS swagger-ui

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04

ARG VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install Python, ffmpeg, and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev \
    python3-pip git curl ca-certificates \
    ffmpeg pkg-config gcc \
    libavformat-dev libavcodec-dev libavdevice-dev \
    libavutil-dev libswscale-dev libswresample-dev libavfilter-dev && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/python3.12 /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/ahmetoner/whisper-asr-webservice.git .

# Install dependencies with uv
# Use PyTorch CUDA 12.8 index for torch packages
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-strategy unsafe-best-match \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        .

# Upgrade torch to cu128 for RTX 5090 support (whisper-asr-webservice pins cu126)
# Uninstall first to avoid version conflicts, then install matching versions
RUN uv pip uninstall --system --break-system-packages torch torchvision torchaudio && \
    uv pip install --system --break-system-packages \
        --index-url https://download.pytorch.org/whl/cu128 \
        torch torchvision torchaudio

# Fix pyannote-audio for torch 2.9 compatibility (torchaudio.AudioMetaData removed)
# Pin numpy<2.4 for numba compatibility
# Downgrade huggingface-hub<1.0 for transformers compatibility
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages --reinstall \
        "pyannote-audio @ git+https://github.com/pyannote/pyannote-audio.git@develop" \
        "numpy<2.4" \
        "huggingface-hub<1.0"

# Ensure torch ecosystem is cu128 after all installs (pyannote may override)
RUN uv pip uninstall --system --break-system-packages torch torchvision torchaudio && \
    uv pip install --system --break-system-packages \
        --index-url https://download.pytorch.org/whl/cu128 \
        torch torchvision torchaudio

COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui.css swagger-ui-assets/swagger-ui.css
COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui-bundle.js swagger-ui-assets/swagger-ui-bundle.js

EXPOSE 9000

ENTRYPOINT ["whisper-asr-webservice"]
