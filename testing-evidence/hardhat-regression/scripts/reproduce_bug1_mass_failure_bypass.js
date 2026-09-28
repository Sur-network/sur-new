const __log = console.log; console.log = (...a) => { if (a.join(' ').includes('❌')) process.exitCode = 1; __log(...a); }; // ❌ => exit code 1
const hre = require("hardhat");
const fs = require("fs");

const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333";
const DISTRIBUTOR_ADDR = "0x2222222222222222222222222222222222222222";
const TREASURY_ADDR = "0x5555555555555555555555555555555555555555";

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

  for (const s of signers) {
    await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
  }
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
  const evidenceHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("evidence-" + signer.address));
  await (await registry.connect(verifierSigner).recordActivation(signer.address, evidenceHash)).wait();
}

function decisionIdFromReceipt(receipt, wantedType) {
  for (const log of receipt.logs) {
    try {
      const parsed = registry.interface.parseLog(log);
      if (parsed.name === "StatusDecisionRecorded" && Number(parsed.args.decisionType) === wantedType) {
        return parsed.args.decisionId;
      }
    } catch (e) {}
  }
  throw new Error("رویداد پیدا نشد");
}

async function main() {
  console.log("=== بازتولید باگ بحرانی: دورزدن چک رخداد جمعی ===\n");
  await setupRegistry();

  // ۱۰ ولیدیتور فعال کن
  const allValidators = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of allValidators) await registerAndActivate(val);
  for (const val of allValidators) await activateAfterProbation(val);
  console.log("✅ ۱۰ ولیدیتور فعال شدند\n");

  // v1 رو تعلیق کن
  const evidenceHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v1"));
  const tx = await registry.connect(verifierSigner).recordSuspension(v1.address, evidenceHash);
  const receipt = await tx.wait();
  const decisionId = decisionIdFromReceipt(receipt, 1);
  console.log("✅ v1 تعلیق شد، decisionId:", decisionId.toString());

  // بلافاصله (بدون صبر ۱ساعته، بدون resolveMassFailureCheck) تلاش برای confirmDelivery
  console.log("\n🔍 تلاش برای confirmDelivery **بلافاصله بعد از تعلیق**، بدون این‌که resolveMassFailureCheck اجرا شده باشه...");
  try {
    await (await registry.connect(v1).confirmDelivery(decisionId)).wait();
    console.log("❌❌❌ باگ تأیید شد: confirmDelivery موفق شد، درحالی‌که رخداد جمعی هنوز ارزیابی نشده!");
  } catch (e) {
    console.log("✅ درست: confirmDelivery رد شد —", e.reason || e.shortMessage);
    console.log("(اگه این پیام دیده بشه، یعنی باگ قبلاً اصلاح شده یا هنوز اصلاح نشده - چک بالا رو ببین)");
    return;
  }

  // اگه به اینجا رسیدیم، باگ واقعیه - ادامه بدیم تا نشون بدیم می‌شه جریمه رو کامل اجرا کرد
  await (await registry.connect(v1).fileAppeal(decisionId)).wait();
  console.log("❌ fileAppeal هم موفق شد (بدون این‌که رخداد جمعی چک شده باشه)");

  await hre.network.provider.send("evm_increaseTime", [7 * 86400 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveAppealIfExpired(decisionId)).wait();

  let decision = await registry.statusDecisions(decisionId);
  console.log("\nslashOutcome نهایی (قبل از این‌که اصلاً رخداد جمعی چک بشه):", decision.slashOutcome.toString());
  console.log("(این یعنی جریمه قطعی شد/رد شد، بدون این‌که هیچ‌وقت معلوم بشه این رخداد جمعی بوده یا نه!)");

  // حالا سعی کن resolveMassFailureCheck رو صدا بزنی - باید یا شکست بخوره یا بی‌معنی باشه چون پرونده قبلاً بسته شده
  try {
    await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
    await hre.network.provider.send("evm_mine");
    await (await registry.resolveMassFailureCheck(decisionId)).wait();
    console.log("resolveMassFailureCheck هم بعداً موفق شد (ولی بی‌فایده، چون slashOutcome قبلاً نهایی شده)");
  } catch (e) {
    console.log("resolveMassFailureCheck رد شد:", e.reason || e.shortMessage);
  }

  console.log("\n❌❌❌ نتیجه: باگ بحرانی گزارش‌شده توسط ژپتو کاملاً تأیید و بازتولید شد.");
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
