// BH-01 Genesis boots with the NEW (v2.5 owner decisions, commit e1a5f1f) bytecode. Net-A, all 7 founder nodes running, only owner1 Active.
// New in round 1b: Probation founders hold board seats (getBoardSize 5) but hasBoardAuthority is false for owners 2..5, true for owner 1;
// syncBoard() by a stranger does not remove them.
const { Net, Checks, writeResult, ethers, ADDR, send, expectRevert, findEvent, ifaceOf, sealSigners, sameSet, E } = require("./lib");
const crypto = require("crypto");
const fs = require("fs");
(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const p = net.provider;
  const reg = net.c("REG"), board = net.c("BOARD");
  const op1 = net.addr("op1"), own = (i) => net.addr("owner" + i);
  const summary = JSON.parse(fs.readFileSync(require("path").join(E, "evidence/02-genesis/Net-A/build-summary.json"), "utf8"));
  const old = JSON.parse(fs.readFileSync(require("path").join(E, "../besu-live-test-v25-2026-11-19/evidence/02-genesis/Net-A/build-summary.json"), "utf8"));
  const net_ver = await p.send("web3_clientVersion", []);
  const h0 = await net.head(); await net.waitBlocks(5); const h1 = await net.head();
  c.ok("blocks are produced (head advanced by >=5)", h1 >= h0 + 5, { h0, h1 });
  // the bytecode on chain is the new one
  const codeHash = {};
  for (const [k, name] of [["REG", "ValidatorsRegistry"], ["NFT", "ValidatorSeatNFT"], ["BOARD", "ValidatorsBoard"]]) {
    const code = await p.getCode(ADDR[k]);
    codeHash[name] = crypto.createHash("sha256").update(Buffer.from(code.slice(2), "hex")).digest("hex");
    c.ok(`eth_getCode(${name}) sha256 == the freshly compiled runtime code of this run, and != the round-1 code`, codeHash[name] === summary.contracts[name].runtimeCodeSha256 && codeHash[name] !== old.contracts[name].runtimeCodeSha256, { onChain: codeHash[name], round1: old.contracts[name].runtimeCodeSha256 });
  }
  const gv = Array.from(await reg.getValidators());
  c.ok("Registry.getValidators() == [operator1]", gv.length === 1 && gv[0] === op1, gv);
  const head = await net.head();
  const q = await net.qbftValidators(head);
  c.ok("qbft_getValidatorsByBlockNumber(latest) == [operator1]", q.length === 1 && ethers.getAddress(q[0]) === op1, q);
  const q1 = await net.qbftValidators(1);
  c.ok("qbft validators at block 1 == [operator1]", q1.length === 1 && ethers.getAddress(q1[0]) === op1, q1);
  const miners = []; for (let n = head - 4; n <= head; n++) miners.push(ethers.getAddress((await net.block(n)).miner));
  c.ok("miner of last 5 blocks is operator1", miners.every((m) => m === op1), miners);
  const sw = await Promise.all([1, 2, 3].map((n) => sealSigners(net, head - n, [op1])));
  c.ok("committed-seal signers recovered from the header all == operator1", sw.every((s) => s.signers && s.signers.every((a) => a === op1)), sw.map((s) => s.signers));
  const st = {}; for (let i = 1; i <= 7; i++) st["owner" + i] = Number((await reg.validators(own(i))).status);
  c.ok("only owner1 Active (2) at genesis, owners 2..7 Probation (1)", st.owner1 === 2 && [2, 3, 4, 5, 6, 7].every((i) => st["owner" + i] === 1), st);
  const nftOwners = []; for (let i = 1; i <= 7; i++) nftOwners.push(await net.c("NFT").ownerOf(i));
  c.ok("7 founder seats minted, seat i owned by owner i", (await net.c("NFT").totalMinted()) === 7n && nftOwners.every((a, i) => a === own(i + 1)), nftOwners);

  // ---- board
  const members = Array.from(await board.getBoardMembers());
  c.ok("getBoardSize() == 5 and the seats are owner1..owner5", (await board.getBoardSize()) === 5n && sameSet(members, [1, 2, 3, 4, 5].map(own)), members);
  const auth = {}; for (let i = 1; i <= 7; i++) auth["owner" + i] = await board.hasBoardAuthority(own(i));
  c.ok("hasBoardAuthority: true for owner1 (Active); FALSE for the Probation founders owner2..owner5 (seat holders)", auth.owner1 === true && [2, 3, 4, 5].every((i) => auth["owner" + i] === false), auth);
  c.ok("hasBoardAuthority false for owner6/owner7 (not board members)", auth.owner6 === false && auth.owner7 === false);
  c.ok("isBoardMember true for owner1..5 (the seats are held)", (await Promise.all([1, 2, 3, 4, 5].map((i) => board.isBoardMember(own(i))))).every((x) => x === true));
  const bv0 = await board.boardVersion();
  // a Probation founder cannot act
  const nProp = await expectRevert(net, "owner2", "BOARD", "proposeSetEntryCollateral", [ethers.parseEther("550000")]);
  c.ok("negative: Probation founder owner2 cannot propose (message 'caller has no board authority')", nProp.reverted && /no board authority/.test(nProp.reason || ""), nProp.reason);
  // syncBoard by a stranger leaves everything as it is
  const sync = await send(net, "outsider", "BOARD", "syncBoard", []);
  const ended = findEvent(sync.receipt, ifaceOf("BOARD"), "BoardMemberAuthorityEnded");
  const members2 = Array.from(await board.getBoardMembers());
  c.ok("syncBoard() by a stranger: no BoardMemberAuthorityEnded event, getBoardSize() still 5, same members, boardVersion unchanged", ended.length === 0 && (await board.getBoardSize()) === 5n && sameSet(members2, members) && (await board.boardVersion()) === bv0, { block: sync.block, gasUsed: sync.gasUsed, boardVersion: bv0 });
  const auth2 = {}; for (let i = 1; i <= 5; i++) auth2["owner" + i] = await board.hasBoardAuthority(own(i));
  c.ok("after syncBoard: authority flags unchanged (owner1 true, owners 2..5 false)", auth2.owner1 === true && [2, 3, 4, 5].every((i) => auth2["owner" + i] === false), auth2);
  // oracle overlays, sizes
  c.ok("Registry.verifier == test verifier", (await reg.verifier()) === net.addr("verifier"));
  const sizes = {}; for (const k of ["DAO", "REG", "BOARD", "NFT"]) sizes[k] = (await p.getCode(ADDR[k])).length / 2 - 0.5;
  c.ok("Registry still above 24,576 bytes and live through alloc", sizes.REG > 24576, sizes);
  const metrics = await p.send("qbft_getSignerMetrics", []).catch((e) => String(e.message));
  writeResult("BH-01", { verdict: c.verdict, summary: `head=${head}, validators=[operator1], board 5 seats, authority only for owner1, syncBoard keeps 5`, besu: net_ver, checks: c.items, codeHash, qbftValidatorsLatest: q, signerMetrics: metrics, syncBoardTx: sync.hash, negatives: { probationProposal: nProp } });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
