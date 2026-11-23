const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, now, DAY } = require("./helpers");

const ZERO = ethers.ZeroAddress;
const E = ethers.parseEther;
const ORACLE = "0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9"; // SurAddresses.IDENTITY_ORACLE

async function fixture() {
  const S = await ethers.getSigners();
  const board = S.slice(0, 5);
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [board.map((s) => s.address), S[7].address, board[0].address, board[1].address, S[8].address, (await now()) + 730 * DAY], E("10"));
  // IdentityRegistry has no constructor and an all-zero initial state except the oracle initializer: deploy normally and copy
  // via the same recipe by seeding through a plain deploy (its only initial storage is the oracle in slot 1).
  const factory = await ethers.getContractFactory("IdentityRegistry");
  const tmp = await factory.deploy();
  const art = await hre.artifacts.readArtifact("IdentityRegistry");
  await hre.network.provider.send("hardhat_setCode", [ADDR.IDENTITY_REGISTRY, art.deployedBytecode]);
  const slot = await ethers.provider.getStorage(await tmp.getAddress(), 1);
  await hre.network.provider.send("hardhat_setStorageAt", [ADDR.IDENTITY_REGISTRY, "0x1", slot]);
  const idr = await ethers.getContractAt("IdentityRegistry", ADDR.IDENTITY_REGISTRY);
  await hre.network.provider.send("hardhat_setBalance", [ORACLE, "0x56BC75E2D63100000"]);
  const oracle = await ethers.getImpersonatedSigner(ORACLE);
  return { S, board, dao, idr, oracle, user: S[12], user2: S[13], company: S[14] };
}

async function verifyAll(idr, oracle, who) {
  await idr.connect(oracle).setKycVerified(who.address, true, ethers.id("c"));
  await idr.connect(oracle).setPhoneVerified(who.address, true);
  await idr.connect(oracle).setTelegramVerified(who.address, true);
  await idr.connect(oracle).setBaleVerified(who.address, true);
  await idr.connect(oracle).setEmailVerified(who.address, true);
}

describe("IdentityRegistry v2.5", () => {
  it("starts with the configured oracle; every verification setter is oracle-only", async () => {
    const { idr, oracle, user, board } = await loadFixture(fixture);
    expect(await idr.identityOracle()).to.equal(ORACLE);
    await idr.connect(user).registerIdentity(0, "Ali");
    for (const [fn, args] of [["setPhoneVerified", [user.address, true]], ["setTelegramVerified", [user.address, true]], ["setBaleVerified", [user.address, true]], ["setEmailVerified", [user.address, true]], ["setKycVerified", [user.address, true, ethers.id("c")]]]) {
      await expect(idr.connect(board[0])[fn](...args)).to.be.revertedWith("IdentityRegistry: caller is not the identity oracle");
      await idr.connect(oracle)[fn](...args);
    }
  });

  it("isFullyVerified needs a registered individual with all five verifications", async () => {
    const { idr, oracle, user } = await loadFixture(fixture);
    expect(await idr.isFullyVerified(user.address)).to.equal(false);
    await idr.connect(user).registerIdentity(0, "Ali");
    const flags = [
      ["setKycVerified", [user.address, true, ethers.id("c")], false],
      ["setPhoneVerified", [user.address, true], false],
      ["setTelegramVerified", [user.address, true], false],
      ["setBaleVerified", [user.address, true], false],
      ["setEmailVerified", [user.address, true], true],
    ];
    for (const [fn, args, full] of flags) {
      await idr.connect(oracle)[fn](...args);
      expect(await idr.isFullyVerified(user.address)).to.equal(full);
    }
    const st = await idr.getVerificationStatus(user.address);
    expect([...st]).to.deep.equal([true, true, true, true, true, true]);
    await idr.connect(oracle).setBaleVerified(user.address, false); // revoking one flag revokes the status
    expect(await idr.isFullyVerified(user.address)).to.equal(false);
  });

  it("an unregistered address is never fully verified; a legal person cannot be verified", async () => {
    const { idr, oracle, user, company } = await loadFixture(fixture);
    await verifyAll(idr, oracle, user); // flags can exist before the person registers...
    expect(await idr.isFullyVerified(user.address)).to.equal(false); // ...but the status needs the registration
    await idr.connect(company).registerIdentity(1, "Citex");
    for (const [fn, args] of [["setPhoneVerified", [company.address, true]], ["setBaleVerified", [company.address, true]], ["setEmailVerified", [company.address, true]], ["setKycVerified", [company.address, true, ethers.id("c")]]]) {
      await expect(idr.connect(oracle)[fn](...args)).to.be.revertedWith("IdentityRegistry: only individuals can be verified");
    }
    expect(await idr.isFullyVerified(company.address)).to.equal(false);
  });

  it("migration moves all five flags and burns the old address", async () => {
    const { idr, oracle, user, user2 } = await loadFixture(fixture);
    await idr.connect(user).registerIdentity(0, "Ali");
    await verifyAll(idr, oracle, user);
    expect(await idr.isFullyVerified(user.address)).to.equal(true);
    expect(await idr.migratedTo(user.address)).to.equal(ZERO);
    await idr.connect(oracle).migrateIdentity(user.address, user2.address);
    expect(await idr.migratedTo(user.address)).to.equal(user2.address); // read by ValidatorsRegistry.migrateSeat
    expect(await idr.migratedTo(user2.address)).to.equal(ZERO);
    expect(await idr.isFullyVerified(user2.address)).to.equal(true);
    expect(await idr.isFullyVerified(user.address)).to.equal(false);
    expect([...(await idr.getVerificationStatus(user.address))]).to.deep.equal([false, false, false, false, false, false]);
    await expect(idr.connect(oracle).setEmailVerified(user.address, true)).to.be.revertedWith("IdentityRegistry: address was migrated (burned)");
  });

  it("the oracle key is rotated only by FoundationDAO, through the RotateIdentityOracle proposal (3 of 5)", async () => {
    const { idr, dao, board, S } = await loadFixture(fixture);
    const newOracle = S[15];
    await expect(idr.connect(board[0]).setIdentityOracle(newOracle.address)).to.be.revertedWith("IdentityRegistry: caller is not the Foundation");
    await dao.connect(board[0]).proposeRotateIdentityOracle(newOracle.address);
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(board[1]).vote(id, h);
    expect(await idr.identityOracle()).to.equal(ORACLE); // 2 of 5: not yet
    await dao.connect(board[2]).vote(id, h);
    expect(await idr.identityOracle()).to.equal(newOracle.address);
    await expect(idr.connect(await ethers.getImpersonatedSigner(ORACLE)).setBaleVerified(S[12].address, true)).to.be.revertedWith("IdentityRegistry: caller is not the identity oracle");
  });
});
