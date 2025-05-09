#!/bin/bash

set -e

# Help Message
function printHelp() {
  echo "Usage:"
  echo "  start.sh [<channel-name>]"
  echo "    <channel-name> - Channel name to use (defaults to \"mychannel\")"
}

# Environment Setup
function setupEnvironment() {
  export CHANNEL_NAME=${1:-"mychannel"}
  export FABRIC_CFG_PATH=${PWD}/../../config
  export PATH=$PATH:~/go/src/github.com/AnishKhamkar7/fabric-samples/bin
  CONFIG_PATH=../config
}

# Generate crypto materials
function generateCrypto() {
  echo "Creating crypto material using cryptogen..."
  mkdir -p ../crypto-config
  cryptogen generate --config=../config/crypto-config.yaml --output="../config/crypto-config"
}

# Generate channel artifacts
function generateChannelArtifacts() {
  echo "Generating channel artifacts..."
  mkdir -p $CONFIG_PATH
  configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock $CONFIG_PATH/genesis.block
  configtxgen -profile TwoOrgsChannel -outputCreateChannelTx $CONFIG_PATH/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate $CONFIG_PATH/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate $CONFIG_PATH/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
}

# Start the network
function startNetwork() {
  echo "Starting the network..."
  docker-compose up -d
  sleep 10
}

# Channel creation and joining
function createAndJoinChannel() {
  echo "Creating channel..."
  docker exec cli peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.tx --tls --cafile $ORDERER_TLS_CA

  echo "Joining peers to the channel..."
  docker exec cli peer channel join -b ${CHANNEL_NAME}.block
  docker exec cli peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org1MSPanchors.tx --tls --cafile $ORDERER_TLS_CA

  docker exec -e CORE_PEER_ADDRESS=peer1.org1.example.com:7051 -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_PEER1_TLS_CA cli peer channel join -b ${CHANNEL_NAME}.block

  joinOrg2Peers
}

function joinOrg2Peers() {
  for PEER in peer0 peer1; do
    docker exec \
      -e CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP \
      -e CORE_PEER_ADDRESS=${PEER}.org2.example.com:7051 \
      -e CORE_PEER_LOCALMSPID=Org2MSP \
      -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_${PEER^^}_TLS_CA \
      cli peer channel join -b ${CHANNEL_NAME}.block
  done

  docker exec \
    -e CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_CA \
    cli peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org2MSPanchors.tx --tls --cafile $ORDERER_TLS_CA
}

# Install and approve chaincode
function deployChaincode() {
  echo "Installing chaincode..."
  docker exec cli peer lifecycle chaincode package asset-transfer.tar.gz --path /opt/gopath/src/github.com/chaincode/src/asset-transfer --lang golang --label asset_transfer_1.0

  for ORG in org1 org2; do
    for PEER in peer0 peer1; do
      if [ "$ORG" == "org2" ]; then
        docker exec \
          -e CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP \
          -e CORE_PEER_ADDRESS=${PEER}.${ORG}.example.com:7051 \
          -e CORE_PEER_LOCALMSPID=Org2MSP \
          -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_${PEER^^}_TLS_CA \
          cli peer lifecycle chaincode install asset-transfer.tar.gz
      else
        docker exec \
          -e CORE_PEER_ADDRESS=${PEER}.${ORG}.example.com:7051 \
          -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_${PEER^^}_TLS_CA \
          cli peer lifecycle chaincode install asset-transfer.tar.gz
      fi
    done
  done

  PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled | grep asset_transfer | awk '{print $3}' | sed 's/,//')
  echo "Chaincode package ID: $PACKAGE_ID"

  echo "Approving chaincode for orgs..."
  docker exec cli peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile $ORDERER_TLS_CA --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --package-id $PACKAGE_ID --sequence 1

  docker exec \
    -e CORE_PEER_MSPCONFIGPATH=$ORG2_ADMIN_MSP \
    -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 \
    -e CORE_PEER_LOCALMSPID=Org2MSP \
    -e CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_PEER0_TLS_CA \
    cli peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile $ORDERER_TLS_CA --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --package-id $PACKAGE_ID --sequence 1

  docker exec cli peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --sequence 1 --output json

  echo "Committing chaincode..."
  docker exec cli peer lifecycle chaincode commit -o orderer.example.com:7050 --tls --cafile $ORDERER_TLS_CA --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --sequence 1 \
    --peerAddresses peer0.org1.example.com:7051 --tlsRootCertFiles $ORG1_PEER0_TLS_CA \
    --peerAddresses peer0.org2.example.com:7051 --tlsRootCertFiles $ORG2_PEER0_TLS_CA
}

# Constants (to avoid repeating paths)
ORDERER_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
ORG1_PEER0_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
ORG1_PEER1_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt
ORG2_PEER0_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
ORG2_PEER1_TLS_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer1.org2.example.com/tls/ca.crt
ORG2_ADMIN_MSP=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp

# ------------------------------
# MAIN SCRIPT EXECUTION STARTS
# ------------------------------

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  printHelp
  exit 0
fi

setupEnvironment "$1"
generateCrypto
generateChannelArtifacts
startNetwork
createAndJoinChannel
deployChaincode

echo "✅ Network setup and chaincode deployment completed!"
