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

  // ست‌کردن همه‌ی state variable هایی که constructor implicit باید ست می‌کرد ولی چون فقط
  // deployedBytecode کپی شده (نه storage)، دستی لازمه
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
  // برای رد شدن از rate limit (فقط ۱ ثبت‌نام در هر ۲۴ ساعت)، هربار کمی زمان جلو می‌بریم
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
  throw new Error("رویداد StatusDecisionRecorded پیدا نشد");
}

async function main() {
  console.log("=== راه‌اندازی ===");
  await setupRegistry();
  console.log("✅ Registry دیپلوی و پارامترها ست شدند");

  console.log("\n=== سناریوی ۱: ثبت‌نام و فعال‌سازی ۱۰ ولیدیتور (تا تعلیق ۱ نفر رخداد جمعی نشه: ۱۰٪ < ۲۰٪) ===");
  const allValidators = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10];
  for (const val of allValidators) {
    await registerAndActivate(val);
  }
  for (const val of allValidators) {
    await activateAfterProbation(val);
  }
  let info = await registry.getValidatorInfo(v1.address);
  if (Number(info[0]) !== 2) throw new Error("فعال‌سازی v1 شکست خورد!");
  const activeCount = await registry.getActiveValidatorCount();
  console.log("✅ همه‌ی " + activeCount.toString() + " ولیدیتور فعال شدند");

  console.log("\n=== سناریوی ۲: تعلیق v1 + بدون رخداد جمعی + بی‌اعتراض (جریمه‌ی خودکار) ===");
  const evidenceHash2 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v1"));
  const tx2 = await registry.connect(verifierSigner).recordSuspension(v1.address, evidenceHash2);
  const receipt2 = await tx2.wait();
  const d1 = decisionIdFromReceipt(receipt2, 1); // Suspension
  console.log("decisionId:", d1.toString());

  info = await registry.getValidatorInfo(v1.address);
  if (Number(info[0]) !== 3) throw new Error("تعلیق v1 شکست خورد!");
  console.log("✅ حذف فوری از لیست فعال تأیید شد");

  try {
    await registry.resolveMassFailureCheck(d1);
    throw new Error("نباید موفق می‌شد!");
  } catch (e) {
    if (e.message.includes("نباید")) throw e;
    console.log("✅ resolveMassFailureCheck زودهنگام درست رد شد");
  }

  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(d1)).wait();
  let decision = await registry.statusDecisions(d1);
  if (Number(decision.slashOutcome) !== 0) throw new Error("باید Undetermined بمونه (رخداد جمعی نبود)!");
  console.log("✅ رخداد جمعی رد شد (فقط ۱ دموت)، پرونده به فاز تحویل رفت");

  await (await registry.connect(v1).confirmDelivery(d1)).wait();
  decision = await registry.statusDecisions(d1);
  if (Number(decision.delivery) !== 2) throw new Error("تأیید تحویل شکست خورد!");
  console.log("✅ خودتأییدی تحویل موفق");

  await hre.network.provider.send("evm_increaseTime", [72 * 3600 + 1]);
  await hre.network.provider.send("evm_mine");

  const balBefore = await hre.ethers.provider.getBalance(TREASURY_ADDR);
  await (await registry.executeUncontestedSlash(d1)).wait();
  const balAfter = await hre.ethers.provider.getBalance(TREASURY_ADDR);
  console.log("سورن جریمه رسیده به خزانه:", hre.ethers.formatEther(balAfter - balBefore));
  decision = await registry.statusDecisions(d1);
  if (Number(decision.slashOutcome) !== 6) throw new Error("اجرای جریمه‌ی بی‌اعتراض شکست خورد!");
  console.log("✅ جریمه‌ی بی‌اعتراض با موفقیت اجرا شد (SlashOutcome=ExecutedUncontested)");

  console.log("\n=== سناریوی ۳: رخداد جمعی (mass-failure) — معافیت خودکار جریمه ===");
  // ۹ ولیدیتور فعال باقی مونده (v2..v10). دموت ۲ تا (v2, v3) توی همون پنجره‌ی ۱ساعته:
  // epoch با اولین دموت باز میشه: referenceCount = 8(بعد حذف v2)+1 = 9. دومین دموت (v3) توی
  // همون پنجره: demotionCount=2. آیا 2*10000=20000 > 9*2000=18000؟ بله، پس رخداد جمعیه.
  const evV2 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v2"));
  const txV2 = await registry.connect(verifierSigner).recordSuspension(v2.address, evV2);
  const rV2 = await txV2.wait();
  const dV2 = decisionIdFromReceipt(rV2, 1);

  const evV3 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v3"));
  const txV3 = await registry.connect(verifierSigner).recordSuspension(v3.address, evV3);
  const rV3 = await txV3.wait();
  const dV3 = decisionIdFromReceipt(rV3, 1);

  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dV2)).wait();

  let decV2 = await registry.statusDecisions(dV2);
  let decV3 = await registry.statusDecisions(dV3);
  console.log("slashOutcome v2:", decV2.slashOutcome.toString(), "(باید 1=ExemptMassFailure باشه)");
  if (Number(decV2.slashOutcome) !== 1) throw new Error("معافیت رخداد جمعی v2 شکست خورد!");
  console.log("✅ v2 معاف از جریمه شد (رخداد جمعی)");

  // v3 هنوز resolveMassFailureCheck نشده جداگانه — باید صداش بزنیم چون هرکدوم decision جدا داره
  await (await registry.resolveMassFailureCheck(dV3)).wait();
  decV3 = await registry.statusDecisions(dV3);
  if (Number(decV3.slashOutcome) !== 1) throw new Error("معافیت رخداد جمعی v3 شکست خورد!");
  console.log("✅ v3 هم معاف از جریمه شد — همه‌ی دموت‌های یه رخداد جمعی، یه سرنوشت یکسان دارن");

  console.log("\n=== سناریوی ۴: اعتراض موفق (رأی مجمع، جریمه تأیید می‌شه) ===");
  const evV4 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v4"));
  const txV4 = await registry.connect(verifierSigner).recordSuspension(v4.address, evV4);
  const rV4 = await txV4.wait();
  const dV4 = decisionIdFromReceipt(rV4, 1);
  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dV4)).wait();
  let decV4 = await registry.statusDecisions(dV4);
  console.log("slashOutcome v4 بعد از mass-failure check:", decV4.slashOutcome.toString(), "(باید 0=Undetermined باشه، چون فقط ۱ دموته)");

  await (await registry.connect(v4).confirmDelivery(dV4)).wait();
  await (await registry.connect(v4).fileAppeal(dV4)).wait();
  decV4 = await registry.statusDecisions(dV4);
  console.log("requiredConfirmVotes:", decV4.requiredConfirmVotes.toString());

  // مجمع فعلی: v5..v10 (6 نفر فعال). نصاب = (6/2)+1 = 4
  const activeVoters = [v5, v6, v7, v8, v9, v10];
  const balBeforeV4 = await hre.ethers.provider.getBalance(TREASURY_ADDR);
  for (let i = 0; i < 4; i++) {
    await (await registry.connect(activeVoters[i]).confirmSlash(dV4)).wait();
  }
  decV4 = await registry.statusDecisions(dV4);
  const balAfterV4 = await hre.ethers.provider.getBalance(TREASURY_ADDR);
  console.log("سورن جریمه‌ی v4 رسیده به خزانه:", hre.ethers.formatEther(balAfterV4 - balBeforeV4));
  console.log("slashOutcome v4 نهایی:", decV4.slashOutcome.toString(), "(باید 3=Confirmed باشه)");
  if (Number(decV4.slashOutcome) !== 3) throw new Error("تأیید جریمه با رأی مجمع شکست خورد!");
  console.log("✅ اعتراض ثبت شد، مجمع رأی داد، جریمه تأیید و اجرا شد");

  console.log("\n=== سناریوی ۵: اعتراض بدون رسیدن به نصاب — جریمه رد می‌شه ===");
  const evV5 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v5"));
  const txV5 = await registry.connect(verifierSigner).recordSuspension(v5.address, evV5);
  const rV5 = await txV5.wait();
  const dV5 = decisionIdFromReceipt(rV5, 1);
  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dV5)).wait();
  await (await registry.connect(v5).confirmDelivery(dV5)).wait();
  await (await registry.connect(v5).fileAppeal(dV5)).wait();
  // هیچ‌کس رأی نمی‌ده — فقط زمان رأی‌گیری (۷ روز) رو رد می‌کنیم
  await hre.network.provider.send("evm_increaseTime", [7 * 86400 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveAppealIfExpired(dV5)).wait();
  const decV5 = await registry.statusDecisions(dV5);
  console.log("slashOutcome v5:", decV5.slashOutcome.toString(), "(باید 5=RejectedNoQuorum باشه)");
  if (Number(decV5.slashOutcome) !== 5) throw new Error("رد جریمه به‌خاطر نبود نصاب شکست خورد!");
  const infoV5 = await registry.getValidatorInfo(v5.address);
  console.log("وضعیت v5 بعد از رد جریمه:", infoV5[0].toString(), "(باید 3=Demoted بمونه — تعلیق خودکار لغو نمیشه)");
  if (Number(infoV5[0]) !== 3) throw new Error("v5 نباید خودکار به Active برگرده!");
  console.log("✅ جریمه رد شد (نبود نصاب)، ولی تعلیق اجماعی دست‌نخورده موند");

  console.log("\n=== سناریوی ۶: اختلاف تحویل — ولیدیتور تأیید نمی‌کنه، مجمع رأی می‌ده ===");
  const evV6 = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("suspension-v6"));
  const txV6 = await registry.connect(verifierSigner).recordSuspension(v6.address, evV6);
  const rV6 = await txV6.wait();
  const dV6 = decisionIdFromReceipt(rV6, 1);
  await hre.network.provider.send("evm_increaseTime", [3600 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.resolveMassFailureCheck(dV6)).wait();

  // v6 خودش تحویل رو تأیید نمی‌کنه؛ بعد از grace period، Verifier مطرحش می‌کنه
  await hre.network.provider.send("evm_increaseTime", [7 * 86400 + 1]);
  await hre.network.provider.send("evm_mine");
  await (await registry.connect(verifierSigner).assertDeliveryDisputed(dV6)).wait();

  // مجمع فعلی: v7, v8, v9, v10 (۴ نفر). نصاب = (4/2)+1 = 3
  const remainingVoters = [v7, v8, v9, v10];
  for (let i = 0; i < 3; i++) {
    await (await registry.connect(remainingVoters[i]).voteOnDelivery(dV6, true)).wait();
  }
  const decV6 = await registry.statusDecisions(dV6);
  console.log("delivery status v6:", decV6.delivery.toString(), "(باید 2=Confirmed باشه)");
  if (Number(decV6.delivery) !== 2) throw new Error("تأیید تحویل با رأی مجمع شکست خورد!");
  console.log("✅ مجمع تحویل رو تأیید کرد؛ حالا اعتراض/جریمه‌ی معمولی ادامه پیدا می‌کنه");

  console.log("\n=== همه‌ی ۶ سناریو با موفقیت کامل تأیید شدند ===");
}

main().catch((e) => { console.error("❌ خطا:", e.message); process.exit(1); });
