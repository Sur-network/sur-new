// RD-18: paginated distribution (openDistribution / payPage / closeDistribution).
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

/// blocks aligned with `all`: the contract owner mined 4 blocks, the four EOAs 3, 2, 1 and 0 (10 in all)
function blocksFor(f) { const rest = [3, 2, 1, 0]; return f.all.map((a) => (a === f.c.target ? 4 : rest.shift())); }
const REV = (m) => "BlockRewardDistributor: " + m;

describe("RD-18 - paginated distribution", () => {
  it("open / pages / close: events, reservation, RewardsDistributed only at close, same money as one big page", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all, c } = f;
    const blocks = blocksFor(f); // 5 payees, 10 blocks
    const start = await Promise.all(all.map((a) => ethers.provider.getBalance(a)));
    const dBal = await ethers.provider.getBalance(dist.target);
    const d = dist.connect(oracle);
    const open = d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await expect(open).to.emit(dist, "EpochRangeSettled").withArgs(1, 1, 10);
    await expect(open).to.emit(dist, "DistributionOpened").withArgs(1, 1, 10, 10, E("20"), E("0.7"));
    await expect(open).to.not.emit(dist, "RewardsDistributed");
    expect(await dist.lastSettledBlock()).to.equal(10); // moves at OPEN
    expect((await dist.epochBlockRanges(1)).toBlock).to.equal(10);
    let info = await dist.openDistributionInfo();
    expect(info.isOpen).to.equal(true);
    expect(info.budgetLeft).to.equal(E("20") + E("1")); // approved rewards + the whole fee pool are reserved
    expect(await dist.getDistributableBalance()).to.equal(dBal - E("21"));

    const p1 = d.payPage(all.slice(0, 2), blocks.slice(0, 2));
    await expect(p1).to.emit(dist, "DistributionPage").withArgs(1, 2, BigInt(blocks[0] + blocks[1]), BigInt(blocks[0] + blocks[1]));
    await expect(p1).to.not.emit(dist, "RewardsDistributed");
    await d.payPage(all.slice(2, 5), blocks.slice(2, 5));
    info = await dist.openDistributionInfo();
    expect(info.paidBlocks).to.equal(10);
    expect(info.lastPayee).to.equal(all[4]);
    const close = d.closeDistribution();
    await expect(close).to.emit(dist, "RewardsDistributed").withArgs(1, E("20"), E("1"), anyValue, 10, 4);
    await close;
    info = await dist.openDistributionInfo();
    expect(info.isOpen).to.equal(false);
    expect(info.budgetLeft).to.equal(0);
    // every payee got blocks/10 of 10 Suren of rewards + 0.07 per block of fees
    const want = blocks.map((b) => (E("1") * BigInt(b)) + (E("0.07") * BigInt(b)));
    for (let i = 0; i < all.length; i++) {
      if (all[i] === c.target) { expect(await dist.claimable(all[i])).to.equal(want[i]); continue; }
      expect((await ethers.provider.getBalance(all[i])) - start[i]).to.equal(want[i]);
    }
    expect((await dist.getEpoch(1)).validatorCount).to.equal(4);
    // nothing but the debt is left of the reserved money: the contract keeps its old balance minus what was paid out
    expect(await dist.getDistributableBalance()).to.be.gt(0);
  });

  it("page size does not change who gets what (one page of five vs five pages of one)", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const blocks = blocksFor(f);
    const snap = await hre.network.provider.send("evm_snapshot");
    await distribute(dist, oracle, R(1, 10), all, blocks, E("20"), E("1"), 5);
    const a = await Promise.all([...all.map((x) => ethers.provider.getBalance(x)), ethers.provider.getBalance(TREASURY), ethers.provider.getBalance(FOUNDATION), dist.totalClaimable()]);
    await hre.network.provider.send("evm_revert", [snap]);
    await distribute(dist, oracle, R(1, 10), all, blocks, E("20"), E("1"), 1);
    const b = await Promise.all([...all.map((x) => ethers.provider.getBalance(x)), ethers.provider.getBalance(TREASURY), ethers.provider.getBalance(FOUNDATION), dist.totalClaimable()]);
    expect(b).to.deep.equal(a);
  });

  it("order is global across pages: unsorted, duplicate, repeated-in-a-later-page and zero addresses are refused", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await expect(d.payPage([all[1], all[0]], [1, 1])).to.be.revertedWith(REV("validators must be strictly ascending"));
    await expect(d.payPage([all[0], all[0]], [1, 1])).to.be.revertedWith(REV("validators must be strictly ascending"));
    await expect(d.payPage([ZERO], [1])).to.be.revertedWith(REV("validators must be strictly ascending"));
    await expect(d.payPage([], [])).to.be.revertedWith(REV("empty validator list"));
    await expect(d.payPage([all[0]], [1, 1])).to.be.revertedWith(REV("length mismatch"));
    await d.payPage([all[0], all[1]], [2, 2]);
    await expect(d.payPage([all[1]], [1])).to.be.revertedWith(REV("validators must be strictly ascending")); // paid in the previous page
    await expect(d.payPage([all[0]], [1])).to.be.revertedWith(REV("validators must be strictly ascending"));
    await d.payPage([all[2]], [1]); // the next higher address is fine
  });

  it("close needs the paged blocks to equal the declared total EXACTLY; pages cannot exceed it", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await d.payPage([all[0], all[1]], [3, 3]);
    await expect(d.closeDistribution()).to.be.revertedWith(REV("paged blocks differ from the declared total")); // 6 of 10
    await expect(d.payPage([all[2]], [5])).to.be.revertedWith(REV("paged blocks exceed the declared total")); // 11 of 10
    await d.payPage([all[2]], [4]);
    await d.closeDistribution();
  });

  it("no page or close without an open distribution; none after close; closing twice is refused", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await expect(d.payPage([all[0]], [1])).to.be.revertedWith(REV("no open distribution"));
    await expect(d.closeDistribution()).to.be.revertedWith(REV("no open distribution"));
    await distribute(dist, oracle, R(1, 10), all, [4, 3, 2, 1, 0], E("20"), E("1"));
    await expect(d.payPage([all[4]], [1])).to.be.revertedWith(REV("no open distribution"));
    await expect(d.closeDistribution()).to.be.revertedWith(REV("no open distribution"));
  });

  it("opening while another distribution is open is refused, even after the 23 hours; the range cannot be reopened", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await increaseTime(2 * DAY);
    await expect(d.openDistribution(R(11, 20), 10, E("20"), E("1"))).to.be.revertedWith(REV("another distribution is open"));
    await expect(d.openDistribution(R(1, 10), 10, E("20"), E("1"))).to.be.revertedWith(REV("another distribution is open"));
  });

  it("the 23-hour gap is counted from OPEN, not from close", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await increaseTime(5 * 3600);
    await d.payPage(all.slice(0, 3), [4, 3, 3]);
    await d.closeDistribution(); // closed 5 hours after open
    await mine(30);
    await increaseTime(17 * 3600); // 22 hours after OPEN, 17 after close
    await expect(d.openDistribution(R(11, 20), 10, E("20"), E("1"))).to.be.revertedWith(REV("too soon since last distribution"));
    await increaseTime(1.2 * 3600); // past 23 hours after open
    await d.openDistribution(R(11, 20), 10, E("20"), E("1"));
  });

  it("opening reserves the money: an insufficient balance (also counting claimable) is refused at open and nothing is changed", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle } = f;
    const d = dist.connect(oracle);
    const bal = await ethers.provider.getBalance(dist.target);
    await expect(d.openDistribution(R(1, 10), 10, bal, E("1"))).to.be.revertedWith(REV("insufficient contract balance"));
    expect(await dist.lastSettledBlock()).to.equal(0);
    expect((await dist.openDistributionInfo()).isOpen).to.equal(false);
    await expect(d.openDistribution(R(1, 10), 0, E("1"), 0)).to.be.revertedWith(REV("total blocks is zero"));
    await expect(d.openDistribution(R(1, 10), 11, E("1"), 0)).to.be.revertedWith(REV("reported blocks exceed the range size"));
  });

  it("an interrupted distribution can only be continued: still open after days, new oracle key may finish it, nobody can abandon it", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, board, all, S } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await d.payPage(all.slice(0, 2), [4, 3]);
    await increaseTime(10 * DAY);
    expect((await dist.openDistributionInfo()).isOpen).to.equal(true);
    await expect(d.openDistribution(R(11, 20), 10, E("20"), E("1"))).to.be.revertedWith(REV("another distribution is open"));
    // the board rotates the oracle key; the NEW key finishes the same distribution, the old one no longer can
    await dist.connect(board).setDistributionOracle(S[15].address);
    await expect(d.payPage([all[2]], [3])).to.be.revertedWith(REV("caller is not the distribution oracle"));
    await dist.connect(S[15]).payPage(all.slice(2, 4), [2, 1]);
    await dist.connect(S[15]).closeDistribution(); // 4+3+2+1 = 10 of 10
    expect((await dist.openDistributionInfo()).isOpen).to.equal(false);
  });

  it("deferred payment inside pages (RD-12b): the owner with code is credited, claim works between pages, and the reservation stays consistent", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all, c } = f;
    const d = dist.connect(oracle);
    const bl = blocksFor(f);
    const blocks = Object.fromEntries(all.map((a, i) => [a, bl[i]]));
    const ci = all.indexOf(c.target);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    const before = (await dist.openDistributionInfo()).budgetLeft;
    // page with the contract owner (it is credited, not called)
    await d.payPage(all.slice(0, ci + 1), all.slice(0, ci + 1).map((a) => blocks[a]));
    const owed = await dist.claimable(c.target);
    expect(owed).to.equal(E("1.07") * BigInt(blocks[c.target]));
    expect(await c.received()).to.equal(0);
    // it claims BETWEEN pages: the distribution is open, the claim is paid from the balance, the reservation is untouched
    await c.setAttack(true, dist.target); // and tries to re-enter claim() from receive(): refused
    await c.callClaim(dist.target);
    expect(await c.received()).to.equal(owed);
    expect(await c.reenterSucceeded()).to.equal(false);
    expect(await dist.totalClaimable()).to.equal(0);
    const info = await dist.openDistributionInfo();
    expect(info.budgetLeft).to.equal(before - owed - (E("1.07") * BigInt(all.slice(0, ci).reduce((s, a) => s + blocks[a], 0))));
    await d.payPage(all.slice(ci + 1), all.slice(ci + 1).map((a) => blocks[a]));
    await d.closeDistribution();
    expect(await ethers.provider.getBalance(dist.target)).to.be.gte(await dist.totalClaimable());
  });

  it("claim() cannot be used to drain the reservation: claim pays only the caller's claimable, and the Distributable view subtracts the reservation", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, all, S } = f;
    const d = dist.connect(oracle);
    await d.openDistribution(R(1, 10), 10, E("20"), E("1"));
    await expect(dist.connect(S[16]).claim()).to.be.revertedWith(REV("nothing to claim"));
    const bal = await ethers.provider.getBalance(dist.target);
    expect(await dist.getDistributableBalance()).to.equal(bal - E("21"));
  });
});

// chai-matchers helper: any value
const anyValue = require("@nomicfoundation/hardhat-chai-matchers/withArgs").anyValue;
