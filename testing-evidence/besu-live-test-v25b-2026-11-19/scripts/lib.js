// Shared helpers for the v2.5 live Besu test scripts (ethers 6.17 via NODE_PATH, ABIs from the compiled build dir).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const E = path.resolve(__dirname, "..");
const keys = JSON.parse(fs.readFileSync(path.join(E, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const BUILD = process.env.SUR25_BUILD;
const GAS_PRICE = 100000000000000n; // 1e14 wei = min-gas-price of the nodes
const ZERO = ethers.ZeroAddress;

const ADDR = {
  DAO: "0x1111111111111111111111111111111111111111",
  DIST: "0x2222222222222222222222222222222222222222",
  REG: "0x3333333333333333333333333333333333333333",
  BOARD: "0x4444444444444444444444444444444444444444",
  TREASURY: "0x5555555555555555555555555555555555555555",
  IDENTITY: "0x6666666666666666666666666666666666666666",
  MEMBERS: "0x7777777777777777777777777777777777777777",
  NFT: "0x8888888888888888888888888888888888888888",
  VAULT: "0x9999999999999999999999999999999999999999",
  LOTTERY: "0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa",
};
const FILES = { DAO: "FoundationDAO", DIST: "BlockRewardDistributor", REG: "ValidatorsRegistry", BOARD: "ValidatorsBoard", TREASURY: "ValidatorsTreasury",
  IDENTITY: "IdentityRegistry", MEMBERS: "FoundationMembers", NFT: "ValidatorSeatNFT", VAULT: "GenesisClaimsVault", LOTTERY: "ValidatorLottery" };

function abiOf(name) {
  return JSON.parse(fs.readFileSync(path.join(BUILD, "artifacts", "contracts", name + ".sol", name + ".json"), "utf8")).abi;
}
const NETS = {
  A: { name: "Net-A", chainId: 425035, rpcBase: 19500 },
  T: { name: "Net-T", chainId: 425038, rpcBase: 19600 },
};
const NODE_SUFFIX = { n1: 11, n2: 12, n3: 13, n4: 14, n5: 15, n6: 16, n7: 17, n2b: 22, n3b: 23, nC: 31 };

class Net {
  constructor(key, node = "n1") {
    this.key = key; this.def = NETS[key]; this.node = node;
    this.url = `http://127.0.0.1:${this.def.rpcBase + NODE_SUFFIX[node]}`;
    this.provider = new ethers.JsonRpcProvider(this.url, this.def.chainId, { staticNetwork: ethers.Network.from(this.def.chainId), polling: true, pollingInterval: 400, batchMaxCount: 1 });
    this.contracts = {};
    this.nonces = {};
  }
  at(node) { return new Net(this.key, node); }
  w(role) { return new ethers.Wallet(keys[role].privateKey, this.provider); }
  addr(role) { return keys[role].address; }
  c(which, role) { // contract instance, optionally connected to a role's wallet
    return new ethers.Contract(ADDR[which], abiOf(FILES[which]), role ? this.w(role) : this.provider);
  }
  async head() { return this.provider.getBlockNumber(); }
  async block(n) { return this.provider.send("eth_getBlockByNumber", [typeof n === "string" ? n : ethers.toQuantity(n), false]); }
  async qbftValidators(n = "latest") { return this.provider.send("qbft_getValidatorsByBlockNumber", [typeof n === "string" ? n : ethers.toQuantity(n)]); }
  async waitBlocks(k) { const h0 = await this.head(); return this.waitForBlock(h0 + k); }
  async waitForBlock(target, timeoutMs = 1500000) {
    const t0 = Date.now();
    for (;;) { const h = await this.head(); if (h >= target) return h; if (Date.now() - t0 > timeoutMs) throw new Error("timeout waiting for block " + target + " (head " + h + ")"); await sleep(400); }
  }
  async balance(a, tag = "latest") { return this.provider.getBalance(a, tag); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fmt = (wei) => ethers.formatEther(wei);
const S = (n) => ethers.parseEther(String(n));

// Sends a transaction (legacy type 0, gasPrice = min-gas-price). Returns {receipt, tx}. Throws with the decoded reason when it reverts (status 0 or estimate failure).
async function send(net, role, contractWhich, fn, args = [], opts = {}) {
  const c = net.c(contractWhich, role);
  const overrides = { gasPrice: GAS_PRICE, type: 0 };
  if (opts.value !== undefined) overrides.value = opts.value;
  if (opts.gasLimit) overrides.gasLimit = opts.gasLimit;
  const tx = await c[fn](...args, overrides);
  const receipt = await tx.wait();
  if (receipt.status !== 1) throw new Error(`tx ${fn} mined with status 0 (${tx.hash})`);
  return { tx, receipt, hash: tx.hash, block: receipt.blockNumber, gasUsed: receipt.gasUsed.toString() };
}
// Expects a revert. Returns {reverted:true, reason, stage}. Stage "estimate" = rejected before sending; stage "mined" = mined with status 0 (explicit gasLimit).
async function expectRevert(net, role, contractWhich, fn, args = [], opts = {}) {
  const c = net.c(contractWhich, role);
  let reason = null, stage = null;
  try { await c[fn].staticCall(...args, opts.value !== undefined ? { value: opts.value } : {}); }
  catch (e) { reason = e.reason || e.shortMessage || String(e.message).slice(0, 200); stage = "eth_call"; }
  if (!stage) return { reverted: false, note: "eth_call did not revert" };
  // also try a mined failure with explicit gas limit to confirm the on-chain status 0
  let minedHash = null, minedStatus = null;
  try {
    const tx = await c[fn](...args, { gasPrice: GAS_PRICE, type: 0, gasLimit: opts.gasLimit || 600000n, ...(opts.value !== undefined ? { value: opts.value } : {}) });
    const rc = await tx.wait().catch((e) => e.receipt);
    minedHash = tx.hash; minedStatus = rc ? rc.status : null;
  } catch (e) { minedStatus = "rejected: " + (e.shortMessage || e.message).slice(0, 120); }
  return { reverted: true, reason, stage, minedHash, minedStatus };
}

// Raw sender that does not wait: used to put several txs in one block.
async function sendNoWait(net, role, contractWhich, fn, args = [], opts = {}) {
  const wallet = net.w(role);
  const c = new ethers.Contract(ADDR[contractWhich], abiOf(FILES[contractWhich]), wallet);
  const key = keys[role].address;
  if (net.nonces[key] === undefined) net.nonces[key] = await net.provider.getTransactionCount(key, "pending");
  const nonce = net.nonces[key]++;
  const tx = await c[fn](...args, { gasPrice: GAS_PRICE, type: 0, nonce, gasLimit: opts.gasLimit || 800000n, ...(opts.value !== undefined ? { value: opts.value } : {}) });
  return tx;
}

function findEvent(receipt, iface, name) {
  const out = [];
  for (const l of receipt.logs) { try { const p = iface.parseLog(l); if (p && p.name === name) out.push(p); } catch (e) {} }
  return out;
}
const ifaceOf = (which) => new ethers.Interface(abiOf(FILES[which]));

// Result files
function writeResult(id, obj) {
  const dir = path.join(E, "evidence", "04-results");
  fs.mkdirSync(dir, { recursive: true });
  const o = { id, writtenAtUTC: new Date().toISOString(), ...obj };
  fs.writeFileSync(path.join(dir, id + ".json"), JSON.stringify(o, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2));
  console.log(`[${id}] ${o.verdict || ""} ${o.summary || ""}`);
}
// checks collector
class Checks {
  constructor() { this.items = []; }
  ok(name, cond, detail) { this.items.push({ name, pass: !!cond, detail: detail === undefined ? undefined : (typeof detail === "bigint" ? detail.toString() : detail) }); console.log(`  ${cond ? "PASS" : "FAIL"}  ${name}${detail !== undefined ? "  :: " + (typeof detail === "object" ? JSON.stringify(detail, (k, v) => typeof v === "bigint" ? v.toString() : v) : detail) : ""}`); return !!cond; }
  get allPass() { return this.items.every((i) => i.pass); }
  get verdict() { return this.allPass ? "PASS" : "FAIL"; }
}

// Decode a QBFT block header extraData (vanity, validators[], vote, round, seals[]) and recover the committed-seal signers.
function decodeExtra(extraData) {
  const dec = ethers.decodeRlp(extraData);
  return { vanity: dec[0], validators: dec[1].map((a) => ethers.getAddress(a)), vote: dec[2], round: dec[3], seals: dec[4] };
}
async function sealSigners(net, n, expected) {
  const b = await net.provider.send("eth_getBlockByNumber", [ethers.toQuantity(n), false]);
  const ex = decodeExtra(b.extraData);
  // header without committed seals: extraData rlp = [validators, vote, round, []]
  const extraNoSeals = ethers.encodeRlp([ex.vanity, ex.validators, ex.vote, ex.round, []]);
  const hdr = [b.parentHash, b.sha3Uncles, b.miner, b.stateRoot, b.transactionsRoot, b.receiptsRoot, b.logsBloom,
    q(b.difficulty), q(b.number), q(b.gasLimit), q(b.gasUsed), q(b.timestamp), extraNoSeals, b.mixHash, b.nonce];
  if (b.baseFeePerGas !== undefined && b.baseFeePerGas !== null) hdr.push(q(b.baseFeePerGas));
  const hdrHash = ethers.keccak256(ethers.encodeRlp(hdr));
  const result = { block: n, miner: ethers.getAddress(b.miner), headerValidators: ex.validators, sealCount: ex.seals.length, round: ex.round };
  { // (Besu QBFT 26.9.0: the committed seals sign keccak256(rlp(header with extraData = [vanity, validators, vote, round, []])); verified empirically)
    const digest = hdrHash; const code = "0x";
    const signers = ex.seals.map((s) => { try { return ethers.recoverAddress(digest, ethers.Signature.from(s)); } catch (e) { return null; } });
    if (signers.every((s) => s && expected.map((x) => x.toLowerCase()).includes(s.toLowerCase()))) { result.digestSuffix = code === "0x" ? "(none)" : code; result.signers = signers.map(ethers.getAddress); return result; }
  }
  result.signers = null; return result;
  function q(x) { const v = BigInt(x); return v === 0n ? "0x" : ethers.toBeHex(v); }
}
// All the identity flags for one address (register + oracle flags). `role` registers itself; identityOracle sets flags.
async function makeFullyVerified(net, role, name) {
  const hs = [];
  const r = await send(net, role, "IDENTITY", "registerIdentity", [0, name]); hs.push(r.hash);
  for (const [fn, args] of [["setPhoneVerified", [net.addr(role), true]], ["setTelegramVerified", [net.addr(role), true]], ["setBaleVerified", [net.addr(role), true]], ["setEmailVerified", [net.addr(role), true]], ["setKycVerified", [net.addr(role), true, ethers.keccak256(ethers.toUtf8Bytes("kyc-" + role))]]]) {
    const x = await send(net, "identityOracle", "IDENTITY", fn, args); hs.push(x.hash);
  }
  return hs;
}
// parallel version: sends registerIdentity for many roles, then all oracle flag txs with consecutive nonces, then waits.
async function makeManyFullyVerified(net, roles) {
  const txs = [];
  for (const role of roles) txs.push(await sendNoWait(net, role, "IDENTITY", "registerIdentity", [0, "Test Person " + role], { gasLimit: 300000n }));
  const oracleTxs = [];
  for (const role of roles) for (const [fn, args] of [["setPhoneVerified", [net.addr(role), true]], ["setTelegramVerified", [net.addr(role), true]], ["setBaleVerified", [net.addr(role), true]], ["setEmailVerified", [net.addr(role), true]], ["setKycVerified", [net.addr(role), true, ethers.keccak256(ethers.toUtf8Bytes("kyc-" + role))]]]) oracleTxs.push(await sendNoWait(net, "identityOracle", "IDENTITY", fn, args, { gasLimit: 300000n }));
  const all = [...txs, ...oracleTxs];
  const rcs = [];
  for (const t of all) rcs.push(await t.wait());
  if (rcs.some((r) => r.status !== 1)) throw new Error("identity flag tx failed");
  return all.map((t) => t.hash);
}

module.exports = { ethers, keys, ADDR, Net, NETS, send, sendNoWait, expectRevert, findEvent, ifaceOf, abiOf, writeResult, Checks, sleep, fmt, S, GAS_PRICE, ZERO, E, decodeExtra, sealSigners, makeFullyVerified, makeManyFullyVerified };

// ---- extra helpers (appended) ----
const { execSync } = require("child_process");
function ctl(action, netKey, node) { return execSync(`bash ${__dirname}/netctl.sh ${action} ${netKey} ${node}`, { stdio: "pipe" }).toString(); }
const lowerSet = (a) => a.map((x) => x.toLowerCase()).sort();
const sameSet = (a, b) => JSON.stringify(lowerSet(a)) === JSON.stringify(lowerSet(b));
// miner + timestamp of blocks [from, to]
async function minerSeries(net, from, to) {
  const out = [];
  for (let n = from; n <= to; n++) { const b = await net.block(n); out.push({ block: n, miner: ethers.getAddress(b.miner), ts: Number(BigInt(b.timestamp)) }); }
  return out;
}
function gapsOf(series) { return series.slice(1).map((s, i) => s.ts - series[i].ts); }
async function waitSynced(net, node, tol = 2, timeoutMs = 180000) {
  const t0 = Date.now(); const other = net.at(node);
  for (;;) { try { const a = await net.head(), b = await other.head(); if (Math.abs(a - b) <= tol) return { head: a, node: b }; } catch (e) {} if (Date.now() - t0 > timeoutMs) throw new Error("node " + node + " did not sync"); await sleep(1000); }
}
Object.assign(module.exports, { ctl, lowerSet, sameSet, minerSeries, gapsOf, waitSynced });
