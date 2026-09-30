// L07 (open finding, audit follow-up 2026-09-30) — CHARACTERIZATION test: documents what the current contract actually does
// when the same address appears more than once in `validators`. It asserts observed behaviour; it does NOT fix anything.
// Compared case: [v1:30, v1:30, v2:40]  vs  [v1:60, v2:40]  — same attribution, same range, same totals.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111",
      REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const MOCK = `pragma solidity ^0.8.24;
contract AllValid { function isValidator(address) external pure returns (bool) { return true; } function everActivated(address) external pure returns (bool) { return true; } }
contract Sink { receive() external payable {} }`;
async function runCase(label, list, counts, totalRewards, totalFees) {
  const [deployer, oracle, v1, v2] = await hre.ethers.getSigners();
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const M = out.contracts["M.sol"];
  await put(REG, M.AllValid.abi, "0x" + M.AllValid.evm.bytecode.object); await put(FOUND, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object); await put(TRES, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(x => x.label === n).slot));
  const set = (n, v) => hre.network.provider.send("hardhat_setStorageAt", [DIST, S(n), hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
  await set("distributionOracle", oracle.address); await set("validatorDirectShareBps", 5000);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + (10n ** 24n).toString(16)]);
  await hre.network.provider.send("hardhat_mine", ["0x80"]);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  const addr = { v1: v1.address, v2: v2.address };
  const b0 = { v1: await hre.ethers.provider.getBalance(v1.address), v2: await hre.ethers.provider.getBalance(v2.address), t: await hre.ethers.provider.getBalance(TRES) };
  const rc = await (await d.distributeRewards({ fromBlock: 1, toBlock: 100 }, list.map(k => addr[k]), counts, totalRewards, totalFees)).wait();
  const paid = { v1: (await hre.ethers.provider.getBalance(v1.address)) - b0.v1, v2: (await hre.ethers.provider.getBalance(v2.address)) - b0.v2 };
  const events = rc.logs.map(l => { try { return d.interface.parseLog(l); } catch (e) { return null; } }).filter(e => e && e.name === "ValidatorRewarded");
  const r = {
    paid, events: events.length,
    epochBlocksV1: await d.epochValidatorBlocks(1, v1.address), epochRewardV1: await d.epochValidatorRewardShare(1, v1.address),
    epochFeeV1: await d.epochValidatorFeeShare(1, v1.address), totalBlocksV1: await d.totalBlocksRecorded(v1.address),
    epoch: await d.getEpoch(1), dustLeft: (await hre.ethers.provider.getBalance(DIST)), treasury: (await hre.ethers.provider.getBalance(TRES)) - b0.t,
  };
  console.log(`   [${label}] v1 paid=${paid.v1} wei, v2 paid=${paid.v2} wei, ValidatorRewarded events=${r.events}, epochValidatorBlocks[v1]=${r.epochBlocksV1}, totalBlocksRecorded[v1]=${r.totalBlocksV1}`);
  return r;
}
(async () => {
  // totals chosen so that per-entry floor division leaves a remainder (validatorDirect = 50,000,000,000,000,000,001 wei; not divisible by 100)
  const TR = 100000000000000000003n, TF = 7n;
  const snap = await hre.network.provider.send("evm_snapshot");
  console.log("=== L07 — آدرس تکراری در فهرست validators (آزمون توصیفی رفتار فعلی) ===");
  const single = await runCase("بدون تکرار [v1:60, v2:40]", ["v1", "v2"], [60, 40], TR, TF);
  await hre.network.provider.send("evm_revert", [snap]);
  const dup = await runCase("با تکرار [v1:30, v1:30, v2:40]", ["v1", "v1", "v2"], [30, 30, 40], TR, TF);
  ok("L07.1) فهرست دارای آدرس تکراری پذیرفته می‌شود (هیچ require جلوی آن را نمی‌گیرد)", dup.events === 3);
  const diff = single.paid.v1 - dup.paid.v1;
  ok("L07.2) مبلغ نهایی v1 با تکرار حداکثر به اندازه‌ی گردکردن‌های اضافی (≤ ۲ wei) کمتر است؛ پول اضافه‌ای خارج از تقسیم اوراکل پرداخت نمی‌شود",
     diff >= 0n && diff <= 2n, `اختلاف=${diff} wei`);
  ok("L07.3) v2 در هر دو حالت دقیقاً یکسان دریافت کرد", single.paid.v2 === dup.paid.v2);
  ok("L07.4) هر ورودی جداگانه پردازش و یک رویداد ValidatorRewarded جدا منتشر می‌شود (۳ به‌جای ۲)", dup.events === 3 && single.events === 2);
  ok("L07.5) رکورد هر-epoch بازنویسی می‌شود نه جمع: epochValidatorBlocks[v1]=۳۰ در حالی که برای ۶۰ بلاک پرداخت شده",
     dup.epochBlocksV1 === 30n && single.epochBlocksV1 === 60n, `dup=${dup.epochBlocksV1}, single=${single.epochBlocksV1}`);
  ok("L07.6) رکورد پاداش هر-epoch هم فقط سهم آخرین ورودی را نشان می‌دهد (حدود نصف مبلغ پرداخت‌شده‌ی v1)",
     dup.epochRewardV1 * 2n <= dup.paid.v1 + 2n && dup.epochRewardV1 < dup.paid.v1);
  ok("L07.7) جمع طول‌عمر (totalBlocksRecorded) درست جمع می‌شود (۶۰ در هر دو حالت)", dup.totalBlocksV1 === 60n && single.totalBlocksV1 === 60n);
  console.log(`   دریافتی خزانه: بدون تکرار=${single.treasury}، با تکرار=${dup.treasury}؛ موجودی باقی‌مانده‌ی قرارداد برابر: ${single.dustLeft === dup.dustLeft}`);
  // Correction: the first version of this check assumed dust stays in the contract. _finalizeEpoch routes reward/fee rounding
  // dust to the treasury by design, so the extra rounding of a duplicate entry moves wei from the validator to the treasury.
  ok("L07.8) گردکردن اضافه‌ی ورودی تکراری به خزانه می‌رود (طبق _finalizeEpoch)، نه در قرارداد می‌ماند", dup.treasury - single.treasury === diff && dup.dustLeft === single.dustLeft, `Δخزانه=${dup.treasury - single.treasury}`);
  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر (آزمون توصیفی؛ L07 باز است)`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
