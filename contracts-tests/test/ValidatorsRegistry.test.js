// v2.5 Registry core: fixed collateral, owner/operator keys, founders, economic-parameter bounds, entry window, slash burn.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY, agr } = require("./helpers");

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
    await expect(reg.connect(S[15]).requestMembership(rnd(), agr(), { value: p })).to.be.revertedWith("ValidatorsRegistry: identity not fully verified");
    await expect(reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: p - 1n })).to.be.revertedWith("ValidatorsRegistry: incorrect payment amount");
    await reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: p });
    const v = await reg.validators(buyers[0].address);
    expect(v.status).to.equal(ST.Probation);
    expect(v.lockedStake).to.equal(E("500000"));
    expect(v.isPaidEntrant).to.equal(true);
    expect(await ethers.provider.getBalance(ADDR.VALIDATORS_REGISTRY)).to.equal(E("500000"));
    expect(await ethers.provider.getBalance(ADDR.BLOCK_REWARD_DISTRIBUTOR)).to.equal(E("20000"));
  });

  it("the collateral does not grow with the number of validators (no growth curve); requests are not rate-limited (the entry window is counted at activation, see EntryWindowAndFixedParams.test.js)", async () => {
    const { reg, buyers } = await loadFixture(fixture);
    const p = await price(reg);
    await reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: p });
    await reg.connect(buyers[1]).requestMembership(rnd(), agr(), { value: p }); // allowed at once: Probation until the Verifier activates it
    expect(await reg.paidValidatorCount()).to.equal(2);
    await increaseTime(7 * DAY + 10);
    expect(await price(reg)).to.equal(p); // unchanged after one more paid entrant
    await reg.connect(buyers[2]).requestMembership(rnd(), agr(), { value: p });
    expect(await reg.paidValidatorCount()).to.equal(3);
  });

  it("operator keys are unique: zero, another owner's operator and another owner's address are refused", async () => {
    const { reg, buyers, founders, op0 } = await loadFixture(fixture);
    const p = await price(reg);
    await expect(reg.connect(buyers[0]).requestMembership(ZERO, agr(), { value: p })).to.be.revertedWith("ValidatorsRegistry: zero operator");
    await expect(reg.connect(buyers[0]).requestMembership(op0, agr(), { value: p })).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
    await expect(reg.connect(buyers[0]).requestMembership(founders[1].address, agr(), { value: p })).to.be.revertedWith("ValidatorsRegistry: operator is another owner");
    const op = rnd();
    await reg.connect(buyers[0]).requestMembership(op, agr(), { value: p });
    await increaseTime(7 * DAY + 10);
    await expect(reg.connect(buyers[1]).requestMembership(op, agr(), { value: p })).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
  });
});

describe("Registry v2.5 - changing the node key", () => {
  it("setOperator is immediate only outside the consensus set; an Active validator must use the two-step path", async () => {
    const { reg, founders, S, verifier } = await loadFixture(fixture);
    await expect(reg.connect(S[15]).setOperator(rnd())).to.be.revertedWith("ValidatorsRegistry: cannot change the operator in this status");
    await expect(reg.connect(founders[0]).setOperator(rnd())).to.be.revertedWith("ValidatorsRegistry: an Active validator changes the node key in two steps (proposeOperator)");
    // a Probation founder: immediate, unique, may return to an own earlier key
    const f = founders[1];
    const a = rnd(), b = rnd();
    await expect(reg.connect(f).setOperator(ZERO)).to.be.revertedWith("ValidatorsRegistry: zero operator");
    await reg.connect(f).setOperator(a);
    await expect(reg.connect(f).setOperator(a)).to.be.revertedWith("ValidatorsRegistry: same operator");
    await reg.connect(f).setOperator(b);
    expect(await reg.operatorOf(f.address)).to.equal(b);
    expect(await reg.ownerOfOperator(a)).to.equal(f.address); // the old key stays attached forever
    await expect(reg.connect(founders[2]).setOperator(a)).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
    await reg.connect(f).setOperator(a); // own earlier key
    expect(await reg.operatorOf(f.address)).to.equal(a);
    await expect(reg.connect(founders[2]).setOperator(founders[3].address)).to.be.revertedWith("ValidatorsRegistry: operator is another owner");
  });

  it("two steps for an Active validator: propose reserves the key, nothing changes in consensus until the Verifier confirms", async () => {
    const { reg, founders, verifier, op0, S } = await loadFixture(fixture);
    const first = founders[0];
    const op1 = rnd();
    await expect(reg.connect(S[15]).proposeOperator(op1)).to.be.revertedWith("ValidatorsRegistry: only an Active validator proposes (others use setOperator)");
    await expect(reg.connect(first).proposeOperator(op0)).to.be.revertedWith("ValidatorsRegistry: same operator");
    await expect(reg.connect(first).proposeOperator(ZERO)).to.be.revertedWith("ValidatorsRegistry: zero operator");
    await reg.connect(first).proposeOperator(op1);
    expect(await reg.pendingOperator(first.address)).to.equal(op1);
    expect(await reg.getValidators()).to.deep.equal([op0]); // consensus unchanged: a dead node can never get in by proposing
    await expect(reg.connect(first).proposeOperator(rnd())).to.be.revertedWith("ValidatorsRegistry: a proposal is already open");
    // the reserved key cannot be taken by anyone else meanwhile
    await expect(reg.connect(founders[1]).setOperator(op1)).to.be.revertedWith("ValidatorsRegistry: operator reserved by another owner's pending change");
    // only the Verifier confirms, with evidence
    await expect(reg.connect(first).confirmOperatorReady(first.address, op1, HASH)).to.be.revertedWith("ValidatorsRegistry: caller is not the verifier");
    await expect(reg.connect(verifier).confirmOperatorReady(first.address, op1, ethers.ZeroHash)).to.be.revertedWith("ValidatorsRegistry: empty evidence hash");
    await reg.connect(verifier).confirmOperatorReady(first.address, op1, HASH);
    expect(await reg.getValidators()).to.deep.equal([op1]); // the switch happens in the Verifier's transaction
    expect(await reg.operatorOf(first.address)).to.equal(op1);
    expect(await reg.ownerOfOperator(op0)).to.equal(first.address); // old key stays attached (event history, F-4)
    expect(await reg.pendingOperator(first.address)).to.equal(ZERO);
    await expect(reg.connect(verifier).confirmOperatorReady(first.address, op1, HASH)).to.be.revertedWith("ValidatorsRegistry: no open proposal");
  });

  it("VD-13: confirmOperatorReady names the key; the owner cancelling and re-proposing another key between the check and the confirmation is refused", async () => {
    const { reg, founders, verifier, op0 } = await loadFixture(fixture);
    const first = founders[0];
    const checked = rnd(), swapped = rnd();
    await reg.connect(first).proposeOperator(checked);
    // the Verifier checked `checked`; before its transaction is mined the owner swaps the proposal
    await reg.connect(first).cancelOperatorChange();
    await reg.connect(first).proposeOperator(swapped);
    await expect(reg.connect(verifier).confirmOperatorReady(first.address, checked, HASH)).to.be.revertedWith("ValidatorsRegistry: operator differs from the open proposal");
    await expect(reg.connect(verifier).confirmOperatorReady(first.address, ZERO, HASH)).to.be.revertedWith("ValidatorsRegistry: operator differs from the open proposal");
    expect(await reg.getValidators()).to.deep.equal([op0]); // nothing was applied
    expect(await reg.pendingOperator(first.address)).to.equal(swapped);
    // the right key goes through
    await reg.connect(verifier).confirmOperatorReady(first.address, swapped, HASH);
    expect(await reg.getValidators()).to.deep.equal([swapped]);
  });

  it("the owner can cancel; a proposal lapses after 7 days and frees the key; confirm after expiry is refused", async () => {
    const { reg, founders, verifier } = await loadFixture(fixture);
    const first = founders[0];
    const op1 = rnd(), op2 = rnd();
    await expect(reg.connect(first).cancelOperatorChange()).to.be.revertedWith("ValidatorsRegistry: no open proposal");
    await reg.connect(first).proposeOperator(op1);
    await reg.connect(first).cancelOperatorChange();
    expect(await reg.pendingOperator(first.address)).to.equal(ZERO);
    await reg.connect(founders[1]).setOperator(op1); // reservation gone: another owner may use the key
    await reg.connect(first).proposeOperator(op2);
    await increaseTime(7 * DAY + 10);
    await expect(reg.connect(verifier).confirmOperatorReady(first.address, op2, HASH)).to.be.revertedWith("ValidatorsRegistry: proposal expired");
    await reg.connect(founders[2]).setOperator(op2); // an expired reservation does not block others
    await reg.connect(first).proposeOperator(rnd()); // a new proposal after expiry is allowed
  });

  it("a proposal for a key that belongs to another owner or to an owner address is refused", async () => {
    const { reg, founders } = await loadFixture(fixture);
    const first = founders[0];
    await reg.connect(founders[1]).setOperator(rnd());
    const taken = await reg.operatorOf(founders[1].address);
    await expect(reg.connect(first).proposeOperator(taken)).to.be.revertedWith("ValidatorsRegistry: operator belongs to another owner");
    await expect(reg.connect(first).proposeOperator(founders[2].address)).to.be.revertedWith("ValidatorsRegistry: operator is another owner");
  });

  it("the Verifier cannot apply a proposal once the owner is no longer Active", async () => {
    const f = await loadFixture(fixture);
    const { reg, founders, verifier } = f;
    // activate founders 1..3 so the first validator is not the only one; then the second validator proposes and gets suspended
    for (const x of founders.slice(1)) {
      await reg.connect(x).setOperator(rnd());
      await reg.connect(verifier).recordActivation(x.address, HASH);
    }
    const second = founders[1];
    const pendKey = rnd();
    await reg.connect(second).proposeOperator(pendKey);
    await reg.connect(verifier).recordSuspension(second.address, HASH);
    await expect(reg.connect(verifier).confirmOperatorReady(second.address, pendKey, HASH)).to.be.revertedWith("ValidatorsRegistry: owner is no longer Active");
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
    const { reg, board, founders, verifier } = await loadFixture(fixture);
    // board members must be Active to act: activate the first three founders (the first validator already is)
    for (const x of founders.slice(1, 3)) {
      await reg.connect(x).setOperator(rnd());
      await reg.connect(verifier).recordActivation(x.address, HASH);
    }
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
    await reg.connect(owner).requestMembership(rnd(), agr(), { value: await price(reg) });
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
    await f.reg.connect(owner).requestMembership(rnd(), agr(), { value: await price(f.reg) });
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

describe("Board authority needs more than a seat (founders in Probation)", () => {
  it("a founder still in Probation holds the seat but cannot propose or vote; syncBoard does not remove it; once Active it acts", async () => {
    const { reg, board, founders, verifier, S } = await loadFixture(fixture);
    // genesis: only founders[0] is Active; founders[1..4] are Probation but seated
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.hasBoardAuthority(founders[0].address)).to.equal(true);
    expect(await board.hasBoardAuthority(founders[1].address)).to.equal(false);
    await expect(board.connect(founders[1]).proposeSetEntryCollateral(E("550000"))).to.be.revertedWith("ValidatorsBoard: caller has no board authority");
    await board.connect(S[15]).syncBoard(); // anyone: must NOT remove the Probation founders
    expect(await board.getBoardSize()).to.equal(5);
    expect(await board.isBoardMember(founders[1].address)).to.equal(true);
    // activation gives the authority
    await reg.connect(founders[1]).setOperator(rnd());
    await reg.connect(verifier).recordActivation(founders[1].address, HASH);
    expect(await board.hasBoardAuthority(founders[1].address)).to.equal(true);
  });
});

describe("clearStaleVotes also covers a long voluntary suspension", () => {
  it("votes of a SelfSuspended validator are cleared after the delay (counted from the suspension)", async () => {
    const { reg, board, founders, verifier, buyers, idr } = await loadFixture(fixture);
    for (const x of founders.slice(1)) {
      await reg.connect(x).setOperator(rnd());
      await reg.connect(verifier).recordActivation(x.address, HASH);
    }
    const owner = buyers[0];
    await reg.connect(owner).requestMembership(rnd(), agr(), { value: await price(reg) });
    await increaseTime(8 * DAY);
    await reg.connect(verifier).recordActivation(owner.address, HASH);
    await reg.connect(owner).selfSuspend();
    await expect(board.clearStaleVotes(owner.address)).to.be.revertedWith("ValidatorsBoard: stale-vote delay not elapsed");
    await expect(board.clearStaleVotes(founders[0].address)).to.be.revertedWith("ValidatorsBoard: validator is not currently suspended");
    await increaseTime(31 * DAY);
    await board.clearStaleVotes(owner.address); // no votes were given, but the call is allowed and must not revert
  });
});
