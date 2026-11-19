// Generates THROW-AWAY local test keys -> ../TEST-KEYS-DO-NOT-REUSE.json (never overwrites an existing file).
// Run from the kit root with ethers on NODE_PATH:  node tools/gen-keys.js
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const out = path.resolve(__dirname, "../TEST-KEYS-DO-NOT-REUSE.json");
if (fs.existsSync(out)) { console.log("exists, not overwritten:", out); process.exit(0); }
const roles = [];
for (let i = 1; i <= 8; i++) roles.push("owner" + i);      // founder OWNER keys; owner8 is the "entrant" (Probation at genesis, activated mid-run)
for (let i = 9; i <= 11; i++) roles.push("owner" + i);     // padding for the validators-board list on the 4-validator net (never registered validators)
for (let i = 1; i <= 7; i++) roles.push("op" + i);         // OPERATOR (node) keys of the validators n1..n7
roles.push("opX1", "opE");                                 // node keys of the two extra nodes: x1 = swap alternate, x2 = entrant node
roles.push("verifier", "identityOracle", "distOracle");    // the three oracle keys (overlaid into genesis storage, see README deviations)
for (let i = 1; i <= 7; i++) roles.push("dao" + i);        // FoundationDAO board seats (only needed to seed the contract)
roles.push("inspector", "ceo");
for (let i = 1; i <= 3; i++) roles.push("claimant" + i);
for (let i = 1; i <= 3; i++) roles.push("fm" + i);
for (let i = 1; i <= 8; i++) roles.push("lg" + i);         // load-generator sender accounts
const keys = { _warning: "THROW-AWAY LOCAL TEST KEYS for the SUR Besu soak kit. Published in the repository on purpose. NEVER reuse, never fund on any real network." };
for (const r of roles) { const w = ethers.Wallet.createRandom(); keys[r] = { address: w.address, privateKey: w.privateKey }; }
fs.writeFileSync(out, JSON.stringify(keys, null, 2));
console.log("wrote", roles.length, "keys to", out);
