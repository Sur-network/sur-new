// Phase E step 1: newValidator1 (not a founder) requests membership.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const ABI = [
  "function requestMembership() external payable",
  "function currentEntryThreshold() view returns (uint256)",
  "function currentMembershipFee() view returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const nv1 = new ethers.Wallet(accounts.newValidator1.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, nv1);

  const threshold = await registry.currentEntryThreshold();
  const fee = await registry.currentMembershipFee();
  const total = threshold + fee;
  console.log("currentEntryThreshold:", ethers.formatEther(threshold), "currentMembershipFee:", ethers.formatEther(fee), "total:", ethers.formatEther(total));

  const balance = await provider.getBalance(nv1.address);
  console.log("newValidator1 balance:", ethers.formatEther(balance));

  const submittedAt = new Date().toISOString();
  const tx = await registry.requestMembership({ value: total, gasLimit: 600000 });
  console.log("tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("status:", receipt.status, "gasUsed:", receipt.gasUsed.toString(), "block:", receipt.blockNumber);

  const info = await registry.getValidatorInfo(nv1.address);
  console.log("getValidatorInfo after join:", info);

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseE-join-result.json"),
    JSON.stringify(
      {
        submittedAt,
        txHash: receipt.hash,
        status: receipt.status,
        gasUsed: receipt.gasUsed.toString(),
        joinedInBlock: receipt.blockNumber,
        threshold: threshold.toString(),
        fee: fee.toString(),
        infoStatus: info[0].toString(),
        periodStartedAt: info[2].toString(),
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
