const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8551";
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
const BOARD_ADDR = "0x4444444444444444444444444444444444444444";
const IDENTITY_ADDR = "0x6666666666666666666666666666666666666666";
const GAS_PRICE = 100000000000000n * 2n;
const GAS_LIMIT = 600000n;

const REGISTRY_ABI = ["function getValidators() view returns (address[])"];
const IDENTITY_ABI = ["function registerIdentity(uint8 personType, string calldata name) external", "function hasIdentity(address) view returns (bool)"];
const BOARD_ABI = [
  "function voteFor(address candidate) external",
  "function refreshBoard() external",
  "function syncBoard() external",
  "function isBoardMember(address) view returns (bool)",
  "function boardVersion() view returns (uint256)",
  "function proposeApproveBudget(address to, uint256 amount, string calldata description) external returns (uint256)",
  "function voteAction(uint256 id) external",
  "function proposeRotateOracle(address newOracle) external returns (uint256)",
  "function proposeSetEntryThresholdBase(uint256 newValue) external returns (uint256)",
  "function proposeRotateVerifier(address newVerifier) external returns (uint256)",
  "function clearStaleVotes(address validator) external",
  "event ActionProposed(uint256 indexed id, uint8 atype, address indexed target, uint256 amount, address indexed proposer)",
];

const log = [];
function record(label, obj) { log.push({ label, at: new Date().toISOString(), data: obj }); console.log(`[${new Date().toISOString()}] ${label}:`, JSON.stringify(obj)); }
function wait(s) { record("waiting", { seconds: s }); return new Promise((r) => setTimeout(r, s * 1000)); }
async function send(contract, wallet, provider, method, args) {
  const nonce = await provider.getTransactionCount(wallet.address, "latest");
  const tx = await contract[method](...args, { nonce, gasPrice: GAS_PRICE, gasLimit: GAS_LIMIT, type: 0 });
  return await tx.wait();
}
function boardAs(provider, role) { return new ethers.Contract(BOARD_ADDR, BOARD_ABI, new ethers.Wallet(accounts[role].privateKey, provider)); }
function wOf(role, provider) { return new ethers.Wallet(accounts[role].privateKey, provider); }

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const boardView = new ethers.Contract(BOARD_ADDR, BOARD_ABI, provider);
  const regView = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, provider);

  // ===== Scenario 6 setup: propose a budget action BEFORE the real composition change =====
  const v1 = wOf("validator1", provider);
  const boardV1 = boardAs(provider, "validator1");
  const rPropose = await send(boardV1, v1, provider, "proposeApproveBudget", [accounts.budgetRecipient.address, ethers.parseEther("1"), "will-be-invalidated"]);
  const parsedPropose = rPropose.logs.map((l) => { try { return boardV1.interface.parseLog(l); } catch { return null; } }).find((l) => l && l.name === "ActionProposed");
  const actionId = parsedPropose.args.id.toString();
  record("proposeApproveBudget (for scenario 6, 1/3 votes so far)", { hash: rPropose.hash, status: rPropose.status, actionId });

  // ===== Scenario 3 setup: candidateA becomes a stronger challenger (2 votes vs incumbents' 1) =====
  const identityA = new ethers.Contract(IDENTITY_ADDR, IDENTITY_ABI, wOf("candidateA", provider));
  if (!(await identityA.hasIdentity(accounts.candidateA.address))) {
    await send(identityA, wOf("candidateA", provider), provider, "registerIdentity", [0, "test-candidateA-challenger"]);
  }
  await send(boardAs(provider, "candidateA"), wOf("candidateA", provider), provider, "voteFor", [accounts.candidateA.address]);
  record("candidateA voted for self", {});
  await send(boardAs(provider, "candidateG"), wOf("candidateG", provider), provider, "voteFor", [accounts.candidateA.address]);
  record("candidateG ALSO voted for candidateA (giving A 2 votes vs incumbents' 1 each)", {});

  await wait(185); // BOARD_REFRESH_INTERVAL test 180s + buffer

  const versionBefore3 = await boardView.boardVersion();
  const rRefresh3 = await send(boardV1, v1, provider, "refreshBoard", []);
  const versionAfter3 = await boardView.boardVersion();
  record("refreshBoard (scenario 3: stronger challenger)", { hash: rRefresh3.hash, status: rRefresh3.status, versionBefore: versionBefore3.toString(), versionAfter: versionAfter3.toString() });
  for (const role of ["validator1", "validator2", "validator3", "validator4", "candidateG", "candidateA"]) {
    record(`isBoardMember(${role}) after challenge`, { isBM: await boardView.isBoardMember(accounts[role].address) });
  }

  // ===== Scenario 6: try to vote on the now-stale action =====
  let staleReverted = false, staleError = null;
  try {
    const v2 = wOf("validator2", provider);
    const boardV2 = boardAs(provider, "validator2");
    await send(boardV2, v2, provider, "voteAction", [actionId]);
  } catch (e) { staleReverted = true; staleError = e.shortMessage || e.message; }
  record("SCENARIO 6: vote on stale action after real composition change - should revert", { reverted: staleReverted, error: staleError });

  // ===== Scenario 9: other board actions =====
  const rRotateOracle = await send(boardV1, v1, provider, "proposeRotateOracle", [accounts.distributionOracle.address]);
  record("proposeRotateOracle (self-consistent, same address, just exercising the path)", { hash: rRotateOracle.hash, status: rRotateOracle.status });

  const rSetThreshold = await send(boardV1, v1, provider, "proposeSetEntryThresholdBase", [ethers.parseEther("400000")]);
  record("proposeSetEntryThresholdBase(400000 ether)", { hash: rSetThreshold.hash, status: rSetThreshold.status });

  const rRotateVerifier = await send(boardV1, v1, provider, "proposeRotateVerifier", [accounts.verifier.address]);
  record("proposeRotateVerifier (self-consistent)", { hash: rRotateVerifier.hash, status: rRotateVerifier.status });

  // ===== Scenario 12: no emergency-removal function in the REAL, FULL compiled ABI =====
  const hre = require("hardhat");
  const artifact = await hre.artifacts.readArtifact("ValidatorsBoard");
  const fnNames = artifact.abi.filter((e) => e.type === "function").map((e) => e.name);
  const suspiciousKeywords = ["remove", "emergency", "kick", "dismiss", "expel", "evict", "purge", "forceout", "oust"];
  const suspicious = fnNames.filter((name) => suspiciousKeywords.some((kw) => name.toLowerCase().includes(kw)));
  record("SCENARIO 12: full compiled ABI function names", { count: fnNames.length, names: fnNames });
  record("SCENARIO 12 RESULT: functions matching emergency-removal keywords (should be empty)", { suspicious });

  fs.writeFileSync(path.join(ROOT, "logs", "phase4-final-part2-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase4-final-part2-raw.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
