// RD-18 escape path: abortDistribution (oracle only, 3 days after open).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, mine, increaseTime, now, DAY, distribute } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const ORACLE = "0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6"; // SurAddresses.DISTRIBUTION_ORACLE
const TREASURY = "0x5555555555555555555555555555555555555555";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const rnd = () => ethers.Wallet.createRandom().address;
const sortAsc = (arr) => [...arr].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
const R = (from, to) => ({ fromBlock: from, toBlock: to });

/// Registry + seat NFT + Distributor (2000 Suren): a CONTRACT owner (first founder) and `nEoa` activated EOA founders.
async function fixture() {
  await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const c = await (await ethers.getContractFactory("MockSeatOwner")).deploy(ZERO, ZERO);
  const eoas = Array.from({ length: 4 }, () => ethers.Wallet.createRandom().address);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY, [await c.getAddress(), rnd(), eoas, t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [[await c.getAddress(), ...eoas]]);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("2000"));
  for (const a of [ADDR.VERIFIER, ORACLE, ADDR.VALIDATORS_BOARD]) await hre.network.provider.send("hardhat_setBalance", [a, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);
  const board = await ethers.getImpersonatedSigner(ADDR.VALIDATORS_BOARD);
  for (const a of eoas) {
    await hre.network.provider.send("hardhat_setBalance", [a, "0x56BC75E2D63100000"]);
    await reg.connect(await ethers.getImpersonatedSigner(a)).setOperator(rnd());
    await reg.connect(verifier).recordActivation(a, HASH);
  }
  await mine(60);
  const all = sortAsc([c.target, ...eoas]);
  return { reg, dist, c, eoas, oracle, board, all, S: await ethers.getSigners() };
}

/// blocks aligned with `all`: the contract owner mined 4 blocks, the four EOAs 2, 2, 1 and 1 (10 in all; zero-block entries are refused)
function blocksFor(f) { const rest = [2, 2, 1, 1]; return f.all.map((a) => (a === f.c.target ? 4 : rest.shift())); }
const REV = (m) => "BlockRewardDistributor: " + m;
const DAY3 = 3 * 24 * 3600;
async function ts(tx) { return (await ethers.provider.getBlock((await tx.wait()).blockNumber)).timestamp; }

describe("RD-18 escape path - abortDistribution (oracle only, 3 days after open)", () => {
  it("refused before 3 days (also 1 second before the boundary), by a non-oracle, with nothing open; allowed exactly at open + 3 days; twice refused", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, S } = f;
    const d = dist.connect(oracle);
    await expect(d.abortDistribution()).to.be.revertedWith(REV("no open distribution"));
    const t0 = await ts(await d.openDistribution(R(1, 10), 10, E("20"), E("1")));
    await expect(dist.connect(S[3]).abortDistribution()).to.be.revertedWith(REV("caller is not the distribution oracle"));
    await hre.network.provider.send("evm_setNextBlockTimestamp", [t0 + DAY3 - 1]);
    await expect(d.abortDistribution()).to.be.revertedWith(REV("too early to abort"));
    await hre.network.provider.send("evm_setNextBlockTimestamp", [t0 + DAY3]);
    await expect(d.abortDistribution()).to.emit(dist, "DistributionAborted").withArgs(1, 0, 0, E("21"));
    await expect(d.abortDistribution()).to.be.revertedWith(REV("no open distribution")); // twice
    expect(await dist.ABORT_DELAY()).to.equal(DAY3);
  });

  it("abort after partial pages: paid stays paid, paid + returned = reserved, nothing goes to treasury/foundation/burn, record and totals show only what was paid", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all, c } = f;
    const d = dist.connect(oracle);
    const blocks = blocksFor(f);
    const dBefore = await ethers.provider.getBalance(dist.target);
    const [tB, fB, zB] = await Promise.all([ethers.provider.getBalance(TREASURY), ethers.provider.getBalance(FOUNDATION), ethers.provider.getBalance(ZERO)]);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    const ci = all.indexOf(c.target);
    const upto = Math.max(ci + 1, 2); // the first page includes the contract owner (deferred) and at least two payees
    await d.payPage(all.slice(0, upto), blocks.slice(0, upto));
    const paidBlocks = blocks.slice(0, upto).reduce((a, b) => a + b, 0);
    const owed = await dist.claimable(c.target);
    expect(owed).to.be.gt(0);
    await increaseTime(DAY3);
    const paidAmount = (E("1") + E("0.07")) * BigInt(paidBlocks); // 1 Suren of rewards + 0.07 of fees per block
    const returned = E("21") - paidAmount;
    const tx = await d.abortDistribution();
    await expect(tx).to.emit(dist, "DistributionAborted").withArgs(1, paidBlocks, paidAmount, returned);
    await expect(tx).to.not.emit(dist, "RewardsDistributed");
    await expect(tx).to.not.emit(dist, "FoundationFunded");
    await expect(tx).to.not.emit(dist, "FeesBurned");
    console.log("      [gas] abortDistribution: " + (await tx.wait()).gasUsed);
    // conservation: the EOAs of the page were paid, the contract owner is credited; treasury/foundation/burn untouched
    const paidDirect = paidAmount - owed;
    expect(await ethers.provider.getBalance(dist.target)).to.equal(dBefore - paidDirect);
    expect(await ethers.provider.getBalance(TREASURY)).to.equal(tB);
    expect(await ethers.provider.getBalance(FOUNDATION)).to.equal(fB);
    expect(await ethers.provider.getBalance(ZERO)).to.equal(zB);
    // reservation released: the returned amount is back in the distributable pool
    expect((await dist.openDistributionInfo()).isOpen).to.equal(false);
    expect(await dist.getDistributableBalance()).to.equal((await ethers.provider.getBalance(dist.target)) - owed);
    // record: only what was paid; flagged aborted; totals only what was paid
    expect(await dist.epochAborted(1)).to.equal(true);
    const e = await dist.getEpoch(1);
    expect([e.totalRewards, e.totalFees, e.treasuryAmount, e.totalBlocksMined]).to.deep.equal([E("1") * BigInt(paidBlocks), E("0.07") * BigInt(paidBlocks), 0n, BigInt(paidBlocks)]);
    expect(await dist.totalDistributedToValidators()).to.equal(paidAmount);
    expect(await dist.totalDistributedToTreasury()).to.equal(0);
    expect(await dist.totalDistributedToFoundation()).to.equal(0);
    expect(await dist.lastSettledBlock()).to.equal(10); // the range stays settled
    // the deferred amount survives and is claimable (also against a re-entry attempt)
    await c.setAttack(true, dist.target);
    await c.callClaim(dist.target);
    expect(await c.received()).to.equal(owed);
    expect(await c.reenterSucceeded()).to.equal(false);
  });

  it("abort with zero pages paid: everything is returned; membership fees reserved at open return to the pool too (not back to pending)", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle } = f;
    const d = dist.connect(oracle);
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATORS_REGISTRY, "0x56BC75E2D63100000"]);
    await dist.connect(await ethers.getImpersonatedSigner(ADDR.VALIDATORS_REGISTRY)).receiveMembershipFee({ value: E("5") });
    const bal = await ethers.provider.getBalance(dist.target);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    expect(await dist.pendingMembershipFees()).to.equal(0); // folded into the reservation
    expect((await dist.openDistributionInfo()).budgetLeft).to.equal(E("26"));
    await increaseTime(DAY3);
    await expect(d.abortDistribution()).to.emit(dist, "DistributionAborted").withArgs(1, 0, 0, E("26"));
    expect(await ethers.provider.getBalance(dist.target)).to.equal(bal); // nothing left the contract
    expect(await dist.getDistributableBalance()).to.equal(bal);
    expect(await dist.pendingMembershipFees()).to.equal(0);
    expect(await dist.totalDistributedToValidators()).to.equal(0);
  });

  it("a ROTATED oracle key can abort; the old key cannot", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, board, S } = f;
    await dist.connect(oracle).openDistribution(R(1, 10), 10, E("20"), E("1"));
    await increaseTime(DAY3);
    await dist.connect(board).setDistributionOracle(S[15].address);
    await expect(dist.connect(oracle).abortDistribution()).to.be.revertedWith(REV("caller is not the distribution oracle"));
    await dist.connect(S[15]).abortDistribution();
    expect((await dist.openDistributionInfo()).isOpen).to.equal(false);
  });

  it("no double payment: the aborted range cannot be reopened; after an abort a NORMAL distribution of the next range opens, pays and closes with its full amounts and the totals add up", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    const blocks = blocksFor(f);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await d.payPage(all.slice(0, 2), blocks.slice(0, 2));
    const paid1 = (E("1") + E("0.07")) * BigInt(blocks[0] + blocks[1]);
    await increaseTime(DAY3);
    await d.abortDistribution();
    await expect(d.openDistribution(R(1, 10), 10, E("20"), E("1"))).to.be.revertedWith(REV("range must start right after the last settled block"));
    await expect(d.openDistribution(R(5, 20), 10, E("20"), E("1"))).to.be.revertedWith(REV("range must start right after the last settled block"));
    await mine(20);
    const fB = await ethers.provider.getBalance(FOUNDATION);
    await distribute(dist, oracle, R(11, 20), all, blocks, E("20"), E("1"));
    expect(await dist.epochAborted(1)).to.equal(true);
    expect(await dist.epochAborted(2)).to.equal(false);
    const e2 = await dist.getEpoch(2);
    expect([e2.totalRewards, e2.totalFees, e2.totalBlocksMined, e2.validatorCount]).to.deep.equal([E("20"), E("1"), 10n, 5n]);
    expect((await ethers.provider.getBalance(FOUNDATION)) - fB).to.equal(E("3")); // the normal epoch pays the foundation its full 15%
    expect(await dist.totalDistributedToFoundation()).to.equal(E("3"));
    expect(await dist.totalDistributedToValidators()).to.equal(paid1 + E("10.7")); // aborted epoch's paid part + the closed epoch
    expect(await ethers.provider.getBalance(dist.target)).to.be.gte(await dist.totalClaimable());
  });

  it("a membership fee that arrives while a distribution is open stays pending through the abort and is folded into the next open; the invariant balance >= claimable + pending + reserved holds", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATORS_REGISTRY, "0x56BC75E2D63100000"]);
    await dist.connect(await ethers.getImpersonatedSigner(ADDR.VALIDATORS_REGISTRY)).receiveMembershipFee({ value: E("5") });
    await increaseTime(DAY3);
    await d.abortDistribution();
    expect(await dist.pendingMembershipFees()).to.equal(E("5"));
    const bal = await ethers.provider.getBalance(dist.target);
    expect(bal).to.be.gte((await dist.totalClaimable()) + (await dist.pendingMembershipFees()));
    expect(await dist.getDistributableBalance()).to.equal(bal - E("5"));
    await mine(20);
    await d.openDistribution(R(11, 20), 10, E("20"), E("1"));
    expect((await dist.openDistributionInfo()).budgetLeft).to.equal(E("26")); // 20 + 1 + the 5 folded in
    expect(await dist.pendingMembershipFees()).to.equal(0);
  });

  it("after an abort pages and close are refused; a zero-page abort leaves a clean record", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await increaseTime(DAY3);
    await d.abortDistribution();
    await expect(d.payPage([all[0]], [1])).to.be.revertedWith(REV("no open distribution"));
    await expect(d.closeDistribution()).to.be.revertedWith(REV("no open distribution"));
    const e = await dist.getEpoch(1);
    expect([e.totalRewards, e.totalFees, e.treasuryAmount, e.totalBlocksMined, e.validatorCount]).to.deep.equal([0n, 0n, 0n, 0n, 0n]);
    expect(e.timestamp).to.be.gt(0);
    expect(await dist.epochAborted(1)).to.equal(true);
    expect((await dist.epochBlockRanges(1)).toBlock).to.equal(10); // the settled range is still on record
  });

  it("KNOWN, accepted consequence: when all blocks are paged but close is never called, abort leaves the treasury, foundation and fee burn parts in the pool (the validators are fully paid)", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    const [tB, fB, zB] = await Promise.all([ethers.provider.getBalance(TREASURY), ethers.provider.getBalance(FOUNDATION), ethers.provider.getBalance(ZERO)]);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await d.payPage(all, blocksFor(f));
    await increaseTime(DAY3);
    await expect(d.abortDistribution()).to.emit(dist, "DistributionAborted").withArgs(1, 10, E("10.7"), E("10.3"));
    expect(await ethers.provider.getBalance(TREASURY)).to.equal(tB);
    expect(await ethers.provider.getBalance(FOUNDATION)).to.equal(fB);
    expect(await ethers.provider.getBalance(ZERO)).to.equal(zB);
  });
});
