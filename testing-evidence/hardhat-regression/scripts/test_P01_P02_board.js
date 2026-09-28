// P01/P02 (final decisions) — board stability, monthly re-selection, exit-driven authority loss, succession, <3 halt.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444", TRES = "0x5555555555555555555555555555555555555555", IDR = "0x6666666666666666666666666666666666666666";
let results = [], board, reg, A, deployer, recipient;
function ok(name, c, extra = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + name + (c === true ? "" : " → " + c) + (extra ? "  " + extra : "")); }
const E1 = hre.ethers.parseEther('10');
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 200); } }
const slot = (art, n) => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
const setS = (addr, sl, v) => hre.network.provider.send("hardhat_setStorageAt", [addr, sl, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
const members = async () => (await board.getBoardMembers()).map(x => x.toLowerCase());
const has = async (a) => (await members()).includes(a.address.toLowerCase());

const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { address[] public vals; mapping(address=>bool) public active; mapping(address=>uint8) public st;
 function setActive(address a, bool on) external { if (on && !active[a]) { active[a]=true; vals.push(a);} else if (!on && active[a]) { active[a]=false; for (uint i=0;i<vals.length;i++) if (vals[i]==a) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
 function setStatus(address a, uint8 s) external { st[a]=s; }
 function isValidator(address a) external view returns (bool) { return active[a]; }
 function getValidators() external view returns (address[] memory) { return vals; }
 function getValidatorInfo(address a) external view returns (uint8,uint256,uint256,uint256,uint256,bool) { return (st[a],0,0,0,0,false); }
 function recoveryPeriod() external pure returns (uint256) { return 172800; } }
contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }`;

async function install(addr, abi, bytecode) { const f = new hre.ethers.ContractFactory(abi, bytecode, deployer); const t = await f.deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); }
async function setup() {
  const signers = await hre.ethers.getSigners(); deployer = signers[0]; recipient = signers[19]; A = signers.slice(2, 14);
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const mr = out.contracts["M.sol"].MockRegistry, mi = out.contracts["M.sol"].MockIdentity;
  await install(REG, mr.abi, "0x" + mr.evm.bytecode.object); await install(IDR, mi.abi, "0x" + mi.evm.bytecode.object);
  const b = JSON.parse(fs.readFileSync("board_artifact.json")), t = JSON.parse(fs.readFileSync("treasury_artifact.json"));
  await install(BOARD, b.abi, b.bytecode); await install(TRES, t.abi, t.bytecode);
  await setS(BOARD, slot(b, "boardVersion"), 1);
  await setS(TRES, slot(t, "perPaymentCap"), hre.ethers.parseEther("50000")); await setS(TRES, slot(t, "periodCap"), hre.ethers.parseEther("200000"));
  await hre.network.provider.send("hardhat_setBalance", [TRES, "0x" + (10n ** 25n).toString(16)]);
  reg = new hre.ethers.Contract(REG, mr.abi, deployer); board = new hre.ethers.Contract(BOARD, b.abi, deployer);
  for (let i = 0; i < 10; i++) { await (await reg.setActive(A[i].address, true)).wait(); await (await reg.setStatus(A[i].address, 2)).wait(); }
  for (let v = 0; v < 10; v++) for (let c = 0; c < 5; c++) await (await board.connect(A[v]).voteFor(A[c].address)).wait();
  return b;
}
(async () => {
  const b = await setup();
  ok("0) بدون هیچ مسیر «عزل اضطراری» در ABI هیأت", !b.abi.some(f => f.type === "function" && /remove|emergency|kick|dismiss|evict/i.test(f.name)));
  const snapPre = await hre.network.provider.send("evm_snapshot"); // هیأت خالی، رأی‌ها ثبت‌شده — برای سناریوهای genesis
  await (await board.refreshBoard()).wait();
  ok("1) هیأت خالی → اولین بازتعیین فوراً مجاز؛ ۵ عضو اول انتخاب شدند", (await members()).length === 5 && (await has(A[0])) && (await has(A[4])));
  ok("1b) ترکیب واقعاً عوض شد → boardVersion افزایش یافت (۱→۲)", (await board.boardVersion()) === 2n);
  const snap0 = await hre.network.provider.send("evm_snapshot"); let snap = snap0;
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };

  // P01: رأی آزاد ولی بازتعیین ماهانه
  { // رأی و تغییر رأی هر زمان
    for (let v = 6; v < 10; v++) { await (await board.connect(A[v]).unvoteFor(A[4].address)).wait(); await (await board.connect(A[v]).voteFor(A[5].address)).wait(); }
    ok("P01-a) رأی‌دادن و تغییر رأی پس از تشکیل هیأت هر زمان آزاد است (A5 اکنون ۴ رأی دارد)", (await board.getVotersFor(A[5].address)).length === 4);
    const early = await reverts(() => board.refreshBoard(), "once every 30 days"); ok("P01-b) بازتعیین عادی زودتر از ۳۰ روز رد می‌شود", early);
    await inc(30 * 86400 + 1); const v0 = await board.boardVersion(); await (await board.refreshBoard()).wait();
    ok("P01-c) پس از ۳۰ روز بازتعیین مجاز است؛ ترکیب همان ماند (A4 هنوز ۶ رأی > A5 ۴ رأی) → boardVersion افزایش نمی‌یابد", (await board.boardVersion()) === v0 && (await has(A[4])) && !(await has(A[5])));
    ok("P01-d) refresh دوباره در همان ماه رد می‌شود (تاریخ آخرین بازتعیین به‌روز شد)", await reverts(() => board.refreshBoard(), "once every 30 days")); }

  // P01: تغییر واقعی ترکیب پیشنهادهای ناتمام را باطل می‌کند
  await fresh(); { await inc(29 * 86400); // پیشنهاد باید نزدیک بازتعیین ساخته شود (انقضای اقدام ۱۴ روز است)؛ وگرنه دلیل رد «expired» می‌شود، نه «ترکیب عوض شد»
    const id = (await board.actionCount()) + 1n;
    await (await board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther("1000"), "t")).wait();
    await (await board.connect(A[1]).voteAction(id)).wait(); ok("P01-e) پیشنهاد با ۲ رأی از ۳ لازم باز است", (await board.actions(id)).votes === 2n);
    for (let v = 0; v < 10; v++) { await (await board.connect(A[v]).unvoteFor(A[4].address)).wait(); await (await board.connect(A[v]).voteFor(A[5].address)).wait(); }
    await inc(1 * 86400 + 1); const v0 = await board.boardVersion(); await (await board.refreshBoard()).wait();
    ok("P01-f) تغییر واقعی (A4→A5) → boardVersion افزایش یافت", (await board.boardVersion()) === v0 + 1n && (await has(A[5])) && !(await has(A[4])));
    const r = await reverts(() => board.connect(A[2]).voteAction(id), "board membership changed since this action was proposed");
    ok("P01-g) پیشنهاد ناتمام هیأت قبلی باطل شد: رأی سوم **با خطای صریح رد می‌شود** (نه موفقیتِ بی‌اثر) و شمرده نمی‌شود", r === true && (await board.actions(id)).votes === 2n && !(await board.actions(id)).executed); }

  // P02: تعلیق به‌تنهایی اختیار را قطع نمی‌کند؛ در بازتعیین ماهانه عضو معلق نمی‌ماند
  await fresh(); { await (await reg.setStatus(A[0].address, 3)).wait(); await (await reg.setActive(A[0].address, false)).wait(); // Demoted
    const r = await reverts(() => board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther("10"), "s"), "NONE"); 
    ok("P02-a) ولیدیتور معلق (Demoted) در طول دوره اختیار هیأت را حفظ می‌کند (پیشنهاد بدون revert)", r === false);
    ok("P02-b) وضعیت آماری: hasBoardAuthority(A0)=true", (await board.hasBoardAuthority(A[0].address)) === true);
    await inc(30 * 86400 + 1); await (await board.refreshBoard()).wait();
    ok("P02-c) در بازتعیین ماهانه، عضو معلق واجد شرایط ماندن نیست و حذف شد", !(await has(A[0]))); }

  // P02: درخواست خروج → قطع فوری اختیار، آزادشدن کرسی، جانشینی، ابطال پیشنهادهای ناتمام
  await fresh(); { for (let v = 6; v < 10; v++) { await (await board.connect(A[v]).unvoteFor(A[4].address)).wait(); await (await board.connect(A[v]).voteFor(A[5].address)).wait(); }
    const id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther("1000"), "t")).wait();
    const v0 = await board.boardVersion();
    await (await reg.setStatus(A[1].address, 4)).wait(); await (await reg.setActive(A[1].address, false)).wait(); // A1 درخواست خروج داد
    ok("P02-d) اختیار A1 با ثبت درخواست خروج **فوراً** قطع شد: خودِ A1 دیگر نمی‌تواند رأی/پیشنهاد بدهد", (await board.hasBoardAuthority(A[1].address)) === false && (await reverts(() => board.connect(A[1]).voteAction(id), "no board authority")) === true);
    ok("P02-d2) تا پاک‌سازی، اقدامات دیگر اعضا **با پیام روشن رد می‌شوند** (بدون موفقیت بی‌اثر): `call syncBoard() first`", (await reverts(() => board.connect(A[2]).voteAction(id), "call syncBoard() first")) === true && (await reverts(() => board.connect(A[2]).proposeApproveBudget(recipient.address, E1, "x"), "call syncBoard() first")) === true);
    await (await board.connect(A[2]).syncBoard()).wait();
    ok("P02-e) syncBoard (تراکنش جدا، پاک‌سازی برنمی‌گردد): کرسی A1 آزاد شد و جانشین (بالاترین‌رأیِ واجد شرایط، A5) بدون انتظار ماهانه جای آن را گرفت", !(await has(A[1])) && (await has(A[5])) && (await members()).length === 5);
    ok("P02-f) این تغییر واقعی ترکیب بود → boardVersion افزایش یافت", (await board.boardVersion()) > v0);
    ok("P02-g) پیشنهاد ناتمام قدیمی حالا با **خطای صریح** رد می‌شود و باید با ترکیب معتبر دوباره مطرح شود (رأی شمرده نشد)", (await reverts(() => board.connect(A[2]).voteAction(id), "board membership changed since this action was proposed")) === true && (await board.actions(id)).votes === 1n);
    ok("P02-h) pendingVacancies پس از پرشدن صفر", (await board.pendingVacancies()) === 0n); }

  // P02: نبودِ کاندیدای واجد شرایط → کرسی خالی می‌ماند؛ با پیدا شدن کاندیدا با fillVacancies پر می‌شود
  await fresh(); { await (await reg.setStatus(A[1].address, 4)).wait(); await (await reg.setActive(A[1].address, false)).wait();
    await (await board.connect(A[2]).syncBoard()).wait();
    ok("P02-i) بدون کاندیدای واجد شرایط: کرسی خالی ماند، pendingVacancies=1، ۴ عضو", (await members()).length === 4 && (await board.pendingVacancies()) === 1n);
    for (let v = 0; v < 10; v++) await (await board.connect(A[v]).unvoteFor(A[4].address)).wait();
    for (let v = 0; v < 10; v++) { if (v === 1) continue; await (await board.connect(A[v]).voteFor(A[6].address)).wait(); } // A1 خارج‌شده و غیرفعال است
    await (await board.connect(A[9]).fillVacancies()).wait();
    ok("P02-j) با ظهور کاندیدا، fillVacancies (بدون مجوز) کرسی خروج‌شده را پر کرد — نه بیشتر", (await has(A[6])) && (await members()).length === 5 && (await board.pendingVacancies()) === 0n); }

  // P02: کمتر از ۳ عضو دارای اختیار → توقف پرداخت خزانه
  await fresh(); { for (let v = 0; v < 10; v++) await (await board.connect(A[v]).unvoteFor(A[4].address)).wait(); // کاندیدای جانشین نداشته باشیم
    for (const i of [1, 2, 3]) { await (await reg.setStatus(A[i].address, 4)).wait(); await (await reg.setActive(A[i].address, false)).wait(); }
    await (await board.connect(A[0]).syncBoard()).wait();
    ok("P02-k) ۳ عضو خارج شدند و جانشین واجدی نیست → ۲ عضو دارای اختیار", (await members()).length === 2);
    ok("P02-l) پرداخت خزانه متوقف شد (حداقل ۳ رأی کاهش نمی‌یابد)", await reverts(() => board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther("10"), "x"), "spending halted")); }

  // مسیر پرداخت سالم با سقف‌های نهایی ۵۰٬۰۰۰/۲۰۰٬۰۰۰
  await fresh(); { const pay = async (amt, expectOk) => { const id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther(String(amt)), "p")).wait(); await (await board.connect(A[1]).voteAction(id)).wait();
      const before = await hre.ethers.provider.getBalance(recipient.address);
      const r = await reverts(() => board.connect(A[2]).voteAction(id), "per-payment cap"); const after = await hre.ethers.provider.getBalance(recipient.address);
      return expectOk ? (r === false && after - before === hre.ethers.parseEther(String(amt))) : (r === true && after === before); };
    ok("Pay-a) ۱٬۰۰۰ سورن با ۳ رأی هیأت اجرا و به گیرنده رسید", await pay(1000, true));
    ok("Pay-b) ۴۹٬۹۹۹ زیر سقف هر پرداخت (۵۰٬۰۰۰) اجرا شد", await pay(49999, true));
    ok("Pay-c) ۵۰٬۰۰۰ (برابر سقف؛ باید کمتر باشد) رد شد", await pay(50000, false)); }

  // ---- سناریوهای genesis: هیأت اولیه‌ی seed‌شده + lastBoardRefreshAt (تصمیم P01 — ثبات ۳۰ روز اول) ----
  const seedBoard = async (lastRefresh) => { await hre.network.provider.send("evm_revert", [snapPre]); snapPre2 = await hre.network.provider.send("evm_snapshot");
    const bm = BigInt(b.layout.storage.find(x => x.label === "boardMembers").slot), im = BigInt(b.layout.storage.find(x => x.label === "isBoardMember").slot);
    const put = (addr, slotHex, val) => hre.network.provider.send("hardhat_setStorageAt", [addr, slotHex, hre.ethers.zeroPadValue(hre.ethers.toBeHex(val), 32)]);
    await put(BOARD, hre.ethers.toBeHex(bm), 5n); const base = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(bm), 32)));
    for (let i = 0; i < 5; i++) { await put(BOARD, hre.ethers.toBeHex(base + BigInt(i)), BigInt(A[i].address));
      await put(BOARD, hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(A[i].address, 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(im), 32)])), 1n); }
    await put(BOARD, slot(b, "lastBoardRefreshAt"), lastRefresh); };
  let snapPre2;
  { const genesisTs = BigInt((await hre.ethers.provider.getBlock("latest")).timestamp); await seedBoard(genesisTs);
    ok("G-a) هیأت اولیه‌ی seed‌شده با lastBoardRefreshAt = زمان genesis: ۵ عضو، همه دارای اختیار", (await members()).length === 5 && (await board.hasBoardAuthority(A[0].address)));
    ok("G-b) در ۳۰ روز اول، هیچ‌کس نمی‌تواند ترکیب را عوض کند (refreshBoard رد می‌شود) — ثبات هیأت اولیه", await reverts(() => board.refreshBoard(), "once every 30 days"));
    await inc(29 * 86400); ok("G-c) روز ۲۹ هنوز رد می‌شود", await reverts(() => board.refreshBoard(), "once every 30 days"));
    await inc(2 * 86400); await (await board.refreshBoard()).wait(); ok("G-d) بعد از ۳۰ روز اولین بازتعیین عادی مجاز است", (await board.lastBoardRefreshAt()) > genesisTs); }
  { await seedBoard(0n); // مستندسازی رفتار: اگر ابزار genesis این slot را overlay نکند
    ok("G-e) (رفتار مستند) بدون overlay (lastBoardRefreshAt=0) اولین refresh فوراً پذیرفته می‌شود → به همین دلیل ابزار genesis باید مقدار را overlay و assert کند", (await reverts(() => board.refreshBoard(), "once every 30 days")) === false);
    await seedBoard(0n); for (let v = 0; v < 10; v++) for (let c = 0; c < 5; c++) await (await board.connect(A[v]).unvoteFor(A[c].address)).wait();
    await (await board.refreshBoard()).wait();
    ok("G-f) (رفتار مستند، ⚠️ نیازمند تصمیم) بازتعیین عادی با صفر رأی، کل هیأت را خالی می‌کند — تصمیم P01 درباره‌ی این حالت چیزی نمی‌گوید", (await members()).length === 0); }

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
