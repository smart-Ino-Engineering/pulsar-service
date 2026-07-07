#!/bin/bash

set -e  # Exit on any error

echo "=== Apache Pulsar Service Stop Script ==="
echo "Current directory: $(pwd)"
echo "Date: $(date)"
echo ""
docker compose down
sudo rm -rf ./data
mkdir -p ./data/zookeeper ./data/bookkeeper
sudo chmod -R 777 ./data
docker compose up -d