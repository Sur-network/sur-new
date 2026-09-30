// Phase C step 1: founder3 mines blocks as a normal active validator, then calls requestExit()
// BEFORE the next distributeRewards() call — this removes it from the active/QBFT set
// immediately (P04 semantics), while it still needs to be paid for blocks it already mined.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const ABI = [
  "function requestExit() external",
  "function isValidator(address) view returns (bool)",
  "function getValidators() view returns (address[])",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founder3 = new ethers.Wallet(accounts.founder3.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, founder3);

  const blockBefore = await provider.getBlockNumber();
  console.log("Block before exit tx:", blockBefore);
  console.log("isValidator(founder3) before:", await registry.isValidator(accounts.founder3.address));

  const submittedAt = new Date().toISOString();
  const tx = await registry.requestExit({ gasLimit: 600000 });
  console.log("tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("status:", receipt.status, "gasUsed:", receipt.gasUsed.toString(), "minedInBlock:", receipt.blockNumber);

  console.log("isValidator(founder3) after:", await registry.isValidator(accounts.founder3.address));
  console.log("getValidators() after:", await registry.getValidators());

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseC-exit-result.json"),
    JSON.stringify(
      {
        submittedAt,
        txHash: receipt.hash,
        status: receipt.status,
        gasUsed: receipt.gasUsed.toString(),
        exitMinedInBlock: receipt.blockNumber,
        blockBefore,
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
