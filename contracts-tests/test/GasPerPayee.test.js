// RD-12b / RD-18: gas per payee of BlockRewardDistributor.distributeRewards (EOA path vs deferred path). Own file: it needs a clean chain (fixed genesis addresses keep storage).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, mine, increaseTime, now, DAY } = require("./helpers");

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

describe("RD-12b / RD-18 - gas per payee (measurement, local Hardhat EVM)", () => {
  async function run(n, contractPayees) {
    const snap = await hre.network.provider.send("evm_snapshot"); // every run starts from a clean chain (fixed genesis addresses keep their storage otherwise)
    const f = await build(n);
    if (contractPayees) {
      // turn every EOA founder into an address WITH code after activation (registry state is unaffected by the code)
      for (const a of f.eoas) await setCodeOf("MockSeatOwner", a);
    }
    await mine(n + 5);
    const addrs = sortAsc([f.c.target, ...f.eoas]);
    const total = addrs.length;
    const tx = await f.dist.connect(f.oracle).distributeRewards({ fromBlock: 1, toBlock: total }, addrs, addrs.map(() => 1), E("2") * BigInt(total), E("1"), { gasLimit: 16_000_000 });
    const gas = (await tx.wait()).gasUsed;
    // second epoch: lifetime totals are non-zero now (steady state)
    await hre.network.provider.send("evm_increaseTime", [24 * 3600]);
    await mine(total + 5);
    const tx2 = await f.dist.connect(f.oracle).distributeRewards({ fromBlock: total + 1, toBlock: 2 * total }, addrs, addrs.map(() => 1), E("2") * BigInt(total), E("1"), { gasLimit: 16_000_000 });
    const gas2 = (await tx2.wait()).gasUsed;
    await hre.network.provider.send("evm_revert", [snap]);
    return [gas, gas2];
  }

  it("marginal gas of one payee, EOA path and deferred path; implied payee cap at a 45M block gas limit", async function () {
    this.timeout(600000);
    const [[a1, a1s], [a2, a2s], [d1, d1s], [d2, d2s]] = [await run(30, false), await run(70, false), await run(30, true), await run(70, true)];
    const rep = (name, g1, g2) => {
      const per = Number(g2 - g1) / 40, fixed = Number(g1) - per * 31;
      console.log("      [gas] " + name + ": " + per.toFixed(0) + " per payee, fixed " + fixed.toFixed(0) + "  => cap at 45M ~ " + Math.floor((45e6 - fixed) / per));
      return per;
    };
    const eoaPer = rep("EOA payee, first epoch (worst case: lifetime totals zero)", a1, a2);
    rep("EOA payee, steady state (second epoch)", a1s, a2s);
    const defPer = rep("deferred payee (owner with code), first epoch", d1, d2);
    rep("deferred payee (owner with code), steady state", d1s, d2s);
    expect(eoaPer).to.be.gt(50_000).and.lt(200_000);
    expect(defPer).to.be.gt(50_000).and.lt(200_000);
  });
});
