// L07-A (owner decision 2026-09-30): Distributor requires STRICTLY ascending validator addresses; RewardRouter aggregates
// blocks per miner and sorts. Same script runs against the pre-change source (rejection checks fail) and the changed source.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111",
      REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 160); } }
const MOCK = `pragma solidity ^0.8.24;
contract AllValid { function isValidator(address) external pure returns (bool) { return true; } function everActivated(address) external pure returns (bool) { return true; } }
contract Sink { receive() external payable {} }`;
(async () => {
  const [deployer, oracle, s1, s2, s3] = await hre.ethers.getSigners();
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
  const [lo, mid, hi] = [s1.address, s2.address, s3.address].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  const E = hre.ethers.parseEther; const TR = E("1000"), TF = E("200");
  const R = { fromBlock: 1, toBlock: 100 };
  const ERR = "validators must be strictly ascending";

  console.log("=== L07-A — ترتیب صعودی اکید ===");
  ok("1) آدرس تکراری [lo, lo] رد می‌شود", await reverts(() => d.distributeRewards(R, [lo, lo], [50, 50], TR, TF), ERR));
  ok("2) تکرار غیرمجاور با تجمیع‌نشدن [lo, hi, lo] رد می‌شود", await reverts(() => d.distributeRewards(R, [lo, hi, lo], [30, 40, 30], TR, TF), ERR));
  ok("3) ترتیب نزولی [hi, lo] رد می‌شود", await reverts(() => d.distributeRewards(R, [hi, lo], [40, 60], TR, TF), ERR));
  ok("4) ورودی صفربلاکی نامرتب هم رد می‌شود [lo, hi, mid:0] (کنترل پیش از skip)", await reverts(() => d.distributeRewards(R, [lo, hi, mid], [60, 40, 0], TR, TF), ERR));
  ok("5) هیچ‌کدام از ردها state را تغییر نداد (lastSettledBlock = 0، epochCount = 0)", (await d.lastSettledBlock()) === 0n && (await d.epochCount()) === 0n);

  // RewardRouter-style aggregation of a would-be duplicate [lo:30, lo:30, hi:40] -> [lo:60, hi:40]
  const b0 = { lo: await hre.ethers.provider.getBalance(lo), hi: await hre.ethers.provider.getBalance(hi) };
  const rc = await (await d.distributeRewards(R, [lo, hi], [60, 40], TR, TF)).wait();
  const paid = { lo: (await hre.ethers.provider.getBalance(lo)) - b0.lo, hi: (await hre.ethers.provider.getBalance(hi)) - b0.hi };
  const direct = TR * 5000n / 10000n, fees = TF - TF * 3000n / 10000n, total = 100n;
  const expect = blocks => direct * blocks / total + fees * blocks / total;
  ok("6) فهرست مرتب و تجمیع‌شده [lo:60, hi:40] پذیرفته شد", rc.status === 1);
  ok("7) مبلغ lo دقیقاً طبق فرمول برای ۶۰ بلاک (معادل جمع دو ورودی تکراری سابق، بدون گردکردن اضافه)", paid.lo === expect(60n), `${paid.lo} == ${expect(60n)}`);
  ok("8) مبلغ hi دقیقاً طبق فرمول برای ۴۰ بلاک", paid.hi === expect(40n));
  ok("9) رکورد epoch برای lo برابر ۶۰ (نه بازنویسی‌شده)", (await d.epochValidatorBlocks(1, lo)) === 60n);
  ok("10) رکورد epoch برای hi برابر ۴۰", (await d.epochValidatorBlocks(1, hi)) === 40n);
  ok("11) رکورد پاداش epoch برای lo برابر سهم پرداخت‌شده‌ی پاداش", (await d.epochValidatorRewardShare(1, lo)) === direct * 60n / total);
  const evs = rc.logs.map(l => { try { return d.interface.parseLog(l); } catch (e) { return null; } }).filter(e => e && e.name === "ValidatorRewarded");
  ok("12) دقیقاً یک رویداد ValidatorRewarded برای هر تولیدکننده (۲)", evs.length === 2);
  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
