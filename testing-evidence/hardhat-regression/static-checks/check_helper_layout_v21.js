// Compares the storage layout of each genesis seed helper with the real contract for every shared label (slot and offset).
// Run from testing-evidence/hardhat-regression/ (needs the solc package from this folder's node_modules).
const solc = require("solc"), fs = require("fs");
const imp = (p) => { for (const d of ["../../contracts/"]) { const f = d + p.replace("./", ""); if (fs.existsSync(f)) return { contents: fs.readFileSync(f, "utf8") }; } return { error: "nf " + p }; };
function layout(file, name) { const o = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { [name + ".sol"]: { content: fs.readFileSync(file, "utf8") } }, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["storageLayout"] } } } }), { import: imp })); const e = (o.errors || []).filter(x => x.severity === "error"); if (e.length) throw new Error(e[0].formattedMessage); return o.contracts[name + ".sol"][name].storageLayout.storage; }
let bad = 0;
for (const [real, helper, name] of [["../../contracts/ValidatorsRegistry.sol", "../../contracts/genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol", "ValidatorsRegistry"], ["../../contracts/ValidatorsBoard.sol", "../../contracts/genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol", "ValidatorsBoard"]]) {
  const R = layout(real, name), H = layout(helper, name + "_GenesisSeed"); let shared = 0;
  for (const h of H) { if (/^__gap\d*$/.test(h.label)) continue; const r = R.find(x => x.label === h.label); if (!r) { console.log("❌", name, "helper-only variable:", h.label); bad++; continue; } shared++; if (r.slot !== h.slot || r.offset !== h.offset) { console.log("❌", name, "SLOT MISMATCH", h.label, "real", r.slot + "/" + r.offset, "helper", h.slot + "/" + h.offset); bad++; } }
  console.log((bad ? "❌" : "✅") + " " + name + ": " + shared + " shared variables checked against the helper");
}
process.exit(bad ? 1 : 0);
