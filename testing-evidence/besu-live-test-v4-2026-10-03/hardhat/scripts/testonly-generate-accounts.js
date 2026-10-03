// TESTONLY TOOL — generates deterministic throwaway test accounts for the v4 Besu live-test.
// Local dev-chains only — private keys stored in plaintext on purpose, never reused anywhere real.
// File is prefixed TEST-KEYS-DO-NOT-REUSE per the v4 brief's rule 7.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROLES = [
  // G6 founders (6, no candidate) — Net-D / Net-D2
  "g6_v1", "g6_v2", "g6_v3", "g6_v4", "g6_v5", "g6_v6",
  // G5 founders (5) + candidate C6 — Net-B, Net-L01, Net-L02, Net-L04, Net-L05a, Net-L05b, Net-E*, Net-F*
  "g5_v1", "g5_v2", "g5_v3", "g5_v4", "g5_v5", "g5_c6",
  // X7 — deliberately-different-config node, Net-F4/Net-F5 only
  "x7",
  "verifier",
  "distributionOracle",
  ...Array.from({ length: 15 }, (_, i) => `foundation${i + 1}`),
  "serviceStakingUser1", "serviceStakingUser2",
  "fakeAddress", // never-activated address for C-REG-2 / D01 reject tests
];

const outPath = path.join(__dirname, "..", "..", "TEST-KEYS-DO-NOT-REUSE.json");
let accounts = {};
if (fs.existsSync(outPath)) {
  accounts = JSON.parse(fs.readFileSync(outPath, "utf8"));
}
let added = 0;
for (const role of ROLES) {
  if (!accounts[role]) {
    const wallet = ethers.Wallet.createRandom();
    accounts[role] = { address: wallet.address, privateKey: wallet.privateKey };
    added++;
  }
}

// 150 payee addresses for Group E (benchmark) — no private keys needed, they never send a tx.
if (!accounts.e_payees || accounts.e_payees.length !== 150) {
  accounts.e_payees = Array.from({ length: 150 }, () => ethers.Wallet.createRandom().address);
}

fs.writeFileSync(outPath, JSON.stringify(accounts, null, 2));
console.log(`Wrote ${outPath} (${added} new roles, ${Object.keys(accounts).length - 1} total + 150 e_payees)`);
