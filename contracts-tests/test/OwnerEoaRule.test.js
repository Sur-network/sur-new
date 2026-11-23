// RD-12: a validator seat owner must be a plain wallet (EOA): checked at entry (paid and lottery) and when the seat NFT moves.
// (RD-12b, the check at payment time that closes the gap left by a constructor-time or pre-computed-address contract, is in DeferredClaim.test.js.)
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY, agr } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const rnd = () => ethers.Wallet.createRandom().address;
const AGR = ethers.id("signed validators agreement v1"); // hash of the signed agreement document (any non-zero bytes32)
const EOA_REG = "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)";
const EOA_NFT = "ValidatorSeatNFT: a seat owner must be a plain wallet (EOA)";

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
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const x of founders.slice(1)) {
    await reg.connect(x).setOperator(rnd());
    await reg.connect(verifier).recordActivation(x.address, HASH);
  }
  const seller = S[10], buyer = S[11];
  for (const b of [seller, buyer]) {
    await idr.setVerified(b.address, true);
    await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  }
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  await hre.network.provider.send("hardhat_setBalance", [S[15].address, "0x" + E("2000000").toString(16)]); // deployer of the owner contracts
  const factory = await ethers.getContractFactory("MockSeatOwner", S[15]);
  return { S, reg, nft, idr, verifier, seller, buyer, price, factory };
}

describe("RD-12 - the seat owner must be a plain wallet (EOA)", () => {
  it("paid entry: a contract caller is refused, an EOA enters", async () => {
    const { reg, idr, seller, price, factory } = await loadFixture(fixture);
    const c = await factory.deploy(ZERO, ZERO);
    await idr.setVerified(await c.getAddress(), true);
    await expect(c.enter(ADDR.VALIDATORS_REGISTRY, rnd(), { value: price })).to.be.revertedWith(EOA_REG);
    expect((await reg.validators(await c.getAddress())).status).to.equal(0);
    await reg.connect(seller).requestMembership(rnd(), agr(), { value: price });
    expect((await reg.validators(seller.address)).status).to.equal(1); // Probation
  });

  it("a contract cannot enter even from its own constructor (code.length is 0 there, so msg.sender == tx.origin is required too); the remaining limit is an address that gets code AFTER entry, closed by RD-12b at payment", async () => {
    const { reg, idr, S, price, factory } = await loadFixture(fixture);
    const next = ethers.getCreateAddress({ from: S[15].address, nonce: await ethers.provider.getTransactionCount(S[15].address) });
    await idr.setVerified(next, true);
    await expect(factory.deploy(ADDR.VALIDATORS_REGISTRY, rnd(), { value: price })).to.be.revertedWith(EOA_REG);
    expect((await reg.validators(next)).status).to.equal(0);
  });

  it("Registry.enterAsLotteryWinner called as the lottery: a contract winner is refused, an EOA winner is entered (drawBatch's try/catch and entryFailed are not exercised here)", async () => {
    const { reg, buyer, factory } = await loadFixture(fixture);
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATOR_LOTTERY, "0x56BC75E2D63100000"]);
    const lottery = await ethers.getImpersonatedSigner(ADDR.VALIDATOR_LOTTERY);
    const c = await factory.deploy(ZERO, ZERO);
    await expect(reg.connect(lottery).enterAsLotteryWinner(await c.getAddress())).to.be.revertedWith(EOA_REG);
    await reg.connect(lottery).enterAsLotteryWinner(buyer.address);
    expect((await reg.validators(buyer.address)).status).to.equal(1);
  });

  it("seat transfer: transferFrom and safeTransferFrom to a contract revert and leave the seat with the seller; to an EOA it works", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, idr, verifier, seller, buyer, price, factory } = f;
    await reg.connect(seller).requestMembership(rnd(), agr(), { value: price });
    await increaseTime(8 * DAY);
    await reg.connect(verifier).recordActivation(seller.address, HASH);
    const id = await nft.seatOf(seller.address);
    const c = await factory.deploy(ZERO, ZERO); // would even accept an ERC-721 only if it implemented the receiver; the EOA rule fires first
    await idr.setVerified(await c.getAddress(), true);
    await expect(nft.connect(seller).transferFrom(seller.address, await c.getAddress(), id)).to.be.revertedWith(EOA_NFT);
    await expect(nft.connect(seller)["safeTransferFrom(address,address,uint256)"](seller.address, await c.getAddress(), id)).to.be.revertedWith(EOA_NFT);
    expect(await nft.ownerOf(id)).to.equal(seller.address);
    await reg.connect(buyer).acceptSeatAgreement(id, AGR); // the buyer must accept the validators' agreement for this seat first
    await nft.connect(seller).transferFrom(seller.address, buyer.address, id);
    expect(await nft.ownerOf(id)).to.equal(buyer.address);
    expect((await reg.validators(buyer.address)).status).to.equal(2); // an Active seat stays Active
  });
});
