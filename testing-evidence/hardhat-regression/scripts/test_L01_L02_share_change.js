// L01 + L02 (audit 2026-09-30) — bicameral validatorDirectShareBps governance.
// Same script is run against the pre-fix source (must show the violations as ❌) and the fixed source (all ✅).
// L01: the 180-day minimum between SUCCESSFUL share changes must hold at the moment a change is applied,
//      not only when a proposal is created.
// L02: the board chamber must use live board authority (hasBoardAuthority, not the raw seat flag) and a
//      proposal is bound to the board composition (boardVersion) it was created under — checked at the
//      board vote AND at final execution.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const DIST = "0x2222222222222222222222222222222222222222", REG = "0x3333333333333333333333333333333333333333",
      BOARD = "0x4444444444444444444444444444444444444444";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
async function reverts(fn, expected) {
  try { await (await fn()).wait(); return "did NOT revert"; }
  catch (e) { const m = e.reason || e.shortMessage || e.message || ""; return expected.some(s => m.includes(s)) ? true : "wrong reason: " + m.slice(0, 200); }
}
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
const DAY = 24 * 3600;
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry {
  mapping(address=>bool) public act; uint256 public activeCount;
  function setActive(address a, bool v) external { if (act[a]!=v) _cp(a,v); act[a]=v; }
  uint256 public statusNonce; struct Cp { uint256 n; bool a; } mapping(address=>Cp[]) cps;
  function _cp(address x, bool on) internal { statusNonce++; cps[x].push(Cp(statusNonce, on)); }
  function wasActiveAt(address x, uint256 n) external view returns (bool) { Cp[] storage c=cps[x]; bool r=false; for (uint i=0;i<c.length;i++){ if (c[i].n<=n) r=c[i].a; else break; } return r; }
  function setActiveCount(uint256 n) external { activeCount=n; }
  function isValidator(address a) external view returns (bool) { return act[a]; }
  function everActivated(address a) external view returns (bool) { return act[a]; }
  function getActiveValidatorCount() external view returns (uint256) { return activeCount; }
}
contract MockBoard {
  mapping(address=>bool) public isBoardMember; mapping(address=>bool) public auth; uint256 public boardVersion = 1;
  function setSeat(address a, bool seat, bool authority) external { isBoardMember[a]=seat; auth[a]=authority; }
  function setVersion(uint256 v) external { boardVersion=v; }
  function hasBoardAuthority(address a) external view returns (bool) { return auth[a]; }
}`;

(async () => {
  const s = await hre.ethers.getSigners();
  const [deployer] = s; const B = s.slice(1, 6); const V = s.slice(6, 12); const newMember = s[12];
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const mr = out.contracts["M.sol"].MockRegistry, mb = out.contracts["M.sol"].MockBoard;
  await put(REG, mr.abi, "0x" + mr.evm.bytecode.object); await put(BOARD, mb.abi, "0x" + mb.evm.bytecode.object);
  const art = JSON.parse(fs.readFileSync("distributor_artifact.json")); await put(DIST, art.abi, art.bytecode);
  const S = n => hre.ethers.toBeHex(BigInt(art.layout.storage.find(x => x.label === n).slot));
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, S("validatorDirectShareBps"), hre.ethers.zeroPadValue(hre.ethers.toBeHex(5000), 32)]);
  const reg = new hre.ethers.Contract(REG, mr.abi, deployer), board = new hre.ethers.Contract(BOARD, mb.abi, deployer);
  for (const v of V) await reg.setActive(v.address, true);
  await reg.setActiveCount(6); // required validator approvals = ceil(2/3 * 6) = 4
  for (const b of B) await board.setSeat(b.address, true, true);
  const d = (who) => new hre.ethers.Contract(DIST, art.abi, who);
  const share = async () => await d(deployer).validatorDirectShareBps();
  const propose = async (bps) => { const rc = await (await d(V[0]).proposeShareChange(bps)).wait(); return await d(deployer).shareProposalCount(); };
  const bv = (i, id) => d(B[i]).boardVoteShareChange(id), vv = (i, id) => d(V[i]).validatorVoteShareChange(id);
  const base = await hre.network.provider.send("evm_snapshot"); let snap = base;
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };

  console.log("=== L01 — فاصله‌ی ۱۸۰روزه در نقطه‌ی اجرا ===");
  await fresh();
  { // 1: two pre-built proposals, second completed by the VALIDATOR chamber
    const A = await propose(5500), Bp = await propose(6000);
    for (let i = 0; i < 3; i++) await (await bv(i, A)).wait();
    for (let i = 0; i < 4; i++) await (await vv(i, A)).wait();
    ok("L01.1) پیشنهاد A عادی اجرا شد (۵۵۰۰)", (await share()) === 5500n);
    for (let i = 0; i < 3; i++) await (await bv(i, Bp)).wait();
    for (let i = 0; i < 3; i++) await (await vv(i, Bp)).wait();
    const r = await reverts(() => vv(3, Bp), ["too soon since the last successful share change"]);
    ok("L01.2) رأی آخرِ مجلس ولیدیتورها روی B چند ثانیه بعد از A رد شد", r);
    ok("L01.3) سهم همان ۵۵۰۰ ماند (تغییر دوم اعمال نشد)", (await share()) === 5500n, `share=${await share()}`);
  }
  await fresh();
  { // 2: same, but second proposal completed by the BOARD chamber
    const A = await propose(5500), Bp = await propose(6000);
    for (let i = 0; i < 4; i++) await (await vv(i, Bp)).wait();
    for (let i = 0; i < 2; i++) await (await bv(i, Bp)).wait();
    for (let i = 0; i < 3; i++) await (await bv(i, A)).wait();
    for (let i = 0; i < 4; i++) await (await vv(i, A)).wait();
    const r = await reverts(() => bv(2, Bp), ["too soon since the last successful share change"]);
    ok("L01.4) رأی آخرِ مجلس هیأت روی B بعد از اجرای A رد شد", r);
    ok("L01.5) سهم همان ۵۵۰۰ ماند", (await share()) === 5500n, `share=${await share()}`);
  }
  await fresh();
  { // 3: after the interval, the old proposal is expired (expiry NOT removed to allow it); a fresh one works
    const A = await propose(5500), Bp = await propose(6000);
    for (let i = 0; i < 3; i++) await (await bv(i, A)).wait();
    for (let i = 0; i < 4; i++) await (await vv(i, A)).wait();
    for (let i = 0; i < 3; i++) await (await bv(i, Bp)).wait();
    for (let i = 0; i < 3; i++) await (await vv(i, Bp)).wait();
    await inc(181 * DAY);
    ok("L01.6) پس از ۱۸۰ روز، B منقضی است و اجرا نمی‌شود (انقضا حذف نشده)", await reverts(() => vv(3, Bp), ["proposal has expired"]));
    const C = await propose(6000);
    for (let i = 0; i < 3; i++) await (await bv(i, C)).wait();
    for (let i = 0; i < 4; i++) await (await vv(i, C)).wait();
    ok("L01.7) پیشنهاد تازه پس از ۱۸۰ روز عادی اجرا شد (۶۰۰۰)", (await share()) === 6000n);
    ok("L01.8) پیشنهاد جدید بلافاصله پس از تغییر، در ساخت رد می‌شود (کنترل قبلی حفظ شد)", await reverts(() => d(V[0]).proposeShareChange(5000), ["too soon since the last successful share change"]));
  }

  console.log("\n=== L02 — اختیار زنده و نسخه‌ی ترکیب هیأت ===");
  await fresh();
  { // 1: exited member: seat flag still true before sync, live authority false
    const P = await propose(5500);
    await board.setSeat(B[0].address, true, false);
    ok("L02.1) عضو خروج‌کرده (isBoardMember=true، hasBoardAuthority=false) پیش از sync رأی هیأت نمی‌دهد",
      await reverts(() => bv(0, P), ["caller has no live board authority"]));
  }
  await fresh();
  { // 2: two votes of the old composition + one of the new must not combine
    const P = await propose(5500);
    await (await bv(0, P)).wait(); await (await bv(1, P)).wait();
    await board.setSeat(B[2].address, false, false); await board.setSeat(newMember.address, true, true); await board.setVersion(2);
    const r = await reverts(() => d(newMember).boardVoteShareChange(P), ["board membership changed since this proposal was created"]);
    ok("L02.2) آرای دو عضو ترکیب قدیم با رأی عضو ترکیب جدید ترکیب نمی‌شوند", r);
    const p = await d(deployer).shareProposals(P);
    ok("L02.3) مجلس هیأت پاس نشد", p.boardPassed === false);
  }
  await fresh();
  { // 3: boardPassed already true, composition changes before the last validator vote
    const P = await propose(5500);
    for (let i = 0; i < 3; i++) await (await bv(i, P)).wait();
    for (let i = 0; i < 3; i++) await (await vv(i, P)).wait();
    await board.setVersion(2);
    ok("L02.4) boardPassed قبلی پس از تغییر واقعی ترکیب، اجرای نهایی را ممکن نمی‌کند",
      await reverts(() => vv(3, P), ["board membership changed since this proposal was created"]));
    ok("L02.5) سهم تغییر نکرد (۵۰۰۰)", (await share()) === 5000n, `share=${await share()}`);
  }
  await fresh();
  { // 4: refresh WITHOUT a real change does not bump boardVersion (real Board behaviour) -> proposal still valid
    const P = await propose(5500);
    for (let i = 0; i < 2; i++) await (await bv(i, P)).wait();
    // no setVersion: the real ValidatorsBoard only increments boardVersion on a real composition change
    await (await bv(2, P)).wait();
    for (let i = 0; i < 4; i++) await (await vv(i, P)).wait();
    ok("L02.6) بدون تغییر واقعی ترکیب، پیشنهاد معتبر بی‌دلیل باطل نمی‌شود و اجرا شد", (await share()) === 5500n);
  }
  await fresh();
  { // 5: a suspended (Demoted) member keeps authority until the monthly point — the Distributor must not add its own rule
    const P = await propose(5500);
    // real Board: _hasAuthority = seated && same membershipEpoch && status not None/Exiting -> Demoted keeps authority
    await board.setSeat(B[0].address, true, true);
    await (await bv(0, P)).wait();
    ok("L02.7) عضو معلق (اختیار زنده در Board=true) می‌تواند رأی دهد — تفاوت تعلیق و خروج از Board ارث برده می‌شود",
      (await d(deployer).shareProposals(P)).boardApprovals === 1n);
  }

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
