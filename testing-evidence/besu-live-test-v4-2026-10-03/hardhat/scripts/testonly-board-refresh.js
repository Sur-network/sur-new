// A09 fix verification: ValidatorsBoard.lastBoardRefreshAt must equal the genesis timestamp when the board is seeded, and refreshBoard() must be rejected before BOARD_REFRESH_INTERVAL (30 days) has elapsed.
// env: NET (Net-BR = fixed builder; Net-BR0 = NEGATIVE CONTROL built with BUILDER_BOARD_REFRESH_ZERO=1 = the old value 0), PORT, MODE=FIXED|CONTROL.
// FIXED:   real transactions on the fresh network: refreshBoard() reverts with the exact message (eth_call AND mined, state unchanged); syncBoard() stays the separate exit path (a validator that exits is removed by syncBoard()
//          while refreshBoard() is still rejected, and syncBoard() does not touch lastBoardRefreshAt).
// CONTROL: read-only (eth_call only, nothing mined): the SAME assertions are evaluated; the control is expected to FAIL R1 and R4 (that is what "the test detects the defect" means) and refreshBoard() is callable at once.
const fs = require("fs");
const { ethers, ADDR, accounts, saveEvidence } = require("./v5-lib");
const NET = process.env.NET, PORT = process.env.PORT, MODE = process.env.MODE || "FIXED";
const E18 = 10n ** 18n, DAY = 86400n;
const EXPECT_MSG = "ValidatorsBoard: ordinary board changes are applied once every 30 days";
const BOARD_ABI = [
  "function lastBoardRefreshAt() view returns (uint256)", "function BOARD_REFRESH_INTERVAL() view returns (uint256)", "function boardVersion() view returns (uint256)",
  "function getBoardMembers() view returns (address[])", "function isBoardMember(address) view returns (bool)", "function hasBoardAuthority(address) view returns (bool)",
  "function pendingVacancies() view returns (uint256)", "function refreshBoard()", "function syncBoard()",
];
const REG_ABI = ["function requestExit()", "function isValidator(address) view returns (bool)", "function getValidators() view returns (address[])"];
const reason = (e) => e.reason || e.shortMessage || e.message;

async function main() {
  const provider = new ethers.JsonRpcProvider(`http://127.0.0.1:${PORT}`);
  const board = (w) => new ethers.Contract(ADDR.BOARD, BOARD_ABI, w || provider);
  const reg = (w) => new ethers.Contract(ADDR.REGISTRY, REG_ABI, w || provider);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const founders = ["g5_v1", "g5_v2", "g5_v3", "g5_v4", "g5_v5"].map((k) => new ethers.Wallet(accounts[k].privateKey, provider));
  const out = { NET, MODE, startedAt: new Date().toISOString(), steps: [], assertions: [] };
  const A = (id, text, expected, actual, pass) => { out.assertions.push({ id, text, expected: String(expected), actual: String(actual), pass: !!pass }); console.log(pass ? "PASS" : "FAIL", id, text, "| expected", String(expected), "| actual", String(actual)); return !!pass; };
  const tx = async (label, promise) => { const t = await promise; const r = await t.wait(); out.steps.push({ label, hash: r.hash, block: r.blockNumber, status: r.status, gasUsed: r.gasUsed.toString() }); return r; };
  const callMsg = async (fn) => { try { await fn(); return "NO_REVERT (call succeeded)"; } catch (e) { return reason(e); } };
  const snap = async () => ({ lastBoardRefreshAt: (await board().lastBoardRefreshAt()).toString(), boardVersion: (await board().boardVersion()).toString(), members: [...(await board().getBoardMembers())].join(","), pendingVacancies: (await board().pendingVacancies()).toString() });

  const g0 = await provider.send("eth_getBlockByNumber", ["0x0", false]);
  const genesisTs = BigInt(g0.timestamp);
  const genesisFile = JSON.parse(fs.readFileSync(`D:/Amir/Business/SUR/Test/besu-test-v4/nets/${NET}/genesis.json`, "utf8"));
  const gfTs = BigInt(genesisFile.timestamp);
  out.genesisTimestamp = genesisTs.toString();
  const head = await provider.getBlock("latest");
  out.headAtStart = { number: head.number, timestamp: head.timestamp };
  // pristine check: no transaction in any block so far (this network is used for this test only)
  let txs = 0; for (let n = 1; n <= head.number; n++) txs += (await provider.send("eth_getBlockByNumber", ["0x" + n.toString(16), false])).transactions.length;
  A("R0", "pristine: no transaction in blocks 1..head before this test", 0, txs, txs === 0);

  // ---- R1 getter equals the genesis timestamp (block 0 header, genesis file, raw storage slot) ----
  const last0 = await board().lastBoardRefreshAt();
  A("R1.1", "block-0 header timestamp equals the genesis.json timestamp (reference value)", gfTs.toString(), genesisTs.toString(), gfTs === genesisTs);
  A("R1.2", "ValidatorsBoard.lastBoardRefreshAt() == genesis timestamp", genesisTs.toString(), last0.toString(), last0 === genesisTs);
  const layout = JSON.parse(fs.readFileSync("D:/Amir/Business/SUR/Test/besu-test-v4/evidence/00-baseline/storage-layout-ValidatorsBoard.json", "utf8"));
  const slotIdx = layout.lastBoardRefreshAt;
  const raw = BigInt(await provider.send("eth_getStorageAt", [ADDR.BOARD, "0x" + BigInt(slotIdx).toString(16), "latest"]));
  A("R1.3", `raw storage slot ${slotIdx} (lastBoardRefreshAt) equals the genesis timestamp`, genesisTs.toString(), raw.toString(), raw === genesisTs);
  const gAlloc = genesisFile.alloc[ADDR.BOARD.slice(2)] || genesisFile.alloc[ADDR.BOARD] || genesisFile.alloc[ADDR.BOARD.toLowerCase()];
  const gVal = BigInt((gAlloc.storage || {})["0x" + BigInt(slotIdx).toString(16).padStart(64, "0")] || "0x0");
  A("R1.4", "genesis.json alloc has the same value at that slot", genesisTs.toString(), gVal.toString(), gVal === genesisTs);
  const interval = await board().BOARD_REFRESH_INTERVAL();
  A("R2.1", "BOARD_REFRESH_INTERVAL() = 30 days", String(30n * DAY), interval.toString(), interval === 30n * DAY);
  const members0 = await board().getBoardMembers();
  A("R2.2", "board seeded with 5 members, boardVersion 1", "5;1", `${members0.length};${await board().boardVersion()}`, members0.length === 5 && (await board().boardVersion()) === 1n);

  // ---- R3 elapsed time is far below 30 days ----
  const now = await provider.getBlock("latest");
  const elapsed = BigInt(now.timestamp) - last0;
  const remaining = last0 + interval - BigInt(now.timestamp);
  out.timing = { blockNumber: now.number, blockTimestamp: now.timestamp, lastBoardRefreshAt: last0.toString(), elapsedSeconds: elapsed.toString(), remainingSeconds: remaining.toString() };
  A("R3.1", "block.timestamp < lastBoardRefreshAt + 30 days (elapsed since genesis is minutes, remaining ≈ 30 days)", "elapsed < 30 d", `elapsed ${elapsed} s; remaining ${remaining} s`, BigInt(now.timestamp) < last0 + interval);

  // ---- R4 refreshBoard() before the 30 days: eth_call ----
  const caller = founders[0];
  const msg = await callMsg(() => board(caller).refreshBoard.staticCall());
  A("R4.1", "refreshBoard() (eth_call, any caller) is rejected with the exact message", EXPECT_MSG, msg, msg.includes(EXPECT_MSG));
  const msgOracle = await callMsg(() => board(oracle).refreshBoard.staticCall());
  A("R4.2", "same rejection for a caller that is not a validator (permissionless function, same gate)", EXPECT_MSG, msgOracle, msgOracle.includes(EXPECT_MSG));

  if (MODE === "FIXED") {
    // ---- R5 mined: status 0, nothing changes ----
    const before = await snap();
    let st; try { const t = await board(caller).refreshBoard({ gasLimit: 800000 }); st = (await t.wait()).status; out.steps.push({ label: "refreshBoard (mined, before 30 days)", status: st, hash: t.hash }); } catch (e) { st = 0; out.steps.push({ label: "refreshBoard (mined, before 30 days)", status: 0, hash: e.receipt ? e.receipt.hash : null, note: reason(e) }); }
    const after = await snap();
    A("R5.1", "refreshBoard() mined before 30 days: status 0 (reverted)", 0, st, st === 0);
    A("R5.2", "board state unchanged by the reverted call (members, boardVersion, lastBoardRefreshAt, pendingVacancies)", JSON.stringify(before), JSON.stringify(after), JSON.stringify(before) === JSON.stringify(after));

    // ---- R6 syncBoard() is the separate exit path ----
    const s0 = await snap();
    await tx("syncBoard() with no exit pending (no-op)", board(caller).syncBoard({ gasLimit: 800000 }));
    const s1 = await snap();
    A("R6.1", "syncBoard() succeeds within the 30 days (no 30-day gate) and is a no-op when nobody exited", JSON.stringify(s0), JSON.stringify(s1), JSON.stringify(s0) === JSON.stringify(s1));
    const V5 = founders[4];
    A("R6.2", "V5 is a seated board member with authority before its exit", "true;true", `${await board().isBoardMember(V5.address)};${await board().hasBoardAuthority(V5.address)}`, (await board().isBoardMember(V5.address)) && (await board().hasBoardAuthority(V5.address)));
    await tx("V5 requestExit()", reg(V5).requestExit({ gasLimit: 800000 }));
    A("R6.3", "after requestExit: V5 loses board authority immediately but is still listed (not yet synced)", "false;true", `${await board().hasBoardAuthority(V5.address)};${await board().isBoardMember(V5.address)}`, !(await board().hasBoardAuthority(V5.address)) && (await board().isBoardMember(V5.address)));
    const msgDuring = await callMsg(() => board(caller).refreshBoard.staticCall());
    A("R6.4", "with an exit pending, refreshBoard() is STILL rejected by the 30-day gate (it is not the exit path)", EXPECT_MSG, msgDuring, msgDuring.includes(EXPECT_MSG));
    const pre = await snap();
    await tx("syncBoard() after V5's exit", board(caller).syncBoard({ gasLimit: 1500000 }));
    const post = await snap();
    A("R6.5", "syncBoard() removes V5: 4 members, V5 no longer seated, boardVersion 2", "4;false;2", `${(await board().getBoardMembers()).length};${await board().isBoardMember(V5.address)};${post.boardVersion}`, (await board().getBoardMembers()).length === 4 && !(await board().isBoardMember(V5.address)) && post.boardVersion === "2");
    A("R6.6", "syncBoard() does NOT touch lastBoardRefreshAt (still the genesis timestamp)", genesisTs.toString(), post.lastBoardRefreshAt, post.lastBoardRefreshAt === genesisTs.toString() && pre.lastBoardRefreshAt === post.lastBoardRefreshAt);
    out.syncBoardObservation = { pendingVacanciesBefore: pre.pendingVacancies, pendingVacanciesAfter: post.pendingVacancies, membersAfter: post.members.split(",").length, note: "no eligible outside candidate exists on this G5 network, so the freed seat stays vacant (contract behaviour); recorded as is" };
    const msgAfter = await callMsg(() => board(caller).refreshBoard.staticCall());
    A("R6.7", "after the exit-driven sync the 30-day gate still applies to refreshBoard() (board is not empty, < 30 days)", EXPECT_MSG, msgAfter, msgAfter.includes(EXPECT_MSG));
    const vals = await reg().getValidators();
    A("R6.8", "V5 left the validator set (4 validators); the network kept producing blocks", "4", `${vals.length}`, vals.length === 4);
    const h1 = (await provider.getBlock("latest")).number; await new Promise((r) => setTimeout(r, 15000)); const h2 = (await provider.getBlock("latest")).number;
    A("R6.9", "block production continues after the exit (≥ 3 new blocks in 15 s)", ">= 3", h2 - h1, h2 - h1 >= 3);
  }

  out.finishedAt = new Date().toISOString();
  out.summary = { total: out.assertions.length, pass: out.assertions.filter((a) => a.pass).length, fail: out.assertions.filter((a) => !a.pass).length, failing: out.assertions.filter((a) => !a.pass).map((a) => a.id) };
  if (MODE === "CONTROL") {
    const mustFail = ["R1.2", "R1.3", "R1.4", "R3.1", "R4.1", "R4.2"].filter((id) => !out.assertions.find((a) => a.id === id).pass);
    out.negativeControl = { expectedToFail: ["R1.2", "R1.3", "R1.4", "R3.1", "R4.1", "R4.2"], actuallyFailed: out.summary.failing, defectDetected: ["R1.2", "R4.1"].every((id) => !out.assertions.find((a) => a.id === id).pass), refreshBoardCallableImmediately: out.assertions.find((a) => a.id === "R4.1").actual.startsWith("NO_REVERT"), note: "R3.1 also fails on the control: with value 0 the elapsed time since lastBoardRefreshAt exceeds 30 days, which is exactly why refreshBoard() is callable at once" };
  }
  console.log(JSON.stringify(out.summary), out.negativeControl ? JSON.stringify(out.negativeControl) : "");
  saveEvidence(`${NET}-board-refresh.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
