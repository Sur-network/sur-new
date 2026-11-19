// BG-10 ValidatorLottery commit-reveal on a live chain (Net-S): DAO StartLottery proposal -> tickets -> commit -> close -> reveal -> draw,
// real 2-second blocks (target = close block + 10, reveal window 250 blocks), seed and winners recomputed off-chain.
// Also BG-10-BH: blockhash behaviour on Besu QBFT (probe contract, offsets around the 256-block horizon).
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, S, findEvent, ifaceOf, ADDR, GAS_PRICE } = require("./lib");
const { replicaDraw, startLotteryViaDao, makeManyFullyVerified } = require("./lib-lottery");

(async () => {
  const net = new Net("S", "n1");
  const c = new Checks();
  const t0 = Date.now();
  const lot = net.c("LOTTERY");
  const timeline = {};
  const stamp = async (k) => { timeline[k] = { wallClockUTC: new Date().toISOString(), block: await net.head() }; };

  // identities for the 6 ticket buyers (+ the CEO must NOT be able to buy)
  await stamp("start");
  const roles = ["lot1", "lot2", "lot3", "lot4", "lot5", "lot6"];
  const idTxs = await makeManyFullyVerified(net, roles);
  await stamp("identities_done");
  for (const r of roles) c.ok(`${r} fully verified`, await net.c("IDENTITY").isFullyVerified(net.addr(r)));
  c.ok("outsider (not registered) is not fully verified", !(await net.c("IDENTITY").isFullyVerified(net.addr("outsider"))));

  // ---- DAO StartLottery (3 of 5)
  const price = S(10), winnersCount = 3;
  const st = await startLotteryViaDao(net, price, winnersCount, 150);
  await stamp("lottery_started");
  c.ok("StartLottery proposal: proposer's vote counts automatically (1 vote), required = 3", st.votesAfterPropose === 1 && st.requiredVotes === 3, st);
  c.ok("after 2 votes still Pending (0), after 3rd vote Executed (1)", st.statusAfterTwo === 0 && st.statusAfterThree === 1 && st.votesAfterThree === 3, st);
  c.ok("vote(id, paramsHash): hash from computeParamsHash == stored paramsHash", st.hashMatchesStored);
  let L = await lot.getLottery(1);
  c.ok("lottery #1 Open (phase 1) with the proposal's parameters", Number(L.phase) === 1 && L.ticketPrice === price && Number(L.winnersCount) === 3 && Number(L.closeTime) === st.closeTime, { phase: Number(L.phase), closeTime: Number(L.closeTime) });
  c.ok("lotteryCount == 1", (await lot.lotteryCount()) === 1n);

  // ---- negative checks while open
  const neg = {};
  neg.ceoBuy = await expectRevert(net, "ceo", "LOTTERY", "buyTicket", [], { value: price });
  neg.outsiderBuy = await expectRevert(net, "outsider", "LOTTERY", "buyTicket", [], { value: price });
  neg.wrongPrice = await expectRevert(net, "lot1", "LOTTERY", "buyTicket", [], { value: price - 1n });
  neg.closeEarly = await expectRevert(net, "tester", "LOTTERY", "closeLottery", []);
  neg.commitNotCeo = await expectRevert(net, "lot1", "LOTTERY", "commitSecret", [ethers.keccak256("0x01")]);
  neg.drawEarly = await expectRevert(net, "tester", "LOTTERY", "drawBatch", [1]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);

  // ---- tickets
  const buyTxs = [];
  for (const r of roles) { const x = await send(net, r, "LOTTERY", "buyTicket", [], { value: price }); buyTxs.push(x.hash); }
  const dup = await expectRevert(net, "lot1", "LOTTERY", "buyTicket", [], { value: price });
  c.ok("negative: second ticket from the same address reverts", dup.reverted, dup.reason);
  const participants = Array.from(await lot.participantsOf(1));
  c.ok("6 participants recorded in order of purchase", participants.length === 6 && participants.every((a, i) => a === net.addr(roles[i])), participants);
  L = await lot.getLottery(1);
  c.ok("pot == 6 x 10 Suren; lottery contract balance == pot", L.pot === price * 6n && (await net.balance(ADDR.LOTTERY)) === price * 6n, { pot: L.pot, bal: await net.balance(ADDR.LOTTERY) });
  await stamp("tickets_bought");

  // ---- commit (CEO)
  const secret = ethers.hexlify(ethers.randomBytes(32));
  const commitment = ethers.keccak256(secret); // keccak256(abi.encodePacked(bytes32)) == keccak256(secret bytes)
  const cm = await send(net, "ceo", "LOTTERY", "commitSecret", [commitment]);
  const cm2 = await expectRevert(net, "ceo", "LOTTERY", "commitSecret", [ethers.keccak256("0x02")]);
  c.ok("CEO commitment stored; a second commitment reverts", (await lot.getLottery(1)).commitment === commitment && cm2.reverted, cm2.reason);
  await stamp("committed");

  // ---- wait for closeTime (chain time), then anyone closes
  for (;;) { const b = await net.block("latest"); if (Number(BigInt(b.timestamp)) >= st.closeTime) break; await sleep(500); }
  const buyLate = await expectRevert(net, "lot1", "LOTTERY", "buyTicket", [], { value: price });
  c.ok("negative: ticket after closeTime reverts", buyLate.reverted, buyLate.reason);
  const cl = await send(net, "tester", "LOTTERY", "closeLottery", []);
  const closeEv = findEvent(cl.receipt, ifaceOf("LOTTERY"), "LotteryClosed")[0];
  const target = Number(closeEv.args.targetBlock);
  c.ok("closeLottery: targetBlock == closeBlock + 10 (TARGET_DELAY)", target === cl.block + 10, { closeBlock: cl.block, target });
  L = await lot.getLottery(1);
  c.ok("phase Closed (2)", Number(L.phase) === 2);
  await stamp("closed");
  const early = await expectRevert(net, "ceo", "LOTTERY", "reveal", [secret]);
  c.ok("negative: reveal before the target block is mined reverts", early.reverted, early.reason);
  const badSecret = await (async () => { await net.waitForBlock(target + 1); return expectRevert(net, "ceo", "LOTTERY", "reveal", [ethers.hexlify(ethers.randomBytes(32))]); })();
  c.ok("negative: wrong secret reverts", badSecret.reverted, badSecret.reason);
  const notCeo = await expectRevert(net, "tester", "LOTTERY", "reveal", [secret]);
  c.ok("negative: reveal by a non-CEO reverts", notCeo.reverted, notCeo.reason);

  // ---- reveal
  const rv = await send(net, "ceo", "LOTTERY", "reveal", [secret]);
  const targetBlock = await net.block(target);
  const seedOnChain = (await lot.getLottery(1)).seed;
  const seedLocal = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32"], [secret, targetBlock.hash]));
  c.ok("seed == keccak256(abi.encode(secret, blockhash(target))) recomputed with eth_getBlockByNumber(target).hash", seedOnChain === seedLocal, { seedOnChain, seedLocal, targetHash: targetBlock.hash });
  c.ok("reveal landed inside the window (target < revealBlock <= target+250)", rv.block > target && rv.block <= target + 250, { revealBlock: rv.block, target, blocksAfterTarget: rv.block - target });
  await stamp("revealed");

  // ---- draw in two batches (partial Fisher-Yates), anyone
  const daoBefore = await net.balance(ADDR.DAO);
  const d1 = await send(net, "tester", "LOTTERY", "drawBatch", [2]);
  const midWinners = Array.from(await lot.winnersOf(1));
  c.ok("after drawBatch(2): 2 winners, phase still Revealed (3)", midWinners.length === 2 && Number((await lot.getLottery(1)).phase) === 3, midWinners);
  const d2 = await send(net, "tester", "LOTTERY", "drawBatch", [10]);
  const winners = Array.from(await lot.winnersOf(1));
  const expected = replicaDraw(seedOnChain, participants, winnersCount);
  c.ok("3 winners == off-chain replica of the Fisher-Yates draw", winners.length === 3 && winners.every((w, i) => w === expected[i]), { winners, expected });
  c.ok("winners are distinct participants", new Set(winners).size === 3 && winners.every((w) => participants.includes(w)));
  L = await lot.getLottery(1);
  c.ok("phase Drawn (4), pot cleared, lottery balance 0", Number(L.phase) === 4 && L.pot === 0n && (await net.balance(ADDR.LOTTERY)) === 0n);
  const daoAfter = await net.balance(ADDR.DAO);
  c.ok("pot (60 Suren) transferred to FoundationDAO", daoAfter - daoBefore === price * 6n, { diff: daoAfter - daoBefore });
  const reg = net.c("REG"), nft = net.c("NFT");
  const sts = []; for (const w of winners) sts.push(Number((await reg.validators(w)).status));
  c.ok("every winner registered in the Registry as Probation (1) with no collateral", sts.every((s) => s === 1), sts);
  const lockedStakes = []; for (const w of winners) lockedStakes.push((await reg.validators(w)).lockedStake.toString());
  c.ok("winners hold zero collateral", lockedStakes.every((x) => x === "0"), lockedStakes);
  const seats = []; for (const w of winners) seats.push((await nft.seatOf(w)).toString());
  c.ok("every winner holds a ValidatorSeatNFT seat (ids 2,3,4), totalMinted == 4", (await nft.totalMinted()) === 4n && seats.every((x) => ["2", "3", "4"].includes(x)), seats);
  const noEntryFail = []; for (const w of winners) noEntryFail.push(await lot.entryFailed(1, w));
  c.ok("no WinnerEntryFailed", noEntryFail.every((x) => !x));
  const again = await expectRevert(net, "tester", "LOTTERY", "drawBatch", [1]);
  c.ok("negative: drawBatch after Drawn reverts", again.reverted, again.reason);
  const newStart = await expectRevert(net, "dao1", "DAO", "proposeStartLottery", [price, 1, Number(BigInt((await net.block("latest")).timestamp)) + 300]);
  await stamp("drawn");

  // ---- blockhash behaviour on Besu QBFT (BG-10-BH). Probe: LOG0 with [blockhash(calldata n), number] ; deployed by `tester`.
  const probeRuntime = "600035406000524360205260406000a000";
  const probeInit = "601180600b6000396000f3" + probeRuntime;
  const tester = net.w("tester");
  const dep = await tester.sendTransaction({ data: "0x" + probeInit, gasPrice: GAS_PRICE, type: 0, gasLimit: 200000n });
  const depRc = await dep.wait();
  const probe = depRc.contractAddress;
  c.ok("probe contract deployed on Besu (contract creation works)", !!probe && (await net.provider.getCode(probe)) === "0x" + probeRuntime, { probe, deployBlock: depRc.blockNumber });
  const need = 300;
  const hNow = await net.head();
  if (hNow < need) await net.waitForBlock(need);
  const rows = [];
  const base = (await net.head()) + 2; // block the first probe tx will probably land in
  const hashOf = async (n) => (await net.block(n)).hash;
  const sent = [];
  for (let off = 250; off <= 262; off++) {
    const n = base - off;
    const tx = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex(n), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n });
    sent.push({ n, tx });
  }
  for (const { n, tx } of sent) {
    const rc = await tx.wait();
    const log = rc.logs[0];
    const bh = ethers.dataSlice(log.data, 0, 32), exec = Number(BigInt(ethers.dataSlice(log.data, 32, 64)));
    const real = await hashOf(n);
    rows.push({ queriedBlock: n, executedInBlock: exec, offset: exec - n, blockhashReturned: bh, realHash: real, equalsReal: bh === real, isZero: BigInt(bh) === 0n });
  }
  const inWindow = rows.filter((r) => r.offset >= 1 && r.offset <= 256), outside = rows.filter((r) => r.offset > 256 || r.offset < 1);
  c.ok("blockhash(n) in a transaction == real block hash for 1 <= offset <= 256", inWindow.length > 0 && inWindow.every((r) => r.equalsReal), inWindow.map((r) => [r.offset, r.equalsReal]));
  c.ok("blockhash(n) == 0 for offset > 256 (expired)", outside.filter((r) => r.offset > 256).length > 0 && outside.filter((r) => r.offset > 256).every((r) => r.isZero), outside.map((r) => [r.offset, r.isZero]));
  // current / future block inside a transaction
  const cur = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex((await net.head()) + 50), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n });
  const curRc = await cur.wait();
  c.ok("blockhash(future block) == 0 in a transaction", BigInt(ethers.dataSlice(curRc.logs[0].data, 0, 32)) === 0n);
  const sameBlk = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex((await net.head()) + 1), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n });
  const sameRc = await sameBlk.wait();
  const sameExec = Number(BigInt(ethers.dataSlice(sameRc.logs[0].data, 32, 64)));
  const sameNum = (await net.head());
  rows.push({ note: "tx asking blockhash(head+1) at send time; executed in block " + sameExec, blockhashReturned: ethers.dataSlice(sameRc.logs[0].data, 0, 32) });

  const wallSeconds = Math.round((Date.now() - t0) / 1000);
  writeResult("BG-10", { verdict: c.verdict, summary: `lottery #1 full cycle on Net-S: close block ${cl.block}, target ${target}, reveal block ${rv.block}, winners recomputed off-chain; blockhash probe rows ${rows.length}`, checks: c.items, timeline, wallSeconds, txs: { identity: idTxs, startLottery: st, tickets: buyTxs, commit: cm.hash, close: cl.hash, reveal: rv.hash, draw1: d1.hash, draw2: d2.hash }, participants, winners, seed: seedOnChain, targetBlock: { number: target, hash: targetBlock.hash }, probeContract: probe, blockhashRows: rows, secondLotteryProposalAttempt: newStart });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
