#!/bin/bash
set -e

IMAGE=$1
VARIANT=${2:-}

# Find the image in base/ or apps/
if [ -d "base/$IMAGE" ]; then
    IMAGE_PATH="base/$IMAGE"
elif [ -d "apps/$IMAGE" ]; then
    IMAGE_PATH="apps/$IMAGE"
else
    echo "Error: Image '$IMAGE' not found in base/ or apps/"
    exit 1
fi

# Use pushd to change to the image directory
pushd "$IMAGE_PATH"

# Build tag and push flag based on whether REGISTRY is set
if [ -z "$REGISTRY" ]; then
    TAG="$IMAGE:${VARIANT:-latest}"
    PUSH=""
else
    TAG="$REGISTRY/$IMAGE:${VARIANT:-latest}"
    PUSH="--push"
fi

# Determine build target based on variant
if [ "$VARIANT" = "devel" ]; then
    TARGET="--target builder"
else
    TARGET=""
fi

echo "Building $IMAGE_PATH -> $TAG"

# Build the Docker image (and push if registry is set)
docker buildx build \
    --platform linux/amd64 \
    --tag "$TAG" \
    $TARGET \
    $PUSH \
    .

popd
