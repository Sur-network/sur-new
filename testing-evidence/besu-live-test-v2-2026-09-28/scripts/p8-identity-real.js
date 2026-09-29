// Phase 8: IdentityRegistry — setPhoneVerified/setTelegramVerified/setKycVerified, migrateIdentity,
// and identityOracle rotation via FoundationDAO.proposeExecute (majority vote).
// All transactions use explicit nonce/gasPrice/gasLimit/type (per the §4 workaround).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8551";
const IDENTITY_ADDR = "0x6666666666666666666666666666666666666666";
const FOUNDATION_ADDR = "0x1111111111111111111111111111111111111111";
const GAS_PRICE = 100000000000000n * 2n;
const GAS_LIMIT = 600000n;

const IDENTITY_ABI = [
  "function registerIdentity(uint8 personType, string calldata name) external",
  "function hasIdentity(address) view returns (bool)",
  "function setPhoneVerified(address who, bool verified) external",
  "function setTelegramVerified(address who, bool verified) external",
  "function setKycVerified(address who, bool verified, bytes32 commitment) external",
  "function migrateIdentity(address oldAddr, address newAddr) external",
  "function getVerificationStatus(address who) view returns (bool,bool,bool)",
  "function identityOracle() view returns (address)",
];
const FOUNDATION_ABI = [
  "function proposeExecute(string calldata description, address target, uint256 value, bytes calldata data) external returns (uint256)",
  "function vote(uint256 proposalId) external",
  "event ProposalCreated(uint256 indexed id, uint8 pType, address indexed proposer)",
];

const log = [];
function record(label, obj) { log.push({ label, at: new Date().toISOString(), data: obj }); console.log(`[${new Date().toISOString()}] ${label}:`, JSON.stringify(obj)); }
async function send(contract, wallet, provider, method, args) {
  const nonce = await provider.getTransactionCount(wallet.address, "latest");
  const tx = await contract[method](...args, { nonce, gasPrice: GAS_PRICE, gasLimit: GAS_LIMIT, type: 0 });
  return await tx.wait();
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const identityView = new ethers.Contract(IDENTITY_ADDR, IDENTITY_ABI, provider);

  record("identityOracle before rotation", { oracle: await identityView.identityOracle() });

  const newOracle = accounts.candidateA.address;
  const setOracleIface = new ethers.Interface(["function setIdentityOracle(address newOracle) external"]);
  const calldata = setOracleIface.encodeFunctionData("setIdentityOracle", [newOracle]);

  const w1 = new ethers.Wallet(accounts.foundation1.privateKey, provider);
  const f1 = new ethers.Contract(FOUNDATION_ADDR, FOUNDATION_ABI, w1);
  const rPropose = await send(f1, w1, provider, "proposeExecute", ["rotate identityOracle", IDENTITY_ADDR, 0, calldata]);
  const parsed = rPropose.logs.map((l) => { try { return f1.interface.parseLog(l); } catch { return null; } }).find((l) => l && l.name === "ProposalCreated");
  const id = parsed.args.id.toString();
  record("proposeExecute(setIdentityOracle)", { hash: rPropose.hash, status: rPropose.status, id });

  for (const role of ["foundation2", "foundation3"]) {
    const w = new ethers.Wallet(accounts[role].privateKey, provider);
    const f = new ethers.Contract(FOUNDATION_ADDR, FOUNDATION_ABI, w);
    const r = await send(f, w, provider, "vote", [id]);
    record(`vote(${id}) by ${role}`, { hash: r.hash, status: r.status });
  }
  record("identityOracle after rotation", { oracle: await identityView.identityOracle() });

  const subject = accounts.candidateG.address;
  const oracleWallet = new ethers.Wallet(accounts.candidateA.privateKey, provider);
  const identityAsOracle = new ethers.Contract(IDENTITY_ADDR, IDENTITY_ABI, oracleWallet);

  if (!(await identityView.hasIdentity(subject))) {
    const subjWallet = new ethers.Wallet(accounts.candidateG.privateKey, provider);
    const identityAsSubject = new ethers.Contract(IDENTITY_ADDR, IDENTITY_ABI, subjWallet);
    const r = await send(identityAsSubject, subjWallet, provider, "registerIdentity", [0, "test-subject-G"]);
    record("registerIdentity(candidateG)", { hash: r.hash, status: r.status });
  }

  const rPhone = await send(identityAsOracle, oracleWallet, provider, "setPhoneVerified", [subject, true]);
  record("setPhoneVerified(true)", { hash: rPhone.hash, status: rPhone.status });

  const rTg = await send(identityAsOracle, oracleWallet, provider, "setTelegramVerified", [subject, true]);
  record("setTelegramVerified(true)", { hash: rTg.hash, status: rTg.status });

  const commitment = ethers.keccak256(ethers.toUtf8Bytes("kyc-commitment-test"));
  const rKyc = await send(identityAsOracle, oracleWallet, provider, "setKycVerified", [subject, true, commitment]);
  record("setKycVerified(true)", { hash: rKyc.hash, status: rKyc.status });

  record("getVerificationStatus(subject)", { status: await identityView.getVerificationStatus(subject) });

  const newAddr = accounts.boardOutside1.address;
  const rMigrate = await send(identityAsOracle, oracleWallet, provider, "migrateIdentity", [subject, newAddr]);
  record("migrateIdentity(subject -> newAddr)", { hash: rMigrate.hash, status: rMigrate.status });
  record("hasIdentity(oldAddr) after migration (should be false)", { has: await identityView.hasIdentity(subject) });
  record("hasIdentity(newAddr) after migration (should be true)", { has: await identityView.hasIdentity(newAddr) });

  fs.writeFileSync(path.join(ROOT, "logs", "phase8-identity-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase8-identity-raw.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
