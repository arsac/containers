#!/bin/bash
set -e

IMAGE=$1

IMAGE_PATH="apps/$IMAGE"
if [ ! -d "$IMAGE_PATH" ]; then
    echo "Error: Image '$IMAGE' not found in apps/"
    exit 1
fi

pushd "$IMAGE_PATH"

# Build tag and push flag based on whether REGISTRY is set
if [ -z "$REGISTRY" ]; then
    TAG="$IMAGE:latest"
    PUSH=""
else
    TAG="$REGISTRY/$IMAGE:latest"
    PUSH="--push"
fi

echo "Building $IMAGE_PATH -> $TAG"

docker buildx build \
    --platform linux/amd64 \
    --tag "$TAG" \
    $PUSH \
    .

popd
