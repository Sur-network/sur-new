// Phase 4 final scenarios: recover candidateA (2nd outside candidate) -> fill vacancy with
// validator4 -> board full (5/5) -> stronger challenger (candidateA) replaces weakest incumbent
// -> tie test -> invalidate open action across real change -> other board actions -> clearStaleVotes
// -> syncBoard immediate succession -> ABI emergency-removal check.
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

const REGISTRY_ABI = [
  "function recordRecovery(address validator, bytes32 evidenceHash) external returns (uint256)",
  "function recordSuspension(address validator, bytes32 evidenceHash) external returns (uint256)",
  "function isValidator(address) view returns (bool)",
];
const IDENTITY_ABI = ["function registerIdentity(uint8 personType, string calldata name) external", "function hasIdentity(address) view returns (bool)"];
const BOARD_ABI = [
  "function voteFor(address candidate) external",
  "function unvoteFor(address candidate) external",
  "function refreshBoard() external",
  "function syncBoard() external",
  "function fillVacancies() external",
  "function isBoardMember(address) view returns (bool)",
  "function boardVersion() view returns (uint256)",
  "function proposeApproveBudget(address to, uint256 amount, string calldata description) external returns (uint256)",
  "function voteAction(uint256 id) external",
  "function proposeRotateOracle(address newOracle) external returns (uint256)",
  "function proposeSetEntryThresholdBase(uint256 newValue) external returns (uint256)",
  "function proposeRotateVerifier(address newVerifier) external returns (uint256)",
  "function clearStaleVotes(address validator) external",
  "function actions(uint256) view returns (uint8 atype,address target,uint256 amount,string description,uint256 votes,uint256 requiredVotes,uint256 createdAt,uint256 expiresAt,bool executed,uint256 boardVersionAtCreation)",
  "event BoardRefreshed(address[] newBoard, uint256[] voteCounts)",
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
function wOf(role) { return new ethers.Wallet(accounts[role].privateKey); }

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const boardView = new ethers.Contract(BOARD_ADDR, BOARD_ABI, provider);
  const regView = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, provider);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const regV = new ethers.Contract(REGISTRY_ADDR, REGISTRY_ABI, verifier);

  // --- Recover candidateA ---
  const rRecoverA = await send(regV, verifier, provider, "recordRecovery", [accounts.candidateA.address, ethers.keccak256(ethers.toUtf8Bytes("recover-A-2"))]);
  record("recordRecovery(candidateA)", { hash: rRecoverA.hash, status: rRecoverA.status });
  record("candidateA isValidator", { isVal: await regView.isValidator(accounts.candidateA.address) });

  // --- Fill the existing vacancy with validator4 first (clean baseline: full board) ---
  const boardV4 = boardAs(provider, "validator4");
  const wV4 = wOf("validator4");
  const identityV4 = new ethers.Contract(IDENTITY_ADDR, IDENTITY_ABI, wV4.connect(provider));
  if (!(await identityV4.hasIdentity(accounts.validator4.address))) {
    await send(identityV4, wV4.connect(provider), provider, "registerIdentity", [0, "test-validator4-rejoin"]);
  }
  await send(boardV4, wV4.connect(provider), provider, "voteFor", [accounts.validator4.address]);
  record("validator4 voted for self (fill vacancy)", {});

  const rFill = await send(boardAs(provider, "validator1"), wOf("validator1").connect(provider), provider, "refreshBoard", []);
  record("refreshBoard (fill vacancy with validator4)", { hash: rFill.hash, status: rFill.status });
  record("isBoardMember(validator4) after fill", { isBM: await boardView.isBoardMember(accounts.validator4.address) });
  record("board is now full (5/5)?", {
    v1: await boardView.isBoardMember(accounts.validator1.address),
    v2: await boardView.isBoardMember(accounts.validator2.address),
    v3: await boardView.isBoardMember(accounts.validator3.address),
    v4: await boardView.isBoardMember(accounts.validator4.address),
    g: await boardView.isBoardMember(accounts.candidateG.address),
  });

  fs.writeFileSync(path.join(ROOT, "logs", "phase4-final-part1-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase4-final-part1-raw.json (part 1 of 2)");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
