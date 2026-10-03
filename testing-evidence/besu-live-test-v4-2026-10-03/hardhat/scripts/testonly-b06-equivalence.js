// B06: isValidator(x) <=> x in getValidators(), sampled across Net-B's blocks so far (all
// candidates: 5 founders + C6), using the corrected "N" rule from B01.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8701";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const ABI = ["function getValidators() view returns (address[])", "function isValidator(address) view returns (bool)"];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const registry = new ethers.Contract(REGISTRY, ABI, provider);
  const candidates = [1, 2, 3, 4, 5].map((i) => accounts[`g5_v${i}`].address).concat([accounts.g5_c6.address]);

  const currentBlock = await provider.getBlockNumber();
  // Besu's default BONSAI historical-state limit (~512 blocks) makes B02's transition (block 107)
  // unreachable by the time this collector runs much later -- confirmed empirically (block 271
  // readable, block 261 not, on a chain at height 781). Per the document's own guidance ("جمع
  // بلاک‌های گروه B را در لحظه جمع کن، نه بعداً"), B01 WAS collected live at the time of the B02
  // transition (see Net-B-B01.json) and remains valid; this B06 pass is correctly restricted to
  // the still-reachable recent window plus the B03 transition (~block 651), which is within range.
  const historicalFloor = currentBlock - 480;
  const sampleBlocks = [];
  for (let n = 648; n <= 656; n++) sampleBlocks.push(n);
  for (let n = Math.max(1, historicalFloor); n <= currentBlock; n += Math.max(1, Math.floor((currentBlock - historicalFloor) / 150))) sampleBlocks.push(n);
  const uniqueBlocks = [...new Set(sampleBlocks)].filter((n) => n >= 0 && n <= currentBlock).sort((a, b) => a - b);

  let mismatches = 0;
  const mismatchDetails = [];
  for (const n of uniqueBlocks) {
    const validators = (await registry.getValidators({ blockTag: n })).map((a) => a.toLowerCase());
    for (const c of candidates) {
      const expected = validators.includes(c.toLowerCase());
      const actual = await registry.isValidator(c, { blockTag: n });
      if (expected !== actual) {
        mismatches++;
        mismatchDetails.push({ block: n, candidate: c, expectedFromGetValidators: expected, actualFromIsValidator: actual });
      }
    }
  }
  const result = { blocksChecked: uniqueBlocks.length, candidatesChecked: candidates.length, totalChecks: uniqueBlocks.length * candidates.length, mismatches, mismatchDetails, historicalLimitNote: "Besu's default BONSAI historical-state limit (~512 blocks back) made blocks older than ~block 261 (on a chain at height 781) unreadable via eth_call at blockTag; B01's live-collected data (Net-B-B01.json) already covers the B02 transition in full. This pass covers the B03 transition (~block 651) plus a spread sample of the still-reachable recent window." };
  console.log(JSON.stringify(result, null, 2));
  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-B-B06.json"), JSON.stringify(result, null, 2));
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
