// P06 (final decision) — initial caps 50,000 / 200,000; the 7-day delay applies to cap CHANGES only; no automatic 25% link.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const E = s => hre.ethers.parseEther(String(s));
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 200); } }
const MOCK = `pragma solidity ^0.8.24; contract R { address[] v; mapping(address=>bool) a; function add(address x) external { a[x]=true; v.push(x);} function isValidator(address x) external view returns (bool) { return a[x]; } function getValidators() external view returns (address[] memory) { return v; } }`;
(async () => {
  const signers = await hre.ethers.getSigners(); const deployer = signers[0], recipient = signers[19];
  const t = JSON.parse(fs.readFileSync("treasury_artifact.json"));
  // ۱) مقادیر اولیه — نسخه‌ی واقعی با اجرای مقداردهی‌ها (دیپلوی عادی)
  const real = await new hre.ethers.ContractFactory(t.abi, t.bytecode, deployer).deploy(); await real.waitForDeployment();
  ok("1) مقدار اولیه‌ی سقف هر پرداخت = ۵۰٬۰۰۰ سورن", (await real.perPaymentCap()) === E(50000));
  ok("2) مقدار اولیه‌ی سقف مجموع دوره = ۲۰۰٬۰۰۰ سورن", (await real.periodCap()) === E(200000));
  ok("3) تأخیر تغییر سقف = ۷ روز", (await real.CAP_CHANGE_TIMELOCK_DELAY()) === 7n * 86400n);
  ok("4) هیچ الزام خودکار نسبت ۲۵٪ در ABI نیست (نه تابع و نه ثابتِ نسبت)", !t.abi.some(f => /ratio|percent|quarter|25/i.test(f.name || "")));

  // ۲) رفتار روی زنجیره: کد + slotها (مثل تزریق genesis)، هیأت با impersonation، Registry ساختگی برای رأی مجمع
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const x = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await x.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await x.getAddress(), "latest"])]); };
  await put(REG, out.contracts["M.sol"].R.abi, "0x" + out.contracts["M.sol"].R.evm.bytecode.object);
  const TRES = "0x5555555555555555555555555555555555555555"; await put(TRES, t.abi, t.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(t.layout.storage.find(s => s.label === n).slot));
  await hre.network.provider.send("hardhat_setStorageAt", [TRES, S("perPaymentCap"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(E(50000)), 32)]);
  await hre.network.provider.send("hardhat_setStorageAt", [TRES, S("periodCap"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(E(200000)), 32)]);
  await hre.network.provider.send("hardhat_setBalance", [TRES, "0x" + (10n ** 25n).toString(16)]);
  const reg = new hre.ethers.Contract(REG, out.contracts["M.sol"].R.abi, deployer); for (let i = 2; i < 8; i++) await (await reg.add(signers[i].address)).wait();
  await hre.network.provider.send("hardhat_impersonateAccount", [BOARD]); await hre.network.provider.send("hardhat_setBalance", [BOARD, "0x" + (10n ** 20n).toString(16)]);
  const board = await hre.ethers.getSigner(BOARD); const tr = new hre.ethers.Contract(TRES, t.abi, deployer);
  const pay = (amt) => tr.connect(board).boardApproveExpenditure(recipient.address, E(amt), "p");

  const b0 = await hre.ethers.provider.getBalance(recipient.address); await (await pay(49999)).wait();
  ok("5) پرداخت عادی ۴۹٬۹۹۹ فوراً اجرا شد — بدون هیچ تأخیر ۷روزه (تأخیر فقط برای تغییر سقف است)", (await hre.ethers.provider.getBalance(recipient.address)) - b0 === E(49999));
  ok("6) پرداخت برابر سقف (۵۰٬۰۰۰) رد می‌شود (باید کمتر باشد)", await reverts(() => pay(50000), "outside per-payment cap"));
  for (let i = 0; i < 3; i++) await (await pay(49999)).wait();
  ok("7) مجموع ۴ پرداخت ۴۹٬۹۹۹ = ۱۹۹٬۹۹۶ زیر سقف دوره (۲۰۰٬۰۰۰) مجاز بود", true);
  ok("8) پرداخت پنجم (۵ سورن) مجموع را از ۲۰۰٬۰۰۰ رد می‌کند → رد", await reverts(() => pay(5), "period cap exceeded"));

  // تغییر سقف: رأی مجمع + تأخیر ۷ روز؛ پرداخت زیر سقف جدید در همان لحظه ممکن نیست
  const rc = await (await tr.connect(signers[2]).proposeCapChange(0, E(100000))).wait();
  const id = await tr.capChangeProposalCount(); for (let i = 3; i < 6; i++) await (await tr.connect(signers[i]).voteCapChange(id)).wait(); // پیشنهاددهنده + ۳ رأی = ۴ = اکثریت ۶ ولیدیتور
  const pc = await tr.pendingCapChange(0); ok("9) با رأی اکثریت مجمع، تغییر سقف هر پرداخت (→۱۰۰٬۰۰۰) در صف تأخیر قرار گرفت", pc.exists === true && pc.newValue === E(100000));
  ok("10) قبل از گذشت ۷ روز، اعمال تغییر رد می‌شود (timelock not elapsed)", await reverts(() => tr.applyPendingCapChange(0), "timelock not elapsed"));
  ok("11) در دوره‌ی تأخیر، سقف قدیمی هنوز حاکم است (۶۰٬۰۰۰ رد می‌شود)", (await reverts(() => pay(60000), "outside per-payment cap")) === true);
  await inc(7 * 86400 + 1); await (await tr.applyPendingCapChange(0)).wait();
  ok("12) پس از ۷ روز اعمال شد: سقف هر پرداخت = ۱۰۰٬۰۰۰ (و سقف مجموع دوره همچنان ۲۰۰٬۰۰۰، بدون پیوند خودکار ۲۵٪)", (await tr.perPaymentCap()) === E(100000) && (await tr.periodCap()) === E(200000));
  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
