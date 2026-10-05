// L02 — INTEGRATION test with the REAL ValidatorsBoard bytecode at 0x4444 and the REAL BlockRewardDistributor at 0x2222.
// Only ValidatorsRegistry (0x3333) and IdentityRegistry (0x6666) are mocked (same MockRegistry as test_P01_P02_board.js,
// extended with everActivated/getActiveValidatorCount for the Distributor). hasBoardAuthority() and boardVersion() are
// therefore produced by the Board's own logic (seat + membershipEpoch + status; version bump only on a real change).
// Still Hardhat, not Besu.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444",
      TRES = "0x5555555555555555555555555555555555555555", IDR = "0x6666666666666666666666666666666666666666",
      DIST = "0x2222222222222222222222222222222222222222";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 200); } }
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
const nextMonthStart = async () => { const b0 = await hre.ethers.provider.getBlock("latest"); const d = new Date(b0.timestamp * 1000); return Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1, 0, 0, 5) / 1000); };
const warpTo = async (ts) => { await hre.network.provider.send("evm_setNextBlockTimestamp", [ts]); await hre.network.provider.send("evm_mine"); };
const slot = (art, n) => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
const setS = (addr, sl, v) => hre.network.provider.send("hardhat_setStorageAt", [addr, sl, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { address[] public vals; mapping(address=>bool) public active; mapping(address=>uint8) public st; mapping(address=>bool) public ever; mapping(address=>uint256) public activationSeq; uint256 public activationCount;
 function setActive(address a, bool on) external { if (on && !active[a]) { active[a]=true; if (!ever[a]) { ever[a]=true; activationSeq[a]=++activationCount; } vals.push(a); _cp(a,true);} else if (!on && active[a]) { active[a]=false; _cp(a,false); for (uint i=0;i<vals.length;i++) if (vals[i]==a) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
  uint256 public statusNonce; struct Cp { uint256 n; bool a; } mapping(address=>Cp[]) cps;
  function _cp(address x, bool on) internal { statusNonce++; cps[x].push(Cp(statusNonce, on)); }
  function wasActiveAt(address x, uint256 n) external view returns (bool) { Cp[] storage c=cps[x]; bool r=false; for (uint i=0;i<c.length;i++){ if (c[i].n<=n) r=c[i].a; else break; } return r; }
 function setStatus(address a, uint8 s) external { st[a]=s; }
 function isValidator(address a) external view returns (bool) { return active[a]; }
 function everActivated(address a) external view returns (bool) { return ever[a]; }
 function getActiveValidatorCount() external view returns (uint256) { return vals.length; }
 function getValidators() external view returns (address[] memory) { return vals; }
 function getValidatorInfo(address a) external view returns (uint8,uint256,uint256,uint256,uint256,bool) { return (st[a],0,0,0,0,false); }
 function recoveryPeriod() external pure returns (uint256) { return 172800; }
 mapping(address=>uint256) public membershipEpoch;
 function bumpEpoch(address a) external { membershipEpoch[a]++; } }
contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }`;

(async () => {
  const signers = await hre.ethers.getSigners(); const deployer = signers[0]; const A = signers.slice(2, 14);
  const install = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const mr = out.contracts["M.sol"].MockRegistry, mi = out.contracts["M.sol"].MockIdentity;
  await install(REG, mr.abi, "0x" + mr.evm.bytecode.object); await install(IDR, mi.abi, "0x" + mi.evm.bytecode.object);
  const b = JSON.parse(fs.readFileSync("board_artifact.json")), dArt = JSON.parse(fs.readFileSync("distributor_artifact.json"));
  await install(BOARD, b.abi, b.bytecode); await install(DIST, dArt.abi, dArt.bytecode);
  await setS(BOARD, slot(b, "boardVersion"), 1); await setS(DIST, slot(dArt, "validatorDirectShareBps"), 5000);
  const reg = new hre.ethers.Contract(REG, mr.abi, deployer), board = new hre.ethers.Contract(BOARD, b.abi, deployer);
  for (let i = 0; i < 10; i++) { await (await reg.setActive(A[i].address, true)).wait(); await (await reg.setStatus(A[i].address, 2)).wait(); }
  // each voter may back at most 5 candidates: A0..A5 back A0..A4; A6..A9 back A0..A3 and A5
  // -> tallies A0..A3 = 10, A4 = 6, A5 = 4: A0..A4 are seated, A5 is the eligible successor after an exit
  for (let v = 0; v < 10; v++) for (const c of (v < 6 ? [0, 1, 2, 3, 4] : [0, 1, 2, 3, 5])) await (await board.connect(A[v]).voteFor(A[c].address)).wait();
  await (await board.refreshBoard([])).wait(); // seats A0..A4, boardVersion 1 -> 2 (real change)
  ok("R0) هیأت واقعی با A0..A4 تشکیل شد؛ boardVersion=2", (await board.boardVersion()) === 2n && (await board.getBoardMembers()).length === 5);
  const d = (who) => new hre.ethers.Contract(DIST, dArt.abi, who);
  const share = async () => await d(deployer).validatorDirectShareBps();
  const propose = async (bps) => { await (await d(A[9]).proposeShareChange(bps)).wait(); return await d(deployer).shareProposalCount(); };
  const bv = (i, id) => d(A[i]).boardVoteShareChange(id), vv = (i, id) => d(A[i]).validatorVoteShareChange(id); // 10 active -> 7 validator votes
  // mirrors ValidatorsRegistry.requestExit(): _removeFromActive (isValidator=false), status=Exiting(4), membershipEpoch++
  const exitOf = async (i) => { await (await reg.setActive(A[i].address, false)).wait(); await (await reg.setStatus(A[i].address, 4)).wait(); await (await reg.bumpEpoch(A[i].address)).wait(); };
  let snap = await hre.network.provider.send("evm_snapshot");
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };

  { const P = await propose(5500); await exitOf(0);
    ok("R1a) پس از درخواست خروج و پیش از sync: isBoardMember(A0)=true ولی hasBoardAuthority(A0)=false (منطق خود Board)",
       (await board.isBoardMember(A[0].address)) === true && (await board.hasBoardAuthority(A[0].address)) === false);
    ok("R1b) Distributor رأی هیأت A0 را رد می‌کند", await reverts(() => bv(0, P), "caller has no live board authority")); }
  await fresh();
  { const P = await propose(5500); await (await bv(0, P)).wait(); await (await bv(1, P)).wait();
    await exitOf(4); await (await board.syncBoard()).wait();
    ok("R2a) syncBoard پس از خروج A4 ترکیب را واقعاً تغییر داد (A5 جانشین شد) و boardVersion افزایش یافت",
       (await board.boardVersion()) === 3n && (await board.isBoardMember(A[5].address)) === true);
    ok("R2b) رأی سوم (A5، ترکیب جدید) با دو رأی ترکیب قدیم جمع نمی‌شود", await reverts(() => bv(5, P), "board membership changed since this proposal was created"));
    ok("R2c) عضو باقی‌مانده‌ی ترکیب قدیم (A2) هم دیگر روی این پیشنهاد رأی نمی‌دهد", await reverts(() => bv(2, P), "board membership changed since this proposal was created")); }
  await fresh();
  { const P = await propose(5500);
    for (let i = 0; i < 3; i++) await (await bv(i, P)).wait();
    for (let i = 0; i < 6; i++) await (await vv(i, P)).wait();
    ok("R3a) مجلس هیأت پاس شد (boardPassed=true) و ۶ از ۷ رأی ولیدیتورها ثبت شد", (await d(deployer).shareProposals(P)).boardPassed === true);
    await exitOf(4); await (await board.syncBoard()).wait();
    ok("R3b) تغییر واقعی ترکیب پس از boardPassed و پیش از رأی آخر ولیدیتورها: اجرای نهایی رد می‌شود", await reverts(() => vv(6, P), "board membership changed since this proposal was created"));
    ok("R3c) سهم تغییر نکرد", (await share()) === 5000n); }
  await fresh();
  { const P = await propose(5500);
    for (let i = 0; i < 2; i++) await (await bv(i, P)).wait();
    await warpTo(await nextMonthStart()); const v0 = await board.boardVersion(); await (await board.refreshBoard([])).wait();
    ok("R4a) refresh of the next calendar month without a composition change does not change boardVersion", (await board.boardVersion()) === v0);
    // the proposal is still inside its 30-day expiry? created before inc(30d+1) -> expired. Re-run inside expiry:
  }
  await fresh();
  { const nm = await nextMonthStart(); await warpTo(nm - 86400); const P = await propose(5500); // proposal created just before the month boundary
    for (let i = 0; i < 2; i++) await (await bv(i, P)).wait();
    await warpTo(nm); const v0 = await board.boardVersion(); await (await board.refreshBoard([])).wait();
    const same = (await board.boardVersion()) === v0;
    await (await bv(2, P)).wait(); for (let i = 0; i < 7; i++) await (await vv(i, P)).wait();
    ok("R4b) پس از refresh بدون تغییر واقعی، همان پیشنهاد معتبر ماند و اجرا شد", same && (await share()) === 5500n); }
  await fresh();
  { const P = await propose(5500); await (await reg.setStatus(A[1].address, 3)).wait(); // Demoted (suspended), not Exiting
    ok("R5a) عضو معلق (Demoted) طبق Board واقعی اختیار زنده دارد", (await board.hasBoardAuthority(A[1].address)) === true);
    await (await bv(1, P)).wait();
    ok("R5b) و Distributor رأی هیأت او را می‌پذیرد (تفاوت تعلیق و خروج از Board ارث برده شد)", (await d(deployer).shareProposals(P)).boardApprovals === 1n); }

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
