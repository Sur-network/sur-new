// BG-10 post-hoc verification from chain data (Net-S). The interactive run bg10.js completed the whole lottery cycle (stdout kept in
// logs/_scriptout/bg10.out, every line PASS) but crashed in its blockhash-probe tail before writing its JSON. This script rebuilds the evidence of the
// lottery cycle from the chain itself: events, the CEO's reveal calldata (secret), the target block hash, the Fisher-Yates replica.
const { Net, Checks, writeResult, ethers, ADDR, ifaceOf } = require("./lib");
const { replicaDraw } = require("./lib-lottery");
const fs = require("fs");

(async () => {
  const net = new Net("S", "n1");
  const c = new Checks();
  const LI = ifaceOf("LOTTERY"), DI = ifaceOf("DAO");
  const lot = net.c("LOTTERY");
  const get = async (addr, iface, name) => {
    const logs = await net.provider.getLogs({ address: addr, fromBlock: 0, toBlock: "latest", topics: [iface.getEvent(name).topicHash] });
    return logs.map((l) => ({ block: l.blockNumber, tx: l.transactionHash, args: iface.parseLog(l).args }));
  };
  const started = (await get(ADDR.LOTTERY, LI, "LotteryStarted"))[0];
  const tickets = await get(ADDR.LOTTERY, LI, "TicketBought");
  const committed = (await get(ADDR.LOTTERY, LI, "SecretCommitted"))[0];
  const closed = (await get(ADDR.LOTTERY, LI, "LotteryClosed"))[0];
  const revealed = (await get(ADDR.LOTTERY, LI, "SecretRevealed"))[0];
  const drawn = await get(ADDR.LOTTERY, LI, "WinnerDrawn");
  const done = (await get(ADDR.LOTTERY, LI, "LotteryDrawn"))[0];
  const failed = await get(ADDR.LOTTERY, LI, "WinnerEntryFailed");
  const execd = await get(ADDR.DAO, DI, "ProposalExecuted");
  const voted = await get(ADDR.DAO, DI, "Voted");
  const created = await get(ADDR.DAO, DI, "ProposalCreated");
  c.ok("DAO: StartLottery (type 10) proposal created, 3 Voted events, ProposalExecuted in the block of the 3rd vote (lottery started in that same block)", created.length === 1 && Number(created[0].args.pType) === 10 && voted.length === 3 && execd.length === 1 && execd[0].block === started.block && execd[0].block === voted[2].block, { createdBlock: created[0].block, voteBlocks: voted.map((v) => v.block), executedBlock: execd[0].block, lotteryStartedBlock: started.block });
  c.ok("LotteryStarted(1, ticket 10 Suren, 3 winners)", started.args.ticketPrice === ethers.parseEther("10") && Number(started.args.winnersCount) === 3, { closeTime: Number(started.args.closeTime) });
  c.ok("6 TicketBought events", tickets.length === 6, tickets.map((t) => t.block));
  const closeBlock = closed.block, target = Number(closed.args.targetBlock);
  c.ok("LotteryClosed: targetBlock == closeBlock + 10", target === closeBlock + 10, { closeBlock, target });
  const closeBlk = await net.block(closeBlock);
  c.ok("closed at/after closeTime (block timestamp >= closeTime)", Number(BigInt(closeBlk.timestamp)) >= Number(started.args.closeTime), { blockTs: Number(BigInt(closeBlk.timestamp)), closeTime: Number(started.args.closeTime) });
  c.ok("SecretCommitted before closeTime", Number(BigInt((await net.block(committed.block)).timestamp)) < Number(started.args.closeTime), { commitBlock: committed.block });
  c.ok("reveal inside the window: target < revealBlock <= target + 250", revealed.block > target && revealed.block <= target + 250, { revealBlock: revealed.block, blocksAfterTarget: revealed.block - target });
  const revealTx = await net.provider.getTransaction(revealed.tx);
  const secret = ethers.dataSlice(revealTx.data, 4, 36);
  c.ok("commitment == keccak256(secret) (secret read from the reveal transaction calldata)", ethers.keccak256(secret) === committed.args.commitment, { secret });
  const tb = await net.block(target);
  const seedLocal = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["bytes32", "bytes32"], [secret, tb.hash]));
  c.ok("seed (event) == keccak256(abi.encode(secret, eth_getBlockByNumber(target).hash)) recomputed off-chain", seedLocal === revealed.args.seed, { target, targetHash: tb.hash, seed: seedLocal });
  const participants = Array.from(await lot.participantsOf(1));
  const winnersChain = Array.from(await lot.winnersOf(1));
  const expected = replicaDraw(revealed.args.seed, participants, 3);
  c.ok("3 WinnerDrawn events == off-chain replica of the partial Fisher-Yates draw", drawn.length === 3 && winnersChain.every((w, i) => w === expected[i]) && drawn.every((d, i) => d.args.winner === expected[i]), { winners: winnersChain, drawBlocks: drawn.map((d) => d.block) });
  c.ok("two draw batches (2 + 1 winners in different blocks), LotteryDrawn(3 winners, pot 60 Suren)", new Set(drawn.map((d) => d.block)).size === 2 && Number(done.args.winners) === 3 && done.args.pot === ethers.parseEther("60"), { drawBlocks: drawn.map((d) => d.block), doneBlock: done.block });
  c.ok("no WinnerEntryFailed", failed.length === 0);
  const L = await lot.getLottery(1);
  c.ok("lottery #1 phase Drawn (4), pot 0, contract balance 0", Number(L.phase) === 4 && L.pot === 0n && (await net.balance(ADDR.LOTTERY)) === 0n);
  const reg = net.c("REG"), nft = net.c("NFT");
  const st = []; for (const w of winnersChain) st.push([Number((await reg.validators(w)).status), (await reg.validators(w)).lockedStake.toString(), (await nft.seatOf(w)).toString()]);
  c.ok("each winner: Registry Probation (1), zero collateral, holds a seat NFT", st.every((x) => x[0] === 1 && x[1] === "0" && Number(x[2]) >= 2), st);
  const timeline = { startBlock: started.block, ticketBlocks: tickets.map((t) => t.block), commitBlock: committed.block, closeBlock, targetBlock: target, revealBlock: revealed.block, drawBlocks: drawn.map((d) => d.block), blockSecondsStartToDrawn: Number(BigInt((await net.block(done.block)).timestamp)) - Number(BigInt((await net.block(started.block)).timestamp)), blockSecondsCloseToReveal: Number(BigInt((await net.block(revealed.block)).timestamp)) - Number(BigInt(closeBlk.timestamp)) };
  const interactive = fs.readFileSync(require("path").join(__dirname, "..", "logs", "_scriptout", "bg10.out"), "utf8").split("\n").filter((l) => /^\s+(PASS|FAIL)/.test(l));
  c.ok("interactive run stdout: all recorded check lines are PASS (" + interactive.length + " lines: identities, negatives, tickets, pot, commit, close, reveal, draw, DAO pot transfer, winners entered, seats)", interactive.length > 40 && interactive.every((l) => /PASS/.test(l)), { lines: interactive.length });
  writeResult("BG-10", { verdict: c.verdict, summary: `lottery #1 full commit-reveal cycle on Net-S: close block ${closeBlock}, target ${target}, reveal ${revealed.block} (${revealed.block - target} blocks after target), 3 winners reproduced off-chain`, checks: c.items, timeline, participants, winners: winnersChain, seed: revealed.args.seed, targetBlock: { number: target, hash: tb.hash }, note: "built post-hoc from chain data; the live interactive checks (negatives, pot->DAO transfer, ids) are the PASS lines of logs/_scriptout/bg10.out; blockhash behaviour: BG-10-BH", interactiveStdoutPassLines: interactive.length });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
