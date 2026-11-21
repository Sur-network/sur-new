// RD-12b / RD-18: gas per payee of a BlockRewardDistributor.payPage page (EOA path vs deferred path). Own file: it needs a clean chain (fixed genesis addresses keep storage).
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

describe("RD-12b / RD-18 - gas per payee in a page (measurement, local Hardhat EVM)", () => {
  /// gas of ONE page holding every payee (first epoch = worst case, lifetime totals zero) and of the same page in the second epoch (steady state)
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
    const ones = addrs.map(() => 1);
    const o = { gasLimit: 16_000_000 };
    const t1 = await distribute(f.dist, f.oracle, { fromBlock: 1, toBlock: total }, addrs, ones, E("2") * BigInt(total), E("1"), 1000, o);
    const first = (await t1.pages[0].wait()).gasUsed;
    const fixedOpenClose = (await t1.open.wait()).gasUsed + (await t1.close.wait()).gasUsed;
    await hre.network.provider.send("evm_increaseTime", [24 * 3600]);
    await mine(total + 5);
    const t2 = await distribute(f.dist, f.oracle, { fromBlock: total + 1, toBlock: 2 * total }, addrs, ones, E("2") * BigInt(total), E("1"), 1000, o);
    const steady = (await t2.pages[0].wait()).gasUsed;
    await hre.network.provider.send("evm_revert", [snap]);
    return { first, steady, fixedOpenClose };
  }

  it("marginal gas of one payee in a page (EOA path and deferred path) and the implied capacity per page at a 45M block gas limit", async function () {
    this.timeout(900000);
    const [a30, a70, d30, d70] = [await run(30, false), await run(70, false), await run(30, true), await run(70, true)];
    const rep = (name, g1, g2) => {
      const per = Number(g2 - g1) / 40, fixed = Number(g1) - per * 31;
      console.log("      [gas/page] " + name + ": " + per.toFixed(0) + " per payee, page fixed " + fixed.toFixed(0) + " => payees per page at 45M ~ " + Math.floor((45e6 - fixed) / per) + ", at 16.7M tx cap ~ " + Math.floor((16777216 - fixed) / per));
      return per;
    };
    console.log("      [gas/page] open + close (once per distribution), 70 payees: " + a70.fixedOpenClose);
    const eoaFirst = rep("EOA, first epoch (worst case)", a30.first, a70.first);
    rep("EOA, steady state", a30.steady, a70.steady);
    const defFirst = rep("deferred (owner with code), first epoch", d30.first, d70.first);
    rep("deferred (owner with code), steady state", d30.steady, d70.steady);
    expect(eoaFirst).to.be.gt(30_000).and.lt(200_000);
    expect(defFirst).to.be.gt(30_000).and.lt(200_000);
  });
});
