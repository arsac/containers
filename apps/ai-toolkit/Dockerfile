# Runtime stage
FROM nvidia/cuda:12.9.0-devel-ubuntu24.04

ENV UV_SYSTEM_PYTHON=1

ARG VERSION
ARG MANAGER_VERSION
ARG CLI_VERSION

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ffmpeg git curl wget htop nvtop rsync unzip openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

RUN curl -sL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# RUN curl https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb && \
#     dpkg -i /tmp/cuda-keyring.deb && \
#     rm /tmp/cuda-keyring.deb && \
#     apt-get update && \
#     apt-get install -y --no-install-recommends \
#     build-essential libnccl-dev cuda-compiler-12-9 cuda-libraries-dev-12-9 libcudnn9-dev && \
#     apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN rm -f /usr/lib/python*/EXTERNALLY-MANAGED

RUN uv pip install --upgrade pip && \
    uv pip install torch torchao torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128

# Copy python wheels from the shared container
COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels
RUN find /tmp/wheels -name "*.whl" -exec uv pip install {} \; && \
    rm -rf /tmp/wheels

RUN uv pip install onnxruntime-gpu


WORKDIR /
# Clone ai-toolkit
RUN git clone --depth 1 --branch main --quiet https://github.com/ostris/ai-toolkit.git app && \
    cd app && \
    sed -i -e 's/torch==/torch>=/g' \
           -e 's/torchvision==/torchvision>=/g' \
           -e 's/torchaudio==/torchaudio>=/g' \
           -e 's/torchao==/torchao>=/g' \
           requirements.txt && \
    uv pip install --requirement requirements.txt


WORKDIR /app


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

RUN npm install && \
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
