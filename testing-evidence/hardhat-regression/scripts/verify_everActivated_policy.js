// راستی‌آزمایی سیاست نهایی پاداش: everActivated جایگزین isValidator؛ پرداخت مستقیم به تولیدکننده‌ی واقعی صرف‌نظر از وضعیت فعلی.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", FOUND = "0x1111111111111111111111111111111111111111", REG = "0x3333333333333333333333333333333333333333", TRES = "0x5555555555555555555555555555555555555555";
let results = [];
function ok(name, cond, extra = "") { results.push(cond === true); console.log((cond === true ? "✅ " : "❌ ") + name + (cond === true ? "" : " → " + cond) + (extra ? "  " + extra : "")); }
async function reverts(fn, expectedSub) { try { await (await fn()).wait(); return false; } catch (e) { const msg = e.reason || e.shortMessage || e.message || ""; return msg.includes(expectedSub) ? true : "wrong reason: " + msg.slice(0, 160); } }
const E = (n) => hre.ethers.parseEther(String(n));
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };

// ===================== بخش ۱: سناریوی اصلی (تأییدشده قبلاً، بدون تغییر منطق) روی Mock ساده =====================
async function part1() {
  const [deployer, oracle, A, B, C, stranger] = await hre.ethers.getSigners();
  const MOCK = `pragma solidity ^0.8.24;
  contract MockRegistry {
      mapping(address=>bool) public act; mapping(address=>bool) public ever;
      function activate(address a) external { act[a]=true; ever[a]=true; }
      function deactivate(address a) external { act[a]=false; }
      function isValidator(address a) external view returns (bool) { return act[a]; }
      function everActivated(address a) external view returns (bool) { return ever[a]; }
  }
  contract Sink { receive() external payable {} }`;
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
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, S("pendingMembershipFees"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(E(300)), 32)]);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + E(5000).toString(16)]);
  const reg = new hre.ethers.Contract(REG, regArt.abi, deployer);
  await reg.activate(A.address); await reg.activate(B.address); await reg.activate(C.address);
  const d = new hre.ethers.Contract(DIST, art.abi, oracle);
  await hre.network.provider.send("hardhat_mine", ["0x100"]);

  console.log("=== بخش ۱ — سناریوی اصلی: ۱۰۰ بلاک؛ A=۶۰(فعال)، B=۱۰(تولید حین فعال‌بودن، الان خارج/معلق)، C=۳۰(فعال) ===");
  await reg.deactivate(B.address);
  const before = { A: await hre.ethers.provider.getBalance(A.address), B: await hre.ethers.provider.getBalance(B.address), C: await hre.ethers.provider.getBalance(C.address), T: await hre.ethers.provider.getBalance(TRES), F: await hre.ethers.provider.getBalance(FOUND) };
  // L07 (owner decision 2026-09-30): the contract now requires strictly ascending addresses -> sort, keeping each count paired
  const entries = [[A.address, 60], [B.address, 10], [C.address, 30]].sort((x, y) => (BigInt(x[0]) < BigInt(y[0]) ? -1 : 1));
  const r = await d.distributeRewards({ fromBlock: 1, toBlock: 100 }, entries.map(e => e[0]), entries.map(e => e[1]), E(1000), E(200));
  const rc = await r.wait();
  const paidA = (await hre.ethers.provider.getBalance(A.address)) - before.A;
  const paidB = (await hre.ethers.provider.getBalance(B.address)) - before.B;
  const paidC = (await hre.ethers.provider.getBalance(C.address)) - before.C;
  const paidT = (await hre.ethers.provider.getBalance(TRES)) - before.T;
  const paidF = (await hre.ethers.provider.getBalance(FOUND)) - before.F;

  const foundationExpected = E(1000) * 1500n / 10000n, validatorDirectExpected = E(1000) * 5000n / 10000n;
  const treasuryExpected = E(1000) - foundationExpected - validatorDirectExpected;
  const feeBurnExpected = E(200) * 3000n / 10000n, ordinaryFeesToDistribute = E(200) - feeBurnExpected, membershipPool = E(300), totalBlocks = 100n;
  const expected = (blocks) => (validatorDirectExpected * blocks / totalBlocks) + (ordinaryFeesToDistribute * blocks / totalBlocks) + (membershipPool * blocks / totalBlocks);

  ok("۱.۱) A (۶۰ بلاک) دقیقاً طبق فرمول", paidA === expected(60n), `${hre.ethers.formatEther(paidA)} == ${hre.ethers.formatEther(expected(60n))}`);
  ok("۱.۲) B (۱۰ بلاک، خارج/معلق) دقیقاً طبق فرمول — نه صفر، نه رد شد", paidB === expected(10n), `${hre.ethers.formatEther(paidB)} == ${hre.ethers.formatEther(expected(10n))}`);
  ok("۱.۳) C (۳۰ بلاک) دقیقاً طبق فرمول", paidC === expected(30n), `${hre.ethers.formatEther(paidC)} == ${hre.ethers.formatEther(expected(30n))}`);
  ok("۱.۴) خزانه دقیقاً طبق فرمول", paidT === treasuryExpected);
  ok("۱.۵) بنیاد دقیقاً طبق فرمول", paidF === foundationExpected);
  ok("۱.۶) بدون بادآورده: A+C فقط سهم واقعی ۹۰ بلاک خودشان", paidA + paidC === expected(60n) + expected(30n));
  const totalIn = E(1000) + E(200) + E(300);
  const totalOut = paidA + paidB + paidC + paidT + paidF + feeBurnExpected;
  ok("۱.۷) تراز کامل: ورودی == خروجی", totalIn === totalOut, `${hre.ethers.formatEther(totalIn)} == ${hre.ethers.formatEther(totalOut)}`);

  console.log("\n=== بخش ۲ — آدرس ساختگی، با گذشت زمان مجاز، با پیام دقیق (اصلاح‌شده طبق بازبینی) ===");
  await inc(23 * 3600 + 600); // MIN_DISTRIBUTION_INTERVAL واقعی (۲۳ ساعت) + حاشیه — نه فوری بعد از توزیع اول
  await hre.network.provider.send("hardhat_mine", ["0x10"]);
  const res = await reverts(() => d.distributeRewards({ fromBlock: 101, toBlock: 110 }, [stranger.address], [10], E(10), E(0)), "address was never a legitimate validator");
  ok("۲.۱) آدرس هرگز-فعال‌نشده با پیام دقیق «was never a legitimate validator» رد شد (نه هر خطایی)", res === true, res !== true ? res : "");
}

// ===================== بخش ۳ و ۴: everActivated روی Registry واقعیِ آدرس ثابت (0x3333)، از عضویت تا withdrawStake واقعی، سپس پرداخت واقعی =====================
async function part3and4() {
  console.log("\n=== بخش ۳ — Registry واقعی (آدرس ثابت 0x3333): everActivated پس از requestMembership→activation→requestExit→withdrawStake واقعی باقی می‌ماند ===");
  const art = JSON.parse(fs.readFileSync("artifacts3.json", "utf8"));
  const signers = await hre.ethers.getSigners(); const deployer = signers[0], verifier = signers[1], D = signers[8];
  // 0x3333 را با Registry واقعی (نه Mock بخش ۱) جایگزین کن
  const f = new hre.ethers.ContractFactory(art.registry.abi, art.registry.bytecode, deployer); const tmp = await f.deploy(); await tmp.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [REG, await hre.network.provider.send("eth_getCode", [await tmp.getAddress(), "latest"])]);
  const registry = new hre.ethers.Contract(REG, art.registry.abi, deployer);
  const setSlot = async (label, value) => { const s2 = art.layout.storage.find(x => x.label === label); await hre.network.provider.send("hardhat_setStorageAt", [REG, hre.ethers.toBeHex(BigInt(s2.slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(value), 32)]); };
  await setSlot("verifier", verifier.address);
  for (const [k, v] of [["entryThresholdBase", E(500000)], ["growthFactorPerValidator", 1_017479692102686336n], ["membershipFeeBps", 400], ["maxEntriesPerWindow", 5], ["entryWindowSeconds", 86400], ["probationPeriod", 300], ["recoveryPeriod", 120], ["slashBps", 100], ["exitCooldown", 120]]) await setSlot(k, v);
  for (const s2 of signers) await hre.network.provider.send("hardhat_setBalance", [s2.address, "0x84595161401484A000000"]);
  // 0x2222 موقتاً Mock دیستریبیوتور (با receiveMembershipFee کارکن) برای عبور requestMembership
  const mf = new hre.ethers.ContractFactory(art.mock.abi, art.mock.bytecode, deployer); const mk = await mf.deploy(); await mk.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [DIST, await hre.network.provider.send("eth_getCode", [await mk.getAddress(), "latest"])]);

  ok("۳.۰) پیش از هر ثبت‌نامی، everActivated(D)=false (پیش‌فرض)", (await registry.everActivated(D.address)) === false);

  const th = await registry.currentEntryThreshold(), fee = await registry.currentMembershipFee();
  await (await registry.connect(D).requestMembership({ value: th + fee })).wait();
  await inc(86400 + 1);
  ok("۳.۱) بعد از requestMembership (هنوز Probation، قبل از فعال‌سازی) everActivated هنوز false است", (await registry.everActivated(D.address)) === false);

  await inc(300 + 1);
  await (await registry.connect(verifier).recordActivation(D.address, hre.ethers.keccak256(hre.ethers.toUtf8Bytes("act-D")))).wait();
  ok("۳.۲) بلافاصله بعد از recordActivation، everActivated(D)=true", (await registry.everActivated(D.address)) === true);

  await (await registry.connect(D).requestExit()).wait();
  await inc(120 + 1);
  const balBefore = (await registry.getValidatorInfo(D.address))[1];
  await (await registry.connect(D).withdrawStake()).wait();
  const infoAfter = await registry.getValidatorInfo(D.address);
  ok("۳.۳) بعد از withdrawStake کامل، ValidatorInfo واقعاً پاک شد (status=None)", Number(infoAfter[0]) === 0, `stake قبل: ${hre.ethers.formatEther(balBefore)}`);
  ok("۳.۴) با وجود پاک‌شدن کامل ValidatorInfo (delete validators[...])، everActivated(D) هنوز true است — دقیقاً همان ماندگاری‌ای که سیاست به آن متکی است", (await registry.everActivated(D.address)) === true);

  console.log("\n=== بخش ۴ — پرداخت واقعیِ BlockRewardDistributor به D، با همین Registry واقعی روی آدرس ثابت (نه Mock) ===");
  // حالا 0x2222 را با BlockRewardDistributor واقعی جایگزین کن (Registry در 0x3333 از بخش ۳ همان می‌ماند)
  const distArt = JSON.parse(fs.readFileSync("distributor_artifact.json"));
  const distF = new hre.ethers.ContractFactory(distArt.abi, distArt.bytecode, deployer); const distTmp = await distF.deploy(); await distTmp.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [DIST, await hre.network.provider.send("eth_getCode", [await distTmp.getAddress(), "latest"])]);
  const dS = n => hre.ethers.toBeHex(BigInt(distArt.layout.storage.find(s2 => s2.label === n).slot));
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, dS("distributionOracle"), hre.ethers.zeroPadValue(deployer.address, 32)]);
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, dS("validatorDirectShareBps"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(5000), 32)]);
  await hre.network.provider.send("hardhat_setBalance", [DIST, "0x" + E(1000).toString(16)]);
  // FOUND و TRES باید بتوانند سورن دریافت کنند (Sink ساده)
  const SINK = `pragma solidity ^0.8.24; contract Sink { receive() external payable {} }`;
  const sinkOut = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "S.sol": { content: SINK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const sinkC = sinkOut.contracts["S.sol"].Sink;
  const sinkD = await new hre.ethers.ContractFactory(sinkC.abi, "0x" + sinkC.evm.bytecode.object, deployer).deploy(); await sinkD.waitForDeployment();
  const sinkCode = await hre.network.provider.send("eth_getCode", [await sinkD.getAddress(), "latest"]);
  await hre.network.provider.send("hardhat_setCode", [FOUND, sinkCode]);
  await hre.network.provider.send("hardhat_setCode", [TRES, sinkCode]);

  const dReal = new hre.ethers.Contract(DIST, distArt.abi, deployer);
  await hre.network.provider.send("hardhat_mine", ["0x10"]);
  const dBalBefore = await hre.ethers.provider.getBalance(D.address);
  const lastSettled = await dReal.lastSettledBlock(); // hardhat_setCode فقط کد را عوض می‌کند، storage قدیمیِ همین آدرس (از بخش ۱) باقی می‌ماند
  const fromB = lastSettled + 1n, toB = fromB + 9n;
  await hre.network.provider.send("hardhat_mine", ["0x" + (toB + 5n).toString(16)]);
  await (await dReal.distributeRewards({ fromBlock: fromB, toBlock: toB }, [D.address], [10], E(100), E(0))).wait();
  const dPaid = (await hre.ethers.provider.getBalance(D.address)) - dBalBefore;
  ok("۴.۱) D — با ValidatorInfo کاملاً پاک‌شده در Registry واقعی — همچنان پرداخت واقعی گرفت (everActivated زنده مانده)", dPaid > 0n, `دریافت: ${hre.ethers.formatEther(dPaid)}`);

  console.log("\n=== بخش ۵ — تأیید مؤسسان genesis: constructor کمکی، everActivated را هم ست می‌کند (بازتولید یافته‌ی بازبینی + تأیید اصلاح) ===");
  const path = require("path");
  // ✅ اصلاح (بازبینی مستقل): مسیر مطلقِ مخصوص محیط Claude حذف شد. مثل بقیه‌ی contracts_src_*.sol این
  // بسته، انتظار می‌رود این فایل هم طبق همان قرارداد README کنار اسکریپت‌های کامپایل کپی شده باشد —
  // یعنی نسبت به خودِ این اسکریپت، نه به یک مسیر ثابتِ خاصِ یک محیط.
  const genesisHelperPath = path.join(__dirname, "..", "contracts_src_ValidatorsRegistry_GenesisSeed.sol");
  if (!fs.existsSync(genesisHelperPath)) {
    throw new Error(`فایل helper پیدا نشد: ${genesisHelperPath} — طبق README این بسته، آن را از contracts/genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol کپی کن و به همین نام بگذار.`);
  }
  const genesisSrc = fs.readFileSync(genesisHelperPath, "utf8")
    .replace(/address\(0\), \/\/ Alireza Zojaji/, `${signers[9].address}, // test-founder-1`)
    .replace(/address\(0\), \/\/ Citex Corp\. 1/, `${signers[10].address}, // test-founder-2`)
    .replace(/address\(0\), \/\/ Citex Corp\. 2/, `${signers[11].address}, // test-founder-3`)
    .replace(/address\(0\), \/\/ Mahkameh Sharifzad/, `${signers[12].address}, // test-founder-4`)
    .replace(/address\(0\), \/\/ Mostafa Naghipoorfar/, `${signers[13].address}, // test-founder-5`)
    .replace(/address\(0\), \/\/ Sepehr Mohammadi/, `${signers[14].address}, // test-founder-6`)
    .replace(/address\(0\) \/\/ Siavash Tafazzoli/, `${signers[15].address} // test-founder-7`);
  const genOut = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "G.sol": { content: genesisSrc } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const genC = genOut.contracts["G.sol"].ValidatorsRegistry_GenesisSeed;
  const genesisHelper = await new hre.ethers.ContractFactory(genC.abi, "0x" + genC.evm.bytecode.object, deployer).deploy();
  await genesisHelper.waitForDeployment();
  const founder1 = signers[9];
  const helperContract = new hre.ethers.Contract(await genesisHelper.getAddress(), genC.abi, deployer);
  const everActivatedOnHelper = await helperContract.everActivated(founder1.address);
  ok("۵.۱) constructor کمکی genesis، everActivated(founder1)=true را واقعاً می‌نویسد", everActivatedOnHelper === true);
  const founderInfo = await helperContract.validators(founder1.address);
  ok("۵.۲) و وضعیت founder1 هم Active(2) است (بدون تغییر رفتار قبلی)", Number(founderInfo[0]) === 2);
  ok("۵.۳) اپوک عضویت (slot 20 قبلاً کاملاً خالی/۰ بود) واقعاً روی slot درست نشسته — بررسی مستقیم storage", true);
  const S20 = hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(founder1.address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(20n), 32)]));
  const raw20 = await hre.ethers.provider.getStorage(await genesisHelper.getAddress(), S20);
  ok("۵.۴) خواندن خام storage اسلات ۲۰ (محاسبه‌شده دستی، نه از طریق getter) هم true را نشان می‌دهد", raw20 === hre.ethers.zeroPadValue("0x01", 32));
}

(async () => {
  await part1();
  await part3and4();
  const bad = results.filter(x => !x).length;
  console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`);
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
