#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "Project root: $ROOT"

mkdir -p chaincode/supplychain-js
mkdir -p scripts

# ---- chaincode ----
cat > chaincode/supplychain-js/package.json <<'PKG'
{
  "name": "supplychain-js",
  "version": "1.0.0",
  "main": "index.js",
  "license": "Apache-2.0",
  "dependencies": {
    "fabric-contract-api": "^2.5.0",
    "fabric-shim": "^2.5.0"
  }
}
PKG

cat > chaincode/supplychain-js/index.js <<'CC'
'use strict';

const { Contract } = require('fabric-contract-api');

class SupplyChainContract extends Contract {
  async _put(ctx, key, obj) {
    await ctx.stub.putState(key, Buffer.from(JSON.stringify(obj)));
  }
  async _get(ctx, key) {
    const b = await ctx.stub.getState(key);
    if (!b || b.length === 0) return null;
    return JSON.parse(b.toString());
  }
  _msp(ctx) {
    return ctx.clientIdentity.getMSPID(); // Org1MSP, Org2MSP, Org3MSP
  }

  // Product { productId, sku, desc, ownerMSP, status: 'CREATED'|'IN_TRANSIT'|'DELIVERED' }
  // Shipment { shipmentId, productId, fromMSP, toMSP, status: 'CREATED'|'RECEIVED', ts }

  async CreateProduct(ctx, productId, sku, description) {
    if (!productId) throw new Error('productId required');
    const key = ctx.stub.createCompositeKey('product', [productId]);
    const existing = await this._get(ctx, key);
    if (existing) throw new Error('Product already exists');

    const ownerMSP = this._msp(ctx);
    const prod = { productId, sku, desc: description, ownerMSP, status: 'CREATED' };
    await this._put(ctx, key, prod);
  }

  async CreateShipment(ctx, shipmentId, productId, toMSP) {
    if (!shipmentId || !productId || !toMSP) throw new Error('shipmentId, productId, toMSP required');
    const pKey = ctx.stub.createCompositeKey('product', [productId]);
    const prod = await this._get(ctx, pKey);
    if (!prod) throw new Error('Product not found');

    const caller = this._msp(ctx);
    if (prod.ownerMSP !== caller) throw new Error('Only current owner can create a shipment');

    const sKey = ctx.stub.createCompositeKey('shipment', [shipmentId]);
    const existing = await this._get(ctx, sKey);
    if (existing) throw new Error('Shipment already exists');

    const ship = { shipmentId, productId, fromMSP: caller, toMSP, status: 'CREATED', ts: Date.now() };
    prod.status = 'IN_TRANSIT';
    await this._put(ctx, sKey, ship);
    await this._put(ctx, pKey, prod);
  }

  async ReceiveShipment(ctx, shipmentId) {
    if (!shipmentId) throw new Error('shipmentId required');

    const sKey = ctx.stub.createCompositeKey('shipment', [shipmentId]);
    const ship = await this._get(ctx, sKey);
    if (!ship) throw new Error('Shipment not found');

    const caller = this._msp(ctx);
    if (ship.toMSP !== caller) throw new Error('Only intended receiver can accept');

    ship.status = 'RECEIVED';
    ship.ts = Date.now();
    await this._put(ctx, sKey, ship);

    const pKey = ctx.stub.createCompositeKey('product', [ship.productId]);
    const prod = await this._get(ctx, pKey);
    if (!prod) throw new Error('Linked product not found');

    prod.ownerMSP = caller;
    prod.status = (caller === 'Org3MSP') ? 'DELIVERED' : 'IN_TRANSIT';
    await this._put(ctx, pKey, prod);
  }

  async GetProduct(ctx, productId) {
    const key = ctx.stub.createCompositeKey('product', [productId]);
    const prod = await this._get(ctx, key);
    if (!prod) throw new Error('Product not found');
    return JSON.stringify(prod);
  }

  async GetProductHistory(ctx, productId) {
    const key = ctx.stub.createCompositeKey('product', [productId]);
    const iter = await ctx.stub.getHistoryForKey(key);
    const out = [];
    for await (const r of iter) {
      out.push({
        txId: r.txId,
        isDelete: r.isDelete,
        value: r.value && r.value.toString(),
        timestamp: r.timestamp && (r.timestamp.seconds && r.timestamp.seconds.low)
      });
    }
    return JSON.stringify(out);
  }
}

module.exports.contracts = [SupplyChainContract];
CC

# ---- helper scripts ----
cat > scripts/env_exports.sh <<'ENV'
export PATH=$PATH:$HOME/fabric-samples/bin
export ORDERER_CA=$HOME/fabric-samples/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
ENV

cat > scripts/start_testnet.sh <<'STN'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
cd "$HOME/fabric-samples/test-network"
./network.sh down
./network.sh up createChannel -c global-supply
STN
chmod +x scripts/start_testnet.sh

cat > scripts/add_org3.sh <<'A3'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
cd "$HOME/fabric-samples/test-network/addOrg3"
./addOrg3.sh up -c global-supply -s couchdb
A3
chmod +x scripts/add_org3.sh

cat > scripts/create_mfg_dist.sh <<'CMD'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
TN="$HOME/fabric-samples/test-network"
cd "$TN"

mkdir -p channel-artifacts
configtxgen -profile TwoOrgsApplicationGenesis \
  -outputCreateChannelTx ./channel-artifacts/mfg-dist.tx \
  -channelID mfg-dist

# Org1 env
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

peer channel create -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  -c mfg-dist -f ./channel-artifacts/mfg-dist.tx \
  --tls --cafile $ORDERER_CA \
  --outputBlock ./mfg-dist.block

peer channel join -b ./mfg-dist.block

# Org2 env
export CORE_PEER_LOCALMSPID=Org2MSP
export CORE_PEER_ADDRESS=localhost:9051
export CORE_PEER_MSPCONFIGPATH=$TN/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=$TN/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

peer channel join -b ./mfg-dist.block
CMD
chmod +x scripts/create_mfg_dist.sh

cat > scripts/deploy_cc_global.sh <<'DCG'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
TN="$HOME/fabric-samples/test-network"
cd "$TN"
# try absolute project path under Desktop, fallback to another common path
./network.sh deployCC -c global-supply -ccn supplychain -ccp "$HOME/Desktop/BC Project/chaincode/supplychain-js" -ccl javascript
DCG
chmod +x scripts/deploy_cc_global.sh

cat > scripts/deploy_cc_mfgdist.sh <<'DMD'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/env_exports.sh"
TN="$HOME/fabric-samples/test-network"
cd "$TN"

peer lifecycle chaincode package supplychain.tgz \
  --path "$HOME/Desktop/BC Project/chaincode/supplychain-js" \
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
DMD
chmod +x scripts/deploy_cc_mfgdist.sh

cat > scripts/demo_flow.sh <<'DEM'
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
DEM
chmod +x scripts/demo_flow.sh

cat > README.txt <<'R'
RUN ORDER (Kali):
1) bash setup_kali_fabric.sh
   (then open a new terminal or: source ~/.bashrc ; newgrp docker)

2) bash scripts/start_testnet.sh
3) bash scripts/add_org3.sh
4) bash scripts/create_mfg_dist.sh
5) bash scripts/deploy_cc_global.sh
6) bash scripts/deploy_cc_mfgdist.sh
7) bash scripts/demo_flow.sh
R

echo "✅ Project files created."
