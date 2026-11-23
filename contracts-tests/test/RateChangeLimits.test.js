// v2.5 owner decision: limits on every block-reward rate change (BlockRewardDistributor.proposeRateChange / executeRateChange):
//   - the new rate is within +-10% RELATIVE of the current approved rate (symmetric, no absolute floor/ceiling);
//   - at least 180 days between two successful decisions, measured between EXECUTION blocks (lastRateChangeTime);
//   - no change at all in the first 180 days after genesis (ValidatorsRegistry.genesisTime());
//   - effect one week after the decision (RATE_CHANGE_DELAY / MIN_RATE_CHANGE_LEAD_SECONDS, unchanged).
// Real Registry (seeded by its genesis helper) and real Distributor; the Board is the MockBoard (authority set by hand) because the real
// board rotates monthly and that is irrelevant to the rate rules. The genesis-freeze re-check at EXECUTION, which cannot be reached with a
// real Registry (a proposal cannot even be created inside the freeze), is in RateChangeGenesisFreeze.test.js.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const HASH = ethers.id("evidence");
const rnd = () => ethers.Wallet.createRandom().address;
const GAS = { gasLimit: 5_000_000 }; // skip estimateGas: the boundary tests mine the call at an exact timestamp

const MSG = {
  freeze: "BlockRewardDistributor: no rate change in the first 6 months after genesis",
  spacing: "BlockRewardDistributor: at least 180 days are required between two rate changes",
  bound: "BlockRewardDistributor: the new rate may differ from the current approved rate by at most 10%",
  lead: "BlockRewardDistributor: activation time is closer than MIN_RATE_CHANGE_LEAD_SECONDS",
  delay: "BlockRewardDistributor: execution delay has not elapsed",
  notActive: "BlockRewardDistributor: only an active validator may propose a rate change",
};

async function fixture() {
  const S = await ethers.getSigners();
  const t0 = await now();
  const founders = S.slice(0, 5);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, rnd(), founders.slice(1).map((s) => s.address), t0]);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("2000"));
  const board = await setCodeOf("MockBoard", ADDR.VALIDATORS_BOARD);
  for (const x of S.slice(0, 3)) await board.setAuth(x.address, true); // three board members: S0, S1, S2
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const x of founders.slice(1)) {
    await reg.connect(x).setOperator(rnd());
    await reg.connect(verifier).recordActivation(x.address, HASH); // five active validators: two thirds = 4 votes
  }
  return { S, reg, dist, board, t0, genesis: await reg.genesisTime() };
}

/// 181 days after genesis: the freeze is over and no rate change has happened yet (current approved rate = 2 Suren). It is NOT a second fixture:
/// two fixtures in one file would leave the first one's leftovers under the second one's snapshot.
async function open(f) {
  await increaseTime(181 * DAY);
  return f;
}

/// Proposes `rate` (activation 30 days from now unless given). The estimated start block grows with the proposal count so that
/// successive entries keep the strictly-ascending, non-overlapping tolerance windows the contract requires.
async function propose(f, rate, o = {}) {
  const t = await now();
  const bn = await ethers.provider.getBlockNumber();
  const k = Number(await f.dist.rateProposalCount()) + 1;
  const act = o.act ?? t + 30 * DAY;
  const sb = o.sb ?? bn + 1_000_000 * k;
  return f.dist.connect(f.S[0]).proposeRateChange(act, sb, rate, o.gas ?? {});
}
async function proposeOk(f, rate, o = {}) {
  await (await propose(f, rate, o)).wait();
  return f.dist.rateProposalCount();
}
/// 3 of 3 board members and 4 of 5 validators: both chambers complete, the 7-day delay starts.
async function approve(f, id) {
  for (const x of f.S.slice(0, 3)) await f.dist.connect(x).boardVoteRateChange(id);
  for (const x of f.S.slice(0, 4)) await f.dist.connect(x).validatorVoteRateChange(id);
}
async function execute(f, id, o = {}) {
  await increaseTime(7 * DAY);
  return f.dist.executeRateChange(id, o);
}
async function decide(f, rate, o = {}) {
  const id = await proposeOk(f, rate, o);
  await approve(f, id);
  await (await execute(f, id)).wait();
  return id;
}
/// Mines the next transaction at exactly `ts`.
async function at(ts) {
  await hre.network.provider.send("evm_setNextBlockTimestamp", [Number(ts)]);
}

describe("Reward-rate limits - the first 6 months after genesis (no change at all)", () => {
  it("a proposal inside the first 180 days is refused, even with a perfectly valid rate; the boundary is exactly genesisTime + 180 days", async () => {
    const f = await loadFixture(fixture);
    const { dist, genesis } = f;
    expect(await dist.RATE_CHANGE_GENESIS_FREEZE()).to.equal(180 * DAY);
    expect(await dist.earliestRateChangeTime()).to.equal(genesis + BigInt(180 * DAY));
    await expect(propose(f, E("2"))).to.be.revertedWith(MSG.freeze); // day 0, no change of rate
    await increaseTime(100 * DAY);
    await expect(propose(f, E("2.2"))).to.be.revertedWith(MSG.freeze);
    await at(genesis + BigInt(180 * DAY) - 1n);
    await expect(propose(f, E("2.2"), { act: Number(genesis) + 210 * DAY, gas: GAS })).to.be.revertedWith(MSG.freeze);
    await at(genesis + BigInt(180 * DAY));
    await propose(f, E("2.2"), { act: Number(genesis) + 210 * DAY, gas: GAS }); // exactly at the end of the freeze: accepted
    expect(await dist.rateProposalCount()).to.equal(1);
  });
});

describe("Reward-rate limits - +-10% relative to the current approved rate", () => {
  it("from the initial 2 Suren: exactly +10% and exactly -10% are accepted; +10% + 1 wei and -10% - 1 wei are refused", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    expect(await dist.RATE_CHANGE_MAX_BPS()).to.equal(1000);
    expect(await dist.currentApprovedRatePerBlock()).to.equal(E("2"));
    await expect(propose(f, E("2.2") + 1n)).to.be.revertedWith(MSG.bound);
    await expect(propose(f, E("1.8") - 1n)).to.be.revertedWith(MSG.bound);
    await expect(propose(f, 0n)).to.be.revertedWith(MSG.bound);
    await expect(propose(f, E("4"))).to.be.revertedWith(MSG.bound);
    await expect(propose(f, E("1"))).to.be.revertedWith(MSG.bound);
    await propose(f, E("2.2")); // +10% exactly
    await propose(f, E("1.8")); // -10% exactly
    await propose(f, E("2")); // no change is inside the limits too
    await propose(f, E("2.2") - 1n);
    await propose(f, E("1.8") + 1n);
    expect(await dist.rateProposalCount()).to.equal(5);
  });

  it("the base is the LATEST approved rate, not the initial one: after +10%, a further +10% (21% above the initial) is allowed but +10% + 1 wei is not; decreases are symmetric", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    await decide(f, E("2.2"));
    expect(await dist.currentApprovedRatePerBlock()).to.equal(E("2.2")); // already counts although it is not active yet
    await increaseTime(180 * DAY);
    await expect(propose(f, E("2.42") + 1n)).to.be.revertedWith(MSG.bound);
    await expect(propose(f, E("1.98") - 1n)).to.be.revertedWith(MSG.bound);
    await propose(f, E("2.42")); // +10% of 2.2
    await propose(f, E("1.98")); // -10% of 2.2
    // the initial 2.0 is no longer the base: 2.0 is -9.09% of 2.2 (fine), 1.8 is -18% (refused)
    await propose(f, E("2"));
    await expect(propose(f, E("1.8"))).to.be.revertedWith(MSG.bound);
  });

  it("the comparison is exact integer arithmetic around an odd current rate: no rounding in the proposer's favour", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    const odd = E("2") + 1n; // 2.000000000000000001 (within +10% of 2.0)
    await decide(f, odd);
    await increaseTime(180 * DAY);
    // 110% of odd = 2.2e18 + 1.1 wei -> floor 2.2e18 + 1 ; 90% of odd = 1.8e18 + 0.9 wei -> ceiling 1.8e18 + 1
    await propose(f, E("2.2") + 1n);
    await expect(propose(f, E("2.2") + 2n)).to.be.revertedWith(MSG.bound);
    await propose(f, E("1.8") + 1n);
    await expect(propose(f, E("1.8"))).to.be.revertedWith(MSG.bound);
    expect(await dist.rateProposalCount()).to.equal(3);
  });

  it("only an active validator proposes; the existing time and lead rules are unchanged (activation at least 7 days ahead)", async () => {
    const f = await open(await loadFixture(fixture));
    const t = await now();
    await expect(f.dist.connect(f.S[9]).proposeRateChange(t + 30 * DAY, 2_000_000, E("2.1"))).to.be.revertedWith(MSG.notActive);
    await expect(propose(f, E("2.1"), { act: t + 6 * DAY })).to.be.revertedWith(MSG.lead);
  });
});

describe("Reward-rate limits - 180 days between two successful decisions (measured between EXECUTION blocks)", () => {
  it("lastRateChangeTime is the execution block; a new proposal is refused until exactly lastRateChangeTime + 180 days, and accepted from then on", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    expect(await dist.lastRateChangeTime()).to.equal(0);
    await decide(f, E("2.2"));
    const X = await dist.lastRateChangeTime();
    expect(X).to.equal(BigInt(await now()));
    expect(await dist.RATE_CHANGE_MIN_INTERVAL()).to.equal(180 * DAY);
    expect(await dist.earliestRateChangeTime()).to.equal(X + BigInt(180 * DAY));
    await expect(propose(f, E("2.3"))).to.be.revertedWith(MSG.spacing); // a day later
    const act = Number(X) + 210 * DAY; // the activation must be in the future of the block that mines the call
    await at(X + BigInt(180 * DAY) - 1n);
    await expect(propose(f, E("2.3"), { act, gas: GAS })).to.be.revertedWith(MSG.spacing);
    await at(X + BigInt(180 * DAY));
    await propose(f, E("2.3"), { act, gas: GAS });
    expect(await dist.rateProposalCount()).to.equal(2);
  });

  it("the spacing counts from EXECUTION, not from the proposal or the vote: a late execution pushes the next allowed date", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    const id = await proposeOk(f, E("2.2"), { act: (await now()) + 300 * DAY });
    await approve(f, id);
    await increaseTime(100 * DAY); // approved long ago, executed late
    await dist.executeRateChange(id);
    const X = await dist.lastRateChangeTime();
    expect(X).to.equal(BigInt(await now()));
    await increaseTime(179 * DAY); // 179 days after execution, but 279 after the vote
    await expect(propose(f, E("2.3"), { act: (await now()) + 400 * DAY })).to.be.revertedWith(MSG.spacing);
  });

  it("the full happy path: propose -> both chambers -> 7-day delay -> execute; the entry is appended, the effect is one week or more after the decision; then a second change 180 days later", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    const t = await now();
    const act = t + 30 * DAY;
    const id = await proposeOk(f, E("1.8"), { act });
    expect(await dist.rateChangeStatus(id)).to.deep.equal([1n, 0n]);
    await approve(f, id);
    expect(await dist.rateChangeStatus(id)).to.deep.equal([4n, 0n]); // approved, waiting for the 7-day delay
    await expect(dist.executeRateChange(id)).to.be.revertedWith(MSG.delay);
    await increaseTime(7 * DAY);
    expect(await dist.rateChangeStatus(id)).to.deep.equal([5n, 0n]);
    await expect(dist.executeRateChange(id)).to.emit(dist, "RateChangeExecuted");
    expect(await dist.rateChangeStatus(id)).to.deep.equal([3n, 0n]);
    expect(await dist.rewardRateChangeCount()).to.equal(1);
    const c = await dist.rewardRateChange(0);
    expect(c.ratePerBlock).to.equal(E("1.8"));
    expect(c.activationTime).to.equal(act);
    expect(c.activationTime).to.be.gte(BigInt(await now()) + BigInt(7 * DAY)); // never earlier than a week after the decision
    await increaseTime(180 * DAY);
    const id2 = await decide(f, E("1.62")); // -10% of 1.8
    expect(id2).to.equal(2);
    expect(await dist.rewardRateChangeCount()).to.equal(2);
    expect(await dist.currentApprovedRatePerBlock()).to.equal(E("1.62"));
  });

  it("several open proposals: whichever executes first makes the others unexecutable until 180 days later (status 6 / problem 7), then the later one executes - at exactly the boundary", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    const t = await now();
    const idA = await proposeOk(f, E("2.2"), { act: t + 30 * DAY });
    const idB = await proposeOk(f, E("2.1"), { act: t + 400 * DAY }); // both are valid when proposed
    await approve(f, idA);
    expect(await dist.rateChangeStatus(idB)).to.deep.equal([1n, 0n]);
    await increaseTime(7 * DAY);
    await dist.executeRateChange(idA);
    const X = await dist.lastRateChangeTime();
    // B (still in voting) can no longer lead to an executable change in its voting period: status 7 / problem 7
    expect(await dist.rateChangeStatus(idB)).to.deep.equal([7n, 7n]);
    await approve(f, idB); // the vote itself is still possible; the block is at execution
    expect(await dist.rateChangeStatus(idB)).to.deep.equal([6n, 7n]);
    await increaseTime(8 * DAY);
    await expect(dist.executeRateChange(idB)).to.be.revertedWith(MSG.spacing);
    expect(await dist.rewardRateChangeCount()).to.equal(1);
    await at(X + BigInt(180 * DAY) - 1n);
    await expect(dist.executeRateChange(idB, GAS)).to.be.revertedWith(MSG.spacing); // execution re-checks the spacing, to the second
    await at(X + BigInt(180 * DAY));
    await dist.executeRateChange(idB, GAS);
    expect(await dist.rewardRateChangeCount()).to.equal(2);
    expect(await dist.lastRateChangeTime()).to.equal(X + BigInt(180 * DAY));
    expect(await dist.currentApprovedRatePerBlock()).to.equal(E("2.1"));
  });

  it("execution re-checks the +-10% rule against the rate that is current THEN: a proposal valid when created is refused once another change moved the base (status 6 / problem 8)", async () => {
    const f = await open(await loadFixture(fixture));
    const { dist } = f;
    const t = await now();
    const idA = await proposeOk(f, E("2.2"), { act: t + 30 * DAY });
    const idB = await proposeOk(f, E("1.8"), { act: t + 400 * DAY }); // -10% of the initial 2.0: valid now
    await approve(f, idA);
    await approve(f, idB);
    await increaseTime(7 * DAY);
    await dist.executeRateChange(idA);
    const X = await dist.lastRateChangeTime();
    await at(X + BigInt(180 * DAY)); // spacing is satisfied; only the rate rule can still fail
    await hre.network.provider.send("evm_mine", []);
    expect(await dist.rateChangeStatus(idB)).to.deep.equal([6n, 8n]); // 1.8 is -18.2% of 2.2
    await expect(dist.executeRateChange(idB)).to.be.revertedWith(MSG.bound);
    expect(await dist.rewardRateChangeCount()).to.equal(1);
    expect(await dist.currentApprovedRatePerBlock()).to.equal(E("2.2"));
  });
});
