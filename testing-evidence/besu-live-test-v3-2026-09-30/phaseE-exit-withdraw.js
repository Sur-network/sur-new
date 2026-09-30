// Phase E steps 3-4: newValidator1 mines blocks as Active, then requestExit(), waits real
// exitCooldown, then a REAL withdrawStake() (fully deletes ValidatorInfo). Confirms everActivated
// survives the deletion.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const ABI = [
  "function requestExit() external",
  "function withdrawStake() external",
  "function isValidator(address) view returns (bool)",
  "function everActivated(address) view returns (bool)",
  "function getValidators() view returns (address[])",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
  "function exitCooldown() view returns (uint256)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const nv1 = new ethers.Wallet(accounts.newValidator1.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, nv1);

  console.log("Waiting ~15s for newValidator1 to mine a few blocks as Active...");
  await new Promise((r) => setTimeout(r, 15000));

  console.log("isValidator before exit:", await registry.isValidator(nv1.address));

  const exitSubmittedAt = new Date().toISOString();
  const exitTx = await registry.requestExit({ gasLimit: 600000 });
  const exitReceipt = await exitTx.wait();
  console.log("requestExit tx:", exitReceipt.hash, "status:", exitReceipt.status, "block:", exitReceipt.blockNumber);

  const infoAfterExit = await registry.getValidatorInfo(nv1.address);
  const periodStartedAt = Number(infoAfterExit[2]);
  const exitCooldown = Number(await registry.exitCooldown());
  const readyAt = periodStartedAt + exitCooldown;
  const nowSec = Math.floor(Date.now() / 1000);
  console.log("exit periodStartedAt:", periodStartedAt, "exitCooldown:", exitCooldown, "readyAt:", readyAt, "now:", nowSec);
  if (nowSec < readyAt) {
    const waitMs = (readyAt - nowSec + 3) * 1000;
    console.log(`Waiting ${waitMs}ms for exitCooldown to elapse...`);
    await new Promise((r) => setTimeout(r, waitMs));
  }

  const balanceBeforeWithdraw = await provider.getBalance(nv1.address);
  const withdrawSubmittedAt = new Date().toISOString();
  const withdrawTx = await registry.withdrawStake({ gasLimit: 600000 });
  const withdrawReceipt = await withdrawTx.wait();
  console.log("withdrawStake tx:", withdrawReceipt.hash, "status:", withdrawReceipt.status, "block:", withdrawReceipt.blockNumber);
  const balanceAfterWithdraw = await provider.getBalance(nv1.address);

  const infoAfterWithdraw = await registry.getValidatorInfo(nv1.address);
  const everActivatedAfter = await registry.everActivated(nv1.address);
  console.log("getValidatorInfo after withdrawStake:", infoAfterWithdraw);
  console.log("everActivated(newValidator1) after withdrawStake:", everActivatedAfter);
  console.log("balance delta from withdraw (minus gas):", ethers.formatEther(balanceAfterWithdraw - balanceBeforeWithdraw));

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseE-exit-withdraw-result.json"),
    JSON.stringify(
      {
        exitSubmittedAt,
        exitTxHash: exitReceipt.hash,
        exitStatus: exitReceipt.status,
        exitBlock: exitReceipt.blockNumber,
        withdrawSubmittedAt,
        withdrawTxHash: withdrawReceipt.hash,
        withdrawStatus: withdrawReceipt.status,
        withdrawBlock: withdrawReceipt.blockNumber,
        infoAfterWithdraw: infoAfterWithdraw.map((v) => v.toString()),
        everActivatedAfterWithdraw: everActivatedAfter,
        balanceDeltaFromWithdraw: (balanceAfterWithdraw - balanceBeforeWithdraw).toString(),
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
