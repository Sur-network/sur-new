// Minimal Ethereum Merkle-Patricia state-root calculator for a genesis `alloc` (test tooling for A14).
// Used to compare Besu's block-0 stateRoot with an independently derived expected alloc. Self-validating: its output for a genesis.json must equal
// the stateRoot Besu reports for block 0 on a running node.
const { ethers } = require("ethers");

const hexToBytes = (h) => ethers.getBytes(h.startsWith("0x") ? h : "0x" + h);
const nibblesOf = (bytes) => { const n = []; for (const b of bytes) { n.push(b >> 4, b & 15); } return n; };
const keccak = (bytes) => ethers.keccak256(bytes);

function hexPrefix(nibbles, leaf) {
  const odd = nibbles.length % 2 === 1;
  const flag = (leaf ? 2 : 0) + (odd ? 1 : 0);
  const out = [];
  let i = 0;
  if (odd) { out.push((flag << 4) | nibbles[0]); i = 1; } else out.push(flag << 4);
  for (; i < nibbles.length; i += 2) out.push((nibbles[i] << 4) | nibbles[i + 1]);
  return ethers.hexlify(Uint8Array.from(out));
}

// returns a node reference: either the node structure itself (embedded, when its RLP is < 32 bytes) or the 32-byte hash
function ref(structure) {
  const enc = ethers.encodeRlp(structure);
  if ((enc.length - 2) / 2 < 32) return structure;
  return keccak(enc);
}

function buildNode(pairs, depth) {
  if (pairs.length === 1) return [hexPrefix(pairs[0].nibbles.slice(depth), true), pairs[0].value];
  // common prefix
  let cp = 0;
  outer: for (;; cp++) {
    const d = depth + cp;
    const first = pairs[0].nibbles[d];
    for (const p of pairs) if (p.nibbles[d] !== first || d >= p.nibbles.length) break outer;
  }
  if (cp > 0) return [hexPrefix(pairs[0].nibbles.slice(depth, depth + cp), false), ref(buildNode(pairs, depth + cp))];
  const children = [];
  for (let nib = 0; nib < 16; nib++) {
    const sub = pairs.filter((p) => p.nibbles[depth] === nib);
    children.push(sub.length ? ref(buildNode(sub, depth + 1)) : "0x");
  }
  children.push("0x");
  return children;
}

const EMPTY_ROOT = "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421";
function trieRoot(entries) { // entries: [{key: hex32 (already hashed), value: hex bytes}]
  if (!entries.length) return EMPTY_ROOT;
  const pairs = entries.map((e) => ({ nibbles: nibblesOf(hexToBytes(e.key)), value: e.value })).sort((a, b) => (a.nibbles.join(",") < b.nibbles.join(",") ? -1 : 1));
  return keccak(ethers.encodeRlp(buildNode(pairs, 0)));
}

const trimBytes = (bn) => (bn === 0n ? "0x" : ethers.toBeHex(bn));
function storageRoot(storage) {
  const entries = [];
  for (const [k, v] of Object.entries(storage || {})) {
    const val = BigInt(v);
    if (val === 0n) continue;
    const key = ethers.zeroPadValue(k.startsWith("0x") ? k : "0x" + k, 32);
    entries.push({ key: keccak(key), value: ethers.encodeRlp(trimBytes(val)) });
  }
  return trieRoot(entries);
}

// alloc: { addressNoPrefixOrWithPrefix: { balance?, nonce?, code?, storage? } }
function allocStateRoot(alloc) {
  const entries = [];
  for (const [addr, a] of Object.entries(alloc)) {
    const address = ethers.getAddress(addr.startsWith("0x") ? addr : "0x" + addr);
    const code = a.code && a.code !== "0x" ? a.code : "0x";
    const codeHash = code === "0x" ? "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470" : keccak(code);
    const acct = ethers.encodeRlp([trimBytes(BigInt(a.nonce || 0)), trimBytes(BigInt(a.balance || 0)), storageRoot(a.storage), codeHash]);
    entries.push({ key: keccak(address), value: acct });
  }
  return trieRoot(entries);
}

module.exports = { allocStateRoot, storageRoot, EMPTY_ROOT };
