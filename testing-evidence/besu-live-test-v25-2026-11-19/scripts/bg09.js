// BG-09 FoundationDAO on a live chain (Net-A): typed Spend proposal (3 of 5), typed-hash voting, Execute proposal; getProposal readable. Also BG-SIZE for the 28 KB DAO.
const { Net, Checks, writeResult, ethers, send, expectRevert, S, findEvent, ifaceOf, ADDR } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const dao = net.c("DAO");
  const iface = ifaceOf("DAO");
  const board = Array.from(await dao.getBoard());
  const exp = [1, 2, 3, 4, 5].map((i) => net.addr("dao" + i));
  c.ok("getBoard() == dao1..dao5 (5 principals seeded at genesis)", board.length === 5 && board.every((a, i) => a === exp[i]), board);
  c.ok("alternates == dao6, dao7; inspector, ceo as seeded", JSON.stringify(Array.from(await dao.getAlternates())) === JSON.stringify([net.addr("dao6"), net.addr("dao7")]) && (await dao.ceo()) === net.addr("ceo") && (await dao.inspector()) === net.addr("inspector"));
  const codeLen = ((await net.provider.getCode(ADDR.DAO)).length - 2) / 2;
  c.ok("BG-SIZE: the 28,365-byte FoundationDAO (> 24,576) answers calls on Besu", codeLen > 24576 && board.length === 5, { codeLen });

  // ---- Spend
  const amount = S(600000);
  const buyer = net.addr("buyer");
  const daoBal0 = await net.balance(ADDR.DAO), buyerBal0 = await net.balance(buyer);
  const r = await send(net, "dao1", "DAO", "proposeSpend", [ethers.ZeroAddress, buyer, amount, "BG-09 test spend (funds the seat buyer)"]);
  const id = Number(await dao.proposalCount());
  const created = findEvent(r.receipt, iface, "ProposalCreated")[0], params = findEvent(r.receipt, iface, "ProposalParams")[0], voted = findEvent(r.receipt, iface, "Voted");
  c.ok("ProposalCreated + ProposalParams + auto Voted(1/3) events", !!created && !!params && voted.length === 1 && Number(voted[0].args.votes) === 1 && Number(voted[0].args.requiredVotes) === 3, { id, gasUsed: r.gasUsed });
  let p = await dao.getProposal(id);
  c.ok("getProposal: typed fields readable (pType Spend=0, addrB=buyer, numA=amount, text, votes 1/3, Pending)", Number(p.pType) === 0 && p.addrB === buyer && p.numA === amount && p.text.startsWith("BG-09") && Number(p.votes) === 1 && Number(p.requiredVotes) === 3 && Number(p.status) === 0 && p.proposer === net.addr("dao1"), { votes: Number(p.votes), createdAt: Number(p.createdAt), expiresAt: Number(p.expiresAt) });
  c.ok("expiry = createdAt + 30 days", Number(p.expiresAt) - Number(p.createdAt) === 30 * 86400);
  const hash = await dao.computeParamsHash(0, ethers.ZeroAddress, buyer, ethers.ZeroAddress, amount, 0, 0, p.text, "0x");
  c.ok("computeParamsHash == stored paramsHash", hash === p.paramsHash, hash);
  const neg = {};
  neg.nonBoardPropose = await expectRevert(net, "outsider", "DAO", "proposeSpend", [ethers.ZeroAddress, buyer, 1n, "x"]);
  neg.alternatePropose = await expectRevert(net, "dao6", "DAO", "proposeSpend", [ethers.ZeroAddress, buyer, 1n, "x"]);
  neg.proposerVotesTwice = await expectRevert(net, "dao1", "DAO", "vote", [id, hash]);
  neg.wrongHash = await expectRevert(net, "dao2", "DAO", "vote", [id, ethers.keccak256("0x1234")]);
  neg.nonBoardVote = await expectRevert(net, "outsider", "DAO", "vote", [id, hash]);
  neg.badId = await expectRevert(net, "dao2", "DAO", "vote", [999, hash]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  const v2 = await send(net, "dao2", "DAO", "vote", [id, hash]);
  p = await dao.getProposal(id);
  c.ok("2 of 5 votes: still Pending, money not moved", Number(p.votes) === 2 && Number(p.status) === 0 && (await net.balance(buyer)) === buyerBal0);
  const v3 = await send(net, "dao3", "DAO", "vote", [id, hash]);
  p = await dao.getProposal(id);
  c.ok("3rd vote executes the Spend: status Executed (1), ProposalExecuted emitted", Number(p.status) === 1 && Number(p.votes) === 3 && findEvent(v3.receipt, iface, "ProposalExecuted").length === 1, { executeBlock: v3.block, gasUsed: v3.gasUsed });
  c.ok("buyer +600,000 Suren exactly; DAO treasury -600,000 exactly", (await net.balance(buyer)) - buyerBal0 === amount && daoBal0 - (await net.balance(ADDR.DAO)) === amount, { buyerDelta: ((await net.balance(buyer)) - buyerBal0).toString() });
  const after = await expectRevert(net, "dao4", "DAO", "vote", [id, hash]);
  c.ok("negative: vote after execution reverts (not pending)", after.reverted, after.reason);

  // ---- Execute: seat NFT setBaseURI called by the DAO
  const nft = net.c("NFT");
  const newBase = "https://besu-live-test.local/seat/";
  const data = nft.interface.encodeFunctionData("setBaseURI", [newBase]);
  const forbidden1 = await expectRevert(net, "dao1", "DAO", "proposeExecute", [ADDR.DAO, 0, "0x", "self"]);
  const forbidden2 = await expectRevert(net, "dao1", "DAO", "proposeExecute", [ADDR.MEMBERS, 0, "0x", "members"]);
  c.ok("negative: Execute proposal may not target FoundationDAO or FoundationMembers", forbidden1.reverted && forbidden2.reverted, [forbidden1.reason, forbidden2.reason]);
  const uriBefore = await nft.tokenURI(1);
  const e = await send(net, "dao2", "DAO", "proposeExecute", [ADDR.NFT, 0, data, "BG-09: change the seat base URI"]);
  const id2 = Number(await dao.proposalCount());
  const p2 = await dao.getProposal(id2);
  c.ok("Execute proposal readable: target, value 0, data stored visibly, text", Number(p2.pType) === 12 && p2.addrA === ADDR.NFT && p2.data === data && p2.numA === 0n, { id2, dataBytes: (p2.data.length - 2) / 2 });
  const hash2 = await dao.computeParamsHash(12, ADDR.NFT, ethers.ZeroAddress, ethers.ZeroAddress, 0, 0, 0, p2.text, data);
  c.ok("Execute: computeParamsHash == stored hash", hash2 === p2.paramsHash);
  await send(net, "dao3", "DAO", "vote", [id2, hash2]);
  c.ok("2 of 5: base URI unchanged", (await nft.baseURI()) !== newBase);
  const ex3 = await send(net, "dao4", "DAO", "vote", [id2, hash2]);
  c.ok("3 of 5 executes: ValidatorSeatNFT.baseURI changed by the DAO call", (await nft.baseURI()) === newBase && findEvent(ex3.receipt, ifaceOf("NFT"), "BaseURIChanged").length === 1, await nft.baseURI());
  c.ok("tokenURI(1) == newBase + '1' (was " + uriBefore + ")", (await nft.tokenURI(1)) === newBase + "1", await nft.tokenURI(1));
  const direct = await expectRevert(net, "dao1", "NFT", "setBaseURI", ["https://evil/"]);
  c.ok("negative: setBaseURI from a board member directly reverts (only FoundationDAO)", direct.reverted, direct.reason);
  c.ok("proposalCount == 2", (await dao.proposalCount()) === 2n);

  writeResult("BG-09", { verdict: c.verdict, summary: `Spend proposal #${id} executed with 3 of 5; Execute proposal #${id2} (setBaseURI) executed with 3 of 5`, checks: c.items, spend: { id, propose: r.hash, vote2: v2.hash, vote3: v3.hash, executeBlock: v3.block }, execute: { id: id2, propose: e.hash, finalVote: ex3.hash }, negatives: neg });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
