// v2.5: removal from the validator list during network recovery (Registry + Board).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const HASH = ethers.id("qbft_getSignerMetrics evidence");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000); // 2027-03-02: leaves four weeks inside one board month

const S_NONE = 0, S_RECORDED = 1, S_OBJECTED = 2, S_REFERRED = 3, S_UPHELD = 4, S_CANCELLED = 5;
const ST_ACTIVE = 2, ST_EXITING = 4, ST_REMOVED = 5, ST_SELF_SUSPENDED = 6;

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  const t0 = await now();
  const founders = S.slice(0, 7);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const op = (i) => ethers.Wallet.createRandom().address; // node (operator) keys are plain addresses here
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, op(0), founders.slice(1).map((s) => s.address), t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  const board = await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [S.slice(0, 5).map((s) => s.address), t0]);
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  // the other six founders set their node key and the Verifier activates them (no probation wait for founders)
  for (const f of founders.slice(1)) {
    await reg.connect(f).setOperator(op());
    await reg.connect(verifier).recordActivation(f.address, HASH);
  }

  // one paid validator with real collateral (500,000 + 4% fee)
  const paid = S[10];
  await idr.setVerified(paid.address, true);
  await hre.network.provider.send("hardhat_setBalance", [paid.address, "0x" + E("1000000").toString(16)]);
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  await reg.connect(paid).requestMembership(op(), { value: price });
  await increaseTime(8 * DAY);
  await reg.connect(verifier).recordActivation(paid.address, HASH);
  return { S, reg, board, verifier, paid, founders };
}

async function remove(f, who, ageDays = 0) {
  const ts = (await now()) - ageDays * DAY;
  return f.reg.connect(f.verifier).recordRecoveryRemoval(who.address, ts, HASH);
}

describe("Recovery removal - recording", () => {
  it("only the Verifier, only an Active validator, sane recoveryTimestamp, non-empty evidence", async () => {
    const f = await loadFixture(fixture);
    const { reg, verifier, S, paid } = f;
    const t = await now();
    await expect(reg.connect(S[0]).recordRecoveryRemoval(paid.address, t, HASH)).to.be.revertedWith("ValidatorsRegistry: caller is not the verifier");
    await expect(reg.connect(verifier).recordRecoveryRemoval(S[15].address, t, HASH)).to.be.revertedWith("ValidatorsRegistry: validator is not active");
    await expect(reg.connect(verifier).recordRecoveryRemoval(paid.address, t + 1000, HASH)).to.be.revertedWith("ValidatorsRegistry: recoveryTimestamp out of range");
    await expect(reg.connect(verifier).recordRecoveryRemoval(paid.address, t - 31 * DAY, HASH)).to.be.revertedWith("ValidatorsRegistry: recoveryTimestamp out of range");
    await expect(reg.connect(verifier).recordRecoveryRemoval(paid.address, t, ethers.ZeroHash)).to.be.revertedWith("ValidatorsRegistry: empty evidence hash");
  });

  it("removes from the list, keeps the collateral, applies the permanent ban, ends board authority", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, S, paid } = f;
    const stake = (await reg.validators(paid.address)).lockedStake;
    expect(stake).to.equal(E("500000"));
    const paidBefore = await reg.paidValidatorCount();
    expect(await board.hasBoardAuthority(S[0].address)).to.equal(true);

    await remove(f, paid);
    await remove(f, S[0]);
    expect(await reg.getActiveOwners()).to.not.include(paid.address);
    expect(await reg.getActiveOwners()).to.not.include(S[0].address);
    expect((await reg.validators(paid.address)).status).to.equal(ST_REMOVED);
    expect((await reg.validators(paid.address)).lockedStake).to.equal(stake); // no penalty
    expect(await reg.isValidator(paid.address)).to.equal(false);
    expect(await reg.permanentlyExited(paid.address)).to.equal(true);
    expect(await reg.paidValidatorCount()).to.equal(paidBefore - 1n);
    expect(await board.hasBoardAuthority(S[0].address)).to.equal(false);

    const r = await reg.recoveryRemovals(paid.address);
    expect(r.state).to.equal(S_RECORDED);
    expect(r.evidenceHash).to.equal(HASH);
    expect(r.exitAllowedAt).to.equal(r.recoveryTimestamp + BigInt(90 * DAY));
    expect(r.objectionDeadline).to.equal(r.recordedAt + BigInt(72 * 3600));
    await expect(remove(f, paid)).to.be.revertedWith("ValidatorsRegistry: validator is not active");
    await expect(reg.connect(paid).requestMembership(ethers.Wallet.createRandom().address, { value: 1 })).to.be.reverted; // the ban
  });
});

describe("Recovery removal - no objection", () => {
  it("collateral is locked 90 days from the recovery, then requestExit + cooldown + withdraw", async () => {
    const f = await loadFixture(fixture);
    const { reg, paid } = f;
    await remove(f, paid);
    await expect(reg.connect(paid).requestExit()).to.be.revertedWith("ValidatorsRegistry: removal case still open"); // objection window
    await increaseTime(4 * DAY);
    await expect(reg.connect(paid).requestExit()).to.be.revertedWith("ValidatorsRegistry: collateral locked for 90 days after recovery");
    await increaseTime(87 * DAY);
    await reg.connect(paid).requestExit();
    expect((await reg.validators(paid.address)).status).to.equal(ST_EXITING);
    await expect(reg.connect(paid).withdrawStake()).to.be.revertedWith("ValidatorsRegistry: exit cooldown not elapsed");
    await increaseTime(8 * DAY);
    const before = await ethers.provider.getBalance(paid.address);
    const tx = await reg.connect(paid).withdrawStake();
    const rc = await tx.wait();
    expect(await ethers.provider.getBalance(paid.address)).to.equal(before + E("500000") - rc.gasUsed * rc.gasPrice);
  });

  it("the 90 days count from the recovery, not from the recording", async () => {
    const f = await loadFixture(fixture);
    const { reg, paid } = f;
    await remove(f, paid, 20); // the network came back 20 days ago
    await increaseTime(4 * DAY);
    await increaseTime(66 * DAY); // 90 days after the recovery = 70 days after the recording
    await reg.connect(paid).requestExit();
    expect((await reg.validators(paid.address)).status).to.equal(ST_EXITING);
  });
});

describe("Recovery removal - objection decided by the board", () => {
  it("objection window is 72 hours and only for the removed validator", async () => {
    const f = await loadFixture(fixture);
    const { reg, paid, S } = f;
    await expect(reg.connect(paid).objectRecoveryRemoval()).to.be.revertedWith("ValidatorsRegistry: nothing to object to");
    await remove(f, paid);
    await expect(reg.connect(S[1]).objectRecoveryRemoval()).to.be.revertedWith("ValidatorsRegistry: nothing to object to");
    await increaseTime(73 * 3600);
    await expect(reg.connect(paid).objectRecoveryRemoval()).to.be.revertedWith("ValidatorsRegistry: objection window over");
  });

  it("3 board votes to uphold: the removal stands and the exit path opens after the lock", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, paid, S } = f;
    await remove(f, paid);
    await reg.connect(paid).objectRecoveryRemoval();
    await expect(board.connect(paid).voteRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    await expect(board.connect(S[5]).voteRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    await board.connect(S[0]).voteRecoveryRemoval(paid.address, true);
    await expect(board.connect(S[0]).voteRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsBoard: already voted");
    await board.connect(S[1]).voteRecoveryRemoval(paid.address, false);
    await board.connect(S[2]).voteRecoveryRemoval(paid.address, true);
    expect((await reg.recoveryRemovals(paid.address)).state).to.equal(S_OBJECTED);
    await board.connect(S[3]).voteRecoveryRemoval(paid.address, true);
    expect((await reg.recoveryRemovals(paid.address)).state).to.equal(S_UPHELD);
    await increaseTime(91 * DAY);
    await reg.connect(paid).requestExit();
    expect((await reg.validators(paid.address)).status).to.equal(ST_EXITING);
  });

  it("VD-4: 3 board votes to cancel: the validator returns to SelfSuspended (NOT Active), the ban is lifted, and only the Verifier's recordResume brings it back", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, paid, S } = f;
    const paidBefore = await reg.paidValidatorCount();
    await remove(f, paid);
    await reg.connect(paid).objectRecoveryRemoval();
    for (const i of [0, 1, 2]) await board.connect(S[i]).voteRecoveryRemoval(paid.address, false);
    expect((await reg.recoveryRemovals(paid.address)).state).to.equal(S_CANCELLED);
    expect((await reg.validators(paid.address)).status).to.equal(ST_SELF_SUSPENDED);
    expect(await reg.getActiveOwners()).to.not.include(paid.address); // still out of the consensus list: the node was never checked
    expect(await reg.permanentlyExited(paid.address)).to.equal(false);
    expect(await reg.paidValidatorCount()).to.equal(paidBefore);
    expect((await reg.validators(paid.address)).lockedStake).to.equal(E("500000"));
    expect(await reg.resumeRequested(paid.address)).to.equal(true); // the resume request is opened by the cancellation
    // nobody but the Verifier brings it back; the owner cannot do it itself
    await expect(reg.connect(paid).recordResume(paid.address, HASH)).to.be.revertedWith("ValidatorsRegistry: caller is not the verifier");
    await reg.connect(f.verifier).recordResume(paid.address, HASH);
    expect((await reg.validators(paid.address)).status).to.equal(ST_ACTIVE);
    expect(await reg.getActiveOwners()).to.include(paid.address);
    expect(await reg.resumeRequested(paid.address)).to.equal(false);
  });

  it("VD-4: a cancelled validator may also exit normally or change its node key while SelfSuspended; recordResume needs the operator key", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, paid, S, verifier } = f;
    await remove(f, paid);
    await reg.connect(paid).objectRecoveryRemoval();
    for (const i of [0, 1, 2]) await board.connect(S[i]).voteRecoveryRemoval(paid.address, false);
    await reg.connect(paid).setOperator(ethers.Wallet.createRandom().address); // SelfSuspended: immediate
    await expect(reg.connect(paid).requestResume()).to.not.be.reverted;
    await reg.connect(verifier).recordResume(paid.address, HASH);
    expect((await reg.validators(paid.address)).status).to.equal(ST_ACTIVE);
    // a second recordResume is refused: no longer suspended
    await expect(reg.connect(verifier).recordResume(paid.address, HASH)).to.be.revertedWith("ValidatorsRegistry: not self-suspended");
  });

  it("no decision within 7 days: anyone can cancel (expire) the removal; a late board vote is refused", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, paid, S } = f;
    await remove(f, paid);
    await reg.connect(paid).objectRecoveryRemoval();
    await board.connect(S[0]).voteRecoveryRemoval(paid.address, true);
    await expect(reg.expireRecoveryRemoval(paid.address)).to.be.revertedWith("ValidatorsRegistry: nothing to expire");
    await increaseTime(7 * DAY + 10);
    await expect(board.connect(S[1]).voteRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsBoard: decision window over");
    await reg.connect(S[9]).expireRecoveryRemoval(paid.address);
    expect((await reg.recoveryRemovals(paid.address)).state).to.equal(S_CANCELLED);
    expect((await reg.validators(paid.address)).status).to.equal(ST_SELF_SUSPENDED); // VD-4
  });

  it("only the board can resolve or refer a case; the board vote needs an open case", async () => {
    const f = await loadFixture(fixture);
    const { reg, board, paid, S } = f;
    await remove(f, paid);
    await expect(reg.connect(S[0]).resolveRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsRegistry: caller is not the validators board");
    await expect(reg.connect(S[0]).setRecoveryCaseReferred(paid.address)).to.be.revertedWith("ValidatorsRegistry: caller is not the validators board");
    await expect(board.connect(S[0]).voteRecoveryRemoval(paid.address, true)).to.be.revertedWith("ValidatorsBoard: no open board case");
    await expect(board.referRecoveryRemovalToAssembly(paid.address)).to.be.revertedWith("ValidatorsBoard: enough impartial board members");
  });
});

describe("Recovery removal - fewer than 3 impartial board members: the validators decide", () => {
  /// remove board members S1, S2, S3; S1 objects, leaving only S0 and S4 with authority besides the subject
  async function referred() {
    const f = await loadFixture(fixture);
    const { reg, board, S } = f;
    for (const i of [1, 2, 3]) await remove(f, S[i]);
    await reg.connect(S[1]).objectRecoveryRemoval();
    await board.referRecoveryRemovalToAssembly(S[1].address); // anyone
    return f;
  }

  it("referral freezes the electorate; two thirds uphold the removal", async () => {
    const { reg, board, S } = await referred();
    const r = await reg.recoveryRemovals(S[1].address);
    expect(r.state).to.equal(S_REFERRED);
    expect(r.eligibleCount).to.equal(5); // S0, S4, S5, S6 and the paid validator S10
    const voters = [S[0], S[4], S[5], S[6], S[10]];
    await expect(board.connect(S[2]).voteRecoveryAssembly(S[1].address, true)).to.be.revertedWith("ValidatorsBoard: not an eligible validator"); // removed meanwhile
    await expect(board.connect(S[1]).voteRecoveryAssembly(S[1].address, true)).to.be.revertedWith("ValidatorsBoard: the subject of a case cannot vote");
    await expect(board.connect(S[12]).voteRecoveryAssembly(S[1].address, true)).to.be.revertedWith("ValidatorsBoard: not an eligible validator");
    for (const v of voters.slice(0, 3)) await board.connect(v).voteRecoveryAssembly(S[1].address, true);
    await expect(board.connect(S[0]).voteRecoveryAssembly(S[1].address, true)).to.be.revertedWith("ValidatorsBoard: already voted");
    expect((await reg.recoveryRemovals(S[1].address)).state).to.equal(S_REFERRED); // 3 of 5 is not two thirds
    await board.connect(voters[3]).voteRecoveryAssembly(S[1].address, true); // 4 = ceil(10/3)
    expect((await reg.recoveryRemovals(S[1].address)).state).to.equal(S_UPHELD);
  });

  it("when two thirds can no longer be reached the removal is cancelled and the validator reinstated", async () => {
    const { reg, board, S } = await referred();
    await board.connect(S[0]).voteRecoveryAssembly(S[1].address, false);
    expect((await reg.recoveryRemovals(S[1].address)).state).to.equal(S_REFERRED);
    await board.connect(S[4]).voteRecoveryAssembly(S[1].address, false); // 2 cancel > 5 - 4
    expect((await reg.recoveryRemovals(S[1].address)).state).to.equal(S_CANCELLED);
    expect((await reg.validators(S[1].address)).status).to.equal(ST_SELF_SUSPENDED); // VD-4: not Active until recordResume
    expect(await reg.getActiveOwners()).to.not.include(S[1].address);
    expect(await reg.permanentlyExited(S[1].address)).to.equal(false);
  });

  it("no decision within the new 7-day window cancels the removal; the other removals are unaffected", async () => {
    const { reg, board, S } = await referred();
    await board.connect(S[0]).voteRecoveryAssembly(S[1].address, true);
    await increaseTime(7 * DAY + 10);
    await expect(board.connect(S[4]).voteRecoveryAssembly(S[1].address, true)).to.be.revertedWith("ValidatorsBoard: decision window over");
    await reg.expireRecoveryRemoval(S[1].address);
    expect((await reg.validators(S[1].address)).status).to.equal(ST_SELF_SUSPENDED); // VD-4
    expect((await reg.validators(S[2].address)).status).to.equal(ST_REMOVED);
  });
});
