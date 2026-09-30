// Phase E step 2: verifier calls recordActivation() for newValidator1 after real probationPeriod
// wall-clock wait (not evm_increaseTime — this is a real Besu network).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const ABI = [
  "function recordActivation(address,bytes32) external returns (uint256)",
  "function isValidator(address) view returns (bool)",
  "function everActivated(address) view returns (bool)",
  "function getValidators() view returns (address[])",
  "function probationPeriod() view returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, verifier);

  const info = await registry.getValidatorInfo(accounts.newValidator1.address);
  const periodStartedAt = Number(info[2]);
  const probationPeriod = Number(await registry.probationPeriod());
  const readyAt = periodStartedAt + probationPeriod;
  const nowSec = Math.floor(Date.now() / 1000);
  console.log("periodStartedAt:", periodStartedAt, "probationPeriod:", probationPeriod, "readyAt:", readyAt, "now:", nowSec);
  if (nowSec < readyAt) {
    const waitMs = (readyAt - nowSec + 3) * 1000;
    console.log(`Waiting ${waitMs}ms for probationPeriod to elapse...`);
    await new Promise((r) => setTimeout(r, waitMs));
  }

  const submittedAt = new Date().toISOString();
  const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes("phaseE-activation-evidence"));
  const tx = await registry.recordActivation(accounts.newValidator1.address, evidenceHash, { gasLimit: 600000 });
  console.log("tx hash:", tx.hash);
  const receipt = await tx.wait();
  console.log("status:", receipt.status, "gasUsed:", receipt.gasUsed.toString(), "block:", receipt.blockNumber);

  const isVal = await registry.isValidator(accounts.newValidator1.address);
  const everAct = await registry.everActivated(accounts.newValidator1.address);
  const validators = await registry.getValidators();
  console.log("isValidator(newValidator1):", isVal, "everActivated(newValidator1):", everAct);
  console.log("getValidators():", validators);

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseE-activate-result.json"),
    JSON.stringify(
      {
        submittedAt,
        txHash: receipt.hash,
        status: receipt.status,
        gasUsed: receipt.gasUsed.toString(),
        activatedInBlock: receipt.blockNumber,
        isValidatorAfter: isVal,
        everActivatedAfter: everAct,
        validatorsAfter: validators,
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
