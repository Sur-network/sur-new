// Lost owner key and the validators' board: ValidatorsRegistry.migrateSeat hands the old address's BOARD SEAT (and its election votes) to
// the new address of the SAME person through the required call ValidatorsBoard.onSeatMigrated; a seat SALE does not. A person never counts
// twice across a migration (ValidatorsBoard actions and the Distributor's board chambers record votes under boardVoterKey).
// Real Registry, Board, Seat NFT, IdentityRegistry and Distributor; the five founders are the board.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY, agr } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const AGR = ethers.id("signed validators agreement v1");
const ORACLE = "0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9"; // SurAddresses.IDENTITY_ORACLE
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const rnd = () => ethers.Wallet.createRandom().address;
const ST = { None: 0, Probation: 1, Active: 2, Demoted: 3, Exiting: 4, RemovedInRecovery: 5, SelfSuspended: 6 };

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("2000"));
  const tmp = await (await ethers.getContractFactory("IdentityRegistry")).deploy();
  const art = await hre.artifacts.readArtifact("IdentityRegistry");
  await hre.network.provider.send("hardhat_setCode", [ADDR.IDENTITY_REGISTRY, art.deployedBytecode]);
  await hre.network.provider.send("hardhat_setStorageAt", [ADDR.IDENTITY_REGISTRY, "0x1", await ethers.provider.getStorage(await tmp.getAddress(), 1)]);
  const idr = await ethers.getContractAt("IdentityRegistry", ADDR.IDENTITY_REGISTRY);
  await hre.network.provider.send("hardhat_setBalance", [ORACLE, "0x56BC75E2D63100000"]);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);

  const t0 = await now();
  const founders = S.slice(0, 5);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY, [founders[0].address, rnd(), founders.slice(1).map((s) => s.address), t0]);
  const nft = await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  const board = await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [founders.map((s) => s.address), t0]);
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const x of founders.slice(1)) {
    await reg.connect(x).setOperator(rnd());
    await reg.connect(verifier).recordActivation(x.address, HASH);
  }
  const people = { heir: S[10], heir2: S[11], buyer: S[12], payer: S[13], stranger: S[14] };
  for (const b of Object.values(people)) await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  return { S, reg, nft, idr, board, dist, oracle, verifier, founders, price, ...people };
}

async function verifyAll(f, who) {
  await f.idr.connect(who).registerIdentity(0, "Person");
  const o = f.idr.connect(f.oracle);
  await o.setKycVerified(who.address, true, ethers.id("c"));
  await o.setPhoneVerified(who.address, true);
  await o.setTelegramVerified(who.address, true);
  await o.setBaleVerified(who.address, true);
  await o.setEmailVerified(who.address, true);
}
async function enterActive(f, who) {
  await verifyAll(f, who);
  await f.reg.connect(who).requestMembership(rnd(), agr(), { value: f.price });
  await increaseTime(8 * DAY);
  await f.reg.connect(f.verifier).recordActivation(who.address, HASH);
}
const migrateId = (f, from, to) => f.idr.connect(f.oracle).migrateIdentity(from.address ?? from, to.address ?? to);
const migrateSeat = (f, from, to) => f.reg.connect(f.verifier).migrateSeat(from.address ?? from, to.address ?? to);
/// identity migration (oracle) + seat migration (Verifier); a founder has no identity yet, so it gets one first
async function migrate(f, from, to) {
  if (!(await f.idr.hasIdentity(from.address))) await verifyAll(f, from);
  await migrateId(f, from, to);
  return migrateSeat(f, from, to);
}
const members = async (f) => (await f.board.getBoardMembers()).map((a) => a.toLowerCase());
const lc = (a) => a.address.toLowerCase();

describe("ValidatorsBoard - a board member migrates its seat (lost owner key)", () => {
  it("the new address takes the seat IN PLACE: authority true, old false, same position, no vacancy, boardVersion unchanged; the new address can act, the old one cannot", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, founders, heir } = f;
    const old = founders[2];
    const before = await members(f);
    const version = await board.boardVersion();
    expect(await board.hasBoardAuthority(old.address)).to.equal(true);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);

    await expect(migrate(f, old, heir)).to.emit(board, "BoardSeatMigrated").withArgs(old.address, heir.address, true, 0, 0);

    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
    expect(await board.hasBoardAuthority(old.address)).to.equal(false);
    expect(await board.isBoardMember(heir.address)).to.equal(true);
    expect(await board.isBoardMember(old.address)).to.equal(false);
    const after = await members(f);
    expect(after.length).to.equal(5);
    expect(after.indexOf(lc(heir))).to.equal(before.indexOf(lc(old))); // same position
    expect(after.filter((a) => a !== lc(heir))).to.deep.equal(before.filter((a) => a !== lc(old)));
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.pendingVacancies()).to.equal(0);
    expect(await board.boardVersion()).to.equal(version); // the set of PEOPLE did not change
    expect(await board.seatMembershipEpoch(heir.address)).to.equal(await reg.membershipEpoch(heir.address));
    expect(await board.seatMembershipEpoch(old.address)).to.equal(0);
    expect(await reg.membershipEpoch(old.address)).to.equal(1); // the old address is an ex-member: its own epoch moved

    // nothing to repair: syncBoard changes nothing, and the board still works (no "a seat holder has requested exit")
    await board.syncBoard();
    expect(await members(f)).to.deep.equal(after);
    expect(await board.boardVersion()).to.equal(version);
    await board.connect(heir).proposeRotateOracle(rnd());
    await expect(board.connect(old).proposeRotateOracle(rnd())).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    // the seat follows the person in the Registry's own rule too: a board member cannot suspend voluntarily
    await expect(reg.connect(heir).selfSuspend()).to.be.revertedWith("ValidatorsRegistry: a board member cannot suspend voluntarily");
  });

  it("a board member that is migrated twice (old -> heir -> heir2) keeps the seat; only the last address has authority", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, heir2 } = f;
    const old = founders[3];
    await migrate(f, old, heir);
    await migrate(f, heir, heir2);
    expect(await board.hasBoardAuthority(heir2.address)).to.equal(true);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);
    expect(await board.hasBoardAuthority(old.address)).to.equal(false);
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.boardVersion()).to.equal(1);
    expect(await board.boardVoterKey(heir2.address)).to.equal(old.address); // the FIRST address of the chain
    expect(await board.boardVoterKey(heir.address)).to.equal(old.address);
    expect(await board.boardVoterKey(old.address)).to.equal(old.address);
    expect(await board.boardVoterKey(f.stranger.address)).to.equal(f.stranger.address);
  });

  it("gas of migrateSeat: a board member (with votes), a board member without votes, a non-member", async () => {
    const f = await loadFixture(fixture);
    const { founders, heir, heir2, payer, stranger } = f;
    await enterActive(f, payer);
    let r = await (await migrate(f, payer, stranger)).wait();
    console.log("      migrateSeat gas, non-board paying validator:", r.gasUsed.toString());
    r = await (await migrate(f, founders[1], heir)).wait();
    console.log("      migrateSeat gas, board founder without votes:", r.gasUsed.toString());
    for (const x of [founders[0], founders[2], founders[3], founders[4]]) await verifyAll(f, x);
    for (const x of [founders[0], founders[2], founders[3], founders[4]]) for (const c of [founders[0], founders[2], founders[3], founders[4], heir]) await f.board.connect(x).voteFor(c.address);
    r = await (await migrate(f, founders[2], heir2)).wait();
    console.log("      migrateSeat gas, board founder, 5 votes cast and 4 received:", r.gasUsed.toString());
  });
});

describe("ValidatorsBoard - a non-member migrates, a seat is SOLD", () => {
  it("a validator that is not on the board migrates: the board is untouched, the new address has no board authority", async () => {
    const f = await loadFixture(fixture);
    const { board, payer, stranger } = f;
    await enterActive(f, payer);
    const before = await members(f);
    const version = await board.boardVersion();
    await expect(migrate(f, payer, stranger)).to.emit(board, "BoardSeatMigrated").withArgs(payer.address, stranger.address, false, 0, 0);
    expect(await members(f)).to.deep.equal(before);
    expect(await board.boardVersion()).to.equal(version);
    expect(await board.pendingVacancies()).to.equal(0);
    expect(await board.isBoardMember(stranger.address)).to.equal(false);
    expect(await board.hasBoardAuthority(stranger.address)).to.equal(false);
    expect(await board.boardVoterKey(stranger.address)).to.equal(payer.address); // the chain is recorded on EVERY migration, seat or not
  });

  it("REGRESSION - a seat SALE of a board member still ends its authority: the buyer takes no board seat, a vacancy opens", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, board, founders, buyer } = f;
    const seller = founders[3];
    const seatId = await nft.seatOf(seller.address);
    await verifyAll(f, buyer);
    await reg.connect(buyer).acceptSeatAgreement(seatId, AGR);
    const version = await board.boardVersion();
    await nft.connect(seller).transferFrom(seller.address, buyer.address, seatId);
    expect(await nft.ownerOf(seatId)).to.equal(buyer.address);
    expect(await board.hasBoardAuthority(seller.address)).to.equal(false);
    expect(await board.hasBoardAuthority(buyer.address)).to.equal(false);
    expect(await board.isBoardMember(buyer.address)).to.equal(false);
    expect(await board.boardVoterKey(buyer.address)).to.equal(buyer.address);
    // the raw seat flag stays until syncBoard(), which opens the vacancy as before
    expect(await board.isBoardMember(seller.address)).to.equal(true);
    await board.syncBoard();
    expect(await board.isBoardMember(seller.address)).to.equal(false);
    expect(await board.getBoardSize()).to.equal(4);
    expect(await board.pendingVacancies()).to.equal(1);
    expect(await board.boardVersion()).to.equal(version + 1n);
  });
});

describe("ValidatorsBoard - the hook is Registry-only and REQUIRED", () => {
  it("nobody but the Registry can call onSeatMigrated; the Registry itself cannot name bad pairs", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, stranger, verifier } = f;
    const msg = "ValidatorsBoard: caller is not the validators registry";
    await expect(board.connect(stranger).onSeatMigrated(founders[0].address, heir.address, true)).to.be.revertedWith(msg);
    await expect(board.connect(founders[0]).onSeatMigrated(founders[0].address, heir.address, true)).to.be.revertedWith(msg); // a board member
    await expect(board.connect(verifier).onSeatMigrated(founders[0].address, heir.address, true)).to.be.revertedWith(msg);
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATORS_REGISTRY, "0x56BC75E2D63100000"]);
    const asReg = await ethers.getImpersonatedSigner(ADDR.VALIDATORS_REGISTRY);
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, ZERO, true)).to.be.revertedWith("ValidatorsBoard: bad migration addresses");
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, founders[0].address, true)).to.be.revertedWith("ValidatorsBoard: bad migration addresses");
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, founders[1].address, true)).to.be.revertedWith("ValidatorsBoard: new owner already holds a seat");
    expect(await board.getBoardSize()).to.equal(5);
  });

  it("the call is REQUIRED: if the board cannot take it, the whole migration reverts and nothing moves", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, founders, heir } = f;
    await verifyAll(f, founders[2]);
    await migrateId(f, founders[2], heir);
    await setCodeOf("MockBoard", ADDR.VALIDATORS_BOARD); // a board without onSeatMigrated
    await expect(migrateSeat(f, founders[2], heir)).to.be.reverted;
    expect((await reg.validators(heir.address)).status).to.equal(ST.None);
    expect((await reg.validators(founders[2].address)).status).to.equal(ST.Active);
    expect(await nft.ownerOf(await nft.seatOf(founders[2].address))).to.equal(founders[2].address);
    expect(await reg.permanentlyExited(founders[2].address)).to.equal(false);
  });
});

describe("ValidatorsBoard - no double counting across a migration (board actions)", () => {
  it("an action the old address already voted on cannot be voted on again by the new address; one it had not voted on can be, once", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, heir2 } = f;
    const [s0, s1, s2, s3] = founders;
    // A: proposed by S0, voted by S2 (2 of the 3 needed). B: proposed by S1, S2 has not voted.
    await board.connect(s0).proposeRotateOracle(rnd());
    const A = await board.actionCount();
    await board.connect(s2).voteAction(A);
    await board.connect(s1).proposeRotateOracle(rnd());
    const B = await board.actionCount();
    expect((await board.actions(A)).votes).to.equal(2);
    expect((await board.actions(B)).votes).to.equal(1);

    await migrate(f, s2, heir);
    expect(await board.boardVersion()).to.equal(1); // open actions stay valid: the set of people is the same

    // A: the person already voted (as S2): heir cannot add a second vote, so S0 + S2 + heir can never reach the quorum of 3 alone
    await expect(board.connect(heir).voteAction(A)).to.be.revertedWith("ValidatorsBoard: already voted");
    expect((await board.actions(A)).votes).to.equal(2);
    expect((await board.actions(A)).executed).to.equal(false);
    // B: the person had not voted: heir votes once, a second try fails, the old address cannot vote at all
    await board.connect(heir).voteAction(B);
    expect((await board.actions(B)).votes).to.equal(2);
    await expect(board.connect(heir).voteAction(B)).to.be.revertedWith("ValidatorsBoard: already voted");
    await expect(board.connect(s2).voteAction(B)).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    // a third PERSON completes A, and only then
    await board.connect(s3).voteAction(A);
    expect((await board.actions(A)).votes).to.equal(3);
    expect((await board.actions(A)).executed).to.equal(true);

    // a second migration (heir -> heir2) keeps the same single vote
    await board.connect(s0).proposeRotateOracle(rnd());
    const C = await board.actionCount();
    await board.connect(heir).voteAction(C);
    await migrate(f, heir, heir2);
    await expect(board.connect(heir2).voteAction(C)).to.be.revertedWith("ValidatorsBoard: already voted");
    await expect(board.connect(heir2).voteAction(B)).to.be.revertedWith("ValidatorsBoard: already voted");
    // an action proposed after the migration: the new address proposes and votes normally (its own proposal vote counts once)
    await board.connect(heir2).proposeRotateOracle(rnd());
    const D = await board.actionCount();
    expect((await board.actions(D)).votes).to.equal(1);
    await expect(board.connect(heir2).voteAction(D)).to.be.revertedWith("ValidatorsBoard: already voted");
  });
});

describe("BlockRewardDistributor - the board chambers count a migrated person once", () => {
  it("share change: a vote cast by the old address blocks the new one on that proposal; a proposal it had not voted on takes one vote", async () => {
    const f = await loadFixture(fixture);
    const { dist, board, founders, heir } = f;
    const [s0, s1, s2, s3] = founders;
    await dist.connect(s0).proposeShareChange(5000);
    const P1 = await dist.shareProposalCount();
    await dist.connect(s0).proposeShareChange(5100);
    const P2 = await dist.shareProposalCount();
    await dist.connect(s2).boardVoteShareChange(P1);
    expect((await dist.shareProposals(P1)).boardApprovals).to.equal(1);

    await migrate(f, s2, heir);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);

    await expect(dist.connect(heir).boardVoteShareChange(P1)).to.be.revertedWith("BlockRewardDistributor: board member already voted");
    expect((await dist.shareProposals(P1)).boardApprovals).to.equal(1);
    await dist.connect(heir).boardVoteShareChange(P2); // had not voted on P2
    expect((await dist.shareProposals(P2)).boardApprovals).to.equal(1);
    await expect(dist.connect(heir).boardVoteShareChange(P2)).to.be.revertedWith("BlockRewardDistributor: board member already voted");
    await expect(dist.connect(s2).boardVoteShareChange(P2)).to.be.revertedWith("BlockRewardDistributor: caller has no live board authority");
    await dist.connect(s1).boardVoteShareChange(P1);
    expect((await dist.shareProposals(P1)).boardApprovals).to.equal(2);
    await dist.connect(s3).boardVoteShareChange(P1);
    expect((await dist.shareProposals(P1)).boardApprovals).to.equal(3);
    expect((await dist.shareProposals(P1)).boardPassed).to.equal(true);
  });

  it("rate change (a later month, after a refresh): same rule", async () => {
    const f = await loadFixture(fixture);
    const { dist, board, founders, heir } = f;
    // the founders vote for each other so that the board of the next month is the same five people, then a month passes
    for (const x of founders) await verifyAll(f, x);
    for (const x of founders) for (const c of founders) await board.connect(x).voteFor(c.address);
    await increaseTime(181 * DAY);
    expect(await board.hasBoardAuthority(founders[2].address)).to.equal(false); // the founding board's month is over
    await board.refreshBoard([]);
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.hasBoardAuthority(founders[2].address)).to.equal(true);
    const bn = await ethers.provider.getBlockNumber();
    const t = await now();
    const [s0, s1, s2] = founders;
    await dist.connect(s0).proposeRateChange(t + 30 * DAY, bn + 1_000_000, E("2.1"));
    const R = await dist.rateProposalCount();
    await dist.connect(s2).boardVoteRateChange(R);
    expect((await dist.rateProposals(R)).boardApprovals).to.equal(1);

    await migrate(f, s2, heir);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
    await expect(dist.connect(heir).boardVoteRateChange(R)).to.be.revertedWith("BlockRewardDistributor: board member already voted");
    expect((await dist.rateProposals(R)).boardApprovals).to.equal(1);
    await dist.connect(s1).boardVoteRateChange(R);
    expect((await dist.rateProposals(R)).boardApprovals).to.equal(2);
    // a rate proposal made after the migration: the new address votes on it once
    await dist.connect(s0).proposeRateChange(t + 31 * DAY, bn + 2_000_000, E("2.05"));
    const R2 = await dist.rateProposalCount();
    await dist.connect(heir).boardVoteRateChange(R2);
    await expect(dist.connect(heir).boardVoteRateChange(R2)).to.be.revertedWith("BlockRewardDistributor: board member already voted");
    expect((await dist.rateProposals(R2)).boardApprovals).to.equal(1);
  });
});

describe("ValidatorsBoard - election votes follow the person", () => {
  it("votes the old address cast and received move to the new one (a non-member validator too); counters, lists and self-votes stay consistent", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, payer, stranger } = f;
    const [s0, s1] = founders;
    await enterActive(f, payer);
    await verifyAll(f, s0);
    await verifyAll(f, s1);
    await board.connect(s0).voteFor(payer.address);
    await board.connect(s1).voteFor(payer.address);
    await board.connect(payer).voteFor(payer.address); // a self-vote
    await board.connect(payer).voteFor(s0.address);
    expect(await board.voteCount(payer.address)).to.equal(3);
    expect(await board.voteCount(s0.address)).to.equal(1);

    await expect(migrate(f, payer, stranger)).to.emit(board, "BoardSeatMigrated").withArgs(payer.address, stranger.address, false, 2, 2);
    expect(await board.voteCount(stranger.address)).to.equal(1); // only the self-vote (a CAST vote) has moved so far
    await board.connect(f.verifier).moveReceivedVotes(payer.address, 10); // anyone may finish the move

    expect(await board.voteCount(stranger.address)).to.equal(3);
    expect(await board.voteCount(payer.address)).to.equal(0);
    expect(await board.voteCount(s0.address)).to.equal(1); // still one vote from the person, now cast by the new address
    expect(await board.hasVotedFor(stranger.address, stranger.address)).to.equal(true);
    expect(await board.hasVotedFor(stranger.address, s0.address)).to.equal(true);
    expect(await board.hasVotedFor(s0.address, stranger.address)).to.equal(true);
    expect(await board.hasVotedFor(s1.address, stranger.address)).to.equal(true);
    expect(await board.hasVotedFor(payer.address, payer.address)).to.equal(false);
    expect(await board.hasVotedFor(payer.address, s0.address)).to.equal(false);
    expect(await board.hasVotedFor(s0.address, payer.address)).to.equal(false);
    expect((await board.getVotesOf(payer.address)).length).to.equal(0);
    expect((await board.getVotersFor(payer.address)).length).to.equal(0);
    expect((await board.getVotesOf(stranger.address)).length).to.equal(2);
    expect((await board.getVotersFor(stranger.address)).length).to.equal(3);
    const list = (await board.getCandidateList()).map((a) => a.toLowerCase());
    expect(list).to.include(lc(stranger));
    expect(list).to.not.include(lc(payer));
    expect(await board.votesCounted(stranger.address)).to.equal(true);
    // the moved votes keep working: the new address can withdraw one, the counter follows
    await board.connect(stranger).unvoteFor(s0.address);
    expect(await board.voteCount(s0.address)).to.equal(0);
    await board.connect(s0).unvoteFor(stranger.address);
    expect(await board.voteCount(stranger.address)).to.equal(2);
  });

  it("month ENDED before the migration: the seat is still replaced in place, nobody has authority until the refresh, and the refresh keeps the person (moved votes, no board-version change)", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir } = f;
    for (const x of founders) await verifyAll(f, x);
    for (const x of founders) for (const c of founders) await board.connect(x).voteFor(c.address);
    await increaseTime(40 * DAY); // the founding board's month is over
    const old = founders[2];
    const before = await members(f);
    const version = await board.boardVersion();
    expect(await board.refreshDue()).to.equal(true);

    await migrate(f, old, heir);
    await expect(board.refreshBoard([])).to.be.revertedWith("ValidatorsBoard: move pending"); // 4 received votes are still to be moved
    await board.moveReceivedVotes(old.address, 10);

    // (a) bookkeeping: the stored seat follows the person, but there is no authority for anybody in an ended month
    expect(await board.isBoardMember(heir.address)).to.equal(true);
    expect(await board.isBoardMember(old.address)).to.equal(false);
    expect((await members(f)).indexOf(lc(heir))).to.equal(before.indexOf(lc(old)));
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);
    expect(await board.hasBoardAuthority(old.address)).to.equal(false);
    await expect(board.connect(heir).proposeRotateOracle(rnd())).to.be.revertedWith("ValidatorsBoard: board term ended - call refreshBoard for the new month");
    await expect(board.syncBoard()).to.be.revertedWith("ValidatorsBoard: board term ended - call refreshBoard for the new month");
    // (b) the votes moved: the new address holds the old address's 5 votes, so the next refresh seats it
    expect(await board.voteCount(heir.address)).to.equal(5);
    expect(await board.voteCount(old.address)).to.equal(0);
    // (c) the refresh keeps the same five PEOPLE: composition unchanged, boardVersion unchanged
    await board.refreshBoard([]);
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.isBoardMember(heir.address)).to.equal(true);
    expect(await board.isBoardMember(old.address)).to.equal(false);
    expect(await board.boardVersion()).to.equal(version);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
    expect(await board.hasBoardAuthority(old.address)).to.equal(false);
    expect(await board.seatMembershipEpoch(heir.address)).to.equal(0);
  });
});

// ------------------------------------------------------------------------------------------------------------------------------
// Review fixes: (1) an ended seat is not revived, (2) the vote key is recorded on EVERY migration (recovery-case votes),
// (3) the work of a migration is bounded: dead voters' entries are dropped, and anyone can purge them beforehand.
// ------------------------------------------------------------------------------------------------------------------------------
const removeInRecovery = async (f, who) => f.reg.connect(f.verifier).recordRecoveryRemoval(who.address, await now(), HASH);

describe("ValidatorsBoard - a seat that had already ended is NOT revived by a migration", () => {
  it("recovery removal cancelled (seat void, not yet cleared): the new address gets no seat, syncBoard clears the old one", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, founders, heir } = f;
    const A = founders[2];
    await removeInRecovery(f, A); // membershipEpoch++ : the seat is void
    await reg.connect(A).objectRecoveryRemoval();
    await increaseTime(8 * DAY); // no decision in 7 days
    await reg.expireRecoveryRemoval(A.address); // cancelled: back to SelfSuspended, the epoch is NOT restored
    expect((await reg.validators(A.address)).status).to.equal(ST.SelfSuspended);
    expect(await board.isBoardMember(A.address)).to.equal(true); // the raw flag is still there
    expect(await board.hasBoardAuthority(A.address)).to.equal(false);
    expect(await board.hasValidSeat(A.address)).to.equal(false);
    expect(await board.hasValidSeat(founders[1].address)).to.equal(true);
    expect(await board.hasValidSeat(f.stranger.address)).to.equal(false);

    await expect(migrate(f, A, heir)).to.emit(board, "BoardSeatMigrated").withArgs(A.address, heir.address, false, 0, 0);

    expect(await board.isBoardMember(heir.address)).to.equal(false);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);
    expect(await board.isBoardMember(A.address)).to.equal(true); // left for syncBoard
    await reg.connect(f.verifier).recordResume(heir.address, HASH); // heir is Active again, still no seat
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);
    const version = await board.boardVersion();
    await board.syncBoard();
    expect(await board.isBoardMember(A.address)).to.equal(false);
    expect(await board.getBoardSize()).to.equal(4);
    expect(await board.pendingVacancies()).to.equal(1);
    expect(await board.boardVersion()).to.equal(version + 1n);
    expect(await board.seatMembershipEpoch(heir.address)).to.equal(0);
  });
});

describe("ValidatorsBoard - the vote key is recorded on EVERY migration (recovery-case votes)", () => {
  it("A votes on a removal case, loses its seat, is migrated WITHOUT a seat to B, B is seated again later and cannot vote on the case a second time", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, verifier, founders, heir, payer } = f;
    const [s0, s1, , s3] = founders;
    const A = founders[2];
    await enterActive(f, payer);
    await verifyAll(f, s0);
    await board.connect(s0).voteFor(A.address); // a vote for A: it will follow the person and seat it again

    // case X: the paying validator is removed in a recovery and objects; A (a board member) votes on it
    await removeInRecovery(f, payer);
    await reg.connect(payer).objectRecoveryRemoval();
    await board.connect(A).voteRecoveryRemoval(payer.address, false);
    const recordedAt = (await reg.recoveryCaseInfo(payer.address)).recordedAt;
    expect((await board.boardRecoveryTallies(payer.address, recordedAt)).cancel).to.equal(1);

    // A itself is removed (its seat is void), the board clears the seat, then the board cancels A's removal
    await removeInRecovery(f, A);
    await board.syncBoard();
    expect(await board.isBoardMember(A.address)).to.equal(false);
    expect(await board.getBoardSize()).to.equal(4);
    await reg.connect(A).objectRecoveryRemoval();
    for (const x of [s0, s1, s3]) await board.connect(x).voteRecoveryRemoval(A.address, false);
    expect((await reg.validators(A.address)).status).to.equal(ST.SelfSuspended);

    // A's key is lost: migrated to B (heir) with NO seat; the key is recorded anyway
    await expect(migrate(f, A, heir)).to.emit(board, "BoardSeatMigrated").withArgs(A.address, heir.address, false, 0, 1);
    expect(await board.boardVoterKey(heir.address)).to.equal(A.address);
    await reg.connect(verifier).recordResume(heir.address, HASH);
    await board.moveReceivedVotes(A.address, 10); // finish the move (fillVacancies waits for it)
    expect(await board.voteCount(heir.address)).to.equal(1); // s0's vote moved to B
    await board.fillVacancies(); // B is seated again, by votes
    expect(await board.isBoardMember(heir.address)).to.equal(true);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
    // the person already voted on case X as A: B cannot vote again
    await expect(board.connect(heir).voteRecoveryRemoval(payer.address, false)).to.be.revertedWith("ValidatorsBoard: already voted");
    expect((await board.boardRecoveryTallies(payer.address, recordedAt)).cancel).to.equal(1);
  });

  it("a seated member migrated twice (a -> b -> c) stays blocked on a case the first address voted on", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, founders, heir, heir2, payer } = f;
    const A = founders[2];
    await enterActive(f, payer);
    await removeInRecovery(f, payer);
    await reg.connect(payer).objectRecoveryRemoval();
    await board.connect(A).voteRecoveryRemoval(payer.address, false);
    await migrate(f, A, heir);
    await expect(board.connect(heir).voteRecoveryRemoval(payer.address, false)).to.be.revertedWith("ValidatorsBoard: already voted");
    await migrate(f, heir, heir2);
    expect(await board.boardVoterKey(heir2.address)).to.equal(A.address);
    await expect(board.connect(heir2).voteRecoveryRemoval(payer.address, false)).to.be.revertedWith("ValidatorsBoard: already voted");
  });
});

describe("ValidatorsBoard - dead voters: dropped by the chunked move, purged by clearDeadVotes", () => {
  const sell = async (f, seller, buyer) => {
    const seatId = await f.nft.seatOf(seller.address);
    await verifyAll(f, buyer);
    await f.reg.connect(buyer).acceptSeatAgreement(seatId, AGR);
    await f.nft.connect(seller).transferFrom(seller.address, buyer.address, seatId);
  };
  /// The candidate is founders[2]. `liveIdx` founders keep their seat and vote for it; `deadIdx` founders vote for it and then SELL their seat
  /// (their address is permanently exited from then on, its entry stays in the candidate's voter list).
  async function setup(f, liveIdx, deadIdx) {
    const { board, founders, S } = f;
    for (const i of [...liveIdx, ...deadIdx]) {
      await verifyAll(f, founders[i]);
      await board.connect(founders[i]).voteFor(founders[2].address);
    }
    let b = 15;
    for (const i of deadIdx) await sell(f, founders[i], S[b++]);
  }

  it("the chunked move DROPS the entries of dead voters instead of moving them; live ones move; counters stay right", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, stranger } = f;
    await setup(f, [4], [0, 1, 3]);
    expect((await board.getVotersFor(founders[2].address)).length).to.equal(4);
    expect(await board.voteCount(founders[2].address)).to.equal(1); // only the live voter counts
    await expect(migrate(f, founders[2], heir)).to.emit(board, "BoardSeatMigrated").withArgs(founders[2].address, heir.address, true, 0, 4);
    // the dead entries are the LAST ones of the list: one chunk of 3 drops them, a second moves the live voter
    await expect(board.connect(stranger).moveReceivedVotes(founders[2].address, 3))
      .to.emit(board, "ReceivedVotesMoved").withArgs(founders[2].address, heir.address, 0, 3, 0, 1)
      .and.to.not.emit(board, "ReceivedVotesMoveCompleted");
    expect(await board.pendingVoteMoves()).to.equal(1);
    await expect(board.connect(stranger).moveReceivedVotes(founders[2].address, 3))
      .to.emit(board, "ReceivedVotesMoved").withArgs(founders[2].address, heir.address, 1, 0, 0, 0)
      .and.to.emit(board, "ReceivedVotesMoveCompleted").withArgs(founders[2].address, heir.address);
    expect(await board.pendingVoteMoves()).to.equal(0);
    expect((await board.getVotersFor(heir.address)).length).to.equal(1);
    expect(await board.voteCount(heir.address)).to.equal(1);
    expect((await board.getVotersFor(founders[2].address)).length).to.equal(0);
    expect(await board.hasVotedFor(founders[4].address, heir.address)).to.equal(true);
    expect(await board.hasVotedFor(founders[0].address, founders[2].address)).to.equal(false);
    expect(await board.hasVotedFor(founders[0].address, heir.address)).to.equal(false);
  });

  it("clearDeadVotes: anyone can purge the votes of permanently exited voters beforehand; live voters and voters removed in a recovery are skipped", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, stranger } = f;
    await setup(f, [4], [0, 1, 3]);
    const A = founders[2].address;
    // S4 is removed in a recovery: not dead (that case can be cancelled), so it is skipped like a live voter
    await removeInRecovery(f, founders[4]);
    expect(await board.votesCounted(founders[4].address)).to.equal(false);
    const dead = [founders[0].address, founders[1].address, founders[3].address];
    const r = await (await board.connect(stranger).clearDeadVotes([...dead, founders[4].address, founders[2].address, stranger.address])).wait();
    console.log("      clearDeadVotes gas for 3 dead voters (1 vote each) + 3 skipped:", r.gasUsed.toString());
    for (const d of dead) {
      expect((await board.getVotesOf(d)).length).to.equal(0);
      expect(await board.hasVotedFor(d, A)).to.equal(false);
    }
    expect(await board.getVotersFor(A)).to.deep.equal([founders[4].address]);
    expect(await board.hasVotedFor(founders[4].address, A)).to.equal(true);
    // idempotent
    await board.connect(stranger).clearDeadVotes(dead);
    expect((await board.getVotersFor(A)).length).to.equal(1);
  });
});

describe("ValidatorsBoard - chunked move of RECEIVED votes: chain, refresh, fill, access", () => {
  /// founders s0,s1,s3,s4 (verified) vote for the candidate founders[2]
  async function withVoters(f) {
    for (const i of [0, 1, 3, 4]) {
      await verifyAll(f, f.founders[i]);
      await f.board.connect(f.founders[i]).voteFor(f.founders[2].address);
    }
  }

  it("the hook records a pending move; max = 0, nothing pending, repeated calls and permissionless access", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, stranger } = f;
    await withVoters(f);
    const A = founders[2].address;
    await expect(board.connect(stranger).moveReceivedVotes(A, 1)).to.be.revertedWith("ValidatorsBoard: nothing pending"); // before the migration
    await expect(migrate(f, founders[2], heir)).to.emit(board, "BoardSeatMigrated").withArgs(A, heir.address, true, 0, 4);
    expect(await board.pendingVoteMove(A)).to.equal(heir.address);
    expect(await board.pendingVoteMoves()).to.equal(1);
    expect(await board.voteCount(heir.address)).to.equal(0); // nothing moved yet
    expect(await board.voteCount(A)).to.equal(4);
    await expect(board.connect(stranger).moveReceivedVotes(A, 0)).to.be.revertedWith("ValidatorsBoard: max is zero");
    await expect(board.connect(stranger).moveReceivedVotes(heir.address, 1)).to.be.revertedWith("ValidatorsBoard: nothing pending"); // keyed by the OLD address
    // a stranger (no role at all) moves the first chunk
    await expect(board.connect(stranger).moveReceivedVotes(A, 1)).to.emit(board, "ReceivedVotesMoved").withArgs(A, heir.address, 1, 0, 0, 3);
    expect(await board.voteCount(heir.address)).to.equal(1);
    expect(await board.voteCount(A)).to.equal(3);
    await board.connect(stranger).moveReceivedVotes(A, 1);
    expect(await board.voteCount(heir.address)).to.equal(2);
    // a max larger than the rest is fine; the last call completes
    await expect(board.connect(stranger).moveReceivedVotes(A, 1000)).to.emit(board, "ReceivedVotesMoveCompleted").withArgs(A, heir.address);
    expect(await board.voteCount(heir.address)).to.equal(4);
    expect(await board.voteCount(A)).to.equal(0);
    expect(await board.pendingVoteMove(A)).to.equal(ZERO);
    expect(await board.pendingVoteMoves()).to.equal(0);
    // repeated calls after completion are refused, nothing changes
    await expect(board.connect(stranger).moveReceivedVotes(A, 1)).to.be.revertedWith("ValidatorsBoard: nothing pending");
    expect(await board.voteCount(heir.address)).to.equal(4);
    expect((await board.getVotersFor(heir.address)).length).to.equal(4);
  });

  it("a voter that votes for the new address directly while the move is pending is merged: one vote, counters exact; a voter may withdraw meanwhile", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, stranger } = f;
    await withVoters(f);
    const A = founders[2].address;
    await migrate(f, founders[2], heir);
    await board.connect(founders[0]).voteFor(heir.address); // directly, while pending
    await board.connect(founders[1]).unvoteFor(A); // withdraws the old vote itself, while pending
    expect(await board.voteCount(heir.address)).to.equal(1);
    expect(await board.voteCount(A)).to.equal(3);
    await expect(board.connect(stranger).moveReceivedVotes(A, 100)).to.emit(board, "ReceivedVotesMoveCompleted");
    // 4 voters, one withdrew, one voted directly: s0 (merged), s3, s4 -> 3 votes in all, s1 none
    expect(await board.voteCount(heir.address)).to.equal(3);
    expect(await board.voteCount(A)).to.equal(0);
    expect((await board.getVotersFor(heir.address)).length).to.equal(3);
    expect(await board.hasVotedFor(founders[1].address, heir.address)).to.equal(false);
    expect((await board.getVotesOf(founders[0].address)).length).to.equal(1); // not two
  });

  it("CHAIN with a pending move: a -> b, then b -> c is refused until the first move is complete; then nothing is lost or counted twice", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, heir2, stranger } = f;
    await withVoters(f);
    const A = founders[2];
    await migrate(f, A, heir);
    await board.connect(stranger).moveReceivedVotes(A.address, 2); // half done
    await migrateId(f, heir, heir2);
    await expect(migrateSeat(f, heir, heir2)).to.be.revertedWith("ValidatorsBoard: move pending"); // the whole migration reverts
    expect((await f.reg.validators(heir2.address)).status).to.equal(ST.None);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
    await board.connect(stranger).moveReceivedVotes(A.address, 2);
    expect(await board.voteCount(heir.address)).to.equal(4);
    // now the second migration goes through; the four votes follow once more, in a new pending move
    await expect(migrateSeat(f, heir, heir2)).to.emit(board, "BoardSeatMigrated").withArgs(heir.address, heir2.address, true, 0, 4);
    expect(await board.pendingVoteMove(heir.address)).to.equal(heir2.address);
    await board.connect(stranger).moveReceivedVotes(heir.address, 100);
    expect(await board.voteCount(heir2.address)).to.equal(4);
    expect(await board.voteCount(heir.address)).to.equal(0);
    expect(await board.voteCount(A.address)).to.equal(0);
    expect(await board.pendingVoteMoves()).to.equal(0);
    expect(await board.boardVoterKey(heir2.address)).to.equal(A.address);
    expect(await board.hasBoardAuthority(heir2.address)).to.equal(true);
    expect((await board.getVotersFor(heir2.address)).length).to.equal(4);
  });

  it("fillVacancies waits for a pending move (syncBoard still clears the void seat and leaves the vacancy); then it seats the right person", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, board, founders, heir, buyer, payer, stranger } = f;
    await enterActive(f, payer); // a non-member candidate
    await withVoters(f);
    for (const i of [0, 1]) await board.connect(founders[i]).voteFor(payer.address);
    await migrate(f, founders[2], heir); // pending: 4 received votes
    // a seat is sold: its seat is void, the vacancy opens
    const seatId = await nft.seatOf(founders[3].address);
    await verifyAll(f, buyer);
    await reg.connect(buyer).acceptSeatAgreement(seatId, AGR);
    await nft.connect(founders[3]).transferFrom(founders[3].address, buyer.address, seatId);
    await board.syncBoard(); // clears the void seat; the fill is skipped while the move is pending
    expect(await board.getBoardSize()).to.equal(4);
    expect(await board.pendingVacancies()).to.equal(1);
    await expect(board.fillVacancies()).to.be.revertedWith("ValidatorsBoard: move pending");
    expect(await board.getBoardSize()).to.equal(4);
    await board.connect(stranger).moveReceivedVotes(founders[2].address, 100);
    await board.fillVacancies();
    expect(await board.getBoardSize()).to.equal(5);
    // the best non-member candidate is the one with most votes: heir is a member, payer (2 votes) is next, founders[3]'s buyer none
    expect(await board.isBoardMember(payer.address)).to.equal(true);
    expect(await board.pendingVacancies()).to.equal(0);
  });

  it("a month-end refresh WAITS while a move is pending; after it, the migrated person is seated with all its votes and the board version does not change", async () => {
    const f = await loadFixture(fixture);
    const { board, founders, heir, stranger } = f;
    for (const x of founders) await verifyAll(f, x);
    for (const x of founders) for (const c of founders) await board.connect(x).voteFor(c.address); // each candidate: 5 votes
    await increaseTime(40 * DAY);
    const version = await board.boardVersion();
    await migrate(f, founders[2], heir); // heir: 5 cast votes moved now; 4 received are pending
    expect(await board.voteCount(heir.address)).to.equal(1); // only its own cast self-vote so far
    await expect(board.refreshBoard([])).to.be.revertedWith("ValidatorsBoard: move pending");
    await board.connect(stranger).moveReceivedVotes(founders[2].address, 100);
    expect(await board.voteCount(heir.address)).to.equal(5);
    await board.refreshBoard([]);
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.isBoardMember(heir.address)).to.equal(true);
    expect(await board.isBoardMember(founders[2].address)).to.equal(false);
    expect(await board.boardVersion()).to.equal(version); // the same five PEOPLE
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
  });

  it("a void seat combined with a migration AFTER the month ended: no seat for the new address; the refresh seats the person by its moved votes", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, verifier, founders, heir, stranger } = f;
    const A = founders[2];
    for (const x of founders) await verifyAll(f, x);
    for (const x of founders) for (const c of founders) await board.connect(x).voteFor(c.address);
    // A's seat becomes void: removed in a recovery, the removal expires (cancelled), the epoch is not restored
    await removeInRecovery(f, A);
    await reg.connect(A).objectRecoveryRemoval();
    await increaseTime(8 * DAY);
    await reg.expireRecoveryRemoval(A.address);
    expect(await board.hasValidSeat(A.address)).to.equal(false);
    await increaseTime(40 * DAY); // the board's month is over too
    expect(await board.refreshDue()).to.equal(true);

    await expect(migrate(f, A, heir)).to.emit(board, "BoardSeatMigrated").withArgs(A.address, heir.address, false, 5, 4);
    expect(await board.isBoardMember(heir.address)).to.equal(false); // the void seat is NOT revived
    expect(await board.isBoardMember(A.address)).to.equal(true); // left for the refresh
    expect(await board.hasBoardAuthority(heir.address)).to.equal(false);
    expect(await board.hasBoardAuthority(A.address)).to.equal(false);
    await reg.connect(verifier).recordResume(heir.address, HASH); // Active again: its votes count
    await expect(board.refreshBoard([])).to.be.revertedWith("ValidatorsBoard: move pending");
    await board.connect(stranger).moveReceivedVotes(A.address, 100);
    await board.refreshBoard([]);
    expect(await board.isBoardMember(A.address)).to.equal(false);
    expect(await board.isBoardMember(heir.address)).to.equal(true); // elected by the votes that followed the person
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.hasBoardAuthority(heir.address)).to.equal(true);
  });
});

describe("ValidatorsBoard - a LARGE received-vote list (320 live voters, built for real)", function () {
  this.timeout(0);
  const N = 320;
  async function bigFixture() {
    const f = await loadFixture(fixture); // start from the clean snapshot (a second fixture in one file would inherit the leftovers of earlier tests)
    const A = f.founders[2];
    const voters = [];
    for (let i = 0; i < N; i++) {
      const w = ethers.Wallet.createRandom().connect(ethers.provider);
      await hre.network.provider.send("hardhat_setBalance", [w.address, "0x" + E("2000000").toString(16)]);
      await enterActive(f, w); // identity, collateral, probation, activation (one paid entry per week)
      await f.board.connect(w).voteFor(A.address);
      voters.push(w);
    }
    return { ...f, voters };
  }
  /// the counters must equal the number of COUNTED voters in the lists (exactness check over a whole list)
  async function countedIn(board, list) {
    const flags = await Promise.all(list.map((v) => board.votesCounted(v)));
    return flags.filter(Boolean).length;
  }

  it("migrates with several chunks: counters exact after every chunk; one dead voter dropped, one pre-voter merged", async () => {
    const f = await loadFixture(bigFixture);
    const { board, reg, founders, heir, voters, stranger } = f;
    const A = founders[2].address;
    expect(await board.voteCount(A)).to.equal(N);
    await reg.connect(voters[0]).requestExit({ gasLimit: 3_000_000 }); // (explicit gas: estimateGas would size the best-effort board notification too small) a dead voter: its entry is dropped, not moved
    expect(await board.voteCount(A)).to.equal(N - 1);
    expect((await board.getVotersFor(A)).length).to.equal(N);

    await expect(migrate(f, founders[2], heir)).to.emit(board, "BoardSeatMigrated").withArgs(A, heir.address, true, 0, N);
    expect(await board.voteCount(heir.address)).to.equal(0);
    await board.connect(voters[1]).voteFor(heir.address); // merged later: one vote, not two
    expect(await board.voteCount(heir.address)).to.equal(1);

    let totalMoved = 0, totalDropped = 0, totalMerged = 0, calls = 0;
    const sizes = [100, 100, 100, 1000];
    for (const max of sizes) {
      const rc = await (await board.connect(stranger).moveReceivedVotes(A, max)).wait();
      calls++;
      const ev = rc.logs.map((l) => { try { return board.interface.parseLog(l); } catch { return null; } }).filter((e) => e && e.name === "ReceivedVotesMoved")[0];
      totalMoved += Number(ev.args.moved); totalDropped += Number(ev.args.dropped); totalMerged += Number(ev.args.merged);
      const oldList = await board.getVotersFor(A);
      const newList = await board.getVotersFor(heir.address);
      expect(Number(ev.args.remaining)).to.equal(oldList.length);
      expect(await board.voteCount(A)).to.equal(await countedIn(board, oldList)); // exact, every chunk
      expect(await board.voteCount(heir.address)).to.equal(await countedIn(board, newList));
      if (max === 100) expect(rc.gasUsed).to.be.lt(15_000_000n);
      if (oldList.length === 0) break;
    }
    expect(calls).to.equal(4);
    expect(totalDropped).to.equal(1);
    expect(totalMerged).to.equal(1);
    expect(totalMoved).to.equal(N - 2);
    expect(await board.pendingVoteMoves()).to.equal(0);
    expect(await board.voteCount(A)).to.equal(0);
    expect(await board.voteCount(heir.address)).to.equal(N - 1); // everybody but the voter that left
    expect((await board.getVotersFor(heir.address)).length).to.equal(N - 1);
    expect(await board.hasVotedFor(voters[5].address, heir.address)).to.equal(true);
    expect(await board.hasVotedFor(voters[5].address, A)).to.equal(false);
    expect(await board.hasVotedFor(voters[1].address, A)).to.equal(false);
    expect((await board.getVotesOf(voters[1].address)).length).to.equal(1);
  });

  it("the hook's gas does NOT depend on the number of received votes (20 vs 320); gas per chunk entry", async () => {
    const f = await loadFixture(bigFixture);
    const { board, founders, heir, heir2, voters, stranger } = f;
    for (let i = 0; i < 20; i++) await board.connect(voters[i]).voteFor(founders[3].address); // founders[3] receives 20 votes, founders[2] 320
    const g20 = (await (await migrate(f, founders[3], heir)).wait()).gasUsed;
    const g320 = (await (await migrate(f, founders[2], heir2)).wait()).gasUsed;
    console.log("      migrateSeat gas with 20 received votes: " + g20 + ", with 320 received votes: " + g320);
    const diff = g20 > g320 ? g20 - g320 : g320 - g20;
    expect(diff).to.be.lt(30_000n); // the same work but for one counter written from zero (~17k): the lists are not touched (300 entries would cost ~27,000,000)
    expect(g320).to.be.lt(900_000n);
    const c50 = (await (await board.connect(stranger).moveReceivedVotes(founders[2].address, 50)).wait()).gasUsed;
    const c100 = (await (await board.connect(stranger).moveReceivedVotes(founders[2].address, 100)).wait()).gasUsed;
    const perEntry = (c100 - c50) / 50n;
    console.log("      moveReceivedVotes: 50 entries " + c50 + ", 100 entries " + c100 + ", per live entry ~" + perEntry);
    console.log("      entries per 45,000,000 gas: ~" + 45_000_000n / perEntry + "; per 16,700,000 gas (EIP-7825): ~" + 16_700_000n / perEntry);
    // (the test network enforces a ~16.7M per-transaction cap, so chunks stay small)
    await board.connect(stranger).moveReceivedVotes(founders[2].address, 100);
    await board.connect(stranger).moveReceivedVotes(founders[2].address, 100);
    await board.connect(stranger).moveReceivedVotes(founders[3].address, 1000);
    expect(await board.voteCount(heir2.address)).to.equal(N);
    expect(await board.voteCount(heir.address)).to.equal(20);
    expect(await board.pendingVoteMoves()).to.equal(0);
  });
});
