ARG VERSION="v0.6.3"

FROM python:3.12-slim-bookworm AS build

ARG VERSION

ENV PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    DEBIAN_FRONTEND=noninteractive \
    REDIS_HOST=localhost \
    REDIS_PORT=6379

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    gnupg \
    git \
    cmake \
    pkg-config \
    python3-dev \
    libjpeg-dev \
    redis-server \
    supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxcb1 \
    libxkbcommon0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get dist-upgrade -y \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && apt-get install -y --no-install-recommends \
    cuda-toolkit-12-9 libomp-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* ;

WORKDIR /app

RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/unclecode/crawl4ai.git /tmp/crawl4ai

RUN cp /tmp/crawl4ai/deploy/docker/requirements.txt /app/requirements.txt && \
    pip install --no-cache-dir -r requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
            scikit-learn \
            nltk \
            transformers \
            tokenizers && \
            python -m nltk.downloader punkt stopwords ;


RUN pip install --no-cache-dir torch torchao torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128

RUN pip install "/tmp/crawl4ai/[all]"

RUN pip install --no-cache-dir /tmp/crawl4ai && \
    python -c "import crawl4ai; print('✅ crawl4ai is ready to rock!')" && \
    python -c "from playwright.sync_api import sync_playwright; print('✅ Playwright is feeling dramatic!')"

RUN crawl4ai-setup

RUN playwright install --with-deps

RUN cp -rn /tmp/crawl4ai/deploy/docker/* /app/

ENV PATH="/config/.venv/bin:$PATH"
ENV HOME="/config"

RUN mkdir -p /config/.cache/ms-playwright \
    && cp -r /root/.cache/ms-playwright/chromium-* /config/.cache/ms-playwright/ \
    && chown -R nobody:nogroup /config/.cache/ms-playwright

RUN crawl4ai-doctor

RUN chown -R nobody:nogroup /app /config

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]
EXPOSE 11235

ENV PYTHON_ENV=production
ENV PYTHONPATH=/app

CMD ["/usr/local/bin/gunicorn", "--bind", "0.0.0.0:11235", "--workers", "1", "--threads", "4", "--timeout", "1800", "--graceful-timeout", "30", "--keep-alive", "300", "--log-level", "info", "--worker-class", "uvicorn.workers.UvicornWorker", "server:app"]
