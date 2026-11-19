// BR-SIZE: derived from the result files of BG-01 and BG-09 (and the successful Registry calls of every other test) - the nets were already destroyed when this was written.
const fs = require("fs"); const path = require("path");
const R = (id) => JSON.parse(fs.readFileSync(path.join(__dirname, "..", "evidence", "04-results", id + ".json"), "utf8"));
const bg01 = R("BG-01"), bg09 = R("BG-09"), bg02 = R("BG-02");
const pick = (r, re) => r.checks.filter((c) => re.test(c.name));
const checks = [...pick(bg01, /eth_getCode DAO\/Registry/), ...pick(bg09, /BG-SIZE/), ...pick(bg09, /Spend proposal|3rd vote executes|getProposal: typed/), ...pick(bg02, /contract list == QBFT set == 7/)];
fs.writeFileSync(path.join(__dirname, "..", "evidence", "04-results", "BR-SIZE.json"), JSON.stringify({ id: "BR-SIZE", writtenAtUTC: new Date().toISOString(), verdict: checks.every((c) => c.pass) ? "PASS" : "FAIL",
  summary: "FoundationDAO (28,365 bytes) and ValidatorsRegistry (34,605 bytes) exceed the 24,576-byte EIP-170 CREATE limit; injected via genesis alloc they answer eth_getCode, eth_call and state-changing transactions on Besu (Registry: getValidators/activations/swaps/removals in BG-02..BG-07; DAO: proposals/votes/execution in BG-09, BG-10).",
  derivedFrom: ["BG-01.json", "BG-09.json", "BG-02.json"], checks }, null, 2));
console.log("BR-SIZE", checks.length, "checks derived,", checks.every((c) => c.pass) ? "PASS" : "FAIL");
