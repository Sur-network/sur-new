// SurKMS freeze switch: KmsDirectives (per-key frozen flag) + ValidatorsBoard.KmsFreeze action + FoundationDAO Execute for identityOracle.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000); // leaves four weeks inside one board month
const SLOT = { Verifier: 0, DistributionOracle: 1, IdentityOracle: 2 };
const KMS_FREEZE = 5; // ActionType.KmsFreeze
const rnd = () => ethers.Wallet.createRandom().address;

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const founders = S.slice(0, 7);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, rnd(), founders.slice(1).map((s) => s.address), t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  const board = await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [S.slice(0, 5).map((s) => s.address), t0]);
  const kms = await deployAtFixed("KmsDirectives", "KmsDirectives", ADDR.KMS_DIRECTIVES, []);
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const daoBoard = S.slice(12, 17);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [daoBoard.map((s) => s.address), S[17].address, daoBoard[0].address, daoBoard[1].address, S[18].address, t0 + 730 * DAY], E("10"));
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const f of founders.slice(1)) {
    await reg.connect(f).setOperator(rnd());
    await reg.connect(verifier).recordActivation(f.address, HASH);
  }
  return { S, reg, board, kms, dao, daoBoard, verifier, founders };
}

async function lastId(c) { return await c.actionCount(); }

async function asAddr(addr) {
  await hre.network.provider.send("hardhat_setBalance", [addr, "0x56BC75E2D63100000"]);
  return ethers.getImpersonatedSigner(addr);
}

describe("KmsDirectives - the contract", () => {
  it("starts with nothing frozen; only the right caller may set each slot", async () => {
    const { kms, S } = await loadFixture(fixture);
    for (const s of [0, 1, 2]) expect(await kms.frozen(s)).to.equal(false);
    const board = await asAddr(ADDR.VALIDATORS_BOARD), dao = await asAddr(ADDR.FOUNDATION_DAO);
    await expect(kms.connect(S[5]).setFrozen(SLOT.Verifier, true)).to.be.revertedWith("KmsDirectives: this key is frozen only by ValidatorsBoard");
    await expect(kms.connect(S[5]).setFrozen(SLOT.IdentityOracle, true)).to.be.revertedWith("KmsDirectives: identityOracle is frozen only by FoundationDAO");
    await expect(kms.connect(dao).setFrozen(SLOT.Verifier, true)).to.be.revertedWith("KmsDirectives: this key is frozen only by ValidatorsBoard");
    await expect(kms.connect(dao).setFrozen(SLOT.DistributionOracle, true)).to.be.revertedWith("KmsDirectives: this key is frozen only by ValidatorsBoard");
    await expect(kms.connect(board).setFrozen(SLOT.IdentityOracle, true)).to.be.revertedWith("KmsDirectives: identityOracle is frozen only by FoundationDAO");
    await expect(kms.connect(board).setFrozen(3, true)).to.be.reverted; // not a slot
    // a freeze is per slot and visible through frozen(slot); the event carries slot and value; a repeat is a silent no-op
    await expect(kms.connect(board).setFrozen(SLOT.DistributionOracle, true)).to.emit(kms, "FrozenChanged").withArgs(SLOT.DistributionOracle, true);
    expect([await kms.frozen(0), await kms.frozen(1), await kms.frozen(2)]).to.deep.equal([false, true, false]);
    await expect(kms.connect(board).setFrozen(SLOT.DistributionOracle, true)).to.not.emit(kms, "FrozenChanged");
    await expect(kms.connect(dao).setFrozen(SLOT.IdentityOracle, true)).to.emit(kms, "FrozenChanged").withArgs(SLOT.IdentityOracle, true);
    await expect(kms.connect(board).setFrozen(SLOT.DistributionOracle, false)).to.emit(kms, "FrozenChanged").withArgs(SLOT.DistributionOracle, false);
    expect([await kms.frozen(0), await kms.frozen(1), await kms.frozen(2)]).to.deep.equal([false, false, true]);
  });
});

describe("ValidatorsBoard - KmsFreeze action", () => {
  it("only a board member proposes; the board cannot freeze identityOracle; 3 votes execute; nothing happens before the quorum", async () => {
    const { board, kms, S } = await loadFixture(fixture);
    await expect(board.connect(S[5]).proposeKmsFreeze(SLOT.Verifier, true)).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    await expect(board.connect(S[0]).proposeKmsFreeze(SLOT.IdentityOracle, true)).to.be.revertedWith("ValidatorsBoard: the board freezes only the verifier and distributionOracle keys");
    await expect(board.connect(S[0]).proposeKmsFreeze(7, true)).to.be.revertedWith("ValidatorsBoard: the board freezes only the verifier and distributionOracle keys");

    await expect(board.connect(S[0]).proposeKmsFreeze(SLOT.Verifier, true)).to.emit(board, "ActionProposed");
    const id = await lastId(board);
    const a = await board.actions(id);
    expect(a.atype).to.equal(KMS_FREEZE);
    expect(a.requiredVotes).to.equal(3); // max(majority 3, MIN_VOTES_SENSITIVE_ACTION 3)
    expect(a.votes).to.equal(1);
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
    await board.connect(S[1]).voteAction(id);
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
    await expect(board.connect(S[1]).voteAction(id)).to.be.revertedWith("ValidatorsBoard: already voted");
    await expect(board.connect(S[5]).voteAction(id)).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    const tx = board.connect(S[2]).voteAction(id);
    await expect(tx).to.emit(kms, "FrozenChanged").withArgs(SLOT.Verifier, true);
    await expect(tx).to.emit(board, "KmsFreezeApplied").withArgs(SLOT.Verifier, true);
    expect(await kms.frozen(SLOT.Verifier)).to.equal(true);
    expect(await kms.frozen(SLOT.DistributionOracle)).to.equal(false);
    await expect(board.connect(S[3]).voteAction(id)).to.be.revertedWith("ValidatorsBoard: already executed");
  });

  it("unfreeze goes through the same vote; the distributionOracle slot is independent", async () => {
    const { board, kms, S } = await loadFixture(fixture);
    for (const [slot, frozen] of [[SLOT.DistributionOracle, true], [SLOT.DistributionOracle, false]]) {
      await board.connect(S[0]).proposeKmsFreeze(slot, frozen);
      const id = await lastId(board);
      await board.connect(S[1]).voteAction(id);
      await board.connect(S[2]).voteAction(id);
      expect(await kms.frozen(slot)).to.equal(frozen);
    }
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
  });

  it("an action that sets the value a slot already has executes without error (no stuck proposal)", async () => {
    const { board, kms, S } = await loadFixture(fixture);
    await board.connect(S[0]).proposeKmsFreeze(SLOT.Verifier, false);
    const id = await lastId(board);
    await board.connect(S[1]).voteAction(id);
    await expect(board.connect(S[2]).voteAction(id)).to.emit(board, "KmsFreezeApplied").withArgs(SLOT.Verifier, false);
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
  });

  it("the action is void after a board change (boardVersion) and after BOARD_ACTION_EXPIRY", async () => {
    const f = await loadFixture(fixture);
    const { board, reg, verifier, kms, S } = f;
    // 1) board change: S4 is removed in a recovery, the board syncs, boardVersion moves
    await board.connect(S[0]).proposeKmsFreeze(SLOT.Verifier, true);
    const id = await lastId(board);
    await board.connect(S[1]).voteAction(id); // 2 of 3
    const v0 = await board.boardVersion();
    await reg.connect(verifier).recordRecoveryRemoval(S[4].address, await now(), HASH);
    await board.syncBoard();
    expect(await board.boardVersion()).to.be.gt(v0);
    await expect(board.connect(S[2]).voteAction(id)).to.be.revertedWith("ValidatorsBoard: board membership changed since this action was proposed - propose again");
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
    // a fresh proposal by the new board still works
    await board.connect(S[0]).proposeKmsFreeze(SLOT.Verifier, true);
    const id2 = await lastId(board);
    expect((await board.actions(id2)).boardVersionAtCreation).to.equal(await board.boardVersion());
    // 2) expiry
    await increaseTime(15 * DAY);
    await expect(board.connect(S[1]).voteAction(id2)).to.be.revertedWith("ValidatorsBoard: action has expired");
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
  });
});

describe("FoundationDAO - identityOracle freeze through the existing Execute proposal", () => {
  it("proposeExecute(KmsDirectives.setFrozen(IdentityOracle)) with the DAO majority freezes the key; the DAO needs no change", async () => {
    const { dao, daoBoard, kms } = await loadFixture(fixture);
    const data = kms.interface.encodeFunctionData("setFrozen", [SLOT.IdentityOracle, true]);
    await dao.connect(daoBoard[0]).proposeExecute(ADDR.KMS_DIRECTIVES, 0, data, "freeze identityOracle");
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(daoBoard[1]).vote(id, h);
    expect(await kms.frozen(SLOT.IdentityOracle)).to.equal(false);
    await dao.connect(daoBoard[2]).vote(id, h);
    expect(await kms.frozen(SLOT.IdentityOracle)).to.equal(true);
    // the DAO cannot freeze the board's keys
    const bad = kms.interface.encodeFunctionData("setFrozen", [SLOT.Verifier, true]);
    await dao.connect(daoBoard[0]).proposeExecute(ADDR.KMS_DIRECTIVES, 0, bad, "wrong slot");
    const id2 = await dao.proposalCount();
    const h2 = (await dao.getProposal(id2)).paramsHash;
    await dao.connect(daoBoard[1]).vote(id2, h2);
    await expect(dao.connect(daoBoard[2]).vote(id2, h2)).to.be.revertedWith("KmsDirectives: this key is frozen only by ValidatorsBoard");
    expect(await kms.frozen(SLOT.Verifier)).to.equal(false);
  });
});
