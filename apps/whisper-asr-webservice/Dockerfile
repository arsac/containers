ARG VERSION="v1.9.1"
ARG VENDOR="arsac"

FROM swaggerapi/swagger-ui:v5.9.1 AS swagger-ui

FROM ghcr.io/${VENDOR}/cuda-ml:runtime

ARG VERSION

# Install build dependencies for PyAV compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-dev pkg-config \
    libavformat-dev libavcodec-dev libavdevice-dev \
    libavutil-dev libswscale-dev libswresample-dev libavfilter-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/ahmetoner/whisper-asr-webservice.git .

# Install dependencies with uv (torch already in base, use PyPI only)
RUN --mount=type=cache,target=/root/.cache/uv \
    UV_EXTRA_INDEX_URL= uv pip install --system --break-system-packages .

COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui.css swagger-ui-assets/swagger-ui.css
COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui-bundle.js swagger-ui-assets/swagger-ui-bundle.js

EXPOSE 9000

ENTRYPOINT ["whisper-asr-webservice"]
