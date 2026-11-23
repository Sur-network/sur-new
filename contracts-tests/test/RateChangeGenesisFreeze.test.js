// Reward-rate limits, the genesis reference: BlockRewardDistributor reads the genesis time from ValidatorsRegistry.genesisTime() (seeded by the
// Registry genesis helper; nothing new is seeded in the Distributor). This file uses a MockRateRegistry whose genesis time can be set by
// hand to cover the two cases a real Registry cannot produce:
//   - genesisTime never seeded (0): the rule FAILS CLOSED (no rate change), it does not read as "genesis was long ago";
//   - the freeze re-check at EXECUTION (a real Registry cannot get there: no proposal can even be created inside the freeze). The test
//     moves the mock's genesis time after the proposal was approved; it documents that execution does not rely on the proposal-time check.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const MSG_FREEZE = "BlockRewardDistributor: no rate change in the first 6 months after genesis";
const MAX = (1n << 256n) - 1n;

async function fixture() {
  const S = await ethers.getSigners();
  const reg = await setCodeOf("MockRateRegistry", ADDR.VALIDATORS_REGISTRY);
  const board = await setCodeOf("MockBoard", ADDR.VALIDATORS_BOARD);
  for (const x of S.slice(0, 3)) await board.setAuth(x.address, true);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("2000"));
  return { S, reg, dist };
}

async function propose(f, rate) {
  const t = await now();
  const bn = await ethers.provider.getBlockNumber();
  return f.dist.connect(f.S[0]).proposeRateChange(t + 30 * DAY, bn + 1_000_000, rate);
}

describe("Reward-rate limits - the genesis reference is the Registry's genesisTime", () => {
  it("genesisTime = 0 (never seeded): no rate change can be proposed (fails closed), and earliestRateChangeTime is unreachable", async () => {
    const f = await loadFixture(fixture);
    expect(await f.reg.genesisTime()).to.equal(0);
    await expect(propose(f, E("2.1"))).to.be.revertedWith(MSG_FREEZE);
    expect(await f.dist.earliestRateChangeTime()).to.equal(MAX);
    await f.reg.setGenesisTime((await now()) - 181 * DAY); // seeded long ago: the same proposal is fine
    await propose(f, E("2.1"));
    expect(await f.dist.rateProposalCount()).to.equal(1);
  });

  it("execution re-checks the freeze against the current genesis time (defence in depth): the proposal stays as it is, and executes once the freeze is over", async () => {
    const f = await loadFixture(fixture);
    const { dist, reg, S } = f;
    await reg.setGenesisTime((await now()) - 181 * DAY);
    await (await propose(f, E("2.1"))).wait();
    for (const x of S.slice(0, 3)) await dist.connect(x).boardVoteRateChange(1);
    await dist.connect(S[0]).validatorVoteRateChange(1); // the mock has one active validator: one vote is two thirds
    expect(await dist.rateChangeStatus(1)).to.deep.equal([4n, 0n]);
    await reg.setGenesisTime(await now()); // pretend the genesis time is only now
    await increaseTime(7 * DAY);
    expect(await dist.rateChangeStatus(1)).to.deep.equal([6n, 6n]);
    await expect(dist.executeRateChange(1)).to.be.revertedWith(MSG_FREEZE);
    expect(await dist.rewardRateChangeCount()).to.equal(0);
    expect(await dist.lastRateChangeTime()).to.equal(0);
    // activation (30 days after the proposal) must still be 7 days away: move the genesis back so only the freeze rule changes
    await reg.setGenesisTime((await now()) - 181 * DAY);
    await dist.executeRateChange(1);
    expect(await dist.rewardRateChangeCount()).to.equal(1);
  });
});
