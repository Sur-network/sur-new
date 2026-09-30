// v3: generates deterministic throwaway test accounts for the round-3 Besu live-test network.
// Local dev-chain only — private keys stored in plaintext on purpose, never reused anywhere real.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROLES = [
  "founder1",
  "founder2",
  "founder3",
  "newValidator1", // Phase E — joins post-genesis, later fully exits+withdraws
  "verifier",
  "distributionOracle",
  "fakeAddress", // Phase D — never activated, used to test the reject-fake-address path
];

const outPath = path.join(__dirname, "..", "..", "accounts.json");
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

fs.writeFileSync(outPath, JSON.stringify(accounts, null, 2));
console.log(`Wrote ${outPath} (${added} new, ${Object.keys(accounts).length} total)`);
console.log(JSON.stringify(Object.fromEntries(Object.entries(accounts).map(([k, v]) => [k, v.address])), null, 2));
