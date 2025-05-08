#!/bin/bash

set -e

# Stop and remove the containers
echo "Stopping and removing containers..."
docker-compose down --volumes --remove-orphans

# Remove generated artifacts
echo "Cleaning up generated artifacts..."
cd ..
rm -rf crypto-config
rm -rf config/*.block config/*.tx

echo "Network shutdown completed successfully!"