// L03 (audit 2026-09-30) — a correct payment must not be rejected because of an unrelated time base, and the settlement
// backlog must not grow because of the contract. Same script runs against the pre-fix source (violations shown as ❌)
// and the fixed source. Uses realistic block counts (one 23-24 h cycle ≈ 27,600-28,800 blocks) mined with
// hardhat_mine(count, interval) so block.number and block.timestamp advance together, as on a real chain.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111",
      REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 200); } }
const mine = (n, interval) => hre.network.provider.send("hardhat_mine", ["0x" + n.toString(16), "0x" + interval.toString(16)]);
const head = () => hre.ethers.provider.getBlockNumber();
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { mapping(address=>bool) public ever;
  function setEver(address a, bool v) external { ever[a]=v; }
  function isValidator(address a) external view returns (bool) { return ever[a]; }
  function everActivated(address a) external view returns (bool) { return ever[a]; } }
contract Sink { receive() external payable {} }`;

(async () => {
  const [deployer, oracle, v1, v2, stranger] = await hre.ethers.getSigners();
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const M = out.contracts["M.sol"];
  await put(REG, M.MockRegistry.abi, "0x" + M.MockRegistry.evm.bytecode.object);
  await put(FOUND, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object); await put(TRES, M.Sink.abi, "0x" + M.Sink.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(x => x.label === n).slot));
  const set = (n, v) => hre.network.provider.send("hardhat_setStorageAt", [DIST, S(n), hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
  await set("distributionOracle", oracle.address); await set("validatorDirectShareBps", 5000);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + (10n ** 30n).toString(16)]);
  const reg = new hre.ethers.Contract(REG, M.MockRegistry.abi, deployer);
  await reg.setEver(v1.address, true); await reg.setEver(v2.address, true);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  const E = hre.ethers.parseEther;
  // Pay a contiguous range to two validators, splitting the blocks 60/40 (sum == range length, i.e. every block attributed).
  const pay = (from, to) => { const n = to - from + 1, a = Math.floor(n * 0.6); return d.distributeRewards({ fromBlock: from, toBlock: to }, [v1.address, v2.address], [a, n - a], E(String(2 * n)), 0); };
  const tryPay = async (from, to) => { try { await (await pay(from, to)).wait(); return { ok: true }; } catch (e) { return { ok: false, msg: msgOf(e) }; } };
  const snap0 = await hre.network.provider.send("evm_snapshot");

  // ---------------------------------------------------------------- A: exact 3 s, settling behind head
  console.log("=== A — آهنگ دقیق ۳ ثانیه؛ تسویه‌ی عقب‌تر از head ===");
  await mine(1000, 3);
  await (await pay(1, 900)).wait(); // previous distribution executed at height ~1001 but settled only up to 900
  await mine(28800, 3); // one day at exactly 3 s
  const hA = await head(); const toA = 29800;
  ok(`A.1) head=${hA}؛ بازه‌ی ۹۰۱..۲۹۸۰۰ کاملاً در گذشته است`, toA < hA);
  const rA = await tryPay(901, toA);
  ok("A.2) پرداخت بازه‌ی صحیح ۲۸٬۹۰۰ بلاکی (۹۰۱..۲۹۸۰۰) رد نشد", rA.ok === true || rA.msg.slice(0, 160));

  // ---------------------------------------------------------------- B: several delayed cycles at 3 s
  await hre.network.provider.send("evm_revert", [snap0]); let snap = await hre.network.provider.send("evm_snapshot");
  console.log("\n=== B — شش چرخه با تأخیر متغیر اسکن/ارسال، آهنگ ۳ ثانیه ===");
  await mine(2000, 3); await (await pay(1, 1990)).wait();
  let settled = 1990; const lags = [400, 20, 900, 5, 600, 0], extraDelaySec = [60, 1800, 5400, 600, 7200, 300] // every cycle waits >= 23 h (the separate MIN_DISTRIBUTION_INTERVAL rule);
  let rejectedB = 0, maxBacklogB = 0;
  for (let c = 0; c < lags.length; c++) {
    await mine(Math.ceil((23 * 3600 + extraDelaySec[c]) / 3), 3);
    const to = (await head()) - lags[c]; const r = await tryPay(settled + 1, to);
    if (r.ok) settled = to; else rejectedB++;
    const backlog = (await head()) - settled; maxBacklogB = Math.max(maxBacklogB, backlog);
    console.log(`   چرخه ${c + 1}: lag=${lags[c]} → ${r.ok ? "پذیرفته" : "رد: " + r.msg.slice(0, 110)}؛ عقب‌ماندگی=${backlog}`);
  }
  ok("B.1) هیچ پرداخت صحیحی در شش چرخه‌ی تأخیردار رد نشد", rejectedB === 0 || `${rejectedB} رد`);
  ok("B.2) عقب‌ماندگی فقط به تأخیر خود اوراکل محدود ماند (≤ بیشینه‌ی lag + ۲)", maxBacklogB <= 902 || `max=${maxBacklogB}`);

  // ---------------------------------------------------------------- C: 2.95 s cadence model
  await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot");
  console.log("\n=== C — مدل آهنگ ۲٫۹۵ ثانیه (۲۶٬۶۶۶ بلاک ×۳s + ۱٬۴۰۲ بلاک ×۲s ≈ ۲۸٬۰۶۸ بلاک در ۲۳ ساعت) ===");
  await mine(2000, 3); await (await pay(1, 1999)).wait();
  settled = 1999; let rejectedC = 0; const backlogC = [];
  for (let c = 0; c < 6; c++) {
    await mine(26666, 3); await mine(1402, 2);
    const to = (await head()) - 1; let r = await tryPay(settled + 1, to);
    if (!r.ok) { // pre-fix workaround the audit rejects: shorten the range to what the time cap allows
      rejectedC++;
      const now = (await hre.ethers.provider.getBlock("latest")).timestamp + 1;
      const last = Number(await d.lastDistributionTime()); const cap = Math.floor((now - last) / 3);
      const r2 = await tryPay(settled + 1, settled + cap); if (r2.ok) settled = settled + cap;
    } else settled = to;
    backlogC.push((await head()) - settled);
    console.log(`   چرخه ${c + 1}: ${r.ok ? "پذیرفته (کل بازه)" : "کل بازه رد شد؛ کوتاه‌شده پرداخت شد"}؛ عقب‌ماندگی=${backlogC[c]}`);
  }
  ok("C.1) با آهنگ ۲٫۹۵ ثانیه هیچ پرداخت کامل و صحیحی رد نشد", rejectedC === 0 || `${rejectedC}/6 رد`);
  ok("C.2) عقب‌ماندگی رشد نکرد (چرخه‌ی آخر ≤ چرخه‌ی اول)", backlogC[5] <= backlogC[0] || `از ${backlogC[0]} به ${backlogC[5]}`);

  // ---------------------------------------------------------------- D: invalid reports must still be rejected
  await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot");
  console.log("\n=== D — گزارش‌های نامعتبر همچنان رد می‌شوند ===");
  await mine(2000, 3); await (await pay(1, 1000)).wait(); await mine(28000, 3);
  const h = await head();
  ok("D.1) بازه‌ی تکراری", await reverts(() => pay(1, 1000), "start right after the last settled block"));
  ok("D.2) بازه‌ی هم‌پوشان", await reverts(() => pay(900, 5000), "start right after the last settled block"));
  ok("D.3) بازه با فاصله (بلاک ۱۰۰۱ جا افتاده)", await reverts(() => pay(1002, 5000), "start right after the last settled block"));
  // NOTE: in Hardhat a reverted tx still mines a block, so head must be read right before this call (the tx lands in head+1).
  ok("D.4) بازه‌ای که بلاک جاری خود تراکنش را شامل می‌شود", await reverts(async () => pay(1001, (await head()) + 1), "not yet produced"));
  ok("D.4b) بازه‌ای که به بلاک آینده می‌رسد", await reverts(async () => pay(1001, (await head()) + 50), "not yet produced"));
  ok("D.5) مجموع بلاک‌های گزارش‌شده بیش از طول بازه", await reverts(() => d.distributeRewards({ fromBlock: 1001, toBlock: 1100 }, [v1.address, v2.address], [60, 41], E("1"), 0), "exceed the range size"));
  ok("D.6) آدرسی که هرگز فعال نشده", await reverts(() => d.distributeRewards({ fromBlock: 1001, toBlock: 1100 }, [stranger.address], [100], E("1"), 0), "never a legitimate validator"));
  ok("D.7) فراخوان غیر اوراکل", await reverts(() => d.connect(stranger).distributeRewards({ fromBlock: 1001, toBlock: 1100 }, [v1.address], [100], E("1"), 0), "caller is not the distribution oracle"));
  await (await pay(1001, 2000)).wait();
  ok("D.8) توزیع زودتر از فاصله‌ی ۲۳ ساعته", await reverts(() => pay(2001, 3000), "too soon since last distribution"));
  ok("D.9) مبلغ بیش از موجودی قرارداد", await reverts(async () => { await hre.network.provider.send("evm_increaseTime", [23 * 3600 + 1]); await hre.network.provider.send("evm_mine"); return d.distributeRewards({ fromBlock: 2001, toBlock: 3000 }, [v1.address], [1000], 10n ** 31n, 0); }, "insufficient contract balance"));

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
