# base image
FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

ARG VERSION="v0.3.40"
ARG MANAGER_VERSION="3.32.5"
ARG CLI_VERSION="v1.4.1"


RUN echo "Building with VERSION: ${VERSION}"

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy


# Installs Git, because ComfyUI and the ComfyUI Manager are installed by cloning their respective Git repositories
RUN apt update --assume-yes && \
    apt install --assume-yes \
        ca-certificates curl git libibverbs-dev zlib1g-dev aria2 build-essential wget \
        libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg \
        libgl1-mesa-glx && \
    apt clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Clones the ComfyUI repository and checks out the latest release
RUN git clone --recurse-submodules https://github.com/comfyanonymous/ComfyUI.git /opt/comfyui && \
    cd /opt/comfyui && \
    git checkout tags/${VERSION}

RUN git clone --recurse-submodules https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/comfyui-manager && \
    cd /opt/comfyui-manager && \
    git checkout tags/${MANAGER_VERSION}

# Installs the required Python packages for both ComfyUI and the ComfyUI Manager
RUN uv pip install --system \
    --requirement /opt/comfyui/requirements.txt \
    --requirement /opt/comfyui-manager/requirements.txt

RUN uv pip install --system comfy-cli==${CLI_VERSION} \
    onnxruntime-gpu ninja

# Build xformers from source in order to support Blackwell GPUs
# Should be removed once xformers releases a version with Blackwell support
# See: https://github.com/facebookresearch/xformers/pull/1262
RUN uv pip install --system -v --no-build-isolation -U git+https://github.com/facebookresearch/xformers.git@main#egg=xformers


ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} comfyui && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -d /app -s /bin/bash comfyui

RUN mkdir -p /app && chown --recursive $USER_ID:$GROUP_ID /app
RUN chown --recursive $USER_ID:$GROUP_ID /opt/comfyui && \
    chown --recursive $USER_ID:$GROUP_ID /opt/comfyui-manager

ENV COMFY_HOME=/opt/comfyui
ENV MODEL_DIR=${COMFY_HOME}/models
ENV OUTPUT_DIR=${COMFY_HOME}/output
ENV INPUT_DIR=${COMFY_HOME}/input
ENV WOKFLOWS_DIR=${COMFY_HOME}/workflows

ENV PATH="/app/.local/bin:$PATH"

USER comfyui

RUN comfy --skip-prompt tracking disable && \
    comfy --skip-prompt set-default ${COMFY_HOME}

ADD entrypoint.sh /entrypoint.sh
EXPOSE 8188
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["comfy", "launch", "--", "--listen", "--port", "8188"]
