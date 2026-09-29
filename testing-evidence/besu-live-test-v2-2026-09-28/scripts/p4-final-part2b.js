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

const BOARD_ABI = [
  "function voteFor(address candidate) external",
  "function refreshBoard() external",
  "function isBoardMember(address) view returns (bool)",
  "function boardVersion() view returns (uint256)",
  "function voteAction(uint256 id) external",
  "function proposeRotateOracle(address newOracle) external returns (uint256)",
  "function proposeSetEntryThresholdBase(uint256 newValue) external returns (uint256)",
  "function proposeRotateVerifier(address newVerifier) external returns (uint256)",
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
  const actionId = "8"; // from the earlier proposeApproveBudget, for scenario 6

  await send(boardAs(provider, "validator2"), wOf("validator2", provider), provider, "voteFor", [accounts.candidateA.address]);
  record("validator2 ALSO voted for candidateA (giving A 2 votes vs incumbents' 1 each)", {});

  await wait(185); // BOARD_REFRESH_INTERVAL test 180s + buffer

  const versionBefore3 = await boardView.boardVersion();
  const rRefresh3 = await send(boardAs(provider, "validator1"), wOf("validator1", provider), provider, "refreshBoard", []);
  const versionAfter3 = await boardView.boardVersion();
  record("refreshBoard (scenario 3: stronger challenger)", { hash: rRefresh3.hash, status: rRefresh3.status, versionBefore: versionBefore3.toString(), versionAfter: versionAfter3.toString() });
  for (const role of ["validator1", "validator2", "validator3", "validator4", "candidateG", "candidateA"]) {
    record(`isBoardMember(${role}) after challenge`, { isBM: await boardView.isBoardMember(accounts[role].address) });
  }

  let staleReverted = false, staleError = null;
  try {
    await send(boardAs(provider, "validator3"), wOf("validator3", provider), provider, "voteAction", [actionId]);
  } catch (e) {
    staleReverted = true;
    staleError = e.shortMessage || e.message;
  }
  record("SCENARIO 6: vote on stale action after real composition change - should revert", { reverted: staleReverted, error: staleError });

  const v1 = wOf("validator1", provider);
  const boardV1 = boardAs(provider, "validator1");
  const rRotateOracle = await send(boardV1, v1, provider, "proposeRotateOracle", [accounts.distributionOracle.address]);
  record("proposeRotateOracle", { hash: rRotateOracle.hash, status: rRotateOracle.status });

  const rSetThreshold = await send(boardV1, v1, provider, "proposeSetEntryThresholdBase", [ethers.parseEther("400000")]);
  record("proposeSetEntryThresholdBase(400000 ether)", { hash: rSetThreshold.hash, status: rSetThreshold.status });

  const rRotateVerifier = await send(boardV1, v1, provider, "proposeRotateVerifier", [accounts.verifier.address]);
  record("proposeRotateVerifier", { hash: rRotateVerifier.hash, status: rRotateVerifier.status });

  fs.writeFileSync(path.join(ROOT, "logs", "phase4-final-part2b-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase4-final-part2b-raw.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
