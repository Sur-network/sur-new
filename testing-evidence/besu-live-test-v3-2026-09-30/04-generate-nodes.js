// v3: generate 4 Besu node directories (founder1, founder2, founder3, newValidator1) — key,
// config.toml, static-nodes.json. Each node's key file IS the validator account's private key, so
// the node's coinbase/address matches exactly what ValidatorsRegistry.getValidators() returns.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));

const NODES = [
  { dir: "node1", role: "founder1", p2p: 32401, rpc: 8651 },
  { dir: "node2", role: "founder2", p2p: 32402, rpc: 8652 },
  { dir: "node3", role: "founder3", p2p: 32403, rpc: 8653 },
  { dir: "node4", role: "newValidator1", p2p: 32404, rpc: 8654 },
];

function pubkeyFromPriv(privHex) {
  const sk = new ethers.SigningKey(privHex);
  return sk.publicKey.slice(4); // drop "0x04" prefix
}

const enodes = [];
for (const n of NODES) {
  const acct = accounts[n.role];
  const pub = pubkeyFromPriv(acct.privateKey);
  n.address = acct.address;
  n.pubkey = pub;
  n.enode = `enode://${pub}@127.0.0.1:${n.p2p}`;
  enodes.push(n.enode);
  console.log(n.dir, n.role, n.address, n.enode);
}

for (const n of NODES) {
  const base = path.join(ROOT, "besu", n.dir);
  fs.mkdirSync(path.join(base, "data"), { recursive: true });
  fs.writeFileSync(path.join(base, "key"), accounts[n.role].privateKey.replace(/^0x/, ""));
  const config = `data-path="${n.dir}/data"
genesis-file="genesis.json"
node-private-key-file="${n.dir}/key"
p2p-host="127.0.0.1"
p2p-port=${n.p2p}
rpc-http-enabled=true
rpc-http-host="127.0.0.1"
rpc-http-port=${n.rpc}
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","DEBUG"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
`;
  fs.writeFileSync(path.join(base, "config.toml"), config);
  const others = enodes.filter((e) => e !== n.enode);
  fs.writeFileSync(path.join(base, "data", "static-nodes.json"), JSON.stringify(others, null, 2));
}

fs.writeFileSync(path.join(ROOT, "nodes-info.json"), JSON.stringify(NODES, null, 2));
console.log("Node setup complete.");
