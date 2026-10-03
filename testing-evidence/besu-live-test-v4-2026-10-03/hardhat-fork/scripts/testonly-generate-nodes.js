// TESTONLY TOOL — generates Besu node dirs (key, config.toml, static-nodes.json) for one network.
// env: BUILDER_NET, BUILDER_FOUNDERS (G5|G6), BUILDER_CANDIDATE (1/0), BUILDER_P2P_BASE, BUILDER_RPC_BASE, BUILDER_PROJECT_ROOT
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = process.env.BUILDER_PROJECT_ROOT;
const NET = process.env.BUILDER_NET;
const FOUNDERS = process.env.BUILDER_FOUNDERS;
const INCLUDE_C6 = process.env.BUILDER_CANDIDATE === "1";
const P2P_BASE = Number(process.env.BUILDER_P2P_BASE);
const RPC_BASE = Number(process.env.BUILDER_RPC_BASE);

const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const founderRoleList = FOUNDERS === "G5" ? ["g5_v1", "g5_v2", "g5_v3", "g5_v4", "g5_v5"] : ["g6_v1", "g6_v2", "g6_v3", "g6_v4", "g6_v5", "g6_v6"];
const roles = INCLUDE_C6 ? [...founderRoleList, "g5_c6"] : founderRoleList;

function pubkeyFromPriv(privHex) {
  const sk = new ethers.SigningKey(privHex);
  return sk.publicKey.slice(4);
}

const nodes = roles.map((role, i) => ({
  dir: `node${i + 1}`,
  role,
  p2p: P2P_BASE + i,
  rpc: RPC_BASE + i,
}));

const enodes = [];
for (const n of nodes) {
  const acct = accounts[n.role];
  const pub = pubkeyFromPriv(acct.privateKey);
  n.address = acct.address;
  n.enode = `enode://${pub}@127.0.0.1:${n.p2p}`;
  enodes.push(n.enode);
}

const netDir = path.join(ROOT, "nets", NET);
for (const n of nodes) {
  const base = path.join(netDir, n.dir);
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
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","DEBUG","TRACE","TXPOOL"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
`;
  fs.writeFileSync(path.join(base, "config.toml"), config);
  const others = enodes.filter((e) => e !== n.enode);
  fs.writeFileSync(path.join(base, "data", "static-nodes.json"), JSON.stringify(others, null, 2));
}

fs.writeFileSync(path.join(netDir, "nodes-info.json"), JSON.stringify(nodes, null, 2));
console.log(`[${NET}] generated ${nodes.length} nodes: ${nodes.map((n) => `${n.dir}=${n.role}(rpc:${n.rpc})`).join(", ")}`);
