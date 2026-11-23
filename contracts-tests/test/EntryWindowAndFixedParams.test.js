// Owner decisions (round 2): (a) maxEntriesPerWindow, probationPeriod and slashBps are FIXED (no vote can change them);
// (b) the entry window is counted at ACTIVATION of a paying entrant, not at the membership request; lottery winners and founders are exempt.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY, agr } = require("./helpers");

const E = ethers.parseEther;
const HASH = ethers.id("evidence");
const AGR = ethers.id("signed validators agreement v1");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const rnd = () => ethers.Wallet.createRandom().address;
const ST = { None: 0, Probation: 1, Active: 2 };
const KEY = { MaxEntriesPerWindow: 0, EntryWindowSeconds: 1, ProbationPeriod: 2, RecoveryPeriod: 3, SlashBps: 4, ExitCooldown: 5 };
const FIXED = "ValidatorsRegistry: this parameter is fixed and cannot be changed";
const USED = "ValidatorsRegistry: entry window used - only one new paid validator per window";
const GAS = { gasLimit: 5_000_000 };

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const founders = S.slice(0, 5);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, rnd(), founders.slice(1).map((s) => s.address), t0]);
  const nft = await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [founders.map((s) => s.address), t0]);
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  const buyers = S.slice(10, 15);
  for (const b of buyers) {
    await idr.setVerified(b.address, true);
    await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  }
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  return { S, reg, nft, idr, verifier, founders, buyers, price, t0 };
}

async function activateFounders(f, from = 1) {
  for (const x of f.founders.slice(from)) {
    await f.reg.connect(x).setOperator(rnd());
    await f.reg.connect(f.verifier).recordActivation(x.address, HASH);
  }
}
async function at(ts) { await hre.network.provider.send("evm_setNextBlockTimestamp", [Number(ts)]); }

describe("Fixed parameters: maxEntriesPerWindow, probationPeriod, slashBps", () => {
  it("they are constants with the values decided (1 entry per window, 1 week, 1%); the getters keep their names", async () => {
    const { reg } = await loadFixture(fixture);
    expect(await reg.maxEntriesPerWindow()).to.equal(1);
    expect(await reg.probationPeriod()).to.equal(7 * DAY);
    expect(await reg.slashBps()).to.equal(100);
  });

  it("the parameter-change path refuses those three keys at proposal time (enum order unchanged: 0, 2 and 4 are the fixed ones); the other keys still work", async () => {
    const f = await loadFixture(fixture);
    await activateFounders(f);
    const { reg, founders } = f;
    for (const [k, v] of [[KEY.MaxEntriesPerWindow, 3], [KEY.ProbationPeriod, 3 * DAY], [KEY.SlashBps, 5000], [KEY.MaxEntriesPerWindow, 1], [KEY.SlashBps, 100]]) {
      await expect(reg.connect(founders[0]).proposeParameterChange(k, v)).to.be.revertedWith(FIXED);
    }
    expect(await reg.paramProposalCount()).to.equal(0);
    // the other keys are still governed by the validators' vote: recoveryPeriod (3) and exitCooldown (5)
    await reg.connect(founders[0]).proposeParameterChange(KEY.RecoveryPeriod, 3 * DAY);
    for (const x of founders.slice(1, 3)) await reg.connect(x).voteParameterChange(1);
    expect(await reg.recoveryPeriod()).to.equal(3 * DAY);
    await reg.connect(founders[0]).proposeParameterChange(KEY.ExitCooldown, 10 * DAY);
    for (const x of founders.slice(1, 3)) await reg.connect(x).voteParameterChange(2);
    expect(await reg.exitCooldown()).to.equal(10 * DAY);
    expect(await reg.slashBps()).to.equal(100);
  });
});

describe("Entry window counted at ACTIVATION (audit A2)", () => {
  it("any number of paying entrants may REQUEST at once; the Verifier activates one per window and is refused for the others until the window has passed", async () => {
    const f = await loadFixture(fixture);
    const { reg, verifier, buyers, price } = f;
    for (const b of buyers.slice(0, 3)) await reg.connect(b).requestMembership(rnd(), agr(), { value: price }); // no "entry rate limit" any more
    expect(await reg.paidValidatorCount()).to.equal(3);
    for (const b of buyers.slice(0, 3)) expect((await reg.validators(b.address)).status).to.equal(ST.Probation);
    const startedAt = (await reg.validators(buyers[1].address)).periodStartedAt;
    expect(await reg.lastPaidActivationAt()).to.equal(0);
    expect(await reg.nextPaidActivationAllowedAt()).to.equal(0);

    await increaseTime(7 * DAY + 10); // probation over for all three
    await reg.connect(verifier).recordActivation(buyers[0].address, HASH);
    const X = await reg.lastPaidActivationAt();
    expect(X).to.equal(BigInt(await now()));
    expect(await reg.nextPaidActivationAllowedAt()).to.equal(X + BigInt(7 * DAY));
    await expect(reg.connect(verifier).recordActivation(buyers[1].address, HASH)).to.be.revertedWith(USED);
    // the refused candidate loses nothing: still Probation with its original probation start, its collateral stays
    const v1 = await reg.validators(buyers[1].address);
    expect(v1.status).to.equal(ST.Probation);
    expect(v1.periodStartedAt).to.equal(startedAt);
    expect(v1.lockedStake).to.equal(E("500000"));

    await at(X + BigInt(7 * DAY) - 1n);
    await expect(reg.connect(verifier).recordActivation(buyers[1].address, HASH, GAS)).to.be.revertedWith(USED); // one second early
    await at(X + BigInt(7 * DAY));
    await reg.connect(verifier).recordActivation(buyers[1].address, HASH, GAS); // exactly one window later
    expect((await reg.validators(buyers[1].address)).status).to.equal(ST.Active);
    await expect(reg.connect(verifier).recordActivation(buyers[2].address, HASH)).to.be.revertedWith(USED);
    await increaseTime(7 * DAY);
    await reg.connect(verifier).recordActivation(buyers[2].address, HASH);
    expect(await reg.getActiveOwners()).to.include.members([buyers[0].address, buyers[1].address, buyers[2].address]);
  });

  it("founders and lottery winners are exempt: they neither wait for the window nor use it", async () => {
    const f = await loadFixture(fixture);
    const { reg, verifier, buyers, founders, price } = f;
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATOR_LOTTERY, "0x56BC75E2D63100000"]);
    const lottery = await ethers.getImpersonatedSigner(ADDR.VALIDATOR_LOTTERY);
    const winner = buyers[4];
    await reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: price });
    await reg.connect(buyers[1]).requestMembership(rnd(), agr(), { value: price });
    await reg.connect(lottery).enterAsLotteryWinner(winner.address);
    await reg.connect(winner).setOperator(rnd());
    await increaseTime(7 * DAY + 10);

    await reg.connect(verifier).recordActivation(buyers[0].address, HASH); // the paid entrant uses the window
    const X = await reg.lastPaidActivationAt();
    await expect(reg.connect(verifier).recordActivation(buyers[1].address, HASH)).to.be.revertedWith(USED);
    await reg.connect(verifier).recordActivation(winner.address, HASH); // lottery winner: inside the used window, no problem
    expect((await reg.validators(winner.address)).status).to.equal(ST.Active);
    expect(await reg.lastPaidActivationAt()).to.equal(X); // and it did not move the window
    await activateFounders(f, 1); // all four other founders, also inside the used window
    for (const x of founders) expect((await reg.validators(x.address)).status).to.equal(ST.Active);
    expect(await reg.lastPaidActivationAt()).to.equal(X);
    await expect(reg.connect(verifier).recordActivation(buyers[1].address, HASH)).to.be.revertedWith(USED); // still the paid entrant's turn later
    await increaseTime(7 * DAY);
    await reg.connect(verifier).recordActivation(buyers[1].address, HASH);
  });

  it("a Probation seat that is SOLD stays a paying entrant: its new owner's activation uses the window", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, verifier, buyers, price } = f;
    await reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: price }); // seat 6
    await reg.connect(buyers[1]).requestMembership(rnd(), agr(), { value: price }); // seat 7
    await reg.connect(buyers[3]).acceptSeatAgreement(7, AGR);
    await nft.connect(buyers[1]).transferFrom(buyers[1].address, buyers[3].address, 7); // sold while in Probation
    expect((await reg.validators(buyers[3].address)).isPaidEntrant).to.equal(true);
    await increaseTime(7 * DAY + 10);
    await reg.connect(verifier).recordActivation(buyers[0].address, HASH);
    await expect(reg.connect(verifier).recordActivation(buyers[3].address, HASH)).to.be.revertedWith(USED);
    await increaseTime(7 * DAY);
    await reg.connect(verifier).recordActivation(buyers[3].address, HASH);
  });

  it("the window length is the vote-governed entryWindowSeconds (1..30 days): after a change to 8 days the next paid activation waits 8 days", async () => {
    const f = await loadFixture(fixture);
    const { reg, verifier, buyers, founders, price } = f;
    await activateFounders(f);
    await increaseTime(181 * DAY); // 6 months pass: the window length may now be changed
    await reg.connect(founders[0]).proposeParameterChange(KEY.EntryWindowSeconds, 8 * DAY);
    for (const x of founders.slice(1, 3)) await reg.connect(x).voteParameterChange(1);
    expect(await reg.entryWindowSeconds()).to.equal(8 * DAY);
    await reg.connect(buyers[0]).requestMembership(rnd(), agr(), { value: price });
    await reg.connect(buyers[1]).requestMembership(rnd(), agr(), { value: price });
    await increaseTime(7 * DAY + 10);
    await reg.connect(verifier).recordActivation(buyers[0].address, HASH);
    await increaseTime(7 * DAY + 10); // 7 days later: enough for the old window, not for 8 days
    await expect(reg.connect(verifier).recordActivation(buyers[1].address, HASH)).to.be.revertedWith(USED);
    await increaseTime(DAY);
    await reg.connect(verifier).recordActivation(buyers[1].address, HASH);
  });
});
