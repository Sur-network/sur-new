// RD-12b: BlockRewardDistributor pays an owner that has code through claimable[] + claim() instead of calling it.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, mine, increaseTime, now, DAY, distribute } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const ORACLE = "0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6"; // SurAddresses.DISTRIBUTION_ORACLE
const rnd = () => ethers.Wallet.createRandom().address;
const sortAsc = (arr) => [...arr].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));

/// Registry + seat NFT + Distributor (200000 Suren). The first founder (Active at genesis) is a CONTRACT owner (MockSeatOwner),
/// followed by `nEoa` activated EOA founders (random addresses driven through impersonation).
async function build(nEoa) {
  const S = await ethers.getSigners();
  await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const c = await (await ethers.getContractFactory("MockSeatOwner")).deploy(ZERO, ZERO);
  const eoas = Array.from({ length: nEoa }, () => ethers.Wallet.createRandom().address);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [await c.getAddress(), rnd(), eoas, t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [[await c.getAddress(), ...eoas]]);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("200000"));
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  await hre.network.provider.send("hardhat_setBalance", [ORACLE, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);
  for (const a of eoas) {
    await hre.network.provider.send("hardhat_setBalance", [a, "0x56BC75E2D63100000"]);
    const s = await ethers.getImpersonatedSigner(a);
    await reg.connect(s).setOperator(rnd());
    await reg.connect(verifier).recordActivation(a, HASH);
  }
  return { S, reg, dist, c, eoas, oracle, verifier };
}

async function fixture() {
  const f = await build(3);
  await mine(30);
  return f;
}

/// ascending list with the contract owner included
function listOf(f, perBlocks) {
  const all = sortAsc([f.c.target, ...f.eoas]);
  return { addrs: all, blocks: all.map((a) => perBlocks(a)) };
}

describe("RD-12b - deferred payment to an owner with code", () => {
  it("an EOA is paid directly (ValidatorRewarded); an owner with code is credited to claimable (ValidatorRewardDeferred) and NOT called", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, c, eoas } = f;
    const { addrs, blocks } = listOf(f, (a) => (a === c.target ? 4 : 2)); // total 10 blocks: contract 4, three EOAs 2 each
    const before = Object.fromEntries(await Promise.all(addrs.map(async (a) => [a, await ethers.provider.getBalance(a)])));
    const txs = await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, addrs, blocks, E("20"), E("1"));
    const tx = txs.pages[0];
    // validator share of the 20 rewards = 50% = 10 split by 10 blocks => 1 per block; fees 1 - 30% burn = 0.7 => 0.07 per block
    await expect(tx).to.emit(dist, "ValidatorRewardDeferred").withArgs(1, c.target, 4, E("4"), E("0.28"), E("4.28"));
    await expect(tx).to.emit(dist, "ValidatorRewarded").withArgs(1, sortAsc(eoas)[0], 2, E("2"), E("0.14"), E("2.14"));
    // the contract owner was neither paid nor called
    expect(await ethers.provider.getBalance(c.target)).to.equal(before[c.target]);
    expect(await c.received()).to.equal(0);
    expect(await dist.claimable(c.target)).to.equal(E("4.28"));
    expect(await dist.totalClaimable()).to.equal(E("4.28"));
    for (const a of eoas) expect(await ethers.provider.getBalance(a)).to.equal(before[a] + E("2.14"));
    // lifetime totals are kept for the deferred owner too (per-epoch records are the events only)
    const [tr, tf, tb] = await dist.getValidatorTotals(c.target);
    expect([tr, tf, tb]).to.deep.equal([E("4"), E("0.28"), 4n]);
    expect((await dist.getEpoch(1)).validatorCount).to.equal(4);
    expect(await dist.getDistributableBalance()).to.equal((await ethers.provider.getBalance(dist.target)) - E("4.28"));
  });

  it("claim(): only the caller's own balance; zero is refused; strangers get nothing; the state is cleared before paying", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, c, S } = f;
    const { addrs, blocks } = listOf(f, (a) => (a === c.target ? 4 : 2));
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, addrs, blocks, E("20"), E("1"));
    await expect(dist.connect(S[15]).claim()).to.be.revertedWith("BlockRewardDistributor: nothing to claim");
    const tx = c.callClaim(dist.target);
    await expect(tx).to.emit(dist, "ClaimableWithdrawn").withArgs(c.target, E("4.28"));
    await tx;
    expect(await c.received()).to.equal(E("4.28"));
    expect(await dist.claimable(c.target)).to.equal(0);
    expect(await dist.totalClaimable()).to.equal(0);
    await expect(c.callClaim(dist.target)).to.be.revertedWith("BlockRewardDistributor: nothing to claim");
  });

  it("an owner whose receive() reverts cannot halt the distribution; only its own claim() fails (and works again later)", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, c } = f;
    await c.setReject(true);
    const { addrs, blocks } = listOf(f, (a) => (a === c.target ? 4 : 2));
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, addrs, blocks, E("20"), E("1")); // does not revert
    expect(await dist.lastSettledBlock()).to.equal(10);
    expect(await dist.claimable(c.target)).to.equal(E("4.28"));
    await expect(c.callClaim(dist.target)).to.be.revertedWith("BlockRewardDistributor: claim transfer failed");
    expect(await dist.claimable(c.target)).to.equal(E("4.28")); // intact
    await c.setReject(false);
    await c.callClaim(dist.target);
    expect(await c.received()).to.equal(E("4.28"));
  });

  it("reentrancy: re-entering claim() from receive() is refused by nonReentrant and cannot double-withdraw", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, c } = f;
    const { addrs, blocks } = listOf(f, (a) => (a === c.target ? 4 : 2));
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, addrs, blocks, E("20"), E("1"));
    await c.setAttack(true, dist.target);
    const distBefore = await ethers.provider.getBalance(dist.target);
    await c.callClaim(dist.target);
    expect(await c.reenterSucceeded()).to.equal(false);
    const reason = ethers.AbiCoder.defaultAbiCoder().decode(["string"], "0x" + (await c.reenterReason()).slice(10))[0];
    expect(reason).to.equal("BlockRewardDistributor: reentrant call");
    expect(await c.received()).to.equal(E("4.28")); // exactly once
    expect(await ethers.provider.getBalance(dist.target)).to.equal(distBefore - E("4.28"));
    expect(await dist.totalClaimable()).to.equal(0);
  });

  it("claimable is a contract debt: a distribution cannot spend it (balance check), and the debt survives a distribution that spends everything else", async () => {
    const f = await loadFixture(fixture);
    const { dist, oracle, c } = f;
    const { addrs, blocks } = listOf(f, (a) => (a === c.target ? 4 : 2));
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, addrs, blocks, E("20"), E("1"));
    const K = await dist.totalClaimable();
    expect(K).to.equal(E("4.28"));
    await increaseTime(DAY);
    await mine(20);
    const bal = await ethers.provider.getBalance(dist.target);
    // reported rewards that fit the raw balance but not balance - claimable are refused
    await expect(dist.connect(oracle).openDistribution({ fromBlock: 11, toBlock: 20 }, 10, bal - K / 2n, 0))
      .to.be.revertedWith("BlockRewardDistributor: insufficient contract balance");
    // everything except the debt can be used (what exceeds the approved reward of the range is burned)
    await distribute(dist, oracle, { fromBlock: 11, toBlock: 20 }, addrs, blocks, bal - K, 0);
    expect(await ethers.provider.getBalance(dist.target)).to.equal(await dist.totalClaimable()); // nothing but the debt is left
    // and the owner with code can still withdraw everything it is owed (both epochs)
    const owed = await dist.claimable(c.target);
    expect(owed).to.be.gt(K);
    await c.callClaim(dist.target);
    expect(await c.received()).to.equal(owed);
  });
});
