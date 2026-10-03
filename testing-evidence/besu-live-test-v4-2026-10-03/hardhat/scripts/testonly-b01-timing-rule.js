// B01: discover which height's Registry.getValidators() exactly matches QBFT's effective set at
// block N, by comparing qbft_getValidatorsByBlockNumber(N) against Registry@(N-2),(N-1),(N) for
// blocks around the B02 validator-set change (block 107) on Net-B.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const RPC = "http://127.0.0.1:8701";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const ABI = ["function getValidators() view returns (address[])"];

async function rpcCall(method, params) {
  const res = await fetch(RPC, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  const json = await res.json();
  if (json.error) throw new Error(JSON.stringify(json.error));
  return json.result;
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const registry = new ethers.Contract(REGISTRY, ABI, provider);
  const results = [];
  const changeBlock = 107; // B02's recordSuspension landed here
  for (let n = changeBlock - 3; n <= changeBlock + 8; n++) {
    const qbftSet = await rpcCall("qbft_getValidatorsByBlockNumber", ["0x" + n.toString(16)]);
    let regAtN2 = null, regAtN1 = null, regAtN = null;
    try { regAtN2 = n - 2 >= 0 ? await registry.getValidators({ blockTag: n - 2 }) : null; } catch (e) { regAtN2 = "ERR:" + e.message; }
    try { regAtN1 = n - 1 >= 0 ? await registry.getValidators({ blockTag: n - 1 }) : null; } catch (e) { regAtN1 = "ERR:" + e.message; }
    try { regAtN = await registry.getValidators({ blockTag: n }); } catch (e) { regAtN = "ERR:" + e.message; }
    const sortLower = (arr) => arr.map((a) => a.toLowerCase()).sort();
    const qbftSorted = sortLower(qbftSet);
    const matchesN2 = Array.isArray(regAtN2) && JSON.stringify(qbftSorted) === JSON.stringify(sortLower(regAtN2));
    const matchesN1 = Array.isArray(regAtN1) && JSON.stringify(qbftSorted) === JSON.stringify(sortLower(regAtN1));
    const matchesN = Array.isArray(regAtN) && JSON.stringify(qbftSorted) === JSON.stringify(sortLower(regAtN));
    results.push({ n, qbftCount: qbftSet.length, matchesN2, matchesN1, matchesN });
  }
  console.log(JSON.stringify(results, null, 2));
  const allN1 = results.every((r) => r.matchesN1);
  const allN2 = results.every((r) => r.matchesN2);
  const allN = results.every((r) => r.matchesN);
  console.log("\nConclusion: matchesN-1 always?", allN1, "| matchesN-2 always?", allN2, "| matchesN always?", allN);
  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-B-B01.json"), JSON.stringify({ results, allN1, allN2, allN }, null, 2));
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
