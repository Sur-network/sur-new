// راستی‌آزمایی سیاست نهایی: پرداخت مستقیم به تولیدکننده‌ی واقعی، صرف‌نظر از وضعیت فعلی؛ everActivated جایگزین isValidator.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111", REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry {
    mapping(address=>bool) public act; mapping(address=>bool) public ever;
    function activate(address a) external { act[a]=true; ever[a]=true; }
    function deactivate(address a) external { act[a]=false; } // خروج/تعلیق: isValidator=false ولی everActivated همچنان true
    function isValidator(address a) external view returns (bool) { return act[a]; }
    function everActivated(address a) external view returns (bool) { return ever[a]; }
}
contract Sink { receive() external payable {} }`;
(async () => {
  const [deployer, oracle, A, B, C, stranger] = await hre.ethers.getSigners();
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const regArt = out.contracts["M.sol"].MockRegistry;
  await put(REG, regArt.abi, "0x" + regArt.evm.bytecode.object);
  await put(FOUND, out.contracts["M.sol"].Sink.abi, "0x" + out.contracts["M.sol"].Sink.evm.bytecode.object);
  await put(TRES, out.contracts["M.sol"].Sink.abi, "0x" + out.contracts["M.sol"].Sink.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, S("distributionOracle"), hre.ethers.zeroPadValue(oracle.address, 32)]);
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, S("validatorDirectShareBps"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(5000), 32)]);
  const membershipSlot = S("pendingMembershipFees");
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, membershipSlot, hre.ethers.zeroPadValue(hre.ethers.toBeHex(hre.ethers.parseEther("300")), 32)]);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + hre.ethers.parseEther("5000").toString(16)]);
  const reg = new hre.ethers.Contract(REG, regArt.abi, deployer);
  await reg.activate(A.address); await reg.activate(B.address); await reg.activate(C.address);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  await hre.network.provider.send("hardhat_mine", ["0x100"]);
  const E = (n) => hre.ethers.parseEther(String(n));

  console.log("=== گام ۰: بازتولید باگ روی رفتار قدیم (شبیه‌سازی isValidator) — B را غیرفعال کن، تلاش برای پرداختش ===");
  await reg.deactivate(B.address);
  // شبیه‌سازی چک قدیمی: چون کد واقعی الان already fixed است، این فقط برای اثبات اینکه لایه‌ی everActivated واقعاً استفاده می‌شود:
  console.log("isValidator(B) الان:", await reg.isValidator(B.address), "| everActivated(B):", await reg.everActivated(B.address));

  console.log("\n=== گام ۱: توزیع واقعی — ۱۰۰ بلاک؛ A=۶۰ (فعال)، B=۱۰ (تولید کرده حین Active بودن، الان خارج/معلق)، C=۳۰ (فعال) ===");
  const bB0 = await hre.ethers.provider.getBalance(B.address);
  const bA0 = await hre.ethers.provider.getBalance(A.address);
  const bC0 = await hre.ethers.provider.getBalance(C.address);
  const bT0 = await hre.ethers.provider.getBalance(TRES);
  const bF0 = await hre.ethers.provider.getBalance(FOUND);
  const r = await d.distributeRewards({ fromBlock: 1, toBlock: 100 }, [A.address, B.address, C.address], [60, 10, 30], E(1000), E(200));
  const rc = await r.wait();
  console.log("نتیجه‌ی تراکنش: status =", rc.status, "| gasUsed =", rc.gasUsed.toString());

  const paidA = (await hre.ethers.provider.getBalance(A.address)) - bA0;
  const paidB = (await hre.ethers.provider.getBalance(B.address)) - bB0;
  const paidC = (await hre.ethers.provider.getBalance(C.address)) - bC0;
  const paidT = (await hre.ethers.provider.getBalance(TRES)) - bT0;
  const paidF = (await hre.ethers.provider.getBalance(FOUND)) - bF0;

  console.log("\n--- نتایج ---");
  console.log("A (۶۰ بلاک، هنوز فعال) دریافت کرد:", hre.ethers.formatEther(paidA));
  console.log("B (۱۰ بلاک، الان خارج/معلق) دریافت کرد:", hre.ethers.formatEther(paidB), "  ← باید غیرصفر و مستقیم پرداخت‌شده باشد");
  console.log("C (۳۰ بلاک، هنوز فعال) دریافت کرد:", hre.ethers.formatEther(paidC));
  console.log("خزانه:", hre.ethers.formatEther(paidT), "| بنیاد:", hre.ethers.formatEther(paidF));

  // محاسبه‌ی مقادیر مورد انتظار طبق فرمول واقعی قرارداد
  const foundationExpected = E(1000) * 1500n / 10000n;
  const validatorDirectExpected = E(1000) * 5000n / 10000n;
  const treasuryExpected = E(1000) - foundationExpected - validatorDirectExpected;
  const feeBurnExpected = E(200) * 3000n / 10000n;
  const ordinaryFeesToDistribute = E(200) - feeBurnExpected;
  const membershipPool = E(300);
  const totalBlocks = 100n;
  const expected = (blocks) => (validatorDirectExpected * blocks / totalBlocks) + (ordinaryFeesToDistribute * blocks / totalBlocks) + (membershipPool * blocks / totalBlocks);

  console.log("\n🔍 تطبیق دقیق با فرمول قرارداد (نه فقط تخمین):");
  console.log("انتظار A (۶۰ بلاک):", hre.ethers.formatEther(expected(60n)), "| واقعی:", hre.ethers.formatEther(paidA), paidA === expected(60n) ? "✅" : "❌");
  console.log("انتظار B (۱۰ بلاک):", hre.ethers.formatEther(expected(10n)), "| واقعی:", hre.ethers.formatEther(paidB), paidB === expected(10n) ? "✅" : "❌");
  console.log("انتظار C (۳۰ بلاک):", hre.ethers.formatEther(expected(30n)), "| واقعی:", hre.ethers.formatEther(paidC), paidC === expected(30n) ? "✅" : "❌");
  console.log("انتظار خزانه:", hre.ethers.formatEther(treasuryExpected), "| واقعی:", hre.ethers.formatEther(paidT), paidT === treasuryExpected ? "✅" : "❌");
  console.log("انتظار بنیاد:", hre.ethers.formatEther(foundationExpected), "| واقعی:", hre.ethers.formatEther(paidF), paidF === foundationExpected ? "✅" : "❌");

  console.log("\n🔍 چک تراز کامل: آیا سهم ۹۰ بلاک باقی‌مانده (A+C) فقط سهم واقعی خودشان است، نه سهم B را هم بلعیده‌اند؟");
  const noWindfall = paidA === expected(60n) && paidC === expected(30n);
  console.log(noWindfall ? "✅ بدون بادآورده — هرکس دقیقاً سهم بلاک‌های خودش را گرفت" : "❌ بادآورده‌ی ناخواسته رخ داد");

  const totalIn = E(1000) + E(200) + E(300);
  const totalOut = paidA + paidB + paidC + paidT + paidF + feeBurnExpected;
  console.log("\n🔍 چک تراز نهایی: ورودی کل =", hre.ethers.formatEther(totalIn), "| خروجی کل (پرداخت‌ها+خزانه+بنیاد+سوزاندن) =", hre.ethers.formatEther(totalOut), totalIn === totalOut ? "✅ دقیقاً برابر" : "❌ ناهمخوان");

  console.log("\n=== گام ۲: تلاش پرداخت به آدرسی که هرگز ولیدیتور نبوده — باید رد شود ===");
  try {
    await hre.network.provider.send("hardhat_mine", ["0x10"]);
    await d.distributeRewards({ fromBlock: 101, toBlock: 110 }, [stranger.address], [10], E(10), E(0));
    console.log("❌ باید رد می‌شد!");
  } catch (e) { console.log("✅ درست رد شد:", e.reason || e.shortMessage); }

  const allOk = paidA === expected(60n) && paidB === expected(10n) && paidC === expected(30n) && paidT === treasuryExpected && paidF === foundationExpected && totalIn === totalOut;
  process.exit(allOk ? 0 : 1);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
