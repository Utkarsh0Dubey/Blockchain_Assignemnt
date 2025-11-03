#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
TN="$HOME/fabric-samples/test-network"
cd "$TN"

# Org1
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

echo "== CreateProduct on global-supply =="
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $ORDERER_CA \
  -C global-supply -n supplychain -c '{"Args":["CreateProduct","P100","SKU-ALPHA","Red widget"]}'

echo "== CreateShipment on mfg-dist =="
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $ORDERER_CA \
  -C mfg-dist -n supplychain -c '{"Args":["CreateShipment","S100","P100","Org2MSP"]}'

# Org2
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

echo "== ReceiveShipment on mfg-dist (Org2) =="
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $ORDERER_CA \
  -C mfg-dist -n supplychain -c '{"Args":["ReceiveShipment","S100"]}'

echo "== GetProduct on global-supply =="
peer chaincode query -C global-supply -n supplychain -c '{"Args":["GetProduct","P100"]}'

echo "== GetProductHistory on global-supply =="
peer chaincode query -C global-supply -n supplychain -c '{"Args":["GetProductHistory","P100"]}'

# Unauthorized: Org3 tries on mfg-dist
export CORE_PEER_LOCALMSPID=Org3MSP
export CORE_PEER_ADDRESS=localhost:11051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org3.example.com/users/Admin@org3.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt

echo "== Unauthorized ReceiveShipment as Org3 (should fail) =="
set +e
peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile $ORDERER_CA \
  -C mfg-dist -n supplychain -c '{"Args":["ReceiveShipment","S100"]}'
echo "EXPECTED FAILURE ABOVE (screenshot this error)"
set -e
