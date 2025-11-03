#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
TN="$HOME/fabric-samples/test-network"
export FABRIC_CFG_PATH="$TN"
cd "$TN"

peer lifecycle chaincode package supplychain.tgz \
  --path "$HOME/Desktop/bc_project/chaincode/supplychain-js" \
  --lang node --label supplychain_1

# Org1 install
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
peer lifecycle chaincode install supplychain.tgz
PKG_ID=$(peer lifecycle chaincode queryinstalled | sed -n 's/Package ID: \(supplychain_1:[^,]*\),.*/\1/p')

# Org2 install
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
peer lifecycle chaincode install supplychain.tgz

# Approvals
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
peer lifecycle chaincode approveformyorg -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID mfg-dist --name supplychain --version 1.0 \
  --package-id $PKG_ID --sequence 1 --tls --cafile $ORDERER_CA

export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
peer lifecycle chaincode approveformyorg -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID mfg-dist --name supplychain --version 1.0 \
  --package-id $PKG_ID --sequence 1 --tls --cafile $ORDERER_CA

peer lifecycle chaincode commit -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID mfg-dist --name supplychain --version 1.0 --sequence 1 \
  --tls --cafile $ORDERER_CA \
  --peerAddresses localhost:7051 --tlsRootCertFiles $TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses localhost:9051 --tlsRootCertFiles $TN/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

peer lifecycle chaincode querycommitted -C mfg-dist -n supplychain
