const hre = require("hardhat");
const fs = require("fs");

const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
const DISTRIBUTOR_ADDR = "0x2222222222222222222222222222222222222222";

let registry, deployer, verifierSigner, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10;
let art;

async function setSlot(label, value) {
  const s = art.layout.storage.find(x => x.label === label);
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, "0x" + BigInt(s.slot).toString(16), hre.ethers.zeroPadValue(hre.ethers.toBeHex(value), 32)]);
}

async function setupRegistry() {
  art = JSON.parse(fs.readFileSync("artifacts3.json", "utf8"));
  const signers = await hre.ethers.getSigners();
  [deployer, verifierSigner, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10] = signers;
  const regFactory = new hre.ethers.ContractFactory(art.registry.abi, art.registry.bytecode, deployer);
  const tempReg = await regFactory.deploy();
  await tempReg.waitForDeployment();
  const regCode = await hre.network.provider.send("eth_getCode", [await tempReg.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [REGISTRY_ADDR, regCode]);
  const mockFactory = new hre.ethers.ContractFactory(art.mock.abi, art.mock.bytecode, deployer);
  const tempMock = await mockFactory.deploy();
  await tempMock.waitForDeployment();
  const mockCode = await hre.network.provider.send("eth_getCode", [await tempMock.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [DISTRIBUTOR_ADDR, mockCode]);
  registry = new hre.ethers.Contract(REGISTRY_ADDR, art.registry.abi, deployer);
  const verifierSlot = art.layout.storage.find(s => s.label === 'verifier').slot;
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, "0x" + BigInt(verifierSlot).toString(16), hre.ethers.zeroPadValue(verifierSigner.address, 32)]);
  await setSlot('entryThresholdBase', hre.ethers.parseEther("500000"));
  await setSlot('growthFactorPerValidator', 1_017479692102686336n);
  await setSlot('membershipFeeBps', 400);
  await setSlot('maxEntriesPerWindow', 1);
  await setSlot('entryWindowSeconds', 86400);
  await setSlot('probationPeriod', 604800);
  await setSlot('recoveryPeriod', 172800);
  await setSlot('slashBps', 100);
  for (const s of signers) await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
}

async function registerAndActivate(signer) {
  const threshold = await registry.currentEntryThreshold();
  const fee = await registry.currentMembershipFee();
  await (await registry.connect(signer).requestMembership({ value: threshold + fee })).wait();
  await hre.network.provider.send("evm_increaseTime", [86400 + 1]);
  await hre.network.provider.send("evm_mine");
}
async function activateAfterProbation(signer) {
  await hre.network.provider.send("evm_increaseTime", [604800 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.connect(verifierSigner).recordActivation(signer.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("ev-" + signer.address)))).wait();
}
function decisionIdFromReceipt(receipt, wantedType) {
  for (const log of receipt.logs) {
    try {
      const parsed = registry.interface.parseLog(log);
      if (parsed.name === "StatusDecisionRecorded" && Number(parsed.args.decisionType) === wantedType) return parsed.args.decisionId;
    } catch (e) {}
  }
  throw new Error("رویداد پیدا نشد");
}

async function main() {
  console.log("=== آزمون لایه‌ی دوم N01: قفل متعلق به پرونده‌ی دیگر نباید توسط resolver پاک شود ===\n");
  await setupRegistry();
  const all = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of all) await registerAndActivate(val);
  for (const val of all) await activateAfterProbation(val);

  // v2 به‌تنهایی تعلیق می‌شود (رخداد جمعی نیست) → پرونده‌ی A، قفل = epoch خودش
  const tx = await registry.connect(verifierSigner).recordSuspension(v2.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v2")));
  const dA = decisionIdFromReceipt(await tx.wait(), 1);
  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dA)).wait();
  await hre.network.provider.send("evm_increaseTime", [604800 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.connect(deployer).assertDeliveryDisputed(dA)).wait(); // اختلاف مشروع روی پرونده‌ی باز
  let info = await registry.getValidatorInfo(v2.address);
  const epochA = info[4];
  console.log("قفل v2 (متعلق به A):", epochA.toString());

  // شبیه‌سازی «قفل جدیدتر متعلق به پرونده‌ی دیگر»: قفل حالا به شناسه‌ی تصمیم بسته است (pendingSlashDecisionId)؛
  // پس شناسه‌ی تصمیم دیگری (999) و اپوک 99 را مستقیم روی storage می‌نویسیم.
  const structSlot = BigInt(hre.ethers.solidityPackedKeccak256(["uint256","uint256"], [v2.address, 0]));
  const lockSlot = "0x" + (structSlot + 3n).toString(16); // pendingSlashEpoch = چهارمین فیلد struct
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, lockSlot, hre.ethers.zeroPadValue("0x63", 32)]);
  const idSlot = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(v2.address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === 'pendingSlashDecisionId').slot)), 32)]));
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, idSlot, hre.ethers.zeroPadValue(hre.ethers.toBeHex(999), 32)]);
  info = await registry.getValidatorInfo(v2.address);
  console.log("قفل v2 بعد از شبیه‌سازی قفل پرونده‌ی دیگر: epoch =", info[4].toString(), "| decisionId =", (await registry.pendingSlashDecisionId(v2.address)).toString(), "(باید 99 و 999 باشد)");

  await hre.network.provider.send("evm_increaseTime", [604800 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveDeliveryDisputeIfExpired(dA)).wait();
  const decA = await registry.statusDecisions(dA);
  info = await registry.getValidatorInfo(v2.address);
  console.log("slashOutcome پرونده‌ی A:", decA.slashOutcome.toString(), "(باید 2=VoidedNoDelivery باشد)");
  const idAfter = (await registry.pendingSlashDecisionId(v2.address)).toString();
  console.log("قفل v2 بعد از resolve پرونده‌ی A: epoch =", info[4].toString(), "| decisionId =", idAfter);
  if (info[4].toString() === "99" && idAfter === "999" && Number(decA.slashOutcome) === 2) {
    console.log("\n✅✅✅ لایه‌ی دوم تأیید شد: resolver پرونده‌ی A فقط پرونده‌ی خودش را بست و قفل پرونده‌ی دیگر (99) را دست نزد.");
  } else {
    console.log("\n❌ لایه‌ی دوم شکست خورد.");
    process.exit(1);
  }
}
main().catch((e) => { console.error("خطا:", e.message); process.exit(1); });
