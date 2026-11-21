const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const ST = { None: 0, Probation: 1, Active: 2, Demoted: 3, Exiting: 4, SelfSuspended: 6 };
const rnd = () => ethers.Wallet.createRandom().address;

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const founders = S.slice(0, 5);
  const op0 = rnd();
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, op0, founders.slice(1).map((s) => s.address), t0]);
  const nft = await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const daoBoard = S.slice(5, 10);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [daoBoard.map((s) => s.address), S[7].address, daoBoard[0].address, daoBoard[1].address, S[8].address, t0 + 730 * DAY], E("10"));
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const x of founders.slice(1)) {
    await reg.connect(x).setOperator(rnd());
    await reg.connect(verifier).recordActivation(x.address, HASH);
  }
  const seller = S[10], buyer = S[11], other = S[12];
  for (const b of [seller, buyer, other]) {
    await idr.setVerified(b.address, true);
    await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  }
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  return { S, reg, nft, dao, daoBoard, idr, verifier, founders, seller, buyer, other, price };
}

async function enterAndActivate(f, owner) {
  const op = rnd();
  await f.reg.connect(owner).requestMembership(op, { value: f.price });
  await increaseTime(8 * DAY);
  await f.reg.connect(f.verifier).recordActivation(owner.address, HASH);
  return op;
}

describe("ValidatorSeatNFT - tokens", () => {
  it("founders hold seats 1..n in seeding order; ERC-721 metadata; tokenURI uses the base URI", async () => {
    const { nft, founders } = await loadFixture(fixture);
    expect(await nft.name()).to.equal("Sur Validator Seat");
    expect(await nft.symbol()).to.equal("SURSEAT");
    for (let i = 0; i < founders.length; i++) {
      expect(await nft.ownerOf(i + 1)).to.equal(founders[i].address);
      expect(await nft.seatOf(founders[i].address)).to.equal(i + 1);
    }
    expect(await nft.tokenURI(3)).to.equal("https://validator-nft.surnet.org/3");
    expect(await nft.supportsInterface("0x80ac58cd")).to.equal(true);
    expect(await nft.supportsInterface("0x5b5e139f")).to.equal(true);
    await expect(nft.tokenURI(99)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
  });

  it("entering mints a seat; only the Registry mints/burns; the base URI changes only through FoundationDAO", async () => {
    const f = await loadFixture(fixture);
    const { nft, seller, dao, daoBoard, S } = f;
    await enterAndActivate(f, seller);
    expect(await nft.ownerOf(6)).to.equal(seller.address);
    await expect(nft.connect(seller).mintSeat(seller.address)).to.be.revertedWith("ValidatorSeatNFT: only ValidatorsRegistry");
    await expect(nft.connect(seller).burnSeat(seller.address)).to.be.revertedWith("ValidatorSeatNFT: only ValidatorsRegistry");
    await expect(nft.connect(seller).setBaseURI("https://x/")).to.be.revertedWith("ValidatorSeatNFT: only FoundationDAO");
    const data = nft.interface.encodeFunctionData("setBaseURI", ["https://new.surnet.org/seat/"]);
    await dao.connect(daoBoard[0]).proposeExecute(await nft.getAddress(), 0, data, "new metadata host");
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(daoBoard[1]).vote(id, h);
    await dao.connect(daoBoard[2]).vote(id, h);
    expect(await nft.tokenURI(6)).to.equal("https://new.surnet.org/seat/6");
  });

  it("approvals work as in ERC-721; a stranger cannot move a seat", async () => {
    const f = await loadFixture(fixture);
    const { nft, reg, seller, buyer, other } = f;
    await enterAndActivate(f, seller);
    await expect(nft.connect(other).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith("ValidatorSeatNFT: not owner nor approved");
    await nft.connect(seller).approve(other.address, 6);
    expect(await nft.getApproved(6)).to.equal(other.address);
    await nft.connect(other).transferFrom(seller.address, buyer.address, 6);
    expect(await nft.ownerOf(6)).to.equal(buyer.address);
    expect(await nft.getApproved(6)).to.equal(ZERO);
    expect((await reg.validators(buyer.address)).lockedStake).to.equal(E("500000"));
  });
});

describe("ValidatorSeatNFT - selling a seat moves the validator record", () => {
  it("an Active seat STAYS Active: collateral, operator and place in the set move to the buyer at once; the buyer is a new voter; acceptance is only a record", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    const op = await enterAndActivate(f, seller);
    expect(await reg.getValidators()).to.include(op);
    const seq = await reg.activationSeq(seller.address);
    const nonceBefore = await reg.statusNonce();
    const ownersBefore = await reg.getActiveOwners();
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);

    const v = await reg.validators(buyer.address);
    expect(v.status).to.equal(ST.Active);
    expect(v.lockedStake).to.equal(E("500000"));
    expect(v.isPaidEntrant).to.equal(true);
    expect((await reg.validators(seller.address)).status).to.equal(ST.None); // record moved
    expect(await reg.operatorOf(buyer.address)).to.equal(op);
    expect(await reg.ownerOfOperator(op)).to.equal(buyer.address);
    expect(await reg.operatorOf(seller.address)).to.equal(ZERO);
    expect(await reg.activationSeq(buyer.address)).to.equal(seq);
    // the node never leaves the validator set and keeps its position
    expect(await reg.getValidators()).to.include(op);
    const ownersAfter = await reg.getActiveOwners();
    expect(ownersAfter.length).to.equal(ownersBefore.length);
    expect(ownersAfter.indexOf(buyer.address)).to.equal(ownersBefore.indexOf(seller.address));
    expect(ownersAfter).to.not.include(seller.address);
    expect(await reg.isValidator(buyer.address)).to.equal(true);
    expect(await reg.isValidator(seller.address)).to.equal(false);
    expect(await reg.permanentlyExited(seller.address)).to.equal(true);
    // the buyer is a NEW voter: cannot vote on what was proposed before the transfer; the seller's vote is gone
    expect(await reg.wasActiveAt(buyer.address, nonceBefore)).to.equal(false);
    expect(await reg.wasActiveAt(buyer.address, await reg.statusNonce())).to.equal(true);
    expect(await reg.wasActiveAt(seller.address, await reg.statusNonce())).to.equal(false);

    // acceptance of the agreement is a record, not a gate
    expect(await reg.seatTransferPending(buyer.address)).to.equal(true);
    await reg.connect(buyer).acceptSeatTransfer();
    await expect(reg.connect(buyer).acceptSeatTransfer()).to.be.revertedWith("ValidatorsRegistry: no pending seat transfer");
    expect(await reg.seatTransferPending(buyer.address)).to.equal(false);
  });

  it("the seller can never return; the buyer starts with no history of its own", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, price } = f;
    await enterAndActivate(f, seller);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    await expect(reg.connect(seller).requestMembership(rnd(), { value: price })).to.be.revertedWith("ValidatorsRegistry: this address has exited before and may not rejoin");
  });

  it("a Probation seat can be sold too; the buyer is activated by the Verifier after the probation wait, acceptance or not", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, verifier, seller, buyer, price } = f;
    await reg.connect(seller).requestMembership(rnd(), { value: price });
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    expect((await reg.validators(buyer.address)).status).to.equal(ST.Probation);
    await increaseTime(8 * DAY);
    await reg.connect(verifier).recordActivation(buyer.address, HASH);
    expect((await reg.validators(buyer.address)).status).to.equal(ST.Active);
  });

  it("buyer rules: fully verified, no seat yet, not an operator key, never a validator before", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, idr, seller, other, S, founders } = f;
    await enterAndActivate(f, seller);
    const stranger = S[15];
    await expect(nft.connect(seller).transferFrom(seller.address, stranger.address, 6)).to.be.revertedWith("ValidatorsRegistry: buyer identity not fully verified");
    await expect(nft.connect(seller).transferFrom(seller.address, founders[1].address, 6)).to.be.revertedWith("ValidatorSeatNFT: recipient already holds a seat");
    await expect(nft.connect(seller).transferFrom(seller.address, ZERO, 6)).to.be.revertedWith("ValidatorSeatNFT: transfer to the zero address");

    // somebody's operator key (the first validator's node key) cannot buy a seat
    const op0 = await reg.operatorOf(founders[0].address);
    await idr.setVerified(op0, true);
    await expect(nft.connect(seller).transferFrom(seller.address, op0, 6)).to.be.revertedWith("ValidatorsRegistry: buyer is an operator key");

    // an address that was a validator before (entered and exited) cannot come back by buying
    await reg.connect(other).requestMembership(rnd(), { value: f.price });
    await reg.connect(other).requestExit();
    await expect(nft.connect(seller).transferFrom(seller.address, other.address, 6)).to.be.revertedWith("ValidatorsRegistry: buyer was a validator before");
  });

  it("blocked while a penalty case is open", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, verifier, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await reg.connect(verifier).recordSuspension(seller.address, HASH); // Demoted with a pending slash decision
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith("ValidatorsRegistry: open penalty case - transfer blocked");
  });

  it("an exiting owner's seat is burned and cannot be moved", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await reg.connect(seller).requestExit();
    await expect(nft.ownerOf(6)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
    expect(await nft.balanceOf(seller.address)).to.equal(0);
    expect(await nft.seatOf(seller.address)).to.equal(0);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
  });

  it("only the NFT contract can call the Registry's transfer hook", async () => {
    const { reg, seller, buyer } = await loadFixture(fixture);
    await expect(reg.connect(seller).onSeatTransferred(6, seller.address, buyer.address)).to.be.revertedWith("ValidatorsRegistry: caller is not the seat NFT");
  });
});

describe("ValidatorSeatNFT - the seller leaves nothing behind", () => {
  it("an open node-key proposal of the seller is cleared and its key freed; the seller's acceptance flag is cleared after a resale", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, other } = f;
    await enterAndActivate(f, seller);
    const newKey = rnd();
    await reg.connect(seller).proposeOperator(newKey);
    expect(await reg.operatorReservedBy(newKey)).to.equal(seller.address);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    // the proposal and its reservation are gone; the buyer starts with no proposal
    expect(await reg.pendingOperator(seller.address)).to.equal(ZERO);
    expect(await reg.pendingOperator(buyer.address)).to.equal(ZERO);
    expect(await reg.operatorReservedBy(newKey)).to.equal(ZERO);
    await expect(f.reg.connect(f.verifier).confirmOperatorReady(seller.address, newKey, HASH)).to.be.revertedWith("ValidatorsRegistry: no open proposal");
    // the freed key can be claimed by the buyer in a fresh proposal
    await reg.connect(buyer).proposeOperator(newKey);
    // resale: the first buyer's pending acceptance flag does not survive on the seller side
    expect(await reg.seatTransferPending(buyer.address)).to.equal(true);
    await nft.connect(buyer).transferFrom(buyer.address, other.address, 6);
    expect(await reg.seatTransferPending(buyer.address)).to.equal(false);
    expect(await reg.seatAcceptDeadline(buyer.address)).to.equal(0);
    expect(await reg.seatTransferPending(other.address)).to.equal(true);
    expect(await reg.pendingOperator(buyer.address)).to.equal(ZERO);
    await expect(reg.connect(buyer).acceptSeatTransfer()).to.be.revertedWith("ValidatorsRegistry: no pending seat transfer");
  });
});
