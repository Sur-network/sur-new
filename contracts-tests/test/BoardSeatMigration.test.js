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
    expect(await board.boardVoterKey(stranger.address)).to.equal(stranger.address); // no chain is recorded for a non-member
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
    await expect(board.connect(stranger).onSeatMigrated(founders[0].address, heir.address)).to.be.revertedWith(msg);
    await expect(board.connect(founders[0]).onSeatMigrated(founders[0].address, heir.address)).to.be.revertedWith(msg); // a board member
    await expect(board.connect(verifier).onSeatMigrated(founders[0].address, heir.address)).to.be.revertedWith(msg);
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATORS_REGISTRY, "0x56BC75E2D63100000"]);
    const asReg = await ethers.getImpersonatedSigner(ADDR.VALIDATORS_REGISTRY);
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, ZERO)).to.be.revertedWith("ValidatorsBoard: bad migration addresses");
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, founders[0].address)).to.be.revertedWith("ValidatorsBoard: bad migration addresses");
    await expect(board.connect(asReg).onSeatMigrated(founders[0].address, founders[1].address)).to.be.revertedWith("ValidatorsBoard: new owner already holds a seat");
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
