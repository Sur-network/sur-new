// Chain helpers for bootstrap.js and loadgen.js: signing with the throw-away test keys, sending, waiting for receipts, view calls.
"use strict";
const { ethers } = require("ethers");
const { rpc, keys, abis, sleep, KIT, readJson } = require("./common");
const path = require("path");

const GAS_PRICE = 100000000000000n; // 1e14 wei = min-gas-price of the nodes
const ADDR = { REG: "0x3333333333333333333333333333333333333333", IDENTITY: "0x6666666666666666666666666666666666666666" };
const IFACE = { REG: new ethers.Interface(abis.ValidatorsRegistry), IDENTITY: new ethers.Interface(abis.IdentityRegistry) };

const wallets = {};
function wallet(role) {
  if (!keys[role]) throw new Error("no test key for role " + role);
  return (wallets[role] = wallets[role] || new ethers.Wallet(keys[role].privateKey));
}
const addrOf = (role) => keys[role].address;

async function view(url, which, fn, args = []) {
  const data = IFACE[which].encodeFunctionData(fn, args);
  const out = await rpc(url, "eth_call", [{ to: ADDR[which], data }, "latest"]);
  return IFACE[which].decodeFunctionResult(fn, out);
}

// Signs and sends (legacy type 0). Returns the tx hash. `nonce` optional (else the pending count is fetched).
async function sendRaw(url, chainId, role, to, data, { value = 0n, gasLimit = 600000n, nonce } = {}) {
  const w = wallet(role);
  if (nonce === undefined) nonce = Number(BigInt(await rpc(url, "eth_getTransactionCount", [w.address, "pending"])));
  const raw = await w.signTransaction({ type: 0, chainId, to, data: data || "0x", value, gasLimit, gasPrice: GAS_PRICE, nonce });
  return rpc(url, "eth_sendRawTransaction", [raw]);
}
async function waitReceipt(url, hash, timeoutMs = 120000) {
  const t0 = Date.now();
  for (;;) {
    const r = await rpc(url, "eth_getTransactionReceipt", [hash]);
    if (r) return { block: Number(BigInt(r.blockNumber)), status: Number(BigInt(r.status)), gasUsed: Number(BigInt(r.gasUsed)), hash, logs: r.logs };
    if (Date.now() - t0 > timeoutMs) throw new Error("receipt timeout " + hash);
    await sleep(500);
  }
}
// Contract transaction: encodes `fn(args)` of `which` (REG / IDENTITY), sends from `role`, waits for the receipt.
async function txCall(url, chainId, role, which, fn, args = [], opts = {}) {
  const data = IFACE[which].encodeFunctionData(fn, args);
  const hash = await sendRaw(url, chainId, role, ADDR[which], data, opts);
  const rc = await waitReceipt(url, hash);
  if (rc.status !== 1) { const e = new Error(`${which}.${fn} mined with status 0 (${hash})`); e.receipt = rc; throw e; }
  return rc;
}
const loadNet = (name) => readJson(path.join(KIT, "nets", name, "soak-net.json"));

module.exports = { ethers, GAS_PRICE, ADDR, IFACE, wallet, addrOf, view, sendRaw, waitReceipt, txCall, loadNet };
