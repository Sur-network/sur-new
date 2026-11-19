// Generates throw-away local test keys -> ../TEST-KEYS-DO-NOT-REUSE.json (never overwrites an existing file).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const out = path.resolve(__dirname, "../TEST-KEYS-DO-NOT-REUSE.json");
if (fs.existsSync(out)) { console.log("exists, not overwritten:", out); process.exit(0); }
const roles = [];
for (let i = 1; i <= 7; i++) roles.push("owner" + i);      // founder OWNER keys (rewards, collateral, votes, seat)
for (let i = 1; i <= 7; i++) roles.push("op" + i);         // founder OPERATOR (node) keys
roles.push("op2b", "op3b", "opC");                         // spare node keys: swap targets, candidate node
roles.push("cand", "buyer", "outsider");                   // paid entrant owner, seat-transfer buyer, unverified outsider
roles.push("verifier", "identityOracle", "distOracle");    // the three oracle keys (overlaid into genesis storage, see DEVIATIONS)
for (let i = 1; i <= 7; i++) roles.push("dao" + i);        // FoundationDAO board: 1..5 principals, 6..7 alternates
roles.push("inspector", "ceo", "spendTo");
for (let i = 1; i <= 6; i++) roles.push("lot" + i);        // lottery ticket buyers
for (let i = 1; i <= 3; i++) roles.push("claimant" + i);   // GenesisClaimsVault claimants
for (let i = 1; i <= 3; i++) roles.push("fm" + i);         // FoundationMembers
roles.push("tester");                                       // deploys probe contracts
const keys = { _warning: "THROW-AWAY LOCAL TEST KEYS. Used only on local Docker dev chains. NEVER reuse, never fund on a real network." };
for (const r of roles) { const w = ethers.Wallet.createRandom(); keys[r] = { address: w.address, privateKey: w.privateKey }; }
fs.writeFileSync(out, JSON.stringify(keys, null, 2));
console.log("wrote", roles.length, "keys to", out);
