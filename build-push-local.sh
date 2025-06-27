# !/bin/bash
# Use pushd to change to the app directory of the desired app  in apps/ that was passed in as an argument
pushd apps/$1
# Build the Docker image
docker buildx build \
    --platform linux/amd64 \
    --tag $REGISTRY/$1:latest \
    --push \
    .
