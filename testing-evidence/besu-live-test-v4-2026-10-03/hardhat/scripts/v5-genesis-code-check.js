// Static (node-free) analogue of A04 for the follow-up networks: keccak256 of each genesis alloc code vs the compiled runtime hash.
const { ethers, ROOT, fs, saveEvidence } = require("./v5-lib");
const fp = JSON.parse(fs.readFileSync(`${ROOT}/evidence/00-baseline/fixed-contracts-fingerprint.json`, "utf8"));
const nets = ["Net-F1", "Net-F2", "Net-F3", "Net-F4", "Net-F5", "Net-L05a", "Net-L05b", "Net-D3", "Net-E15", "Net-E30", "Net-E60"];
const out = { note: "Static check of the genesis.json files (the nodes are stopped); this is NOT a live eth_getCode check, which was not repeated on the follow-up networks", results: {} };
let allOk = true;
for (const n of nets) {
  const g = JSON.parse(fs.readFileSync(`${ROOT}/nets/${n}/genesis.json`, "utf8"));
  const r = {};
  for (const [name, v] of Object.entries(fp)) {
    const code = g.alloc[v.address.toLowerCase().replace("0x", "")] || g.alloc[v.address] || g.alloc[v.address.toLowerCase()];
    const h = code ? ethers.keccak256(code.code) : null;
    r[name] = { address: v.address, genesisCodeHash: h, compiledRuntimeHash: v.runtimeHash, match: h === v.runtimeHash };
    if (h !== v.runtimeHash) allOk = false;
  }
  out.results[n] = r;
}
out.allMatch = allOk;
console.log("all 6 contracts x", nets.length, "networks match compiled runtime hashes:", allOk);
saveEvidence("followup-genesis-code-check.json", out);
