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
const AGR = ethers.id("signed validators agreement v1"); // hash of the signed agreement document (any non-zero bytes32)
const NOT_ACCEPTED = "ValidatorsRegistry: buyer has not accepted the validators' agreement for this seat";

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
    // an approved operator moves the token, but the BUYER must still have accepted the agreement for this seat
    await expect(nft.connect(other).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await nft.connect(other).transferFrom(seller.address, buyer.address, 6);
    expect(await nft.ownerOf(6)).to.equal(buyer.address);
    expect(await nft.getApproved(6)).to.equal(ZERO);
    expect((await reg.validators(buyer.address)).lockedStake).to.equal(E("500000"));
  });
});

describe("ValidatorSeatNFT - selling a seat moves the validator record", () => {
  it("an Active seat STAYS Active: collateral, operator and place in the set move to the buyer at once; the buyer is a new voter; the acceptance made beforehand is consumed", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    const op = await enterAndActivate(f, seller);
    expect(await reg.getValidators()).to.include(op);
    const seq = await reg.activationSeq(seller.address);
    const nonceBefore = await reg.statusNonce();
    const ownersBefore = await reg.getActiveOwners();
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(6);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.emit(reg, "SeatTransferred").withArgs(6, seller.address, buyer.address, ST.Active);

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

    // the acceptance was consumed by the transfer; there is no post-transfer pending record any more
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    await expect(reg.connect(buyer).revokeSeatAcceptance()).to.be.revertedWith("ValidatorsRegistry: no acceptance recorded");
  });

  it("the seller can never return; the buyer starts with no history of its own", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, price } = f;
    await enterAndActivate(f, seller);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    await expect(reg.connect(seller).requestMembership(rnd(), { value: price })).to.be.revertedWith("ValidatorsRegistry: this address has exited before and may not rejoin");
  });

  it("a Probation seat can be sold too (with the buyer's prior acceptance); the buyer is activated by the Verifier after the probation wait", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, verifier, seller, buyer, price } = f;
    await reg.connect(seller).requestMembership(rnd(), { value: price });
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
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
    // every buyer below HAS accepted (so each failure is about its own rule); the identity/operator rules come before the acceptance check
    await reg.connect(stranger).acceptSeatAgreement(6, AGR);
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
    await reg.connect(other).acceptSeatAgreement(6, AGR);
    await expect(nft.connect(seller).transferFrom(seller.address, other.address, 6)).to.be.revertedWith("ValidatorsRegistry: buyer was a validator before");
  });

  it("blocked while a penalty case is open", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, verifier, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await reg.connect(verifier).recordSuspension(seller.address, HASH); // Demoted with a pending slash decision
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
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
  it("an open node-key proposal of the seller is cleared and its key freed; an acceptance the seller once recorded as a buyer is cleared; the buyer's acceptance is consumed at every resale", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, other } = f;
    await reg.connect(seller).acceptSeatAgreement(1, AGR); // the seller once accepted seat 1 as a would-be buyer, then entered another way
    await enterAndActivate(f, seller);
    expect(await reg.seatAcceptedFor(seller.address)).to.equal(1);
    const newKey = rnd();
    await reg.connect(seller).proposeOperator(newKey);
    expect(await reg.operatorReservedBy(newKey)).to.equal(seller.address);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    expect(await reg.seatAcceptedFor(seller.address)).to.equal(0);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    // the proposal and its reservation are gone; the buyer starts with no proposal
    expect(await reg.pendingOperator(seller.address)).to.equal(ZERO);
    expect(await reg.pendingOperator(buyer.address)).to.equal(ZERO);
    expect(await reg.operatorReservedBy(newKey)).to.equal(ZERO);
    await expect(f.reg.connect(f.verifier).confirmOperatorReady(seller.address, newKey, HASH)).to.be.revertedWith("ValidatorsRegistry: no open proposal");
    // the freed key can be claimed by the buyer in a fresh proposal
    await reg.connect(buyer).proposeOperator(newKey);
    // resale: the second buyer needs its own acceptance; nothing is left on the first buyer's side
    await expect(nft.connect(buyer).transferFrom(buyer.address, other.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    await reg.connect(other).acceptSeatAgreement(6, AGR);
    await nft.connect(buyer).transferFrom(buyer.address, other.address, 6);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    expect(await reg.seatAcceptedFor(other.address)).to.equal(0);
    expect(await reg.pendingOperator(buyer.address)).to.equal(ZERO);
    expect(await nft.ownerOf(6)).to.equal(other.address);
  });
});

describe("ValidatorSeatNFT - the buyer must accept the validators' agreement BEFORE the transfer (a gate)", () => {
  it("without a recorded acceptance the transfer reverts and nothing moves (transferFrom and safeTransferFrom)", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    const op = await enterAndActivate(f, seller);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    await expect(nft.connect(seller)["safeTransferFrom(address,address,uint256)"](seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    // the seat is still the seller's, still Active with its collateral and node key; the buyer is nobody
    expect(await nft.ownerOf(6)).to.equal(seller.address);
    expect(await nft.balanceOf(buyer.address)).to.equal(0);
    expect((await reg.validators(seller.address)).status).to.equal(ST.Active);
    expect((await reg.validators(seller.address)).lockedStake).to.equal(E("500000"));
    expect((await reg.validators(buyer.address)).status).to.equal(ST.None);
    expect(await reg.operatorOf(seller.address)).to.equal(op);
    expect(await reg.permanentlyExited(seller.address)).to.equal(false);
  });

  it("the happy path: accept (own key, before) -> transfer -> the buyer owns an Active seat and the acceptance is spent; both events are emitted", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await expect(reg.connect(buyer).acceptSeatAgreement(6, AGR)).to.emit(reg, "SeatAgreementAccepted").withArgs(buyer.address, 6, AGR);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(6);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.emit(nft, "Transfer").withArgs(seller.address, buyer.address, 6);
    expect(await nft.ownerOf(6)).to.equal(buyer.address);
    expect((await reg.validators(buyer.address)).status).to.equal(ST.Active);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    // the removed post-transfer pending mechanism no longer exists
    for (const gone of ["seatTransferPending", "seatAcceptDeadline", "SEAT_ACCEPT_WINDOW", "acceptSeatTransfer"]) {
      expect(reg.interface.getFunction(gone)).to.equal(null);
    }
    expect(reg.interface.getEvent("SeatTransferAccepted")).to.equal(null);
  });

  it("an acceptance for a DIFFERENT seat does not work (the buyer accepted seat 6; seat 7 and seat 1 cannot be moved to it), and accepting another seat replaces the earlier acceptance", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, other, founders } = f;
    await enterAndActivate(f, seller); // seat 6
    await enterAndActivate(f, other); // seat 7
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await expect(nft.connect(other).transferFrom(other.address, buyer.address, 7)).to.be.revertedWith(NOT_ACCEPTED);
    // a founder's seat (1) is gated in the same way
    await expect(nft.connect(founders[1]).transferFrom(founders[1].address, buyer.address, 2)).to.be.revertedWith(NOT_ACCEPTED);
    // replacing: the buyer now accepts seat 7 instead of 6
    await reg.connect(buyer).acceptSeatAgreement(7, AGR);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(7);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    await nft.connect(other).transferFrom(other.address, buyer.address, 7);
    expect(await nft.ownerOf(7)).to.equal(buyer.address);
    expect(await nft.ownerOf(6)).to.equal(seller.address); // seat 6 stayed with its seller
  });

  it("an acceptance by a DIFFERENT address does not work: the seller, a third party or another would-be buyer cannot accept on the buyer's behalf", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, other } = f;
    await enterAndActivate(f, seller);
    await reg.connect(other).acceptSeatAgreement(6, AGR); // somebody else's acceptance of the same seat
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
    // the acceptance is personal: it lets the seat go to `other` only
    await nft.connect(seller).transferFrom(seller.address, other.address, 6);
    expect(await nft.ownerOf(6)).to.equal(other.address);
  });

  it("the acceptance is CONSUMED only by a successful transfer: a transfer that fails another rule leaves it recorded, a successful one clears it", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, idr, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await idr.setVerified(buyer.address, false);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith("ValidatorsRegistry: buyer identity not fully verified");
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(6); // the revert rolled the consumption back
    await idr.setVerified(buyer.address, true);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    // spent: nothing is left that could carry another seat to the same address
    await expect(reg.connect(buyer).revokeSeatAcceptance()).to.be.revertedWith("ValidatorsRegistry: no acceptance recorded");
  });

  it("the buyer can withdraw its acceptance; after that the seat cannot be sent to it", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await expect(reg.connect(buyer).revokeSeatAcceptance()).to.emit(reg, "SeatAcceptanceRevoked").withArgs(buyer.address, 6);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.be.revertedWith(NOT_ACCEPTED);
  });

  it("acceptSeatAgreement: only for a seat that exists and is not already the caller's; id 0 and a burned seat are refused", async () => {
    const f = await loadFixture(fixture);
    const { reg, seller, buyer, founders } = f;
    await expect(reg.connect(buyer).acceptSeatAgreement(0, AGR)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
    await expect(reg.connect(buyer).acceptSeatAgreement(99, AGR)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
    await expect(reg.connect(founders[0]).acceptSeatAgreement(1, AGR)).to.be.revertedWith("ValidatorsRegistry: caller already owns this seat");
    await enterAndActivate(f, seller);
    await reg.connect(seller).requestExit(); // the seat is burned
    await expect(reg.connect(buyer).acceptSeatAgreement(6, AGR)).to.be.revertedWith("ValidatorSeatNFT: nonexistent token");
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
  });

  it("a genesis founder's seat is gated like any other (isFounder moves with it); the lottery winner's seat is minted WITHOUT any acceptance, but its resale needs one", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, buyer, other, founders } = f;
    // founders hold seats from genesis with no acceptance on record
    for (const x of founders) expect(await reg.seatAcceptedFor(x.address)).to.equal(0);
    await expect(nft.connect(founders[1]).transferFrom(founders[1].address, buyer.address, 2)).to.be.revertedWith(NOT_ACCEPTED);
    await reg.connect(buyer).acceptSeatAgreement(2, AGR);
    await nft.connect(founders[1]).transferFrom(founders[1].address, buyer.address, 2);
    expect(await reg.isFounder(buyer.address)).to.equal(true);
    expect(await reg.isFounder(founders[1].address)).to.equal(false);
    // lottery path: enterAsLotteryWinner mints the seat; no acceptance is required or recorded
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VALIDATOR_LOTTERY, "0x56BC75E2D63100000"]);
    const lottery = await ethers.getImpersonatedSigner(ADDR.VALIDATOR_LOTTERY);
    await reg.connect(lottery).enterAsLotteryWinner(other.address);
    const id = await nft.seatOf(other.address);
    expect(id).to.equal(6);
    expect(await reg.seatAcceptedFor(other.address)).to.equal(0);
    expect((await reg.validators(other.address)).status).to.equal(ST.Probation);
    const next = f.S[13];
    await f.idr.setVerified(next.address, true);
    await expect(nft.connect(other).transferFrom(other.address, next.address, id)).to.be.revertedWith(NOT_ACCEPTED);
    await reg.connect(next).acceptSeatAgreement(id, AGR);
    await nft.connect(other).transferFrom(other.address, next.address, id);
    expect(await nft.ownerOf(id)).to.equal(next.address);
  });
});

describe("ValidatorSeatNFT - the agreement hash travels with the acceptance into the transfer", () => {
  const AGR2 = ethers.id("signed validators agreement v2");

  it("the hash must be non-zero; it is stored with the acceptance, emitted, and revoke or replace handle it with the seat id", async () => {
    const f = await loadFixture(fixture);
    const { reg, seller, buyer } = f;
    await enterAndActivate(f, seller);
    await expect(reg.connect(buyer).acceptSeatAgreement(6, ethers.ZeroHash)).to.be.revertedWith("ValidatorsRegistry: empty agreement hash");
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    expect(await reg.seatAcceptedAgreementHash(buyer.address)).to.equal(AGR);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR2); // a new acceptance replaces seat AND hash
    expect(await reg.seatAcceptedAgreementHash(buyer.address)).to.equal(AGR2);
    await reg.connect(buyer).revokeSeatAcceptance();
    expect(await reg.seatAcceptedAgreementHash(buyer.address)).to.equal(ethers.ZeroHash);
    expect(await reg.seatAcceptedFor(buyer.address)).to.equal(0);
  });

  it("the transfer binds the buyer's hash to the seat (readable record + SeatAgreementBound event) and consumes the acceptance; the next sale overwrites it, the events keep the history", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, seller, buyer, other } = f;
    await enterAndActivate(f, seller);
    expect(await reg.seatAgreementHash(6)).to.equal(ethers.ZeroHash); // came by entry: nothing recorded on-chain
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await expect(nft.connect(seller).transferFrom(seller.address, buyer.address, 6)).to.emit(reg, "SeatAgreementBound").withArgs(6, buyer.address, AGR);
    expect(await reg.seatAgreementHash(6)).to.equal(AGR);
    expect(await reg.seatAcceptedAgreementHash(buyer.address)).to.equal(ethers.ZeroHash);
    await reg.connect(other).acceptSeatAgreement(6, AGR2);
    await expect(nft.connect(buyer).transferFrom(buyer.address, other.address, 6)).to.emit(reg, "SeatAgreementBound").withArgs(6, other.address, AGR2);
    expect(await reg.seatAgreementHash(6)).to.equal(AGR2);
    const bound = await reg.queryFilter(reg.filters.SeatAgreementBound(6));
    expect(bound.map((e) => e.args.agreementHash)).to.deep.equal([AGR, AGR2]);
  });

  it("a transfer that fails leaves the recorded hash untouched and the seat's previous hash in place", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, idr, seller, buyer, other } = f;
    await enterAndActivate(f, seller);
    await reg.connect(buyer).acceptSeatAgreement(6, AGR);
    await nft.connect(seller).transferFrom(seller.address, buyer.address, 6);
    await idr.setVerified(other.address, false);
    await reg.connect(other).acceptSeatAgreement(6, AGR2);
    await expect(nft.connect(buyer).transferFrom(buyer.address, other.address, 6)).to.be.revertedWith("ValidatorsRegistry: buyer identity not fully verified");
    expect(await reg.seatAgreementHash(6)).to.equal(AGR);
    expect(await reg.seatAcceptedAgreementHash(other.address)).to.equal(AGR2);
  });
});
