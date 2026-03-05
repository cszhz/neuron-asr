#!/bin/bash

CONTAINER_NAME="neuron-asr"
IMAGE_NAME="cszhzleo/qwen3-asr-align-neuron:latest"
PORT=${PORT:-3003}
PRELOAD_ALIGNER=${PRELOAD_ALIGNER:-false}

# Paths
MODELS_DIR="/home/ubuntu/models"
ASR_COMPILED_DIR="/home/ubuntu/models/Qwen/Qwen3-ASR-1.7B/compiled"
ALIGNER_COMPILED_DIR="/home/ubuntu/models/Qwen/Qwen3-ForcedAligner-0.6B/compiled/forced_aligner"

# Stop and remove existing container
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping existing container..."
    docker stop ${CONTAINER_NAME} 2>/dev/null
    docker rm ${CONTAINER_NAME} 2>/dev/null
fi

echo "Starting ${CONTAINER_NAME} container..."
echo "  Port: ${PORT}"
echo "  Preload Aligner: ${PRELOAD_ALIGNER}"
echo ""

docker run -d \
    --name ${CONTAINER_NAME} \
    -p ${PORT}:3003 \
    --device=/dev/neuron0 \
    -e NEURON_RT_VISIBLE_CORES=0,1 \
    -v ${MODELS_DIR}:/models:ro \
    -v ${ASR_COMPILED_DIR}:/compiled/asr:ro \
    -v ${ALIGNER_COMPILED_DIR}:/compiled/aligner:ro \
    -e COMPILED_DIR=/compiled/asr \
    -e ALIGNER_COMPILED_DIR=/compiled/aligner \
    -e PRELOAD_ALIGNER=${PRELOAD_ALIGNER} \
    ${IMAGE_NAME}

echo ""
echo "Container started. Checking status..."
sleep 2
docker ps --filter name=${CONTAINER_NAME}

echo ""
echo "View logs: docker logs -f ${CONTAINER_NAME}"
echo ""
echo "Usage:"
echo "  # Start with timestamps preloaded"
echo "  PRELOAD_ALIGNER=true ./run.sh"

