#!/bin/bash
set -e

echo "=== Step 1: Pulling Docker image ==="
#docker pull cszhzleo/qwen3-asr-align-neuron:latest

echo "=== Step 2: Downloading model weights ==="
mkdir -p /home/ubuntu/models/

# Install huggingface-cli if not present
if ! command -v huggingface-cli &> /dev/null; then
    echo "Installing huggingface-hub..."
    sudo apt install python3-pip -y
    pip install -U huggingface-hub
fi

# Download model
echo "Downloading model to /home/ubuntu/models/..."
python3 -c "
from huggingface_hub import snapshot_download
import os

# Create models directory
os.makedirs('/home/ubuntu/models/', exist_ok=True)

print('Downloading model...')
try:
    snapshot_download(
        repo_id='cszhzleo/Qwen3-ForcedAligner-0.6B-neuron-2.27.1-trn2',
        local_dir='/home/ubuntu/models/'
    )
    print('Download completed successfully!')
except Exception as e:
    print(f'Download failed: {e}')
    exit(1)
"

echo "=== Setup completed successfully ==="
echo "Docker image: cszhzleo/qwen3-asr-align-neuron:latest"
echo "Model location: /home/ubuntu/models/"

