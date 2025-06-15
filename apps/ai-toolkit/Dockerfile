ARG VERSION=main

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ARG VERSION

ENV PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_NO_CACHE=true \
    UV_SYSTEM_PYTHON=1

# Install only runtime dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    cmake ffmpeg git curl wget htop nvtop rsync unzip openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /usr/share/doc/* /usr/share/man/* /tmp/*

RUN find /usr/local/cuda -name "*.a" -delete \
    && find /usr/local/cuda -name "*_static.a" -delete \
    && rm -rf /usr/local/cuda/doc \
    && rm -rf /usr/local/cuda/samples

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    curl -sL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN rm -f /usr/lib/python*/EXTERNALLY-MANAGED

WORKDIR /
# Clone ai-toolkit
RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/ostris/ai-toolkit.git app

# Copy python wheels from the shared container
COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels

WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --requirement requirements.txt && \
    uv pip install --upgrade accelerate transformers diffusers huggingface_hub ftfy regex tqdm albumentations && \
    uv pip install git+https://github.com/openai/CLIP.git && \
    uv pip install torch torchao torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    find /tmp/wheels -name "*.whl" -exec uv pip install {} \; && \
    rm -rf /tmp/wheels && \
    uv pip install onnxruntime-gpu packaging wheel


ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV HOME="/config" \
    PYTHONUSERBASE="/usr/local" \
    VENV_FOLDER="/config/.venv" \
    npm_config_cache="/config/.cache/npm" \
    npm_config_tmp="/config/.cache/tmp"

ENV CUDA_HOME=/usr/local/cuda
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV CC=gcc
ENV CXX=g++
ENV NVCC=/usr/local/cuda/bin/nvcc

WORKDIR /app/ui

RUN --mount=type=cache,target=/root/.npm \
    npm install && \
    npm run build && \
    npm run update_db

RUN mkdir -p /config && \
    mv /app/aitk_db.db /app/aitk_db.db.default && \
    cp /app/aitk_db.db.default /config/aitk_db.db && \
    ln -s /config/aitk_db.db /app/aitk_db.db && \
    rm -rf /app/config && \
    mkdir -p /config/config && \
    ln -s /config/config /app/config && \
    chown -R root:root /app && \
    chown -R nobody:nogroup /config && \
    chmod -R 755 /app && \
    chown -R nobody:nogroup /app/ui/node_modules && \
    chmod -R 777 /app/ui/node_modules

# Remove /app/config if it exists
RUN rm -rf /app/config && \
    ln -s /config /app/config
    # chmod -R 755 /app && chown -R nobody:nogroup /app/ui/node_modules/.prisma

USER nobody:nogroup

EXPOSE 8675

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

VOLUME ["/config"]

CMD ["npm", "run", "start"]
