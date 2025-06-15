
ARG VERSION="v1.8.2"

FROM onerahmet/ffmpeg:n7.1 AS ffmpeg

FROM swaggerapi/swagger-ui:v5.9.1 AS swagger-ui

FROM nvidia/cuda:12.8.0-base-ubuntu22.04
ARG VERSION


ENV PYTHON_VERSION=3.10

ENV POETRY_VENV=/app/.venv

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get -qq update \
    && apt-get -qq install --no-install-recommends \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python3-pip \
    libcudnn8 \
    python3-pip \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN ln -s -f /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    ln -s -f /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -s -f /usr/bin/pip3 /usr/bin/pip

RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/ahmetoner/whisper-asr-webservice.git /app

RUN python3 -m venv $POETRY_VENV \
    && $POETRY_VENV/bin/pip install -U pip setuptools \
    && $POETRY_VENV/bin/pip install poetry==2.1.1

ENV PATH="${PATH}:${POETRY_VENV}/bin"

WORKDIR /app

RUN poetry config virtualenvs.in-project true
RUN poetry install --no-root


COPY --from=ffmpeg /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui.css swagger-ui-assets/swagger-ui.css
COPY --from=swagger-ui /usr/share/nginx/html/swagger-ui-bundle.js swagger-ui-assets/swagger-ui-bundle.js

RUN poetry install
RUN $POETRY_VENV/bin/pip install torch==2.7.1+cu128 torchaudio==2.7.1+cu128 --index-url https://download.pytorch.org/whl/cu128

EXPOSE 9000

CMD ["whisper-asr-webservice"]
