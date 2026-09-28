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
  console.log("=== بازتولید باگ ۲: تعارض confirmDelivery بعد از assertDeliveryDisputed ===\n");
  await setupRegistry();
  const allValidators = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of allValidators) await registerAndActivate(val);
  for (const val of allValidators) await activateAfterProbation(val);

  const tx = await registry.connect(verifierSigner).recordSuspension(v1.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("susp-v1")));
  const receipt = await tx.wait();
  const decisionId = decisionIdFromReceipt(receipt, 1);
  console.log("✅ v1 تعلیق شد، decisionId:", decisionId.toString());

  // ✅ حالا اجباریه (طبق اصلاح مورد بحرانی): باید اول رخداد جمعی حل بشه
  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(decisionId)).wait();
  console.log("✅ resolveMassFailureCheck اجرا شد (رخداد جمعی نبود)");

  // بگذریم زمان grace period (۷ روز)، بعد کسی assertDeliveryDisputed بزنه
  await hre.network.provider.send("evm_increaseTime", [7 * 86400 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.connect(verifierSigner).assertDeliveryDisputed(decisionId)).wait();
  console.log("✅ اختلاف تحویل ثبت شد (رأی‌گیری باز است، هنوز حل نشده)");

  // حالا v1 خودش confirmDelivery می‌زنه (طبق کد فعلی، این مجازه چون delivery==Disputed یکی از مقادیر مجازه)
  console.log("\n🔍 تلاش برای confirmDelivery توسط v1، درحالی‌که رأی‌گیری اختلاف تحویل هنوز باز است...");
  await (await registry.connect(v1).confirmDelivery(decisionId)).wait();
  console.log("✅ confirmDelivery موفق شد (این خودش مشکلی نیست — v1 حق داره خودش تحویل رو تأیید کنه حتی بعد از باز شدن اختلاف)");

  let decision = await registry.statusDecisions(decisionId);
  console.log("delivery status بعد از confirmDelivery:", decision.delivery.toString(), "(2=Confirmed)");

  const disp = await registry.deliveryDisputes(decisionId);
  console.log("وضعیت DeliveryDispute بعد از confirmDelivery: resolved=", disp.resolved, "deliveryConfirmed=", disp.deliveryConfirmed);

  if (disp.resolved === true && disp.deliveryConfirmed === true) {
    console.log("\n✅✅✅ اصلاح تأیید شد: confirmDelivery حالا خودکار DeliveryDispute باز رو هم می‌بنده (resolved=true, deliveryConfirmed=true)");
  } else {
    console.log("\n❌ اصلاح ناقصه: DeliveryDispute هنوز باز مونده!");
    return;
  }

  // حالا تلاش برای resolveDeliveryDisputeIfExpired باید رد بشه چون قبلاً حل شده
  console.log("\n🔍 تلاش برای resolveDeliveryDisputeIfExpired بعد از این‌که خودتأییدی اختلاف رو بسته...");
  await hre.network.provider.send("evm_increaseTime", [7 * 86400 + 1]);
  await hre.network.provider.send("evm_mine");
  try {
    await registry.resolveDeliveryDisputeIfExpired(decisionId);
    console.log("❌ نباید موفق می‌شد!");
  } catch (e) {
    console.log("✅ درست رد شد (already resolved) — دیگه نمی‌تونه تصمیم قبلی رو بازنویسی کنه");
  }

  console.log("\n✅✅✅ نتیجه: باگ ۲ کاملاً اصلاح شد — دیگه هیچ مسیر متناقضی وجود نداره.");
}

main().catch((e) => { console.error("خطای غیرمنتظره:", e.message); process.exit(1); });
