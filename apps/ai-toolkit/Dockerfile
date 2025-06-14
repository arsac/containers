# Runtime stage
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV UV_SYSTEM_PYTHON=1

ARG VERSION
ARG MANAGER_VERSION
ARG CLI_VERSION

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg libgl1-mesa-glx git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

RUN curl -sL https://deb.nodesource.com/setup_23.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN uv pip install --system --upgrade pip && \
    uv pip install --system torch torchao torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128

# Copy python wheels from the shared container
COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels
RUN find /tmp/wheels -name "*.whl" -exec uv pip install --system {} \; && \
    rm -rf /tmp/wheels

RUN uv pip install --system onnxruntime-gpu

WORKDIR /app

# Clone ai-toolkit
RUN git clone --depth 1 --branch main --quiet https://github.com/ostris/ai-toolkit.git && \
    cd ai-toolkit

WORKDIR /app/ai-toolkit

RUN sed -i -e 's/torch==/torch>=/g' \
           -e 's/torchvision==/torchvision>=/g' \
           -e 's/torchaudio==/torchaudio>=/g' \
           -e 's/torchao==/torchao>=/g' \
           requirements.txt

# Install ai-toolkit requirements at system level too
RUN uv pip install --system \
    --requirement requirements.txt

# Create user and setup directories
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} ai-toolkit && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -d /app -s /bin/bash ai-toolkit && \
    mkdir -p /app && chown --recursive ai-toolkit:ai-toolkit /app



ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch to comfyui user for application installation
USER ai-toolkit

# Create virtual environment that inherits system packages
RUN uv venv --system-site-packages /app/.venv

# Set environment variables
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"


WORKDIR /app/ai-toolkit/ui

RUN npm install && \
    npm run build && \
    npm run update_db


EXPOSE 8675
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["npm", "run", "start"]
