const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setTime, now } = require("./helpers");

const E = ethers.parseEther;
const utc = (y, m, d, h = 0) => Math.floor(Date.UTC(y, m - 1, d, h) / 1000);
const GENESIS = utc(2027, 3, 15, 12);
const VAULT = "0x9999999999999999999999999999999999999999";

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < GENESIS) await setTime(GENESIS);
  const claims = [E("2400100"), E("1000000"), E("500")]; // held: 2,400,000 / 999,900 / 400
  const vault = await deployAtFixed("GenesisClaimsVault", "GenesisClaimsVault_GenesisSeed", VAULT,
    [[S[1].address, S[2].address, S[3].address], claims, GENESIS]);
  const total = await vault.totalHeld();
  await hre.network.provider.send("hardhat_setBalance", [VAULT, "0x" + total.toString(16)]);
  return { S, vault, total, a: S[1], b: S[2], c: S[3] };
}

describe("GenesisClaimsVault", () => {
  it("holds claim - 100 per address; the total matches the funding; no plain transfers", async () => {
    const { vault, a, b, c, total, S } = await loadFixture(fixture);
    expect(total).to.equal(E("2400000") + E("999900") + E("400"));
    const ia = await vault.claimInfo(a.address);
    expect(ia.held).to.equal(E("2400000"));
    expect(ia.walletPart).to.equal(E("100"));
    expect(await vault.installmentAmount(a.address)).to.equal(E("100000"));
    expect(await vault.genesisTimestamp()).to.equal(GENESIS);
    await expect(S[9].sendTransaction({ to: VAULT, value: 1 })).to.be.revertedWith("GenesisClaimsVault: funded only through the genesis alloc");
    await expect(vault.connect(S[9]).withdraw()).to.be.revertedWith("GenesisClaimsVault: no claim for this address");
  });

  it("nothing is released in the genesis month; the first instalment appears on the first day of the next month", async () => {
    const { vault, a } = await loadFixture(fixture);
    expect(await vault.monthsReleased()).to.equal(0);
    await expect(vault.connect(a).withdraw()).to.be.revertedWith("GenesisClaimsVault: nothing released yet");
    await setTime(utc(2027, 3, 31, 23));
    expect(await vault.monthsReleased()).to.equal(0);
    await setTime(utc(2027, 4, 1, 0));
    expect(await vault.monthsReleased()).to.equal(1);
    expect(await vault.withdrawableOf(a.address)).to.equal(E("100000"));
    await setTime(utc(2027, 4, 30, 23));
    expect(await vault.monthsReleased()).to.equal(1); // same month: no second instalment
  });

  it("withdraw pays everything released and not yet taken; unwithdrawn instalments accumulate and never expire", async () => {
    const { vault, a } = await loadFixture(fixture);
    await setTime(utc(2027, 4, 2));
    const before = await ethers.provider.getBalance(a.address);
    const tx = await vault.connect(a).withdraw();
    const rc = await tx.wait();
    expect(await ethers.provider.getBalance(a.address)).to.equal(before + E("100000") - rc.gasUsed * rc.gasPrice);
    await expect(vault.connect(a).withdraw()).to.be.revertedWith("GenesisClaimsVault: nothing released yet");
    await setTime(utc(2027, 9, 1)); // months 2..6 (May..September) not withdrawn meanwhile
    expect(await vault.monthsReleased()).to.equal(6);
    expect(await vault.withdrawableOf(a.address)).to.equal(E("500000")); // five accumulated instalments
    await vault.connect(a).withdraw();
    expect((await vault.claimInfo(a.address)).withdrawn).to.equal(E("600000"));
  });

  it("24 instalments in total; the rounding remainder goes into the last one; nothing more afterwards", async () => {
    const { vault, a, b, c } = await loadFixture(fixture);
    // b holds 999,900 Suren: 999,900 / 24 = 41,662.5 -> floor 41,662.5 is not an integer in wei terms; use the exact wei math
    const held = E("999900");
    const regular = held / 24n;
    expect(await vault.installmentAmount(b.address)).to.equal(regular);
    await setTime(utc(2029, 2, 1)); // 23 instalments (April 2027 .. February 2029)
    expect(await vault.monthsReleased()).to.equal(23);
    expect(await vault.releasedOf(b.address)).to.equal(regular * 23n);
    await setTime(utc(2029, 3, 1)); // the 24th
    expect(await vault.monthsReleased()).to.equal(24);
    expect(await vault.releasedOf(b.address)).to.equal(held); // regular * 23 + (regular + remainder)
    await setTime(utc(2031, 1, 1));
    expect(await vault.monthsReleased()).to.equal(24);
    await vault.connect(b).withdraw();
    await vault.connect(a).withdraw();
    await vault.connect(c).withdraw();
    expect(await ethers.provider.getBalance(VAULT)).to.equal(0); // everything paid out, no dust left behind
    await expect(vault.connect(b).withdraw()).to.be.revertedWith("GenesisClaimsVault: nothing released yet");
  });

  it("the month arithmetic follows the calendar across a year end", async () => {
    const { vault } = await loadFixture(fixture);
    expect(await vault.monthIdOf(utc(2027, 12, 31, 23))).to.equal(2027 * 12 + 11);
    expect(await vault.monthIdOf(utc(2028, 1, 1, 0))).to.equal(2028 * 12);
    expect(await vault.monthIdOf(utc(2028, 2, 29, 12))).to.equal(2028 * 12 + 1); // leap day
  });
});
