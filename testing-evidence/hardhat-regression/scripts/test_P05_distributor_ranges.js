// P05 (final decision) — each distribution declares its real block range; the contract keeps the last settled block.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111", REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 220); } }
const MOCK = `pragma solidity ^0.8.24; contract AllValid { function isValidator(address) external pure returns (bool) { return true; } } contract Sink { receive() external payable {} }`;
(async () => {
  const [deployer, oracle, v1, v2] = await hre.ethers.getSigners();
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  await put(REG, out.contracts["M.sol"].AllValid.abi, "0x" + out.contracts["M.sol"].AllValid.evm.bytecode.object);
  await put(FOUND, out.contracts["M.sol"].Sink.abi, "0x" + out.contracts["M.sol"].Sink.evm.bytecode.object);
  await put(TRES, out.contracts["M.sol"].Sink.abi, "0x" + out.contracts["M.sol"].Sink.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
  const set = (n, v) => hre.network.provider.send("hardhat_setStorageAt", [DIST, S(n), hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
  await set("distributionOracle", oracle.address); await set("validatorDirectShareBps", 5000); // initializers don't run on injection
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + (10n ** 24n).toString(16)]);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  await hre.network.provider.send("hardhat_mine", ["0x400"]); // 1024 blocks so ranges below are in the past
  const R = (a, b) => ({ fromBlock: a, toBlock: b });
  const dist = (a, b, blocks) => d.distributeRewards(R(a, b), [v1.address, v2.address], blocks, hre.ethers.parseEther("100"), 0);

  ok("0) lastSettledBlock ابتدا ۰", (await d.lastSettledBlock()) === 0n);
  ok("1) اولین بازه باید از بلاک ۱ شروع شود (از ۲: رد)", await reverts(() => dist(2, 100, [60, 40]), "start right after the last settled block"));
  const rc = await (await dist(1, 100, [60, 40])).wait();
  ok("2) بازه‌ی ۱..۱۰۰ پذیرفته شد؛ lastSettledBlock=100", (await d.lastSettledBlock()) === 100n);
  const rg = await d.epochBlockRanges(1); ok("3) بازه‌ی تسویه‌شده‌ی epoch ۱ ثبت شد (۱..۱۰۰)", rg.fromBlock === 1n && rg.toBlock === 100n);
  ok("4) رویداد EpochRangeSettled منتشر شد", rc.logs.some(l => { try { return d.interface.parseLog(l).name === "EpochRangeSettled"; } catch (e) { return false; } }));
  await inc(23 * 3600 + 1); // از این‌جا فقط کنترل بازه است که رد می‌کند، نه فاصله‌ی زمانی
  ok("5) بازه‌ی تکراری (۱..۱۰۰) رد شد", await reverts(() => dist(1, 100, [60, 40]), "start right after the last settled block"));
  ok("6) بازه‌ی هم‌پوشان (۵۰..۱۵۰) رد شد", await reverts(() => dist(50, 150, [60, 40]), "start right after the last settled block"));
  ok("7) بازه‌ی دارای فاصله‌ی توضیح‌نداده‌شده (۱۰۲..۲۰۰؛ بلاک ۱۰۱ جا افتاده) رد شد", await reverts(() => dist(102, 200, [60, 40]), "start right after the last settled block"));
  ok("8) بازه‌ی وارونه (۱۰۱..۱۰۰) رد شد", await reverts(() => dist(101, 100, [60, 40]), "empty or inverted"));
  const latest = await hre.ethers.provider.getBlockNumber();
  ok("9) بازه‌ای که به بلاک‌های هنوز تولیدنشده می‌رسد رد شد", await reverts(() => dist(101, latest + 1, [60, 40]), "not yet produced"));
  ok("10) مجموع بلاک‌های گزارش‌شده بیش از اندازه‌ی بازه (۱۰۱..۱۱۰ با مجموع ۱۶) رد شد", await reverts(() => dist(101, 110, [8, 8]), "exceed the range size"));
  ok("11) هیچ‌کدام از ردشدن‌ها وضعیت را تغییر نداد (lastSettledBlock=100، epochCount=1)", (await d.lastSettledBlock()) === 100n && (await d.epochCount()) === 1n);
  await (await dist(101, 200, [60, 40])).wait();
  ok("12) بازه‌ی پیوسته‌ی بعدی (۱۰۱..۲۰۰) پذیرفته شد", (await d.lastSettledBlock()) === 200n && (await d.epochBlockRanges(2)).fromBlock === 101n);
  await inc(23 * 3600 + 1); await (await dist(201, 250, [30, 10])).wait();
  ok("13) مجموع گزارش‌شده کمتر از اندازه‌ی بازه مجاز است (بلاک‌های فیلترشده‌ی تولیدکننده‌ی نامعتبر): ۲۰۱..۲۵۰ با مجموع ۴۰", (await d.lastSettledBlock()) === 250n);
  await inc(23 * 3600 + 1); const big = 1000;
  ok("14) پس از یک «قطعی» (بلاک‌های ۲۵۱..۹۰۰ تسویه نشده) بازه‌ی بعدی باید همه‌ی آن‌ها را بپوشاند: شروع از ۲۵۱ لازم است، نه پرش به ۵۰۱", await reverts(() => dist(501, 900, [200, 200]), "start right after the last settled block"));
  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
