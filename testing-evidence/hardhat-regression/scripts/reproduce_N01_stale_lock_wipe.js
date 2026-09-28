const __log = console.log; console.log = (...a) => { if (a.join(' ').includes('❌')) process.exitCode = 1; __log(...a); }; // ❌ => exit code 1
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
  console.log("=== بازتولید N01: پاک‌شدن قفل جریمه‌ی پرونده‌ی جدید توسط resolver پرونده‌ی قدیمی ===\n");
  await setupRegistry();
  const allValidators = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of allValidators) await registerAndActivate(val);
  for (const val of allValidators) await activateAfterProbation(val);
  console.log("✅ ۱۰ ولیدیتور فعال شدند\n");

  console.log("--- گام ۱: v2, v3, v4 را در همان پنجره تعلیق می‌کنیم (۳۰٪ > ۲۰٪ → رخداد جمعی) ---");
  const tx2 = await registry.connect(verifierSigner).recordSuspension(v2.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v2")));
  const dA = decisionIdFromReceipt(await tx2.wait(), 1);
  await (await registry.connect(verifierSigner).recordSuspension(v3.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v3")))).wait();
  await (await registry.connect(verifierSigner).recordSuspension(v4.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v4")))).wait();

  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dA)).wait();
  let decA = await registry.statusDecisions(dA);
  console.log("پرونده‌ی A (v2) slashOutcome:", decA.slashOutcome.toString(), "(باید 1=ExemptMassFailure باشد)");
  let infoV2 = await registry.getValidatorInfo(v2.address);
  console.log("v2.pendingSlashEpoch بعد از معافیت:", infoV2[4].toString(), "(باید 0 باشد)\n");

  console.log("--- گام ۲: v2 را با recordRecovery برمی‌گردانیم ---");
  await hre.network.provider.send("evm_increaseTime", [172800 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.connect(verifierSigner).recordRecovery(v2.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("recovery-v2")))).wait();
  infoV2 = await registry.getValidatorInfo(v2.address);
  console.log("وضعیت v2 بعد از recordRecovery:", infoV2[0].toString(), "(باید 2=Active باشد)\n");

  console.log("--- گام ۳: بعد از grace period، اختلاف تحویل روی پرونده‌ی قدیمی A را باز می‌کنیم ---");
  await hre.network.provider.send("evm_increaseTime", [604800 + 1]); // DELIVERY_DISPUTE_GRACE_PERIOD
  await hre.network.provider.send("evm_mine");
  try {
    await (await registry.connect(deployer).assertDeliveryDisputed(dA)).wait();
    console.log("❌❌❌ باگ تأیید شد: assertDeliveryDisputed روی پرونده‌ی از قبل بسته‌شده (ExemptMassFailure) موفق شد!\n");
  } catch (e) {
    console.log("✅ درست رد شد:", e.reason || e.shortMessage, "\n(اگر این پیام دیده شد، باگ از قبل اصلاح شده)");
    return;
  }

  console.log("--- گام ۴: v2 دوباره (تنها، بدون رخداد جمعی) تعلیق می‌شود — پرونده‌ی B ---");
  const txB = await registry.connect(verifierSigner).recordSuspension(v2.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v2-again")));
  const dB = decisionIdFromReceipt(await txB.wait(), 1);
  infoV2 = await registry.getValidatorInfo(v2.address);
  console.log("v2.pendingSlashEpoch بعد از تعلیق دوم (پرونده‌ی B):", infoV2[4].toString(), "(باید غیرصفر باشد)\n");

  console.log("--- گام ۵: رأی‌گیری اختلاف تحویل پرونده‌ی A را بدون نصاب تمام می‌کنیم ---");
  await hre.network.provider.send("evm_increaseTime", [604800 + 1]); // DELIVERY_DISPUTE_VOTING_PERIOD
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveDeliveryDisputeIfExpired(dA)).wait();

  infoV2 = await registry.getValidatorInfo(v2.address);
  console.log("\n🔍 نتیجه‌ی نهایی: v2.pendingSlashEpoch بعد از resolve پرونده‌ی A:", infoV2[4].toString());
  if (infoV2[4].toString() === "0") {
    console.log("❌❌❌ باگ N01 کاملاً تأیید شد: قفل جریمه‌ی پرونده‌ی B (که هنوز تعیین‌تکلیف نشده) توسط resolver پرونده‌ی A پاک شد!");
    console.log("این یعنی v2 الان می‌تواند requestExit بزند و بدون حل‌شدن پرونده‌ی B، کل وثیقه‌اش را پس بگیرد.");
  } else {
    console.log("✅ قفل B دست‌نخورده ماند.");
  }
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
