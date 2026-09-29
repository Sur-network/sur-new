// Scenario 10: clearStaleVotes — suspend a validator who has cast votes, wait
// recoveryPeriod+STALE_VOTE_CLEAR_DELAY, then purge its stale votes.
// Scenario 11: syncBoard immediate succession — separate from the monthly refresh.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8551";
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
const BOARD_ADDR = "0x4444444444444444444444444444444444444444";
const GAS_PRICE = 100000000000000n * 2n;
const GAS_LIMIT = 600000n;

const REGISTRY_ABI = [
  "function recordSuspension(address validator, bytes32 evidenceHash) external returns (uint256)",
  "function resolveMassFailureCheck(uint256 decisionId) external",
  "function confirmDelivery(uint256 decisionId) external",
  "function executeUncontestedSlash(uint256 decisionId) external",
  "function recoveryPeriod() view returns (uint256)",
  "function validators(address) view returns (uint8 status, uint256 lockedStake, uint256 periodStartedAt, uint256 pendingSlashEpoch, uint256 demotedAt, bool isPaidEntrant)",
  "event StatusDecisionRecorded(uint256 indexed decisionId, address indexed validator, uint8 decisionType, bytes32 evidenceHash)",
];
const BOARD_ABI = [
  "function clearStaleVotes(address validator) external",
  "function syncBoard() external",
  "function isBoardMember(address) view returns (bool)",
  "function boardVersion() view returns (uint256)",
];

const log = [];
function record(label, obj) { log.push({ label, at: new Date().toISOString(), data: obj }); console.log(`[${new Date().toISOString()}] ${label}:`, JSON.stringify(obj)); }
function wait(s) { record("waiting", { seconds: s }); return new Promise((r) => setTimeout(r, s * 1000)); }
async function send(contract, wallet, provider, method, args) {
  const nonce = await provider.getTransactionCount(wallet.address, "latest");
  const tx = await contract[method](...args, { nonce, gasPrice: GAS_PRICE, gasLimit: GAS_LIMIT, type: 0 });
  return await tx.wait();
}
function wOf(role, provider) { return new ethers.Wallet(accounts[role].privateKey, provider); }

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const boardView = new ethers.Contract(BOARD_ADDR, BOARD_ABI, provider);
  const regView = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, provider);
  const verifier = wOf("verifier", provider);
  const regV = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, verifier);
  const anyone = wOf("boardOutside1", provider);
  const regAnyone = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, anyone);

  // ===== Scenario 10: clearStaleVotes — use candidateG (has cast votes, currently a board member) =====
  const rSuspend = await send(regV, verifier, provider, "recordSuspension", [accounts.candidateG.address, ethers.keccak256(ethers.toUtf8Bytes("stale-vote-test-G"))]);
  const parsed = rSuspend.logs.map((l) => { try { return regV.interface.parseLog(l); } catch { return null; } }).find((l) => l && l.name === "StatusDecisionRecorded");
  const decisionId = parsed.args.decisionId.toString();
  record("recordSuspension(candidateG) for clearStaleVotes test", { hash: rSuspend.hash, status: rSuspend.status, decisionId });

  // ===== Scenario 11: syncBoard immediate succession — separate tx, right after suspension =====
  const versionBeforeSync = await boardView.boardVersion();
  const rSync = await send(new ethers.Contract(BOARD_ADDR, BOARD_ABI, anyone), anyone, provider, "syncBoard", []);
  const versionAfterSync = await boardView.boardVersion();
  record("SCENARIO 11: syncBoard() immediately after suspension (separate from monthly refresh)", {
    hash: rSync.hash,
    status: rSync.status,
    versionBefore: versionBeforeSync.toString(),
    versionAfter: versionAfterSync.toString(),
  });
  record("isBoardMember(candidateG) immediately after syncBoard (should be false - immediate drop)", { isBM: await boardView.isBoardMember(accounts.candidateG.address) });

  await wait(65);
  await send(regAnyone, anyone, provider, "resolveMassFailureCheck", [decisionId]);
  const vG = await regView.validators(accounts.candidateG.address);
  record("candidateG demotedAt", { demotedAt: vG[4].toString() });

  const recoveryPeriod = await regView.recoveryPeriod();
  const staleDelay = 60; // STALE_VOTE_CLEAR_DELAY test value
  const now = Math.floor(Date.now() / 1000);
  const waitNeeded = Math.max(0, Number(vG[4]) + Number(recoveryPeriod) + staleDelay - now) + 10;
  await wait(waitNeeded);

  const rClear = await send(new ethers.Contract(BOARD_ADDR, BOARD_ABI, anyone), anyone, provider, "clearStaleVotes", [accounts.candidateG.address]);
  record("clearStaleVotes(candidateG)", { hash: rClear.hash, status: rClear.status });

  fs.writeFileSync(path.join(ROOT, "logs", "phase4-scenarios-10-11-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase4-scenarios-10-11-raw.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
