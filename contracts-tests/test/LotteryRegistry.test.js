// Integration: the real ValidatorLottery seats its winners in the real ValidatorsRegistry.
const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, mine, setTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const PRICE = E("10");
const START = Math.floor(Date.UTC(2027, 2, 2) / 1000);
const SECRET = ethers.id("ceo secret");
const COMMIT = ethers.keccak256(ethers.solidityPacked(["bytes32"], [SECRET]));
const ST_PROBATION = 1;

async function fixture() {
  const S = await ethers.getSigners();
  if ((await now()) < START) await setTime(START);
  const board = S.slice(0, 5), ceo = S[8];
  await setCodeOf("MockDistributor", ADDR.BLOCK_REWARD_DISTRIBUTOR);
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [board.map((s) => s.address), S[7].address, board[0].address, board[1].address, ceo.address, (await now()) + 730 * DAY], E("100"));
  const reg = await deployAtFixed("ValidatorsRegistry", "ValidatorsRegistry_GenesisSeed", ADDR.VALIDATORS_REGISTRY, [S[15].address, ethers.Wallet.createRandom().address, [S[16].address], await now()]);
  await deployAtFixed("ValidatorSeatNFT", "ValidatorSeatNFT_GenesisSeed", ADDR.VALIDATOR_SEAT_NFT, [[S[15].address, S[16].address]]);
  const lot = await setCodeOf("ValidatorLottery", ADDR.VALIDATOR_LOTTERY);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const buyers = S.slice(10, 14);
  for (const b of buyers) await idr.setVerified(b.address, true);
  const run = async (fn, args = []) => {
    await dao.connect(board[0])[fn](...args);
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(board[1]).vote(id, h);
    await dao.connect(board[2]).vote(id, h);
  };
  return { S, board, ceo, dao, reg, lot, idr, buyers, run };
}

describe("ValidatorLottery -> ValidatorsRegistry", () => {
  it("only the lottery contract can seat a winner", async () => {
    const { reg, S } = await loadFixture(fixture);
    await expect(reg.connect(S[12]).enterAsLotteryWinner(S[12].address)).to.be.revertedWith("ValidatorsRegistry: caller is not the lottery");
  });

  it("winners get a collateral-free Probation seat (not a paid entrant); the Registry's own rules still apply", async () => {
    const f = await loadFixture(fixture);
    const { reg, lot, ceo, buyers, run, S } = f;
    const closeTime = (await now()) + 20 * DAY;
    await run("proposeStartLottery", [PRICE, 3, closeTime]);
    for (const b of buyers) await lot.connect(b).buyTicket({ value: PRICE });
    await lot.connect(ceo).commitSecret(COMMIT);
    await increaseTime(21 * DAY);
    await lot.closeLottery();
    const target = Number((await lot.getLottery(1)).targetBlock);
    await mine(target - (await ethers.provider.getBlockNumber()) + 1);
    await lot.connect(ceo).reveal(SECRET);
    const paidBefore = await reg.paidValidatorCount();
    await lot.drawBatch(10);
    const winners = await lot.winnersOf(1);
    expect(winners.length).to.equal(3);
    for (const w of winners) {
      const v = await reg.validators(w);
      expect(v.status).to.equal(ST_PROBATION);
      expect(v.lockedStake).to.equal(0);
      expect(v.isPaidEntrant).to.equal(false);
      expect(await reg.isValidator(w)).to.equal(false); // no consensus role and no vote before activation
      expect(await reg.getActiveOwners()).to.not.include(w);
    }
    expect(await reg.paidValidatorCount()).to.equal(paidBefore);
  });

  it("an already-registered winner is refused by the Registry without blocking the draw", async () => {
    const f = await loadFixture(fixture);
    const { reg, lot, ceo, S, idr, run } = f;
    // S[15] is a founding validator who also buys a ticket
    await idr.setVerified(S[15].address, true);
    const closeTime = (await now()) + 20 * DAY;
    await run("proposeStartLottery", [PRICE, 1, closeTime]);
    await lot.connect(S[15]).buyTicket({ value: PRICE });
    await lot.connect(ceo).commitSecret(COMMIT);
    await increaseTime(21 * DAY);
    await lot.closeLottery();
    const target = Number((await lot.getLottery(1)).targetBlock);
    await mine(target - (await ethers.provider.getBlockNumber()) + 1);
    await lot.connect(ceo).reveal(SECRET);
    await lot.drawBatch(1);
    expect(await lot.entryFailed(1, S[15].address)).to.equal(true);
    expect((await lot.getLottery(1)).phase).to.equal(4); // drawn
    expect((await reg.validators(S[15].address)).status).to.equal(2); // still the Active founder
  });
});
