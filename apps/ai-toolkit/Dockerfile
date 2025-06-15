# Runtime stage
FROM nvidia/cuda:12.9.0-devel-ubuntu24.04

ENV UV_SYSTEM_PYTHON=1

ARG VERSION
ARG MANAGER_VERSION
ARG CLI_VERSION

# Install only runtime dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ffmpeg git curl wget htop nvtop rsync unzip openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

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

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --upgrade pip && \
    uv pip install torch torchao torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128

# Copy python wheels from the shared container
COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels

RUN --mount=type=cache,target=/root/.cache/uv \
    find /tmp/wheels -name "*.whl" -exec uv pip install {} \; && \
    rm -rf /tmp/wheels && \
    uv pip install onnxruntime-gpu

WORKDIR /
# Clone ai-toolkit
RUN git clone --depth 1 --branch main --quiet https://github.com/ostris/ai-toolkit.git app && \
    cd app && \
    sed -i -e 's/torch==/torch>=/g' \
           -e 's/torchvision==/torchvision>=/g' \
           -e 's/torchaudio==/torchaudio>=/g' \
           -e 's/torchao==/torchao>=/g' \
           requirements.txt

WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --requirement requirements.txt

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV HOME="/config" \
    PYTHONUSERBASE="/usr/local" \
    VENV_FOLDER="/config/.venv"

# # Create virtual environment that inherits system packages
# RUN uv venv --system-site-packages /app/.venv

# # Set environment variables
# ENV VIRTUAL_ENV=/app/.venv
# ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app/ui

RUN --mount=type=cache,target=/root/.npm \
    npm install && \
    npm run build && \
    npm run update_db

RUN mkdir -p /config && mv /app/aitk_db.db /config/aitk_db.db && \
    ln -s /config/aitk_db.db /app/aitk_db.db && chown -R root:root /app && \
    chmod -R 755 /app && chown -R nobody:nogroup /app/ui/node_modules/.prisma

RUN chown nobody:nogroup -R /config

USER nobody:nogroup

RUN npx prisma db push

EXPOSE 8675
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["npm", "run", "start"]
