const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8551";
const FOUNDATION_ADDR = "0x1111111111111111111111111111111111111111";
const GAS_PRICE = 100000000000000n * 2n;
const GAS_LIMIT = 600000n;

const ABI = [
  "function proposeAddMember(string calldata description, string calldata name, address account) external returns (uint256)",
  "function proposeRemoveMember(string calldata description, address account) external returns (uint256)",
  "function proposeSendETH(string calldata description, address to, uint256 amount) external returns (uint256)",
  "function proposeExecute(string calldata description, address target, uint256 value, bytes calldata data) external returns (uint256)",
  "function vote(uint256 id) external",
  "function isMember(address) view returns (bool)",
  "event ProposalCreated(uint256 indexed id, uint8 pType, address indexed proposer)",
];

const log = [];
function record(label, obj) { log.push({ label, at: new Date().toISOString(), data: obj }); console.log(`[${new Date().toISOString()}] ${label}:`, JSON.stringify(obj)); }
function wait(s) { record("waiting", { seconds: s }); return new Promise((r) => setTimeout(r, s * 1000)); }
function foundationAs(provider, role) {
  return new ethers.Contract(FOUNDATION_ADDR, ABI, new ethers.Wallet(accounts[role].privateKey, provider));
}
async function send(contract, wallet, provider, method, args) {
  const nonce = await provider.getTransactionCount(wallet.address, "latest");
  const tx = await contract[method](...args, { nonce, gasPrice: GAS_PRICE, gasLimit: GAS_LIMIT, type: 0 });
  const receipt = await tx.wait();
  return receipt;
}
function findId(contract, receipt) {
  const parsed = receipt.logs.map((l) => { try { return contract.interface.parseLog(l); } catch { return null; } }).find((l) => l && l.name === "ProposalCreated");
  return parsed.args.id.toString();
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const w1 = new ethers.Wallet(accounts.foundation1.privateKey, provider);
  const f1 = foundationAs(provider, "foundation1");
  const newMember = accounts.boardOutside2.address;

  record("isMember(newMember) before", { isMember: await f1.isMember(newMember) });

  const r1 = await send(f1, w1, provider, "proposeAddMember", ["add test member", "TestNewFoundationMember", newMember]);
  const id1 = findId(f1, r1);
  record("proposeAddMember", { hash: r1.hash, status: r1.status, id: id1 });
  for (const role of ["foundation2", "foundation3", "foundation4"]) {
    const w = new ethers.Wallet(accounts[role].privateKey, provider);
    const f = foundationAs(provider, role);
    const r = await send(f, w, provider, "vote", [id1]);
    record(`vote(${id1}) by ${role}`, { hash: r.hash, status: r.status });
  }
  record("isMember(newMember) after AddMember (4/5 votes, needs ceil(10/3)=4)", { isMember: await f1.isMember(newMember) });

  const rRemove = await send(f1, w1, provider, "proposeRemoveMember", ["remove test member", newMember]);
  const idRemove = findId(f1, rRemove);
  record("proposeRemoveMember", { hash: rRemove.hash, status: rRemove.status, id: idRemove });
  for (const role of ["foundation2", "foundation3", "foundation4"]) {
    const w = new ethers.Wallet(accounts[role].privateKey, provider);
    const f = foundationAs(provider, role);
    const r = await send(f, w, provider, "vote", [idRemove]);
    record(`vote(${idRemove}) by ${role}`, { hash: r.hash, status: r.status });
  }
  record("isMember(newMember) after RemoveMember", { isMember: await f1.isMember(newMember) });

  const recipient = accounts.budgetRecipient.address;
  const balBefore = await provider.getBalance(recipient);
  const rSend = await send(f1, w1, provider, "proposeSendETH", ["test send", recipient, ethers.parseEther("100")]);
  const idSend = findId(f1, rSend);
  record("proposeSendETH", { hash: rSend.hash, status: rSend.status, id: idSend });
  for (const role of ["foundation2", "foundation3"]) {
    const w = new ethers.Wallet(accounts[role].privateKey, provider);
    const f = foundationAs(provider, role);
    const r = await send(f, w, provider, "vote", [idSend]);
    record(`vote(${idSend}) by ${role}`, { hash: r.hash, status: r.status });
  }
  const balAfter = await provider.getBalance(recipient);
  record("proposeSendETH RESULT (3 of 5 majority)", { balanceBefore: balBefore.toString(), balanceAfter: balAfter.toString(), delta: (balAfter - balBefore).toString() });

  let executeReverted = false, executeError = null;
  try {
    await send(f1, w1, provider, "proposeExecute", ["bad execute", recipient, 1n, "0x"]);
  } catch (e) { executeReverted = true; executeError = e.shortMessage || e.message; }
  record("proposeExecute(value=1) - should revert", { reverted: executeReverted, error: executeError });

  const rExpire = await send(f1, w1, provider, "proposeSendETH", ["will expire", recipient, ethers.parseEther("1")]);
  const idExpire = findId(f1, rExpire);
  record("proposeSendETH (will let expire)", { hash: rExpire.hash, status: rExpire.status, id: idExpire });
  await wait(130);
  let expiredReverted = false, expiredError = null;
  try {
    const w2 = new ethers.Wallet(accounts.foundation2.privateKey, provider);
    const f2 = foundationAs(provider, "foundation2");
    await send(f2, w2, provider, "vote", [idExpire]);
  } catch (e) { expiredReverted = true; expiredError = e.shortMessage || e.message; }
  record("vote on expired proposal - should revert", { reverted: expiredReverted, error: expiredError });

  fs.writeFileSync(path.join(ROOT, "logs", "phase7-foundation-raw.json"), JSON.stringify(log, null, 2));
  console.log("Wrote logs/phase7-foundation-raw.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
