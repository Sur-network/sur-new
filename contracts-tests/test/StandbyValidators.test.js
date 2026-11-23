// StandbyValidators: the prepared validator list for emergency consensus recovery (written only by FoundationDAO).
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, setTime, increaseTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const rnd = () => ethers.Wallet.createRandom().address;
const asc = (list) => [...list].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const t0 = await now();
  const founders = S.slice(0, 7);
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY,
    [founders[0].address, rnd(), founders.slice(1).map((s) => s.address), t0]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [founders.map((f) => f.address)]);
  await deployAtFixed("ValidatorsBoard", "ValidatorsBoard_GenesisSeed", ADDR.VALIDATORS_BOARD, [S.slice(0, 5).map((s) => s.address), t0]);
  const sb = await deployAtFixed("StandbyValidators", "StandbyValidators", ADDR.STANDBY_VALIDATORS, []);
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const daoBoard = S.slice(12, 17);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [daoBoard.map((s) => s.address), S[17].address, daoBoard[0].address, daoBoard[1].address, S[18].address, t0 + 730 * DAY], E("10"));
  // seats 1..6 (founders[1..6], still Probation) register an operator key each; seat 0 already has one from the seed
  const ops = [await reg.operatorOf(founders[0].address)];
  for (const f of founders.slice(1)) {
    const op = rnd();
    await reg.connect(f).setOperator(op);
    ops.push(op);
  }
  return { S, reg, sb, dao, daoBoard, founders, ops };
}

async function asDao() {
  await hre.network.provider.send("hardhat_setBalance", [ADDR.FOUNDATION_DAO, "0x56BC75E2D63100000"]);
  return ethers.getImpersonatedSigner(ADDR.FOUNDATION_DAO);
}

describe("StandbyValidators - the contract", () => {
  it("the bare contract (no genesis seed here; the real genesis seeds the first validator) starts empty and not ready; only FoundationDAO may write; constants are fixed", async () => {
    const { sb, S, ops } = await loadFixture(fixture);
    expect(await sb.getValidators()).to.deep.equal([]);
    expect(await sb.version()).to.equal(0);
    expect(await sb.updatedAt()).to.equal(0);
    expect(await sb.memberCount()).to.equal(0);
    expect(await sb.isReady()).to.equal(false);
    expect(await sb.MIN_MEMBERS()).to.equal(1);
    expect(await sb.MAX_MEMBERS()).to.equal(100);
    expect(await sb.FOUNDATION()).to.equal(ADDR.FOUNDATION_DAO);
    await expect(sb.connect(S[5]).setStandby(asc(ops.slice(0, 4)))).to.be.revertedWith("StandbyValidators: only FoundationDAO");
    await expect(sb.connect(S[0]).setStandby(asc(ops.slice(0, 4)))).to.be.revertedWith("StandbyValidators: only FoundationDAO");
  });

  it("rejects a bad list: empty, too many, not ascending, duplicate, zero, not an operator key, an owner address", async () => {
    const { sb, ops, founders } = await loadFixture(fixture);
    const dao = await asDao();
    const four = asc(ops.slice(0, 4));
    await expect(sb.connect(dao).setStandby([])).to.be.revertedWith("StandbyValidators: too few members");
    const many = asc(Array.from({ length: 101 }, rnd));
    await expect(sb.connect(dao).setStandby(many)).to.be.revertedWith("StandbyValidators: too many members");
    const msg = "StandbyValidators: members must be strictly ascending and non-zero";
    await expect(sb.connect(dao).setStandby([four[1], four[0], four[2], four[3]])).to.be.revertedWith(msg);
    await expect(sb.connect(dao).setStandby([four[0], four[0], four[2], four[3]])).to.be.revertedWith(msg);
    await expect(sb.connect(dao).setStandby([ZERO, four[0], four[1], four[2]])).to.be.revertedWith(msg);
    const notOp = "StandbyValidators: not the current operator key of a registered seat";
    await expect(sb.connect(dao).setStandby(asc([four[0], four[1], four[2], rnd()]))).to.be.revertedWith(notOp);
    // an OWNER address is not a node key
    await expect(sb.connect(dao).setStandby(asc([four[0], four[1], four[2], founders[6].address]))).to.be.revertedWith(notOp);
    expect(await sb.version()).to.equal(0);
  });

  it("accepts a single member (the genesis case) and then a bigger list, replacing the whole list each time", async () => {
    const { sb, ops } = await loadFixture(fixture);
    const dao = await asDao();
    await expect(sb.connect(dao).setStandby([ops[0]])).to.emit(sb, "StandbyUpdated").withArgs(1, [ops[0]]);
    expect(await sb.getValidators()).to.deep.equal([ops[0]]);
    expect(await sb.isReady()).to.equal(true);
    const three = asc(ops.slice(0, 3));
    await sb.connect(dao).setStandby(three);
    expect(await sb.getValidators()).to.deep.equal(three);
    expect(await sb.version()).to.equal(2);
  });

  it("accepts four current operator keys: stores them, bumps the version, emits, becomes ready; the list is replaced as a whole", async () => {
    const { sb, ops } = await loadFixture(fixture);
    const dao = await asDao();
    const first = asc(ops.slice(0, 4));
    const tx = await sb.connect(dao).setStandby(first);
    await expect(tx).to.emit(sb, "StandbyUpdated").withArgs(1, first);
    expect(await sb.getValidators()).to.deep.equal(first);
    expect(await sb.version()).to.equal(1);
    expect(await sb.updatedAt()).to.equal(await now());
    expect(await sb.memberCount()).to.equal(4);
    expect(await sb.isReady()).to.equal(true);
    expect(await sb.staleMembers()).to.deep.equal([]);
    // a second call replaces the whole list (7 members, shorter later again)
    const all = asc(ops);
    await sb.connect(dao).setStandby(all);
    expect(await sb.getValidators()).to.deep.equal(all);
    expect(await sb.version()).to.equal(2);
    await sb.connect(dao).setStandby(asc(ops.slice(2, 6)));
    expect((await sb.getValidators()).length).to.equal(4);
    expect(await sb.version()).to.equal(3);
  });

  it("a member whose seat changes its node key becomes stale: staleMembers lists it and isReady turns false until the list is refreshed", async () => {
    const { sb, reg, ops, founders } = await loadFixture(fixture);
    const dao = await asDao();
    await sb.connect(dao).setStandby(asc(ops.slice(1, 5)));
    expect(await sb.isReady()).to.equal(true);
    // seat 2 is still in Probation, so its operator key can be swapped at once
    const fresh = rnd();
    await reg.connect(founders[2]).setOperator(fresh);
    expect(await sb.staleMembers()).to.deep.equal([ops[2]]);
    expect(await sb.isReady()).to.equal(false);
    // getValidators() is a plain storage read and still answers (Besu must never see a revert)
    expect((await sb.getValidators()).length).to.equal(4);
    // refresh with the new key
    const refreshed = asc([ops[1], fresh, ops[3], ops[4]]);
    await sb.connect(dao).setStandby(refreshed);
    expect(await sb.staleMembers()).to.deep.equal([]);
    expect(await sb.isReady()).to.equal(true);
    // the old key is no longer a valid member
    await expect(sb.connect(dao).setStandby(asc([ops[1], ops[2], ops[3], ops[4]]))).to.be.revertedWith(
      "StandbyValidators: not the current operator key of a registered seat");
  });
});

describe("StandbyValidators - the member must be the operator of a LIVE seat (audit A5)", () => {
  const notOp = "StandbyValidators: not the current operator key of a registered seat";

  it("an owner that exited (Exiting), withdrew its stake (record deleted) or was removed in a network recovery makes its member stale; setStandby refuses such a key", async () => {
    const { sb, reg, ops, founders } = await loadFixture(fixture);
    const dao = await asDao();
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
    const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
    // live statuses are accepted: ops[0] Active, ops[1..3] Probation founders
    await sb.connect(dao).setStandby(asc(ops.slice(0, 4)));
    expect(await sb.isReady()).to.equal(true);

    // 1) voluntary exit: the key mappings stay (the Registry never frees a key) but the owner is Exiting
    await reg.connect(founders[2]).requestExit();
    expect(await reg.ownerOfOperator(ops[2])).to.equal(founders[2].address); // still mapped
    expect(await sb.staleMembers()).to.deep.equal([ops[2]]);
    expect(await sb.isReady()).to.equal(false);
    await expect(sb.connect(dao).setStandby(asc(ops.slice(0, 4)))).to.be.revertedWith(notOp);

    // 2) after the stake is withdrawn the Registry record is gone (status None): still stale
    await increaseTime(8 * DAY);
    await reg.connect(founders[2]).withdrawStake();
    expect((await reg.validators(founders[2].address)).status).to.equal(0);
    expect(await sb.staleMembers()).to.deep.equal([ops[2]]);

    // 3) removal in a network recovery: needs an Active validator (activate the other founders first)
    for (const f of [founders[1], founders[3], founders[4], founders[5], founders[6]]) await reg.connect(verifier).recordActivation(f.address, ethers.id("e"));
    await reg.connect(verifier).recordRecoveryRemoval(founders[3].address, await now(), ethers.id("e"));
    expect((await reg.validators(founders[3].address)).status).to.equal(5); // RemovedInRecovery
    expect(await reg.ownerOfOperator(ops[3])).to.equal(founders[3].address);
    expect(asc(await sb.staleMembers())).to.deep.equal(asc([ops[2], ops[3]]));
    expect(await sb.isReady()).to.equal(false);
    await expect(sb.connect(dao).setStandby(asc([ops[0], ops[3]]))).to.be.revertedWith(notOp);

    // refreshing the list without them makes it ready again
    await sb.connect(dao).setStandby(asc([ops[0], ops[1], ops[4]]));
    expect(await sb.staleMembers()).to.deep.equal([]);
    expect(await sb.isReady()).to.equal(true);
  });

  it("other live statuses stay valid: a self-suspended or a demoted owner still holds a registered seat", async () => {
    const { sb, reg, ops, founders } = await loadFixture(fixture);
    const dao = await asDao();
    await hre.network.provider.send("hardhat_setBalance", [ADDR.VERIFIER, "0x56BC75E2D63100000"]);
    const verifier = await ethers.getImpersonatedSigner(ADDR.VERIFIER);
    for (const f of founders.slice(1)) await reg.connect(verifier).recordActivation(f.address, ethers.id("e"));
    await sb.connect(dao).setStandby(asc([ops[5], ops[6]])); // founders 5 and 6 are not board members
    await reg.connect(founders[5]).selfSuspend(); // status SelfSuspended
    await reg.connect(verifier).recordSuspension(founders[6].address, ethers.id("e")); // status Demoted
    expect((await reg.validators(founders[5].address)).status).to.equal(6);
    expect((await reg.validators(founders[6].address)).status).to.equal(3);
    expect(await sb.staleMembers()).to.deep.equal([]);
    expect(await sb.isReady()).to.equal(true);
  });
});

describe("FoundationDAO - setting the standby list through the existing Execute proposal", () => {
  it("proposeExecute(StandbyValidators.setStandby) with the DAO majority updates the list; one vote less changes nothing; a bad list reverts the execution", async () => {
    const { dao, daoBoard, sb, ops } = await loadFixture(fixture);
    const list = asc(ops.slice(0, 5));
    const data = sb.interface.encodeFunctionData("setStandby", [list]);
    await dao.connect(daoBoard[0]).proposeExecute(ADDR.STANDBY_VALIDATORS, 0, data, "set the standby list");
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(daoBoard[1]).vote(id, h);
    expect(await sb.version()).to.equal(0);
    await dao.connect(daoBoard[2]).vote(id, h);
    expect(await sb.version()).to.equal(1);
    expect(await sb.getValidators()).to.deep.equal(list);
    // a list with a stranger fails when the proposal executes
    const bad = sb.interface.encodeFunctionData("setStandby", [asc([...ops.slice(0, 3), rnd()])]);
    await dao.connect(daoBoard[0]).proposeExecute(ADDR.STANDBY_VALIDATORS, 0, bad, "bad list");
    const id2 = await dao.proposalCount();
    const h2 = (await dao.getProposal(id2)).paramsHash;
    await dao.connect(daoBoard[1]).vote(id2, h2);
    await expect(dao.connect(daoBoard[2]).vote(id2, h2)).to.be.revertedWith(
      "StandbyValidators: not the current operator key of a registered seat");
    expect(await sb.version()).to.equal(1);
  });
});
