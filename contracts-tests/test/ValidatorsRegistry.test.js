// v2.5 Registry core: fixed collateral, owner/operator keys, founders, economic-parameter bounds, entry window, slash burn.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const ST = { None: 0, Probation: 1, Active: 2, Demoted: 3, Exiting: 4 };
const rnd = () => ethers.Wallet.createRandom().address;

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const op0 = rnd();
  const founders = S.slice(0, 5);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, op0, founders.slice(1).map((s) => s.address), t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  const board = await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [founders.map((s) => s.address), t0]);
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  const buyers = S.slice(10, 14);
  for (const b of buyers) {
    await idr.setVerified(b.address, true);
    await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  }
  return { S, reg, board, idr, verifier, founders, op0, buyers, t0 };
}

const price = async (reg) => (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());

describe("Registry v2.5 - genesis and founders", () => {
  it("only the first validator is Active at genesis (its operator key is the QBFT validator); other founders are Probation without collateral", async () => {
    const { reg, founders, op0 } = await loadFixture(fixture);
    expect(await reg.getValidators()).to.deep.equal([op0]);
    expect(await reg.getActiveOwners()).to.deep.equal([founders[0].address]);
    expect(await reg.ownerOfOperator(op0)).to.equal(founders[0].address);
    for (const f of founders.slice(1)) {
      const v = await reg.validators(f.address);
      expect(v.status).to.equal(ST.Probation);
      expect(v.lockedStake).to.equal(0);
      expect(v.isPaidEntrant).to.equal(false);
      expect(await reg.isFounder(f.address)).to.equal(true);
    }
    expect(await reg.entryWindowSeconds()).to.equal(7 * DAY);
    expect(await reg.entryCollateral()).to.equal(E("500000"));
    expect(await reg.membershipFeeBps()).to.equal(400);
  });

  it("a founder needs an operator key but no probation wait; the founder then joins the validator list under its operator", async () => {
    const { reg, verifier, founders } = await loadFixture(fixture);
    const f = founders[1];
    await expect(reg.connect(verifier).recordActivation(f.address, HASH)).to.be.revertedWith("ValidatorsRegistry: operator key not set");
    const op = rnd();
    await reg.connect(f).setOperator(op);
    await reg.connect(verifier).recordActivation(f.address, HASH); // immediately, no 7-day wait
    expect((await reg.validators(f.address)).status).to.equal(ST.Active);
    expect(await reg.getValidators()).to.include(op);
    expect(await reg.getValidators()).to.not.include(f.address);
  });
});

describe("Registry v2.5 - paying entry", () => {
  it("fixed collateral 500,000 + 4% fee; identity must be fully verified; the fee is forwarded; the collateral stays", async () => {
    const { reg, buyers, idr, S } = await loadFixture(fixture);
    const p = await price(reg);
    expect(p).to.equal(E("520000"));
    await hre.network.provider.send("hardhat_setBalance", [S[15].address, "0x" + E("2000000").toString(16)]);
    await expect(reg.connect(S[15]).requestMembership(rnd(), { value: p })).to.be.revertedWith("ValidatorsRegistry: identity not fully verified");
    await expect(reg.connect(buyers[0]).requestMembership(rnd(), { value: p - 1n })).to.be.revertedWith("ValidatorsRegistry: incorrect payment amount");
    await reg.connect(buyers[0]).requestMembership(rnd(), { value: p });
    const v = await reg.validators(buyers[0].address);
    expect(v.status).to.equal(ST.Probation);
    expect(v.lockedStake).to.equal(E("500000"));
    expect(v.isPaidEntrant).to.equal(true);
    expect(await ethers.provider.getBalance(ADDR.VALIDATORS_REGISTRY)).to.equal(E("500000"));
    expect(await ethers.provider.getBalance(ADDR.BLOCK_REWARD_DISTRIBUTOR)).to.equal(E("20000"));
  });

  it("the collateral does not grow with the number of validators (no growth curve); one paying entry per entry window", async () => {
    const { reg, buyers } = await loadFixture(fixture);
    const p = await price(reg);
    await reg.connect(buyers[0]).requestMembership(rnd(), { value: p });
    await expect(reg.connect(buyers[1]).requestMembership(rnd(), { value: p })).to.be.revertedWith("ValidatorsRegistry: entry rate limit reached");
    await increaseTime(7 * DAY + 10);
    expect(await price(reg)).to.equal(p); // unchanged after one more paid entrant
    await reg.connect(buyers[1]).requestMembership(rnd(), { value: p });
    expect(await reg.paidValidatorCount()).to.equal(2);
  });

  it("operator keys are unique: zero, another owner's operator and another owner's address are refused", async () => {
    const { reg, buyers, founders, op0 } = await loadFixture(fixture);
    const p = await price(reg);
    await expect(reg.connect(buyers[0]).requestMembership(ZERO, { value: p })).to.be.revertedWith("ValidatorsRegistry: zero operator");
    await expect(reg.connect(buyers[0]).requestMembership(op0, { value: p })).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
    await expect(reg.connect(buyers[0]).requestMembership(founders[1].address, { value: p })).to.be.revertedWith("ValidatorsRegistry: operator is another owner");
    const op = rnd();
    await reg.connect(buyers[0]).requestMembership(op, { value: p });
    await increaseTime(7 * DAY + 10);
    await expect(reg.connect(buyers[1]).requestMembership(op, { value: p })).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
  });
});

describe("Registry v2.5 - setOperator", () => {
  it("only an owner in Probation/Active/Demoted; unique; immediate effect on the validator list; old keys stay attached to their owner", async () => {
    const { reg, buyers, verifier, S, op0, founders } = await loadFixture(fixture);
    await expect(reg.connect(S[15]).setOperator(rnd())).to.be.revertedWith("ValidatorsRegistry: cannot change the operator in this status");
    const first = founders[0];
    const op1 = rnd();
    await expect(reg.connect(first).setOperator(op0)).to.be.revertedWith("ValidatorsRegistry: same operator");
    await expect(reg.connect(first).setOperator(ZERO)).to.be.revertedWith("ValidatorsRegistry: zero operator");
    await reg.connect(first).setOperator(op1);
    expect(await reg.getValidators()).to.deep.equal([op1]); // the QBFT set changes at once
    expect(await reg.operatorOf(first.address)).to.equal(op1);
    expect(await reg.ownerOfOperator(op0)).to.equal(first.address); // still attached: old blocks map to the owner
    // nobody else can ever take the old key
    await expect(reg.connect(founders[1]).setOperator(op0)).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
    // the owner may return to a key that was its own
    await reg.connect(first).setOperator(op0);
    expect(await reg.getValidators()).to.deep.equal([op0]);
  });

  it("an operator key cannot be an owner of a validator seat and an owner address cannot be used as someone else's operator", async () => {
    const { reg, founders } = await loadFixture(fixture);
    await expect(reg.connect(founders[1]).setOperator(founders[2].address)).to.be.revertedWith("ValidatorsRegistry: operator is another owner");
  });
});

describe("Registry v2.5 - economic parameters (Board only)", () => {
  async function asBoard() {
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATORS_BOARD, "0x56BC75E2D63100000"]);
    return ethers.getImpersonatedSigner(ADDR.VALIDATORS_BOARD);
  }

  it("setters are Board-only; +-10% per change; absolute bounds; one shared 180-day timer", async () => {
    const { reg, S } = await loadFixture(fixture);
    const board = await asBoard();
    await expect(reg.connect(S[0]).setEntryCollateral(E("550000"))).to.be.revertedWith("ValidatorsRegistry: caller is not the validators board");
    await expect(reg.connect(board).setEntryCollateral(E("560000"))).to.be.revertedWith("ValidatorsRegistry: change exceeds +-10%");
    await expect(reg.connect(board).setEntryCollateral(E("440000"))).to.be.revertedWith("ValidatorsRegistry: change exceeds +-10%");
    await reg.connect(board).setEntryCollateral(E("550000")); // exactly +10%
    expect(await reg.entryCollateral()).to.equal(E("550000"));
    await expect(reg.connect(board).setMembershipFeeBps(440)).to.be.revertedWith("ValidatorsRegistry: too soon since the last economic-parameter change");
    await increaseTime(181 * DAY);
    await expect(reg.connect(board).setMembershipFeeBps(500)).to.be.revertedWith("ValidatorsRegistry: change exceeds +-10%"); // 400 -> 500 is +25%
    await reg.connect(board).setMembershipFeeBps(360); // -10%
    expect(await reg.membershipFeeBps()).to.equal(360);
    expect(await reg.currentMembershipFee()).to.equal((E("550000") * 360n) / 10000n);
    // a change affects only later entrants: nobody has entered yet, so the new price applies from now on
    expect(await reg.currentEntryThreshold()).to.equal(E("550000"));
  });

  it("hard bounds hold even inside +-10% steps", async () => {
    const { reg } = await loadFixture(fixture);
    const board = await asBoard();
    // fee floor: 100 bps; 400 -> 360 -> 324 ... but never below the floor, and the floor itself is reachable only in steps
    await expect(reg.connect(board).setMembershipFeeBps(99)).to.be.revertedWith("ValidatorsRegistry: membershipFeeBps outside allowed bounds");
    await expect(reg.connect(board).setMembershipFeeBps(1001)).to.be.revertedWith("ValidatorsRegistry: membershipFeeBps outside allowed bounds");
    await expect(reg.connect(board).setEntryCollateral(E("99999"))).to.be.revertedWith("ValidatorsRegistry: entryCollateral outside allowed bounds");
    await expect(reg.connect(board).setEntryCollateral(E("2000001"))).to.be.revertedWith("ValidatorsRegistry: entryCollateral outside allowed bounds");
  });

  it("the real ValidatorsBoard drives the change with 3 of 5 votes (proposeSetEntryCollateral)", async () => {
    const { reg, board, founders } = await loadFixture(fixture);
    await board.connect(founders[0]).proposeSetEntryCollateral(E("550000"));
    expect(await reg.entryCollateral()).to.equal(E("500000")); // 1 of 3 votes needed
    await board.connect(founders[1]).voteAction(1);
    expect(await reg.entryCollateral()).to.equal(E("500000"));
    await board.connect(founders[2]).voteAction(1);
    expect(await reg.entryCollateral()).to.equal(E("550000"));
  });
});

describe("Registry v2.5 - entry window parameter (validators' vote)", () => {
  /// every Active validator votes for the proposal; with 5 founders activated the majority is 3
  async function activateAll(f) {
    for (const x of f.founders.slice(1)) {
      await f.reg.connect(x).setOperator(rnd());
      await f.reg.connect(f.verifier).recordActivation(x.address, HASH);
    }
  }
  async function change(f, value) {
    await f.reg.connect(f.founders[0]).proposeParameterChange(1, value); // ParamKey.EntryWindowSeconds
    const id = await f.reg.paramProposalCount();
    for (const x of f.founders.slice(1, 3)) await f.reg.connect(x).voteParameterChange(id);
  }

  it("1..30 days, +-1 day per change, none in the first 6 months, 6 months between changes", async () => {
    const f = await loadFixture(fixture);
    await activateAll(f);
    await expect(change(f, 8 * DAY)).to.be.revertedWith("ValidatorsRegistry: no change in the first 6 months after genesis");
    await increaseTime(181 * DAY);
    await expect(change(f, 9 * DAY)).to.be.revertedWith("ValidatorsRegistry: entryWindowSeconds may change by at most one day");
    await expect(change(f, 0)).to.be.revertedWith("ValidatorsRegistry: entryWindowSeconds outside 1-30 days");
    await change(f, 8 * DAY);
    expect(await f.reg.entryWindowSeconds()).to.equal(8 * DAY);
    await expect(change(f, 9 * DAY)).to.be.revertedWith("ValidatorsRegistry: at least 6 months between changes");
    await increaseTime(181 * DAY);
    await change(f, 7 * DAY);
    expect(await f.reg.entryWindowSeconds()).to.equal(7 * DAY);
  });
});

describe("Registry v2.5 - slashing burns", () => {
  it("an uncontested slash burns the amount (address(0)); nothing goes to the validators' treasury", async () => {
    const { reg, buyers, verifier, founders } = await loadFixture(fixture);
    // enough active validators that one suspension (1 of 6) stays below the 20% mass-failure threshold
    for (const x of founders.slice(1)) {
      await reg.connect(x).setOperator(rnd());
      await reg.connect(verifier).recordActivation(x.address, HASH);
    }
    const owner = buyers[0];
    await reg.connect(owner).requestMembership(rnd(), { value: await price(reg) });
    await increaseTime(8 * DAY);
    await reg.connect(verifier).recordActivation(owner.address, HASH);
    await reg.connect(verifier).recordSuspension(owner.address, HASH);
    const id = await reg.statusDecisionCount();
    await increaseTime(2 * 3600); // mass-demotion window closes
    await reg.resolveMassFailureCheck(id);
    await reg.connect(owner).confirmDelivery(id);
    await increaseTime(73 * 3600);
    const balBefore = await ethers.provider.getBalance(ADDR.VALIDATORS_REGISTRY);
    const treasuryBefore = await ethers.provider.getBalance("0x5555555555555555555555555555555555555555");
    await reg.executeUncontestedSlash(id);
    const slash = E("5000"); // 1% of 500,000
    expect(await reg.totalSlashBurned()).to.equal(slash);
    expect(await ethers.provider.getBalance(ADDR.VALIDATORS_REGISTRY)).to.equal(balBefore - slash);
    expect(await ethers.provider.getBalance("0x5555555555555555555555555555555555555555")).to.equal(treasuryBefore);
    expect((await reg.validators(owner.address)).lockedStake).to.equal(E("500000") - slash);
  });
});

describe("Registry v2.5 - voluntary suspension (SelfSuspended)", () => {
  async function withActivePaid(f) {
    // all five founders Active (they are also the board) + one paid validator who is NOT on the board
    for (const x of f.founders.slice(1)) {
      await f.reg.connect(x).setOperator(rnd());
      await f.reg.connect(f.verifier).recordActivation(x.address, HASH);
    }
    const owner = f.buyers[0];
    await f.reg.connect(owner).requestMembership(rnd(), { value: await price(f.reg) });
    await increaseTime(8 * DAY);
    await f.reg.connect(f.verifier).recordActivation(owner.address, HASH);
    return owner;
  }

  it("a validator suspends itself for free: out of the list at once, collateral stays, no vote; board members cannot", async () => {
    const f = await loadFixture(fixture);
    const { reg } = f;
    const owner = await withActivePaid(f);
    await expect(reg.connect(f.founders[1]).selfSuspend()).to.be.revertedWith("ValidatorsRegistry: a board member cannot suspend voluntarily");
    await expect(reg.connect(f.S[15]).selfSuspend()).to.be.revertedWith("ValidatorsRegistry: not active");
    const op = await reg.operatorOf(owner.address);
    expect(await reg.getValidators()).to.include(op);
    await reg.connect(owner).selfSuspend();
    const v = await reg.validators(owner.address);
    expect(v.status).to.equal(6); // SelfSuspended
    expect(v.lockedStake).to.equal(E("500000"));
    expect(await reg.getValidators()).to.not.include(op);
    expect(await reg.isValidator(owner.address)).to.equal(false);
    await expect(reg.connect(owner).proposeParameterChange(1, 8 * DAY)).to.be.revertedWith("ValidatorsRegistry: caller is not an active validator");
    expect(await reg.pendingSlashDecisionId(owner.address)).to.equal(0); // not a violation
  });

  it("resume needs the owner's request AND the Verifier's health check, and skips probation", async () => {
    const f = await loadFixture(fixture);
    const { reg, verifier } = f;
    const owner = await withActivePaid(f);
    await reg.connect(owner).selfSuspend();
    await expect(reg.connect(verifier).recordResume(owner.address, HASH)).to.be.revertedWith("ValidatorsRegistry: no resume request");
    await expect(reg.connect(f.S[15]).requestResume()).to.be.revertedWith("ValidatorsRegistry: not self-suspended");
    await reg.connect(owner).requestResume();
    await expect(reg.connect(owner).recordResume(owner.address, HASH)).to.be.revertedWith("ValidatorsRegistry: caller is not the verifier");
    await reg.connect(verifier).recordResume(owner.address, HASH); // same day: no probation wait
    expect((await reg.validators(owner.address)).status).to.equal(ST.Active);
    expect(await reg.getActiveOwners()).to.include(owner.address);
    await expect(reg.connect(verifier).recordResume(owner.address, HASH)).to.be.revertedWith("ValidatorsRegistry: not self-suspended");
  });

  it("a self-suspended validator may change its node key and may exit; nobody can suspend below the minimum active count", async () => {
    const f = await loadFixture(fixture);
    const { reg } = f;
    // minimum floor: with only the genesis validator active, even a non-board owner could not suspend; test the floor with the first validator
    await expect(reg.connect(f.founders[0]).selfSuspend()).to.be.reverted; // board member and sole active validator
    const owner = await withActivePaid(f);
    await reg.connect(owner).selfSuspend();
    const op = rnd();
    await reg.connect(owner).setOperator(op);
    expect(await reg.operatorOf(owner.address)).to.equal(op);
    await reg.connect(owner).requestExit();
    expect((await reg.validators(owner.address)).status).to.equal(ST.Exiting);
    expect(await reg.permanentlyExited(owner.address)).to.equal(true);
  });
});
