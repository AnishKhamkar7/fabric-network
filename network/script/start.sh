#!/bin/bash

# Hyperledger Fabric Network Management Script
# This script provides functions to start, deploy chaincode, and manage a Hyperledger Fabric network

set -e

chmod +x start.sh 

# Configuration variables
CHANNEL_NAME="mychannel"
CHAINCODE_NAME="asset-transfer"
CHAINCODE_VERSION="1.0"
CHAINCODE_PATH="/opt/gopath/src/github.com/chaincode/src/asset-transfer"
CHAINCODE_LANG="golang"
CHAINCODE_LABEL="asset_transfer_1.0"

# Directory setup
export FABRIC_CFG_PATH=${PWD}/../../config
export PATH=$PATH:~/go/src/github.com/AnishKhamkar7/fabric-samples/bin

# Function to print help message
print_help() {
  echo "Hyperledger Fabric Network Management Script"
  echo ""
  echo "Usage: "
  echo "  ./start.sh [mode] [options]"
  echo ""
  echo "Modes:"
  echo "  up        - Start the network only"
  echo "  down      - Stop the network"
  echo "  generate  - Generate crypto material and channel artifacts"
  echo "  create    - Create and join channel"
  echo "  deploy    - Install and deploy chaincode"
  echo "  all       - Execute all steps (default)"
  echo ""
  echo "Options:"
  echo "  -c, --channel <name>   - Channel name (default: \"mychannel\")"
  echo "  -h, --help             - Print this help message"
  echo ""
  echo "Examples:"
  echo "  ./start.sh up                   - Start the network only"
  echo "  ./start.sh all -c businesschan  - Run all steps with custom channel name"
  echo "  ./start.sh deploy               - Deploy chaincode on existing network"
}

# Function to generate crypto material
generate_crypto() {
  echo "Cleaning old certificates and artifacts..."
  rm -rf crypto-config channel-artifacts

 echo "Current directory: $(pwd)"
  echo "Checking for crypto-config.yaml..."
  # Generate crypto material using cryptogen
  echo "Generating crypto material..."
  cryptogen generate --config=../../config/crypto-config.yaml --output="../../config/crypto-config"

  # Generate channel artifacts (genesis block and channel transaction)
  echo "=== Generating Channel Artifacts ==="
  mkdir -p channel-artifacts
  
  echo "Generating genesis block..."
  configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBl  ock ../config/genesis.block
  
  echo "Generating channel transaction..."
  configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../config/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
  
  echo "Generating anchor peer updates for Org1..."
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
  
  echo "Generating anchor peer updates for Org2..."
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
  
  echo "✅ Channel artifacts generated successfully!"
}

# Function to generate channel artifacts
  generate_artifacts() {
    echo "=== Generating Channel Artifacts ==="
    mkdir -p channel-artifacts
    
    echo "Generating genesis block..."
    configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock ../config/genesis.block
    
    echo "Generating channel transaction..."
    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../config/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
    
    echo "Generating anchor peer updates for Org1..."
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
    
    echo "Generating anchor peer updates for Org2..."
    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
    
    echo "✅ Channel artifacts generated successfully!"
}

# Function to start the network
start_network() {
  echo "=== Starting the Network ==="
  docker-compose up -d
  
  # Wait for containers to start
  echo "Waiting for containers to start (10 seconds)..."
  sleep 10
  echo "✅ Network started successfully!"
}

# Function to stop the network
stop_network() {
  echo "=== Stopping the Network ==="
  docker-compose down
  echo "✅ Network stopped successfully!"
}

# Function to create and join channel
create_channel() {
  echo "=== Creating Channel: ${CHANNEL_NAME} ==="
  docker exec cli peer channel create -o orderer.example.com:7050 \
    -c $CHANNEL_NAME \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.tx \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
  
  echo "✅ Channel created successfully!"
  
  echo "=== Joining Peers to Channel ==="
  
  echo "Joining peer0.org1 to channel..."
  docker exec cli peer channel join -b ${CHANNEL_NAME}.block
  
  echo "Updating anchor peers for Org1..."
  docker exec cli peer channel update \
    -o orderer.example.com:7050 \
    -c $CHANNEL_NAME \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org1MSPanchors.tx \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
  
  echo "Joining peer1.org1 to channel..."
  docker exec -e CORE_PEER_ADDRESS=peer1.org1.example.com:7051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt \
    cli peer channel join -b ${CHANNEL_NAME}.block
  
  echo "Joining peer0.org2 to channel..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    cli peer channel join -b ${CHANNEL_NAME}.block
  
  echo "Updating anchor peers for Org2..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    cli peer channel update \
    -o orderer.example.com:7050 \
    -c $CHANNEL_NAME \
    -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org2MSPanchors.tx \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
  
  echo "Joining peer1.org2 to channel..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer1.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer1.org2.example.com/tls/ca.crt \
    cli peer channel join -b ${CHANNEL_NAME}.block
  
  echo "✅ All peers joined the channel successfully!"
}

# Function to install and deploy chaincode
deploy_chaincode() {
  echo "=== Installing Chaincode ==="
  
  echo "Packaging chaincode..."
  docker exec cli peer lifecycle chaincode package ${CHAINCODE_NAME}.tar.gz \
    --path ${CHAINCODE_PATH} \
    --lang ${CHAINCODE_LANG} \
    --label ${CHAINCODE_LABEL}
  
  echo "Installing on peer0.org1..."
  docker exec cli peer lifecycle chaincode install ${CHAINCODE_NAME}.tar.gz
  
  echo "Installing on peer1.org1..."
  docker exec -e CORE_PEER_ADDRESS=peer1.org1.example.com:7051 \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt \
    cli peer lifecycle chaincode install ${CHAINCODE_NAME}.tar.gz
  
  echo "Installing on peer0.org2..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    cli peer lifecycle chaincode install ${CHAINCODE_NAME}.tar.gz
  
  echo "Installing on peer1.org2..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer1.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer1.org2.example.com/tls/ca.crt \
    cli peer lifecycle chaincode install ${CHAINCODE_NAME}.tar.gz
  
  echo "✅ Chaincode installed on all peers!"
  
  # Get the package ID
  echo "Querying chaincode package ID..."
  PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled | grep ${CHAINCODE_NAME} | awk '{print $3}' | sed 's/,//')
  
  echo "Chaincode package ID: $PACKAGE_ID"
  
  echo "=== Deploying Chaincode ==="
  
  echo "Approving chaincode for Org1..."
  docker exec cli peer lifecycle chaincode approveformyorg \
    -o orderer.example.com:7050 \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
    --channelID $CHANNEL_NAME \
    --name ${CHAINCODE_NAME} \
    --version ${CHAINCODE_VERSION} \
    --package-id $PACKAGE_ID \
    --sequence 1
  
  echo "Approving chaincode for Org2..."
  docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    cli peer lifecycle chaincode approveformyorg \
    -o orderer.example.com:7050 \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
    --channelID $CHANNEL_NAME \
    --name ${CHAINCODE_NAME} \
    --version ${CHAINCODE_VERSION} \
    --package-id $PACKAGE_ID \
    --sequence 1
  
  echo "Checking commit readiness..."
  docker exec cli peer lifecycle chaincode checkcommitreadiness \
    --channelID $CHANNEL_NAME \
    --name ${CHAINCODE_NAME} \
    --version ${CHAINCODE_VERSION} \
    --sequence 1 \
    --output json
  
  echo "Committing chaincode..."
  docker exec cli peer lifecycle chaincode commit \
    -o orderer.example.com:7050 \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
    --channelID $CHANNEL_NAME \
    --name ${CHAINCODE_NAME} \
    --version ${CHAINCODE_VERSION} \
    --sequence 1 \
    --peerAddresses peer0.org1.example.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
    --peerAddresses peer0.org2.example.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
  
  echo "✅ Chaincode committed successfully!"
}

# Function to initialize the ledger
initialize_ledger() {
  echo "=== Initializing Ledger ==="
  
  docker exec cli peer chaincode invoke \
    -o orderer.example.com:7050 \
    --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
    -C $CHANNEL_NAME \
    -n ${CHAINCODE_NAME} \
    --peerAddresses peer0.org1.example.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
    --peerAddresses peer0.org2.example.com:7051 \
    --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    -c '{"function":"InitLedger","Args":[]}'
  
  echo "✅ Ledger initialized successfully!"
}

# Parse command line arguments
MODE="all"
ARGS=()

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -h|--help)
      print_help
      exit 0
      ;;
    -c|--channel)
      CHANNEL_NAME="$2"
      shift
      shift
      ;;
    up|down|generate|create|deploy|all)
      MODE="$1"
      shift
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# Execute based on mode
case $MODE in
  "up")
    start_network
    ;;
  "down")
    stop_network
    ;;
  "generate")
    generate_crypto
    generate_artifacts
    ;;
  "create")
    create_channel
    ;;
  "deploy")
    deploy_chaincode
    initialize_ledger
    ;;
  "all")
    echo "=== Running Full Network Setup ==="
    echo "Channel name: $CHANNEL_NAME"
    generate_crypto
    # generate_artifacts
    start_network
    create_channel
    deploy_chaincode
    initialize_ledger
    echo "✅ Full network setup completed successfully!"
    ;;
  *)
    echo "Error: Unknown mode '$MODE'"
    print_help
    exit 1
    ;;
esac

exit 0