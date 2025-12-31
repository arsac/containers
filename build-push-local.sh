#!/bin/bash
set -e

# Use pushd to change to the app directory
pushd apps/$1

# Build tag and push flag based on whether REGISTRY is set
if [ -z "$REGISTRY" ]; then
    TAG="$1:latest"
    PUSH=""
else
    TAG="$REGISTRY/$1:latest"
    PUSH="--push"
fi

# Build the Docker image (and push if registry is set)
docker buildx build \
    --platform linux/amd64 \
    --tag "$TAG" \
    $PUSH \
    .

popd
