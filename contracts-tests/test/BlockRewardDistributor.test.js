// v2.5: excess-reward burn in BlockRewardDistributor (the rest of the distributor is unchanged v2.2 behaviour).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, mine, setTime, now, distribute } = require("./helpers");

const E = ethers.parseEther;
const ORACLE = "0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6"; // SurAddresses.DISTRIBUTION_ORACLE
const TREASURY = "0x5555555555555555555555555555555555555555";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const ZERO = ethers.ZeroAddress;

async function fixture() {
  const S = await ethers.getSigners();
  const t0 = await now();
  const owner = S[0];
  const opKey = ethers.Wallet.createRandom().address;
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY, [owner.address, opKey, [], t0]);
  const dist = await deployAtFixed("BlockRewardDistributor", "BlockRewardDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR, [], E("2000"));
  await hre.network.provider.send("hardhat_setBalance", [ORACLE, "0x56BC75E2D63100000"]);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);
  await mine(30);
  return { S, owner, reg, dist, oracle, opKey };
}

describe("BlockRewardDistributor v2.5 - approved reward and excess burn", () => {
  it("reported = approved: split 50% validators / 15% foundation / 35% treasury, no burn", async () => {
    const { dist, oracle, owner } = await loadFixture(fixture);
    expect(await dist.maxRewardsForRange(1, 10)).to.equal(E("20")); // 2 Suren per block
    const before = [await ethers.provider.getBalance(owner.address), await ethers.provider.getBalance(FOUNDATION), await ethers.provider.getBalance(TREASURY)];
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, [owner.address], [10], E("20"), E("1"));
    expect(await dist.totalExcessBurned()).to.equal(0);
    expect(await ethers.provider.getBalance(owner.address)).to.equal(before[0] + E("10") + E("0.7"));
    expect(await ethers.provider.getBalance(FOUNDATION)).to.equal(before[1] + E("3"));
    expect(await ethers.provider.getBalance(TREASURY)).to.equal(before[2] + E("7"));
    expect(await dist.lastSettledBlock()).to.equal(10);
  });

  it("reported > approved: only the approved amount is split; the excess is burned at once and announced; the range still settles", async () => {
    const { dist, oracle, owner } = await loadFixture(fixture);
    const burnedBefore = await ethers.provider.getBalance(ZERO);
    const before = [await ethers.provider.getBalance(owner.address), await ethers.provider.getBalance(FOUNDATION), await ethers.provider.getBalance(TREASURY)];
    const txs = await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, [owner.address], [10], E("25"), E("1"));
    await expect(txs.open).to.emit(dist, "RewardExcessBurned").withArgs(1, 1, 10, E("20"), E("5"));
    expect(await dist.totalExcessBurned()).to.equal(E("5"));
    expect(await ethers.provider.getBalance(ZERO)).to.equal(burnedBefore + E("5") + E("0.3")); // excess + 30% of the fee
    expect(await ethers.provider.getBalance(owner.address)).to.equal(before[0] + E("10") + E("0.7"));
    expect(await ethers.provider.getBalance(FOUNDATION)).to.equal(before[1] + E("3"));
    expect(await ethers.provider.getBalance(TREASURY)).to.equal(before[2] + E("7"));
    expect(await dist.lastSettledBlock()).to.equal(10); // never halted
  });

  it("reported < approved is paid as reported (no burn); there is no cap on the excess burned per epoch", async () => {
    const { dist, oracle, owner } = await loadFixture(fixture);
    await distribute(dist, oracle, { fromBlock: 1, toBlock: 10 }, [owner.address], [10], E("10"), E("0"));
    expect(await dist.totalExcessBurned()).to.equal(0);
    await hre.network.provider.send("evm_increaseTime", [24 * 3600]);
    await distribute(dist, oracle, { fromBlock: 11, toBlock: 20 }, [owner.address], [10], E("1000"), E("0")); // 980 over the approved 20
    expect(await dist.totalExcessBurned()).to.equal(E("980"));
    expect(await dist.lastSettledBlock()).to.equal(20);
  });

  it("only the distribution oracle can distribute; an address never activated is refused", async () => {
    const { dist, S, oracle } = await loadFixture(fixture);
    await expect(dist.connect(S[3]).openDistribution({ fromBlock: 1, toBlock: 10 }, 10, E("20"), 0)).to.be.revertedWith("BlockRewardDistributor: caller is not the distribution oracle");
    await dist.connect(oracle).openDistribution({ fromBlock: 1, toBlock: 10 }, 10, E("20"), 0);
    await expect(dist.connect(S[3]).payPage([S[0].address], [10])).to.be.revertedWith("BlockRewardDistributor: caller is not the distribution oracle");
    await expect(dist.connect(S[3]).closeDistribution()).to.be.revertedWith("BlockRewardDistributor: caller is not the distribution oracle");
    await expect(dist.connect(oracle).payPage([S[5].address], [10])).to.be.revertedWith("BlockRewardDistributor: address was never a legitimate validator");
  });
});
