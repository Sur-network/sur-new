// Lost owner key (audit A4; agreement 5-5, change proposal 32 answer 6): the whole seat moves to the person's new address after an
// authorised identity migration. Authorisation = TWO keys: the identity oracle ran IdentityRegistry.migrateIdentity(old, new) AND the
// Verifier calls ValidatorsRegistry.migrateSeat(old, new). Real IdentityRegistry; the Distributor is the MockDistributor (the real
// Distributor.migrateClaimable is covered in DeferredClaim.test.js).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, setTime, now, DAY, agr } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const HASH = ethers.id("evidence");
const AGR = ethers.id("signed validators agreement v1");
const ORACLE = "0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9"; // SurAddresses.IDENTITY_ORACLE
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const rnd = () => ethers.Wallet.createRandom().address;
const ST = { None: 0, Probation: 1, Active: 2, Demoted: 3, Exiting: 4, RemovedInRecovery: 5, SelfSuspended: 6 };

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  const dist = await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  // the real IdentityRegistry (its only initial storage is the oracle in slot 1; same recipe as IdentityRegistry.test.js)
  const tmp = await (await ethers.getContractFactory("IdentityRegistry")).deploy();
  const art = await hre.artifacts.readArtifact("IdentityRegistry");
  await hre.network.provider.send("hardhat_setCode", [ADDR.IDENTITY_REGISTRY, art.deployedBytecode]);
  await hre.network.provider.send("hardhat_setStorageAt", [ADDR.IDENTITY_REGISTRY, "0x1", await ethers.provider.getStorage(await tmp.getAddress(), 1)]);
  const idr = await ethers.getContractAt("IdentityRegistry", ADDR.IDENTITY_REGISTRY);
  await hre.network.provider.send("hardhat_setBalance", [ORACLE, "0x56BC75E2D63100000"]);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);

  const t0 = await now();
  const founders = S.slice(0, 5);
  const op0 = rnd();
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY, [founders[0].address, op0, founders.slice(1).map((s) => s.address), t0]);
  const nft = await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [founders.map((s) => s.address), t0]);
  await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
  const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
  for (const x of founders.slice(1)) {
    await reg.connect(x).setOperator(rnd());
    await reg.connect(verifier).recordActivation(x.address, HASH);
  }
  const people = { owner: S[10], fresh: S[11], other: S[12], third: S[13] };
  for (const b of Object.values(people)) await hre.network.provider.send("hardhat_setBalance", [b.address, "0x" + E("2000000").toString(16)]);
  const price = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  return { S, reg, nft, idr, oracle, dist, verifier, founders, op0, price, ...people };
}

async function verifyAll(f, who) {
  await f.idr.connect(who).registerIdentity(0, "Person");
  const o = f.idr.connect(f.oracle);
  await o.setKycVerified(who.address, true, ethers.id("c"));
  await o.setPhoneVerified(who.address, true);
  await o.setTelegramVerified(who.address, true);
  await o.setBaleVerified(who.address, true);
  await o.setEmailVerified(who.address, true);
}
/// `who` enters as a paying validator (identity first), waits out probation and is activated.
async function enterActive(f, who) {
  await verifyAll(f, who);
  const op = rnd();
  await f.reg.connect(who).requestMembership(op, agr(), { value: f.price });
  await increaseTime(8 * DAY);
  await f.reg.connect(f.verifier).recordActivation(who.address, HASH);
  return op;
}
const migrateId = (f, from, to) => f.idr.connect(f.oracle).migrateIdentity(from.address ?? from, to.address ?? to);
const migrateSeat = (f, from, to, signer) => f.reg.connect(signer ?? f.verifier).migrateSeat(from.address ?? from, to.address ?? to);

describe("Lost owner key - migrateSeat moves the whole seat to the new address of the same person", () => {
  it("an Active paying seat: record, collateral, operator link, active-set place, NFT, vote (new voter) and exit rights move; the old address is closed for ever", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, idr, owner, fresh, dist } = f;
    const op = await enterActive(f, owner);
    const seatId = await nft.seatOf(owner.address);
    const ownersBefore = await reg.getActiveOwners();
    const seq = await reg.activationSeq(owner.address);
    const nonceBefore = await reg.statusNonce();
    const epochBefore = await reg.membershipEpoch(owner.address);
    const newKey = rnd();
    await reg.connect(owner).proposeOperator(newKey); // an open node-key proposal of the lost key
    expect(await reg.operatorReservedBy(newKey)).to.equal(owner.address);

    await migrateId(f, owner, fresh); // step 1: the identity oracle
    expect(await idr.migratedTo(owner.address)).to.equal(fresh.address);
    await expect(migrateSeat(f, owner, fresh)).to.emit(reg, "SeatMigrated").withArgs(seatId, owner.address, fresh.address, ST.Active); // step 2: the Verifier

    const v = await reg.validators(fresh.address);
    expect(v.status).to.equal(ST.Active);
    expect(v.lockedStake).to.equal(E("500000"));
    expect(v.isPaidEntrant).to.equal(true);
    expect((await reg.validators(owner.address)).status).to.equal(ST.None);
    expect(await reg.operatorOf(fresh.address)).to.equal(op);
    expect(await reg.ownerOfOperator(op)).to.equal(fresh.address);
    expect(await reg.operatorOf(owner.address)).to.equal(ZERO);
    expect(await reg.activationSeq(fresh.address)).to.equal(seq);
    expect(await reg.everActivated(fresh.address)).to.equal(true);
    // the node keeps validating at the same place
    const ownersAfter = await reg.getActiveOwners();
    expect(ownersAfter.indexOf(fresh.address)).to.equal(ownersBefore.indexOf(owner.address));
    expect(await reg.getValidators()).to.include(op);
    expect(await reg.isValidator(fresh.address)).to.equal(true);
    expect(await reg.isValidator(owner.address)).to.equal(false);
    // the NFT moved with it
    expect(await nft.ownerOf(seatId)).to.equal(fresh.address);
    expect(await nft.seatOf(fresh.address)).to.equal(seatId);
    expect(await nft.seatOf(owner.address)).to.equal(0);
    expect(await nft.balanceOf(owner.address)).to.equal(0);
    // the vote: the new address is a new voter from now; the old one's vote is gone
    expect(await reg.wasActiveAt(fresh.address, nonceBefore)).to.equal(false);
    expect(await reg.wasActiveAt(fresh.address, await reg.statusNonce())).to.equal(true);
    expect(await reg.wasActiveAt(owner.address, await reg.statusNonce())).to.equal(false);
    // the old address: permanent ban and board authority over; the NEW one is NOT treated as exited
    expect(await reg.permanentlyExited(owner.address)).to.equal(true);
    expect(await reg.membershipEpoch(owner.address)).to.equal(epochBefore + 1n);
    expect(await reg.permanentlyExited(fresh.address)).to.equal(false);
    // the lost key's leftovers are gone; the new owner can make its own proposal
    expect(await reg.pendingOperator(owner.address)).to.equal(ZERO);
    expect(await reg.operatorReservedBy(newKey)).to.equal(ZERO);
    await reg.connect(fresh).proposeOperator(newKey);
    // what the Distributor owes the old owner was asked to move
    expect(await dist.lastMigrateFrom()).to.equal(owner.address);
    expect(await dist.lastMigrateTo()).to.equal(fresh.address);
    // the old address can never become a validator again (its identity is burned too)
    await expect(reg.connect(owner).requestMembership(rnd(), agr(), { value: f.price })).to.be.revertedWith("ValidatorsRegistry: this address has exited before and may not rejoin");
    // and the new owner holds the exit right and the collateral
    const before = await ethers.provider.getBalance(fresh.address);
    await reg.connect(fresh).requestExit();
    await increaseTime(8 * DAY);
    await reg.connect(fresh).withdrawStake();
    expect((await ethers.provider.getBalance(fresh.address)) - before).to.be.gt(E("499999"));
  });

  it("only the Verifier can call it; the identity oracle, the lost key and a stranger cannot; a second call is refused", async () => {
    const f = await loadFixture(fixture);
    const { reg, owner, fresh, oracle, S } = f;
    await enterActive(f, owner);
    await migrateId(f, owner, fresh);
    const msg = "ValidatorsRegistry: caller is not the verifier";
    await expect(migrateSeat(f, owner, fresh, S[3])).to.be.revertedWith(msg);
    await expect(migrateSeat(f, owner, fresh, owner)).to.be.revertedWith(msg);
    await expect(migrateSeat(f, owner, fresh, fresh)).to.be.revertedWith(msg);
    await expect(migrateSeat(f, owner, fresh, oracle)).to.be.revertedWith(msg);
    await migrateSeat(f, owner, fresh);
    await expect(migrateSeat(f, owner, fresh)).to.be.revertedWith("ValidatorsRegistry: seat cannot be migrated in this status");
  });

  it("the Verifier alone is not enough: the identity must have been migrated to EXACTLY that address by the identity oracle", async () => {
    const f = await loadFixture(fixture);
    const { reg, owner, fresh, other } = f;
    await enterActive(f, owner);
    const notMigrated = "ValidatorsRegistry: the identity of the old owner was not migrated to this address";
    await expect(migrateSeat(f, owner, fresh)).to.be.revertedWith(notMigrated); // no identity migration at all
    await verifyAll(f, other); // a verified address of somebody else does not help
    await expect(migrateSeat(f, owner, other)).to.be.revertedWith(notMigrated);
    await migrateId(f, owner, fresh);
    await expect(migrateSeat(f, owner, other)).to.be.revertedWith(notMigrated); // migrated to `fresh`, not to `other`
    await expect(migrateSeat(f, owner, ZERO)).to.be.revertedWith("ValidatorsRegistry: bad new owner");
    await expect(migrateSeat(f, owner, owner)).to.be.revertedWith("ValidatorsRegistry: bad new owner");
    await migrateSeat(f, owner, fresh);
    expect((await reg.validators(fresh.address)).status).to.equal(ST.Active);
  });

  it("the new address must satisfy the owner rules: fully verified, plain wallet (EOA), never a validator, not an operator key", async () => {
    const f = await loadFixture(fixture);
    const { reg, idr, oracle, owner, fresh, other, third, op0 } = f;
    await enterActive(f, owner);
    // not fully verified: the oracle takes a flag away from the new address after the identity migration
    await migrateId(f, owner, fresh);
    await idr.connect(oracle).setPhoneVerified(fresh.address, false);
    await expect(migrateSeat(f, owner, fresh)).to.be.revertedWith("ValidatorsRegistry: new owner identity not fully verified");
    await idr.connect(oracle).setPhoneVerified(fresh.address, true);

    // a contract address: refused by the EOA rule
    const f2 = await loadFixture(fixture);
    const c = await (await ethers.getContractFactory("MockSeatOwner")).deploy(ZERO, ZERO);
    await enterActive(f2, f2.owner);
    await migrateId(f2, f2.owner, await c.getAddress());
    await expect(migrateSeat(f2, f2.owner, await c.getAddress())).to.be.revertedWith("ValidatorsRegistry: a seat owner must be a plain wallet (EOA)");

    // an existing validator / a node key of another owner
    const f3 = await loadFixture(fixture);
    await enterActive(f3, f3.owner);
    await migrateId(f3, f3.owner, f3.founders[2]);
    await expect(migrateSeat(f3, f3.owner, f3.founders[2])).to.be.revertedWith("ValidatorsRegistry: new owner was a validator before");
    const f4 = await loadFixture(fixture);
    await enterActive(f4, f4.owner);
    await migrateId(f4, f4.owner, f4.op0);
    await expect(migrateSeat(f4, f4.owner, f4.op0)).to.be.revertedWith("ValidatorsRegistry: new owner is an operator key");

    // an ex-validator (exited) address
    const f5 = await loadFixture(fixture);
    await enterActive(f5, f5.owner);
    await enterActive(f5, f5.other);
    await f5.reg.connect(f5.other).requestExit();
    await migrateId(f5, f5.owner, f5.other); // migrateIdentity itself accepts any address that was not burned
    await expect(migrateSeat(f5, f5.owner, f5.other)).to.be.revertedWith("ValidatorsRegistry: new owner was a validator before");
  });

  it("not for an Exiting seat (burned NFT) and not while a penalty case is open", async () => {
    const f = await loadFixture(fixture);
    const { reg, owner, fresh, other, verifier } = f;
    await enterActive(f, owner);
    await enterActive(f, other);
    await reg.connect(owner).requestExit();
    await migrateId(f, owner, fresh);
    await expect(migrateSeat(f, owner, fresh)).to.be.revertedWith("ValidatorsRegistry: seat cannot be migrated in this status");
    // penalty case: a suspension opens a pending slash decision
    const f2 = await loadFixture(fixture);
    await enterActive(f2, f2.owner);
    await f2.reg.connect(f2.verifier).recordSuspension(f2.owner.address, HASH);
    await migrateId(f2, f2.owner, f2.fresh);
    await expect(migrateSeat(f2, f2.owner, f2.fresh)).to.be.revertedWith("ValidatorsRegistry: open penalty case - migration blocked");
  });

  it("a Probation seat, a founder seat and a self-suspended seat with an open resume request all move; founder flag and resume request follow the person", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, fresh, other, third, founders, verifier, price } = f;
    // Probation (never activated)
    await verifyAll(f, owner);
    await reg.connect(owner).requestMembership(rnd(), agr(), { value: price });
    await migrateId(f, owner, fresh);
    await migrateSeat(f, owner, fresh);
    expect((await reg.validators(fresh.address)).status).to.equal(ST.Probation);
    expect(await nft.ownerOf(6)).to.equal(fresh.address);

    // a genesis founder (Active) with an identity
    await verifyAll(f, founders[1]);
    await migrateId(f, founders[1], other);
    await migrateSeat(f, founders[1], other);
    expect(await reg.isFounder(other.address)).to.equal(true);
    expect(await reg.isFounder(founders[1].address)).to.equal(false);
    expect((await reg.validators(other.address)).isPaidEntrant).to.equal(false);
    expect(await nft.ownerOf(2)).to.equal(other.address);
    expect(await reg.permanentlyExited(other.address)).to.equal(false);

    // self-suspended with a resume request (a paying validator, not a board member): the request follows the person and the
    // Verifier can resume the NEW address
    const target = f.S[14];
    await enterActive(f, third);
    await reg.connect(third).selfSuspend();
    await reg.connect(third).requestResume();
    await migrateId(f, third, target);
    await migrateSeat(f, third, target);
    expect((await reg.validators(target.address)).status).to.equal(ST.SelfSuspended);
    expect(await reg.resumeRequested(target.address)).to.equal(true);
    expect(await reg.resumeRequested(third.address)).to.equal(false);
    await reg.connect(verifier).recordResume(target.address, HASH);
    expect((await reg.validators(target.address)).status).to.equal(ST.Active);
  });

  it("a seat bought with an agreement hash keeps that hash when it is migrated (same person, same agreement)", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, fresh, other } = f;
    await enterActive(f, owner);
    await verifyAll(f, other);
    await reg.connect(other).acceptSeatAgreement(6, AGR);
    await nft.connect(owner).transferFrom(owner.address, other.address, 6);
    expect(await reg.seatAgreementHash(6)).to.equal(AGR);
    await migrateId(f, other, fresh);
    await migrateSeat(f, other, fresh);
    expect(await nft.ownerOf(6)).to.equal(fresh.address);
    expect(await reg.seatAgreementHash(6)).to.equal(AGR);
  });
});

describe("Lost owner key - a stale seat-purchase acceptance of the new owner does not survive the migration", () => {
  const AGR2 = ethers.id("another signed agreement");
  it("the new owner's acceptance for ANOTHER seat is cleared (event SeatAcceptanceRevoked); everything else is untouched", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, fresh, other, third, founders } = f;
    await enterActive(f, owner);
    const seatId = await nft.seatOf(owner.address);
    // the future new owner had recorded an acceptance as a prospective buyer of a founder seat (seat 1); two other people did too
    await reg.connect(fresh).acceptSeatAgreement(1, AGR);
    await reg.connect(other).acceptSeatAgreement(2, AGR2);
    await reg.connect(owner).acceptSeatAgreement(3, AGR2); // the old owner's own stale one (cleared by the existing rule)
    expect(await reg.seatAcceptedFor(fresh.address)).to.equal(1n);
    expect(await reg.seatAcceptedAgreementHash(fresh.address)).to.equal(AGR);
    const hashBefore = await reg.seatAgreementHash(seatId);

    await migrateId(f, owner, fresh);
    await expect(migrateSeat(f, owner, fresh))
      .to.emit(reg, "SeatAcceptanceRevoked").withArgs(fresh.address, 1n)
      .and.to.emit(reg, "SeatMigrated").withArgs(seatId, owner.address, fresh.address, ST.Active);

    // the new owner's acceptance is gone, and so is the old owner's
    expect(await reg.seatAcceptedFor(fresh.address)).to.equal(0n);
    expect(await reg.seatAcceptedAgreementHash(fresh.address)).to.equal(ethers.ZeroHash);
    expect(await reg.seatAcceptedFor(owner.address)).to.equal(0n);
    expect(await reg.seatAcceptedAgreementHash(owner.address)).to.equal(ethers.ZeroHash);
    // nothing else changed: another person's acceptance stays, the seat keeps its agreement hash, the seat moved
    expect(await reg.seatAcceptedFor(other.address)).to.equal(2n);
    expect(await reg.seatAcceptedAgreementHash(other.address)).to.equal(AGR2);
    expect(await reg.seatAgreementHash(seatId)).to.equal(hashBefore);
    expect(await nft.ownerOf(seatId)).to.equal(fresh.address);
    expect(await nft.ownerOf(1)).to.equal(founders[0].address);
    expect(await reg.seatAcceptedFor(third.address)).to.equal(0n);
    // the cleared acceptance can no longer be consumed: seat 1 cannot reach the new owner by a transfer
    await expect(nft.connect(founders[0]).transferFrom(founders[0].address, fresh.address, 1)).to.be.reverted;
  });

  it("a migration of a new owner with NO acceptance emits no SeatAcceptanceRevoked", async () => {
    const f = await loadFixture(fixture);
    const { reg, owner, fresh } = f;
    await enterActive(f, owner);
    await migrateId(f, owner, fresh);
    await expect(migrateSeat(f, owner, fresh)).to.not.emit(reg, "SeatAcceptanceRevoked");
    expect(await reg.seatAcceptedFor(fresh.address)).to.equal(0n);
  });

  it("a SALE leaves nothing stale: the buyer's acceptance is consumed by the transfer (no revoke event), the old owner's is cleared", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, other, third } = f;
    await enterActive(f, owner);
    await verifyAll(f, other);
    const seatId = await nft.seatOf(owner.address);
    await reg.connect(other).acceptSeatAgreement(seatId, AGR);
    await reg.connect(owner).acceptSeatAgreement(2, AGR2); // the seller's own acceptance for another seat
    await reg.connect(third).acceptSeatAgreement(2, AGR2); // an unrelated third party
    await expect(nft.connect(owner).transferFrom(owner.address, other.address, seatId))
      .to.emit(reg, "SeatAgreementBound").withArgs(seatId, other.address, AGR)
      .and.to.not.emit(reg, "SeatAcceptanceRevoked");
    expect(await reg.seatAcceptedFor(other.address)).to.equal(0n);
    expect(await reg.seatAcceptedAgreementHash(other.address)).to.equal(ethers.ZeroHash);
    expect(await reg.seatAcceptedFor(owner.address)).to.equal(0n);
    expect(await reg.seatAcceptedAgreementHash(owner.address)).to.equal(ethers.ZeroHash);
    expect(await reg.seatAcceptedFor(third.address)).to.equal(2n);
    expect(await reg.seatAgreementHash(seatId)).to.equal(AGR);
  });
});

describe("ValidatorSeatNFT.reassignSeat and the Distributor hook are Registry-only", () => {
  it("nobody but the Registry can reassign a seat", async () => {
    const { nft, founders, fresh } = await loadFixture(fixture);
    await expect(nft.connect(founders[0]).reassignSeat(founders[0].address, fresh.address)).to.be.revertedWith("ValidatorSeatNFT: only ValidatorsRegistry");
  });
});

describe("Lost owner key - the seat's agreement hash is kept by migrateSeat (same person, same agreement)", () => {
  const ENTRY = ethers.id("signed validators agreement - direct entry");
  const ACCEPTED = ethers.id("signed validators agreement - buyer");

  it("a direct entrant's hash (set by requestMembership) is still the seat's record after the migration; no new agreement event is emitted", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, fresh } = f;
    await verifyAll(f, owner);
    await reg.connect(owner).requestMembership(rnd(), ENTRY, { value: f.price });
    const seatId = await nft.seatOf(owner.address);
    expect(await reg.seatAgreementHash(seatId)).to.equal(ENTRY);
    await increaseTime(8 * DAY);
    await reg.connect(f.verifier).recordActivation(owner.address, HASH);
    await migrateId(f, owner, fresh);
    const tx = migrateSeat(f, owner, fresh);
    await expect(tx).to.emit(reg, "SeatMigrated").and.not.to.emit(reg, "EntryAgreementRecorded").and.not.to.emit(reg, "SeatAgreementBound");
    expect(await nft.ownerOf(seatId)).to.equal(fresh.address);
    expect(await reg.seatAgreementHash(seatId)).to.equal(ENTRY);
  });

  it("a hash bound by a sale survives a later migration of that seat too", async () => {
    const f = await loadFixture(fixture);
    const { reg, nft, owner, fresh, other } = f;
    await verifyAll(f, owner);
    await reg.connect(owner).requestMembership(rnd(), ENTRY, { value: f.price });
    const seatId = await nft.seatOf(owner.address);
    await verifyAll(f, other);
    await reg.connect(other).acceptSeatAgreement(seatId, ACCEPTED);
    await nft.connect(owner).transferFrom(owner.address, other.address, seatId);
    expect(await reg.seatAgreementHash(seatId)).to.equal(ACCEPTED);
    await migrateId(f, other, fresh);
    await migrateSeat(f, other, fresh);
    expect(await nft.ownerOf(seatId)).to.equal(fresh.address);
    expect(await reg.seatAgreementHash(seatId)).to.equal(ACCEPTED);
  });
});
