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
