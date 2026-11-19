const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, now, DAY } = require("./helpers");

const ZERO = ethers.ZeroAddress;
const E = ethers.parseEther;

async function fixture() {
  const S = await ethers.getSigners();
  const board = S.slice(0, 5), alts = S.slice(5, 7);
  const insp = S[7], ceo = S[8];
  const members = S.slice(9, 17); // 8 members
  const rep = S[17], stranger = S[18], recipient = S[19];
  const shares = [30n, 20n, 15n, 10n, 10n, 5n, 5n, 5n];
  const types = members.map((_, i) => (i === 7 ? 1 : 0));
  const reps = members.map((_, i) => (i === 7 ? rep.address : ZERO));

  const mem = await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS,
    [members.map((m) => m.address), members.map((_, i) => "Member " + i), types, reps, shares]);
  const termEnd = (await now()) + 730 * DAY;
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [[...board, ...alts].map((s) => s.address), insp.address, board[0].address, board[1].address, ceo.address, termEnd], E("100"));

  const sale = await (await ethers.getContractFactory("MockSale")).deploy();
  const counter = await (await ethers.getContractFactory("MockCounter")).deploy();
  const token = await (await ethers.getContractFactory("MockToken")).deploy();
  return { S, board, alts, insp, ceo, members, rep, stranger, recipient, mem, dao, sale, counter, token, shares };
}

async function lastId(dao) { return await dao.proposalCount(); }

/// the given voters vote with the stored hash (the proposer already voted)
async function approve(dao, id, voters) {
  const p = await dao.getProposal(id);
  for (const v of voters) await dao.connect(v).vote(id, p.paramsHash);
}

describe("FoundationMembers", () => {
  it("is seeded by the genesis recipe and read-only for outsiders", async () => {
    const { mem, members, rep, shares, stranger } = await loadFixture(fixture);
    expect(await mem.getMemberCount()).to.equal(8);
    expect(await mem.totalShares()).to.equal(100);
    expect(await mem.shareOf(members[0].address)).to.equal(shares[0]);
    expect(await mem.isMemberOrRepresentative(rep.address)).to.equal(true);
    expect(await mem.memberOfVoter(rep.address)).to.equal(members[7].address);
    expect(await mem.memberOfVoter(stranger.address)).to.equal(ZERO);
    await expect(mem.connect(stranger).addMember(stranger.address, "x", 0, ZERO, 1)).to.be.revertedWith("FoundationMembers: only FoundationDAO");
  });
});

describe("FoundationDAO - typed board proposals", () => {
  it("stores every parameter, counts the proposer's vote, requires the params hash, executes at 3 of 5", async () => {
    const { dao, board, recipient } = await loadFixture(fixture);
    const before = await ethers.provider.getBalance(recipient.address);
    await dao.connect(board[0]).proposeSpend(ZERO, recipient.address, E("5"), "grant");
    const id = await lastId(dao);
    const p = await dao.getProposal(id);
    expect(p.pType).to.equal(0);
    expect(p.proposer).to.equal(board[0].address);
    expect(p.addrB).to.equal(recipient.address);
    expect(p.numA).to.equal(E("5"));
    expect(p.text).to.equal("grant");
    expect(p.votes).to.equal(1); // proposer counted
    expect(p.requiredVotes).to.equal(3);
    expect(p.status).to.equal(0);
    const h = await dao.computeParamsHash(0, ZERO, recipient.address, ZERO, E("5"), 0, 0, "grant", "0x");
    expect(h).to.equal(p.paramsHash);

    await expect(dao.connect(board[1]).vote(id, ethers.id("other params"))).to.be.revertedWith("FoundationDAO: parameters hash mismatch");
    await dao.connect(board[1]).vote(id, p.paramsHash);
    expect((await dao.getProposal(id)).status).to.equal(0);
    await dao.connect(board[2]).vote(id, p.paramsHash);
    expect((await dao.getProposal(id)).status).to.equal(1);
    expect(await ethers.provider.getBalance(recipient.address)).to.equal(before + E("5"));
    await expect(dao.connect(board[3]).vote(id, p.paramsHash)).to.be.revertedWith("FoundationDAO: not pending");
  });

  it("rejects double votes, non-board callers and expired proposals", async () => {
    const { dao, board, stranger, recipient } = await loadFixture(fixture);
    await dao.connect(board[0]).proposeSpend(ZERO, recipient.address, E("1"), "x");
    const id = await lastId(dao);
    const h = (await dao.getProposal(id)).paramsHash;
    await expect(dao.connect(board[0]).vote(id, h)).to.be.revertedWith("FoundationDAO: already voted");
    await expect(dao.connect(stranger).vote(id, h)).to.be.revertedWith("FoundationDAO: not a principal board member");
    await expect(dao.connect(stranger).proposeSpend(ZERO, recipient.address, 1, "x")).to.be.revertedWith("FoundationDAO: not a principal board member");
    await increaseTime(31 * DAY);
    await expect(dao.connect(board[1]).vote(id, h)).to.be.revertedWith("FoundationDAO: expired");
  });

  it("spends ERC20 and rolls the vote back when the transfer fails", async () => {
    const { dao, board, recipient, token } = await loadFixture(fixture);
    await token.mint(ADDR.FOUNDATION_DAO, 1000);
    expect(await dao.getErc20Balance(await token.getAddress())).to.equal(1000);
    await dao.connect(board[0]).proposeSpend(await token.getAddress(), recipient.address, 400, "tokens");
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    expect(await token.balanceOf(recipient.address)).to.equal(400);
    await dao.connect(board[0]).proposeSpend(await token.getAddress(), recipient.address, 5000, "too much");
    const id = await lastId(dao);
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(board[1]).vote(id, h);
    await expect(dao.connect(board[2]).vote(id, h)).to.be.reverted;
    expect((await dao.getProposal(id)).votes).to.equal(2);
  });

  it("elects officers (chair and treasurer from the board, CEO may be outside)", async () => {
    const { dao, board, insp, stranger } = await loadFixture(fixture);
    await expect(dao.connect(board[0]).proposeElectOfficers(stranger.address, board[1].address, stranger.address)).to.be.revertedWith("FoundationDAO: chair and treasurer must be principal board members");
    await expect(dao.connect(board[0]).proposeElectOfficers(board[2].address, board[3].address, insp.address)).to.be.revertedWith("FoundationDAO: bad ceo");
    await dao.connect(board[0]).proposeElectOfficers(board[2].address, board[3].address, stranger.address);
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    expect(await dao.chair()).to.equal(board[2].address);
    expect(await dao.treasurer()).to.equal(board[3].address);
    expect(await dao.ceo()).to.equal(stranger.address);
  });

  it("free-form Execute: visible target/value/data, forbidden targets, revert reason bubbles", async () => {
    const { dao, board, counter, mem } = await loadFixture(fixture);
    const data = counter.interface.encodeFunctionData("inc", [7]);
    await expect(dao.connect(board[0]).proposeExecute(ADDR.FOUNDATION_DAO, 0, "0x", "self")).to.be.revertedWith("FoundationDAO: forbidden target");
    await expect(dao.connect(board[0]).proposeExecute(await mem.getAddress(), 0, "0x", "members")).to.be.revertedWith("FoundationDAO: forbidden target");

    await dao.connect(board[0]).proposeExecute(await counter.getAddress(), E("1"), data, "bump counter");
    const id = await lastId(dao);
    const p = await dao.getProposal(id);
    expect(p.pType).to.equal(12);
    expect(p.addrA).to.equal(await counter.getAddress());
    expect(p.numA).to.equal(E("1"));
    expect(p.data).to.equal(data);
    await approve(dao, id, [board[1], board[2]]);
    expect(await counter.n()).to.equal(7);
    expect(await counter.lastCaller()).to.equal(ADDR.FOUNDATION_DAO);
    expect(await ethers.provider.getBalance(await counter.getAddress())).to.equal(E("1"));

    await dao.connect(board[0]).proposeExecute(await counter.getAddress(), 0, counter.interface.encodeFunctionData("fail"), "will fail");
    const id2 = await lastId(dao);
    const h2 = (await dao.getProposal(id2)).paramsHash;
    await dao.connect(board[1]).vote(id2, h2);
    await expect(dao.connect(board[2]).vote(id2, h2)).to.be.revertedWith("MockCounter: boom");
  });

  it("sale proposals need the sale contract; then call SurenSale with the stored parameters", async () => {
    const { dao, board, sale, recipient, stranger } = await loadFixture(fixture);
    await dao.connect(board[0]).proposeRegisterExchange(stranger.address, "Exchange A", 1000);
    const id0 = await lastId(dao);
    const h0 = (await dao.getProposal(id0)).paramsHash;
    await dao.connect(board[1]).vote(id0, h0);
    await expect(dao.connect(board[2]).vote(id0, h0)).to.be.revertedWith("FoundationDAO: SurenSale not set");

    await expect(dao.connect(board[0]).proposeSetSaleContract(stranger.address)).to.be.revertedWith("FoundationDAO: not a contract");
    await dao.connect(board[0]).proposeSetSaleContract(await sale.getAddress());
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    expect(await dao.saleContract()).to.equal(await sale.getAddress());

    await dao.connect(board[2]).vote(id0, h0); // now executes
    expect(await sale.lastCall()).to.equal("registerExchange");
    expect(await sale.lastAccount()).to.equal(stranger.address);
    expect(await sale.lastName()).to.equal("Exchange A");
    expect(await sale.lastNum()).to.equal(1000);
    expect(await sale.lastCaller()).to.equal(ADDR.FOUNDATION_DAO);

    const cases = [
      ["proposeSetExchangeQuota", [stranger.address, 77], "setExchangeQuota", 77],
      ["proposeChangeExchangeKey", [stranger.address, recipient.address], "changeExchangeKey", 0],
      ["proposeResumeExchange", [stranger.address], "resumeExchange", 0],
      ["proposeRemoveExchange", [stranger.address], "removeExchange", 0],
      ["proposeSetSaleTotalCap", [123456], "setTotalCap", 123456],
      ["proposeSweepUnsold", [recipient.address], "sweepUnsold", 0],
    ];
    for (const [fn, args, expectedCall, num] of cases) {
      await dao.connect(board[0])[fn](...args);
      await approve(dao, await lastId(dao), [board[1], board[2]]);
      expect(await sale.lastCall()).to.equal(expectedCall);
      expect(await sale.lastNum()).to.equal(num);
    }
  });

  it("pauseExchange: CEO or any principal member alone; nobody else", async () => {
    const { dao, board, ceo, sale, stranger, alts, insp } = await loadFixture(fixture);
    await dao.connect(board[0]).proposeSetSaleContract(await sale.getAddress());
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    await expect(dao.connect(stranger).pauseExchange(stranger.address)).to.be.revertedWith("FoundationDAO: only CEO or board member");
    await expect(dao.connect(alts[0]).pauseExchange(stranger.address)).to.be.revertedWith("FoundationDAO: only CEO or board member");
    await expect(dao.connect(insp).pauseExchange(stranger.address)).to.be.revertedWith("FoundationDAO: only CEO or board member");
    await dao.connect(ceo).pauseExchange(stranger.address);
    expect(await sale.lastCall()).to.equal("pauseExchange");
    await dao.connect(board[4]).pauseExchange(stranger.address);
    expect(await sale.lastCaller()).to.equal(ADDR.FOUNDATION_DAO);
  });

  it("StartLottery and RotateIdentityOracle reach the fixed-address contracts", async () => {
    const { dao, board, stranger } = await loadFixture(fixture);
    const lot = await setCodeOf("MockLottery", ADDR.VALIDATOR_LOTTERY);
    const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
    const close = (await now()) + 20 * DAY;
    await expect(dao.connect(board[0]).proposeStartLottery(0, 5, close)).to.be.revertedWith("FoundationDAO: bad lottery parameters");
    await dao.connect(board[0]).proposeStartLottery(E("10"), 7, close);
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    expect(await lot.price()).to.equal(E("10"));
    expect(await lot.winners()).to.equal(7);
    expect(await lot.closeTime()).to.equal(close);
    expect(await lot.lastCaller()).to.equal(ADDR.FOUNDATION_DAO);

    await dao.connect(board[0]).proposeRotateIdentityOracle(stranger.address);
    await approve(dao, await lastId(dao), [board[1], board[2]]);
    expect(await idr.oracle()).to.equal(stranger.address);
  });
});

async function callAssembly(dao, caller, kind, days = 11) {
  await dao.connect(caller).callAssembly(kind, (await now()) + days * DAY, "ipfs://agenda");
  return await dao.assemblyCount();
}

describe("FoundationDAO - assemblies, elections, resolutions", () => {
  it("only chair or inspector call an assembly, with 10-40 days notice; the share snapshot is frozen", async () => {
    const { dao, board, insp, stranger, members } = await loadFixture(fixture);
    const t = await now();
    await expect(dao.connect(stranger).callAssembly(0, t + 11 * DAY, "x")).to.be.revertedWith("FoundationDAO: only chair or inspector");
    await expect(dao.connect(board[0]).callAssembly(0, t + 5 * DAY, "x")).to.be.revertedWith("FoundationDAO: notice must be 10-40 days");
    await expect(dao.connect(board[0]).callAssembly(0, t + 45 * DAY, "x")).to.be.revertedWith("FoundationDAO: notice must be 10-40 days");
    const id = await callAssembly(dao, board[0], 0);
    await dao.connect(insp).callAssembly(1, (await now()) + 20 * DAY, "x");
    const a = await dao.getAssembly(id);
    expect(a.totalShares).to.equal(100);
    expect(a.memberCount).to.equal(8);
    expect(await dao.assemblyWeightOf(id, members[0].address)).to.equal(30);
  });

  async function voteAll(dao, id, S) {
    const { members } = S;
    const c = members.map((m) => m.address);
    await dao.connect(members[0]).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]]);
    await dao.connect(members[1]).voteBoard(id, [c[0], c[1], c[2], c[5], c[6]]);
    await dao.connect(members[2]).voteBoard(id, [c[0], c[1], c[2], c[5], c[6]]);
    await dao.connect(members[7]).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]]);
  }

  it("full election: weighted votes, 5 principal + 2 alternates, inspector, old board loses power", async () => {
    const S = await loadFixture(fixture);
    const { dao, board, members, stranger, ceo, recipient } = S;
    const c = members.map((m) => m.address);
    await dao.connect(board[0]).proposeSpend(ZERO, recipient.address, 1, "old");
    const oldId = await lastId(dao);
    const oldHash = (await dao.getProposal(oldId)).paramsHash;

    const id = await callAssembly(dao, board[0], 0);
    await dao.connect(members[0]).proposeBoardElection(id);
    await expect(dao.connect(members[0]).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]])).to.be.revertedWith("FoundationDAO: voting is not open");
    await increaseTime(11 * DAY + 10);

    await expect(dao.connect(stranger).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]])).to.be.revertedWith("FoundationDAO: not a member or representative");
    await expect(dao.connect(members[0]).voteBoard(id, [c[0], c[0], c[2], c[3], c[4]])).to.be.revertedWith("FoundationDAO: duplicate pick");
    await expect(dao.connect(members[0]).voteBoard(id, [stranger.address, c[1], c[2], c[3], c[4]])).to.be.revertedWith("FoundationDAO: candidate must be a member or representative");
    await voteAll(dao, id, S);
    await expect(dao.connect(members[0]).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]])).to.be.revertedWith("FoundationDAO: already voted for the board");
    // inspector: m0 and m1 pick an elected member (must be skipped), m2 picks an outsider
    await dao.connect(members[0]).voteInspector(id, c[0]);
    await dao.connect(members[1]).voteInspector(id, c[0]);
    await dao.connect(members[2]).voteInspector(id, stranger.address);

    await expect(dao.finalizeElection(id)).to.be.revertedWith("FoundationDAO: voting not over");
    await increaseTime(3 * DAY + 10);
    await dao.finalizeElection(id);

    expect(await dao.getBoard()).to.deep.equal([c[0], c[1], c[2], c[3], c[4]]);
    expect(await dao.getAlternates()).to.deep.equal([c[5], c[6]]);
    expect(await dao.getInspector()).to.equal(stranger.address);
    expect(await dao.isBoardMember(board[0].address)).to.equal(false);
    expect(await dao.isBoardMember(c[0])).to.equal(true);
    expect(await dao.chair()).to.equal(ZERO);
    expect(await dao.treasurer()).to.equal(ZERO);
    expect(await dao.ceo()).to.equal(ceo.address);
    expect(await dao.boardTermEnd()).to.be.gt((await now()) + 729 * DAY);
    await expect(dao.finalizeElection(id)).to.be.revertedWith("FoundationDAO: election not open");
    await expect(dao.connect(board[1]).vote(oldId, oldHash)).to.be.revertedWith("FoundationDAO: not a principal board member");
  });

  it("proposals of the previous board composition are void even for a re-elected member", async () => {
    const S = await loadFixture(fixture);
    const { dao, members, stranger, recipient } = S;
    const c = members.map((m) => m.address);
    // first election: board = members 0..4, chair/treasurer reset
    let id = await callAssembly(dao, S.board[0], 0);
    await dao.connect(members[0]).proposeBoardElection(id);
    await increaseTime(11 * DAY + 10);
    await voteAll(dao, id, S);
    await dao.connect(members[0]).voteInspector(id, stranger.address);
    await increaseTime(3 * DAY + 10);
    await dao.finalizeElection(id);
    // the new board proposes, then a second election re-elects the same people
    await dao.connect(members[0]).proposeSpend(ZERO, recipient.address, 1, "pending");
    const pid = await lastId(dao);
    const h = (await dao.getProposal(pid)).paramsHash;
    // officers are needed to call an assembly: inspector can do it
    await dao.connect(stranger).callAssembly(0, (await now()) + 11 * DAY, "again");
    id = await dao.assemblyCount();
    await dao.connect(members[0]).proposeBoardElection(id);
    await increaseTime(11 * DAY + 10);
    await voteAll(dao, id, S);
    await dao.connect(members[0]).voteInspector(id, stranger.address);
    await increaseTime(3 * DAY + 10);
    await dao.finalizeElection(id);
    await expect(dao.connect(members[1]).vote(pid, h)).to.be.revertedWith("FoundationDAO: void - board composition changed");
  });

  it("quorum: first session needs more than half of the shares; a second session needs more than a third", async () => {
    const S = await loadFixture(fixture);
    const { dao, board, members } = S;
    const c = members.map((m) => m.address);
    const id = await callAssembly(dao, board[0], 0);
    await dao.connect(members[0]).proposeBoardElection(id);
    await increaseTime(11 * DAY + 10);
    await dao.connect(members[7]).voteBoard(id, [c[0], c[1], c[2], c[3], c[4]]); // 5 shares only
    await dao.connect(members[7]).voteInspector(id, c[5]);
    await increaseTime(3 * DAY + 10);
    await expect(dao.finalizeElection(id)).to.be.revertedWith("FoundationDAO: quorum not reached");

    await expect(dao.connect(board[0]).callSecondSession(id, (await now()) + 5 * DAY, "x")).to.be.revertedWith("FoundationDAO: notice must be 10-40 days");
    await dao.connect(board[0]).callSecondSession(id, (await now()) + 11 * DAY, "second");
    const id2 = await dao.assemblyCount();
    expect((await dao.getAssembly(id2)).secondSession).to.equal(true);
    await dao.connect(members[0]).proposeBoardElection(id2);
    await increaseTime(11 * DAY + 10);
    await dao.connect(members[0]).voteBoard(id2, [c[0], c[1], c[2], c[3], c[4]]);
    await dao.connect(members[7]).voteBoard(id2, [c[0], c[1], c[2], c[3], c[4]]);
    await dao.connect(members[0]).voteInspector(id2, S.stranger.address);
    await increaseTime(3 * DAY + 10);
    await dao.finalizeElection(id2); // 35 shares: 35*3 > 100
    expect(await dao.getInspector()).to.equal(S.stranger.address);
    await expect(dao.connect(S.stranger).callSecondSession(id, (await now()) + 11 * DAY, "again")).to.be.revertedWith("FoundationDAO: second session already called");
    await expect(dao.connect(S.stranger).callSecondSession(id2, (await now()) + 11 * DAY, "again")).to.be.revertedWith("FoundationDAO: already a second session");
  });

  it("member-ledger resolution fails without a numeric majority even with three quarters of the capital", async () => {
    const S = await loadFixture(fixture);
    const { dao, board, members, stranger, recipient } = S;
    const ex = await callAssembly(dao, board[0], 1);
    const ord = await callAssembly(dao, board[0], 0);
    await expect(dao.connect(members[0]).proposeMembersResolution(ord, 0, recipient.address, ZERO, "N", 0, 10)).to.be.revertedWith("FoundationDAO: needs an extraordinary assembly");
    await expect(dao.connect(stranger).proposeMembersResolution(ex, 0, recipient.address, ZERO, "N", 0, 10)).to.be.revertedWith("FoundationDAO: only members");
    await dao.connect(members[0]).proposeMembersResolution(ex, 0, recipient.address, ZERO, "Newcomer", 0, 10);
    const rid = await dao.resolutionCount();
    await increaseTime(11 * DAY + 10);
    await expect(dao.connect(members[0]).proposeMembersResolution(ex, 1, members[5].address, ZERO, "", 0, 0)).to.be.revertedWith("FoundationDAO: agenda is closed");
    // m0(30) m1(20) m2(15) m3(10) = 75 shares, but only 4 of 8 members
    for (let i = 0; i < 4; i++) await dao.connect(members[i]).voteResolution(rid, true);
    await increaseTime(3 * DAY + 10);
    await expect(dao.executeResolution(rid)).to.be.revertedWith("FoundationDAO: numeric majority not reached");
  });

  it("member-ledger resolutions: add, transfer, remove and representative change when the rules are met", async () => {
    const S = await loadFixture(fixture);
    const { dao, board, members, mem, recipient, rep, stranger } = S;
    const ex = await callAssembly(dao, board[0], 1);
    await dao.connect(members[0]).proposeMembersResolution(ex, 0, recipient.address, ZERO, "Newcomer", 0, 10);
    const rAdd = await dao.resolutionCount();
    await dao.connect(members[0]).proposeMembersResolution(ex, 2, members[0].address, members[5].address, "", 0, 5);
    const rTr = await dao.resolutionCount();
    await dao.connect(members[0]).proposeMembersResolution(ex, 1, members[6].address, ZERO, "", 0, 0);
    const rRm = await dao.resolutionCount();
    await dao.connect(members[0]).proposeMembersResolution(ex, 3, members[7].address, stranger.address, "", 0, 0);
    const rRep = await dao.resolutionCount();
    await increaseTime(11 * DAY + 10);
    for (const rid of [rAdd, rTr, rRm, rRep]) {
      for (let i = 0; i < 5; i++) await dao.connect(members[i]).voteResolution(rid, true); // 85 shares, 5 of 8
    }
    await expect(dao.connect(members[0]).voteResolution(rAdd, true)).to.be.revertedWith("FoundationDAO: already voted");
    await increaseTime(3 * DAY + 10);

    await dao.executeResolution(rAdd);
    expect(await mem.isMember(recipient.address)).to.equal(true);
    expect(await mem.totalShares()).to.equal(110);
    await dao.executeResolution(rTr);
    expect(await mem.shareOf(members[0].address)).to.equal(25);
    expect(await mem.shareOf(members[5].address)).to.equal(10);
    await dao.executeResolution(rRm);
    expect(await mem.isMember(members[6].address)).to.equal(false);
    expect(await mem.totalShares()).to.equal(105);
    await dao.executeResolution(rRep);
    expect(await mem.memberOfVoter(stranger.address)).to.equal(members[7].address);
    expect(await mem.memberOfVoter(rep.address)).to.equal(ZERO);
    await expect(dao.executeResolution(rAdd)).to.be.revertedWith("FoundationDAO: resolution not open");
  });

  it("a board vote can never change the member ledger (Execute cannot target FoundationMembers)", async () => {
    const { dao, board, mem, stranger } = await loadFixture(fixture);
    const data = mem.interface.encodeFunctionData("addMember", [stranger.address, "x", 0, ZERO, 1]);
    await expect(dao.connect(board[0]).proposeExecute(await mem.getAddress(), 0, data, "bypass")).to.be.revertedWith("FoundationDAO: forbidden target");
  });
});
