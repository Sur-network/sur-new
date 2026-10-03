// F06 setup — creates the X7 node: a NON-validator Besu node on Net-F4 started with the ORIGINAL genesis (no transition) AFTER the chain crossed X'.
// Writes nets/Net-F4/node7x/{key,config.toml,data/static-nodes.json}. (Launch is done by the shell afterwards.)
const { ethers, ROOT, fs } = require("./v5-lib");
const NETDIR = `${ROOT}/nets/Net-F4`;
const nodes = JSON.parse(fs.readFileSync(`${NETDIR}/nodes-info.json`, "utf8"));
const w = ethers.Wallet.createRandom(); // fresh key, not an account of this test suite, never a validator
const dir = `${NETDIR}/node7x`;
fs.mkdirSync(`${dir}/data`, { recursive: true });
fs.writeFileSync(`${dir}/key`, w.privateKey.replace(/^0x/, ""));
const cfg = `data-path="node7x/data"
genesis-file="genesis-original-no-transition.json"
node-private-key-file="node7x/key"
p2p-host="127.0.0.1"
p2p-port=33137
rpc-http-enabled=true
rpc-http-host="127.0.0.1"
rpc-http-port=8837
rpc-http-api=["ETH","NET","QBFT","ADMIN","WEB3","DEBUG","TRACE","TXPOOL"]
rpc-http-cors-origins=["*"]
host-allowlist=["*"]
min-gas-price=100000000000000
discovery-enabled=true
`;
fs.writeFileSync(`${dir}/config.toml`, cfg);
fs.writeFileSync(`${dir}/data/static-nodes.json`, JSON.stringify(nodes.map((n) => n.enode), null, 2));
// register in nodes-info so the node control script can find it
nodes.push({ dir: "node7x", role: "X7 (non-validator, no-transition genesis)", p2p: 33137, rpc: 8837, address: w.address });
fs.writeFileSync(`${NETDIR}/nodes-info.json`, JSON.stringify(nodes, null, 2));
console.log("X7 created:", w.address, "genesis-file = genesis-original-no-transition.json");
