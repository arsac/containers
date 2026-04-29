ARG VERSION="1d959b16cc99683824aa849744a95d8ac6c8952a"
ARG CUDA_VERSION="12.8.0"

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04

ARG VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip ffmpeg git gosu tzdata && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install torch with cu128 for Blackwell, then SubGen deps
RUN python3 -m pip install -U --no-cache-dir --break-system-packages \
        torch torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    python3 -m pip install -U --no-cache-dir --break-system-packages \
        numpy stable-ts-whisperless fastapi requests faster-whisper \
        uvicorn python-multipart ffmpeg-python watchdog

# Pin SubGen to a specific upstream commit.
WORKDIR /subgen
RUN git clone https://github.com/McCloudS/subgen.git . && \
    git checkout "${VERSION}" && \
    cp entrypoint.sh /entrypoint.sh && chmod +x /entrypoint.sh

# Apply downstream patches against the pinned upstream tree.
# git apply fails loudly if a hunk doesn't match — so an upstream
# rename or refactor will fail the build instead of silently
# producing a broken image.
COPY patches/01-always-extract-audio-via-ffmpeg.patch /tmp/01-always-extract-audio-via-ffmpeg.patch
RUN git apply --verbose /tmp/01-always-extract-audio-via-ffmpeg.patch && \
    rm -f /tmp/01-always-extract-audio-via-ffmpeg.patch && \
    rm -rf .git

RUN mkdir -p /cache

ENV XDG_CACHE_HOME=/cache \
    HF_HOME=/cache/huggingface \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

EXPOSE 8090

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "launcher.py"]
