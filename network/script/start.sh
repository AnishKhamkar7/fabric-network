#!/bin/bash

set -e

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  start.sh [<channel-name>]"
  echo "    <channel-name> - channel name to use (defaults to \"mychannel\")"
}

# Parse commandline args
if [ "$1" = "-h" -o "$1" = "--help" ]; then
  printHelp
  exit 0
fi

CHANNEL_NAME="mychannel"
if [ ! -z "$1" ]; then
  CHANNEL_NAME=$1
fi

export FABRIC_CFG_PATH=${PWD}/../../config

export PATH=$PATH:~/go/src/github.com/AnishKhamkar7/fabric-samples/bin

echo "Creating crypto material using cryptogen..."
cd ..
mkdir -p crypto-config
cryptogen generate --config=../config/crypto-config.yaml --output="../config/crypto-config"
cd ..
cd network

echo "Generating channel artifacts..."
mkdir -p ../config
configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock ../config/genesis.block
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../config/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../config/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP

echo "Starting the network..."
docker-compose up -d

# Wait for 10 seconds to allow the network to start
sleep 10

echo "Creating channel..."
docker exec cli peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

echo "Joining peers to channel..."
# Peer0.org1 joins the channel
docker exec cli peer channel join -b ${CHANNEL_NAME}.block

# Update anchor peers for Org1
docker exec cli peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org1MSPanchors.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Peer1.org1 joins the channel
docker exec -e CORE_PEER_ADDRESS=peer1.org1.example.com:7051 -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt cli peer channel join -b ${CHANNEL_NAME}.block

# Peer0.org2 joins the channel
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt cli peer channel join -b ${CHANNEL_NAME}.block

# Update anchor peers for Org2
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt cli peer channel update -o orderer.example.com:7050 -c $CHANNEL_NAME -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/Org2MSPanchors.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Peer1.org2 joins the channel
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer1.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer1.org2.example.com/tls/ca.crt cli peer channel join -b ${CHANNEL_NAME}.block

echo "Installing chaincode..."
# Package the chaincode
docker exec cli peer lifecycle chaincode package asset-transfer.tar.gz --path /opt/gopath/src/github.com/chaincode/src/asset-transfer --lang golang --label asset_transfer_1.0

# Install the chaincode on peer0.org1
docker exec cli peer lifecycle chaincode install asset-transfer.tar.gz

# Install the chaincode on peer1.org1
docker exec -e CORE_PEER_ADDRESS=peer1.org1.example.com:7051 -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt cli peer lifecycle chaincode install asset-transfer.tar.gz

# Install the chaincode on peer0.org2
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt cli peer lifecycle chaincode install asset-transfer.tar.gz

# Install the chaincode on peer1.org2
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer1.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer1.org2.example.com/tls/ca.crt cli peer lifecycle chaincode install asset-transfer.tar.gz

# Get the package ID
PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled | grep asset_transfer | awk '{print $3}' | sed 's/,//')

echo "Chaincode package ID: $PACKAGE_ID"

# Approve the chaincode for Org1
docker exec cli peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --package-id $PACKAGE_ID --sequence 1

# Approve the chaincode for Org2
docker exec -e CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp -e CORE_PEER_ADDRESS=peer0.org2.example.com:7051 -e CORE_PEER_LOCALMSPID=Org2MSP -e CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt cli peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --package-id $PACKAGE_ID --sequence 1

# Check commit readiness
docker exec cli peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --sequence 1 --output json

# Commit the chaincode
docker exec cli peer lifecycle chaincode commit -o orderer.example.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem --channelID $CHANNEL_NAME --name asset-transfer --version 1.0 --sequence 1 --peerAddresses peer0.org1.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0.org2.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

# Initialize the ledger
docker exec cli peer chaincode invoke -o orderer.example.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem -C $CHANNEL_NAME -n asset-transfer --peerAddresses peer0.org1.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0.org2.example.com:7051 --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt -c '{"function":"InitLedger","Args":[]}'

echo "Network setup completed successfully!"