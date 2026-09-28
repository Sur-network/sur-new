// P04 (final decision) — exit handling: 72h pre-exit claim window, 7-day withdrawal, reserved amount, mass-failure/delivery/appeal reuse.
const hre = require("hardhat"); const fs = require("fs");
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333", DISTRIBUTOR_ADDR = "0x2222222222222222222222222222222222222222", TREASURY_ADDR = "0x5555555555555555555555555555555555555555";
let registry, art, deployer, verifier, V = [], results = [];
const H = (s) => hre.ethers.keccak256(hre.ethers.toUtf8Bytes(s));
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
const now = async () => (await hre.ethers.provider.getBlock("latest")).timestamp;
async function setSlot(label, value) { const s = art.layout.storage.find(x => x.label === label); await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, hre.ethers.toBeHex(BigInt(s.slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(value), 32)]); }
async function reverts(promiseFn, expected) { try { await (await promiseFn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 160); } }
function ok(name, cond, extra = "") { results.push([name, cond === true]); console.log((cond === true ? "✅ " : "❌ ") + name + (cond === true ? "" : " → " + cond) + (extra ? "  " + extra : "")); }
const decId = (r, evName) => { for (const l of r.logs) { try { const p = registry.interface.parseLog(l); if (p.name === evName) return p.args[0]; } catch (e) {} } throw new Error("no " + evName); };
async function txBal(signer, fn) { const before = await hre.ethers.provider.getBalance(signer.address); const r = await (await fn()).wait(); const after = await hre.ethers.provider.getBalance(signer.address); return after - before + r.gasUsed * r.gasPrice; }
async function stake(a) { return (await registry.getValidatorInfo(a))[1]; }

async function setup() {
  art = JSON.parse(fs.readFileSync("artifacts3.json", "utf8"));
  const signers = await hre.ethers.getSigners(); deployer = signers[0]; verifier = signers[1]; V = signers.slice(2, 16);
  const f = new hre.ethers.ContractFactory(art.registry.abi, art.registry.bytecode, deployer); const tmp = await f.deploy(); await tmp.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [REGISTRY_ADDR, await hre.network.provider.send("eth_getCode", [await tmp.getAddress(), "latest"])]);
  const mf = new hre.ethers.ContractFactory(art.mock.abi, art.mock.bytecode, deployer); const mk = await mf.deploy(); await mk.waitForDeployment();
  await hre.network.provider.send("hardhat_setCode", [DISTRIBUTOR_ADDR, await hre.network.provider.send("eth_getCode", [await mk.getAddress(), "latest"])]);
  registry = new hre.ethers.Contract(REGISTRY_ADDR, art.registry.abi, deployer);
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === "verifier").slot)), hre.ethers.zeroPadValue(verifier.address, 32)]);
  for (const [k, v] of [["entryThresholdBase", hre.ethers.parseEther("500000")], ["growthFactorPerValidator", 1_017479692102686336n], ["membershipFeeBps", 400], ["maxEntriesPerWindow", 1], ["entryWindowSeconds", 86400], ["probationPeriod", 604800], ["recoveryPeriod", 172800], ["slashBps", 100], ["exitCooldown", 604800]]) await setSlot(k, v);
  for (const s of signers) await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
}
async function join(s) { const th = await registry.currentEntryThreshold(), fee = await registry.currentMembershipFee(); await (await registry.connect(s).requestMembership({ value: th + fee })).wait(); await inc(86400 + 1); }
async function activate(s) { await inc(604800 + 1); await (await registry.connect(verifier).recordActivation(s.address, H("act" + s.address))).wait(); }
async function exitAt(s) { const r = await (await registry.connect(s).requestExit()).wait(); return (await hre.ethers.provider.getBlock(r.blockNumber)).timestamp; }
const vr = (a, h, t) => registry.connect(verifier).recordPreExitViolation(a, h, t);

(async () => {
  await setup();
  for (let i = 0; i < 12; i++) await join(V[i]);
  for (let i = 0; i < 12; i++) await activate(V[i]);
  console.log("۱۲ ولیدیتور دارای وثیقه فعال شدند\n");
  const snap = await hre.network.provider.send("evm_snapshot");
  let s = snap; const fresh = async () => { await hre.network.provider.send("evm_revert", [s]); s = await hre.network.provider.send("evm_snapshot"); };

  // ---- a) بدون پرونده: برداشت کامل بعد از ۷ روز ----
  await fresh(); { const v = V[0], S = await stake(v.address);
    await exitAt(v.address ? v : v);
    const early = await reverts(() => registry.connect(v).withdrawStake(), "exit cooldown not elapsed"); ok("a1) برداشت قبل از ۷ روز رد می‌شود", early);
    await inc(604800 + 1); const got = await txBal(v, () => registry.connect(v).withdrawStake());
    ok("a2) بدون پرونده: کل وثیقه پس از ۷ روز پرداخت می‌شود", got === S, `(${hre.ethers.formatEther(got)} از ${hre.ethers.formatEther(S)})`);
    ok("a3) ساختار ولیدیتور پاک شد (status=None)", Number((await registry.getValidatorInfo(v.address))[0]) === 0);
    const gone = await reverts(() => registry.connect(verifier).recordSuspension(v.address, H("x")), "not active"); ok("a4) خروج، وظیفه‌ی اعتبارسنجی را فوراً پایان داد (recordSuspension رد)", gone); }

  // ---- b) پرونده‌ی پیش‌ازخروج: جریان کامل + مبلغ محفوظ ----
  await fresh(); { const v = V[1], S = await stake(v.address), slash = S * 100n / 10000n;
    const T = await exitAt(v); ok("b0) بعد از خروج، از مجموعه‌ی فعال حذف شد", !(await registry.isValidator(v.address)));
    await inc(3600);
    const rc = await (await vr(v.address, H("ev-pre"), T - 4 * 3600)).wait(); const id = decId(rc, "PreExitCaseRecorded");
    ok("b1) Verifier ظرف ۷۲ ساعت پرونده‌ی رفتار قبل از خروج را ثبت کرد", true, `decisionId=${id}`);
    ok("b2) زمان وقوع تخلف روی زنجیره ثبت شد", (await registry.decisionViolationAt(id)) === BigInt(T - 4 * 3600));
    ok("b3) مبلغ درگیر در لحظه‌ی ثبت پرونده ثابت شد (۱٪ وثیقه)", (await registry.decisionSlashAmount(id)) === slash);
    ok("b4) قفل به همین تصمیم بسته شد", (await registry.pendingSlashDecisionId(v.address)) === id);
    await inc(3600 + 1); await (await registry.resolveMassFailureCheck(id)).wait();
    ok("b5) معافیت جمعی رعایت شد: یک پرونده‌ی تنها معاف نیست", Number((await registry.statusDecisions(id)).slashOutcome) === 0);
    await (await registry.connect(v).confirmDelivery(id)).wait(); ok("b6) تحویل شواهد توسط خودِ ولیدیتور (وضعیت Exiting) پذیرفته شد", true);
    await inc(604800 + 1); // ۷ روز از درخواست خروج گذشته، پرونده هنوز اجرا نشده
    const got1 = await txBal(v, () => registry.connect(v).withdrawStake());
    ok("b7) با پرونده‌ی حل‌نشده: فقط مبلغ درگیر محفوظ ماند، بقیه پرداخت شد", got1 === S - slash, `(${hre.ethers.formatEther(got1)} از ${hre.ethers.formatEther(S)})`);
    const info = await registry.getValidatorInfo(v.address);
    ok("b8) ساختار حفظ شد (Exiting) و lockedStake = مبلغ محفوظ", Number(info[0]) === 4 && info[1] === slash);
    // تغییر رفتار اقتصادی (نظر صاحب پروژه): مبلغ درگیر در لحظه‌ی ثبت پرونده ثابت است؛ تغییر بعدی slashBps آن را عوض نمی‌کند
    await (await registry.connect(V[4]).proposeParameterChange(4, 500)).wait(); const pid = await registry.paramProposalCount();
    for (const k of [5, 6, 7, 8, 9]) await (await registry.connect(V[k]).voteParameterChange(pid)).wait();
    ok("b8b) slashBps پس از ثبت پرونده از ۱٪ به ۵٪ تغییر کرد", (await registry.slashBps()) === 500n);
    const tb0 = await hre.ethers.provider.getBalance(TREASURY_ADDR);
    await (await registry.executeUncontestedSlash(id)).wait();
    ok("b9) مبلغ جریمه = ۱٪ وثیقهٔ **زمان ثبت پرونده** (نه ۵٪ جدید) و دقیقاً همان مبلغ محفوظ به خزانه رفت", (await hre.ethers.provider.getBalance(TREASURY_ADDR)) - tb0 === slash);
    const got2 = await txBal(v, () => registry.connect(v).withdrawStake());
    ok("b10) پس از تعیین تکلیف: برداشت دوم مانده را می‌دهد (صفر) و ساختار پاک می‌شود", got2 === 0n && Number((await registry.getValidatorInfo(v.address))[0]) === 0);
    ok("b11) مجموع دریافتی ولیدیتور = وثیقه − جریمه", got1 + got2 === S - slash); }

  // ---- c) رد شدن‌ها ----
  await fresh(); { const v = V[2]; const T = await exitAt(v); await inc(60);
    ok("c1) تخلف هم‌زمان/بعد از درخواست خروج پرونده نمی‌شود (غیرفعالی پس از خروج تخلف نیست)", (await reverts(() => vr(v.address, H("e"), T), "must precede")) === true && (await reverts(() => vr(v.address, H("e"), T + 30), "must precede")) === true);
    ok("c2) فقط Verifier می‌تواند ثبت کند", await reverts(() => registry.connect(V[5]).recordPreExitViolation(v.address, H("e"), T - 10), "caller is not the verifier"));
    const a = V[3]; ok("c3) ولیدیتور خروج‌نکرده: رد", await reverts(() => vr(a.address, H("e"), T - 10), "not exiting"));
    const w = V[4]; const Tw = await exitAt(w); await inc(72 * 3600 + 1);
    ok("c4) بعد از ۷۲ ساعت از درخواست خروج: رد", await reverts(() => vr(w.address, H("e"), Tw - 100), "claim window closed")); }
  await fresh(); { const v = V[5]; const T = await exitAt(v); await inc(60);
    await (await vr(v.address, H("e1"), T - 500)).wait();
    ok("c5) پرونده‌ی دوم وقتی پرونده‌ی معلق هست: رد", await reverts(() => vr(v.address, H("e2"), T - 400), "already pending")); }
  await fresh(); { const nv = (await hre.ethers.getSigners())[17]; await join(nv); const T = await exitAt(nv); await inc(60); // Probation
    ok("c6) خروج در وضعیت Probation (بدون وظیفه‌ی اعتبارسنجی): پرونده‌ی پیش‌ازخروج رد", await reverts(() => vr(nv.address, H("e"), T - 500), "no validation duty")); }
  await fresh(); { const v = V[6]; // تعلیق ← جریمه ← بازگشت ← خروج: تخلف قدیمی‌تر از آخرین تعلیق رد؛ جدیدتر پذیرفته
    const rc = await (await registry.connect(verifier).recordSuspension(v.address, H("s"))).wait(); const id = decId(rc, "StatusDecisionRecorded");
    const demotedAt = Number((await registry.getValidatorInfo(v.address))[3]);
    await inc(3601); await (await registry.resolveMassFailureCheck(id)).wait(); await (await registry.connect(v).confirmDelivery(id)).wait();
    await inc(72 * 3600 + 1); await (await registry.executeUncontestedSlash(id)).wait();
    await inc(172800 + 1); await (await registry.connect(verifier).recordRecovery(v.address, H("r"))).wait();
    await inc(1000); const T = await exitAt(v); await inc(60);
    ok("c7) تخلف مربوط به قبل از آخرین تعلیق (قبلاً جریمه شده) رد", await reverts(() => vr(v.address, H("e"), demotedAt - 10), "predates the last suspension"));
    ok("c8) تخلف بعد از آخرین تعلیق و قبل از خروج پذیرفته می‌شود (بدون هیچ revert)", (await reverts(() => vr(v.address, H("e"), T - 100), "ANY")) === false); }

  // ---- d) معافیت جمعی در مسیر پیش‌ازخروج ----
  await fresh(); { const ids = []; const Ts = [];
    for (let i = 7; i < 11; i++) Ts.push(await exitAt(V[i])); // ۴ خروج → فعال‌ها ۸
    await inc(120);
    for (let k = 0; k < 4; k++) { const rc = await (await vr(V[7 + k].address, H("m" + k), Ts[k] - 1000)).wait(); ids.push(decId(rc, "PreExitCaseRecorded")); }
    await inc(3601); for (const id of ids) await (await registry.resolveMassFailureCheck(id)).wait();
    ok("d1) ۴ پرونده‌ی هم‌زمان از ۸ ولیدیتور فعال (>۲۰٪) → هر ۴ معاف (ExemptMassFailure)", (await Promise.all(ids.map(async id => Number((await registry.statusDecisions(id)).slashOutcome)))).every(x => x === 1));
    await inc(604800 + 1); const v = V[7], S = await stake(v.address); const got = await txBal(v, () => registry.connect(v).withdrawStake());
    ok("d2) پرونده‌ی معاف‌شده مانع برداشت نیست: کل وثیقه پرداخت شد", got === S); }

  // ---- e) کف exitCooldown ----
  await fresh(); { const p = registry.connect(V[11]);
    ok("e1) exitCooldown ≤ ۷۲ ساعت پیشنهاد نمی‌شود", await reverts(() => p.proposeParameterChange(5, 259200), "exitCooldown must exceed"));
    ok("e2) exitCooldown > ۷۲ ساعت پذیرفته می‌شود (بدون هیچ revert)", (await reverts(() => p.proposeParameterChange(5, 259201), "ANY")) === false); }

  const bad = results.filter(r => !r[1]).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
