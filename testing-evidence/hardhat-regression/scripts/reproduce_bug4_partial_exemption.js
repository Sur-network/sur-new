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
  console.log("=== بازتولید باگ ۴: معافیت جمعی فقط برای یه decisionId، نه کل epoch ===\n");
  await setupRegistry();
  const allValidators = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of allValidators) await registerAndActivate(val);
  for (const val of allValidators) await activateAfterProbation(val);
  console.log("✅ ۱۰ ولیدیتور فعال شدند\n");

  // v2 و v3 رو توی همون پنجره‌ی ۱ساعته تعلیق می‌کنیم (که باید رخداد جمعی بشه: ۲/۹>۲۰٪)
  const tx2 = await registry.connect(verifierSigner).recordSuspension(v2.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v2")));
  const r2 = await tx2.wait();
  const dV2 = decisionIdFromReceipt(r2, 1);

  const tx3 = await registry.connect(verifierSigner).recordSuspension(v3.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v3")));
  const r3 = await tx3.wait();
  const dV3 = decisionIdFromReceipt(r3, 1);
  console.log("✅ v2 و v3 توی همون پنجره‌ی ۱ساعته تعلیق شدند، decisionId:", dV2.toString(), dV3.toString());

  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");

  // فقط resolveMassFailureCheck رو برای dV2 صدا می‌زنیم (نه dV3)
  await (await registry.resolveMassFailureCheck(dV2)).wait();
  let decV2 = await registry.statusDecisions(dV2);
  console.log("slashOutcome v2 (که resolveMassFailureCheck مستقیم روش صدا زده شد):", decV2.slashOutcome.toString(), "(باید 1=ExemptMassFailure باشه)");

  let decV3 = await registry.statusDecisions(dV3);
  console.log("slashOutcome v3 (که resolveMassFailureCheck هرگز مستقیم روش صدا زده نشده):", decV3.slashOutcome.toString(), "(هنوز باید 0=Undetermined باشه)");

  // حالا تلاش برای confirmDelivery روی v3 — طبق ادعای ژپتو، باید موفق بشه چون epoch.resolved=true شده
  console.log("\n🔍 تلاش برای confirmDelivery روی v3 (که هرگز resolveMassFailureCheck مخصوص خودش رو نگرفته)...");
  try {
    await (await registry.connect(v3).confirmDelivery(dV3)).wait();
    console.log("❌❌❌ باگ تأیید شد: confirmDelivery برای v3 موفق شد، درحالی‌که v3.slashOutcome هنوز Undetermined بود (نه ExemptMassFailure)!");
    console.log("این یعنی v3 می‌تونه وارد جریان appeal/جریمه بشه، با وجود این‌که واقعاً بخشی از یه رخداد جمعی بوده.");
  } catch (e) {
    console.log("✅ رد شد:", e.reason || e.shortMessage);
  }
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
