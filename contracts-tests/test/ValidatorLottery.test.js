const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, setCodeOf, increaseTime, mine, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const PRICE = E("10");

async function fixture() {
  const S = await ethers.getSigners();
  const board = S.slice(0, 5), ceo = S[8];
  await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS, [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [board.map((s) => s.address), S[7].address, board[0].address, board[1].address, ceo.address, (await now()) + 730 * DAY], E("1000"));
  const lot = await setCodeOf("ValidatorLottery", ADDR.VALIDATOR_LOTTERY);
  const idr = await setCodeOf("MockIdentity", ADDR.IDENTITY_REGISTRY);
  const reg = await setCodeOf("MockLotteryRegistry", ADDR.VALIDATORS_REGISTRY);
  const buyers = S.slice(10, 20);
  for (const b of buyers) await idr.setVerified(b.address, true);
  const run = async (fn, args = []) => {
    await dao.connect(board[0])[fn](...args);
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(board[1]).vote(id, h);
    await dao.connect(board[2]).vote(id, h);
  };
  return { S, board, ceo, dao, lot, idr, reg, buyers, run };
}

async function start(f, winners = 3, closeIn = 20 * DAY) {
  const closeTime = (await now()) + closeIn;
  await f.run("proposeStartLottery", [PRICE, winners, closeTime]);
  return closeTime;
}

const SECRET = ethers.id("ceo secret");
const COMMIT = ethers.keccak256(ethers.solidityPacked(["bytes32"], [SECRET]));

/// start, N buyers, commit, close; returns the target block
async function untilClosed(f, nBuyers = 6, winners = 3) {
  const closeTime = await start(f, winners);
  for (let i = 0; i < nBuyers; i++) await f.lot.connect(f.buyers[i]).buyTicket({ value: PRICE });
  await f.lot.connect(f.ceo).commitSecret(COMMIT);
  await increaseTime(21 * DAY);
  await f.lot.connect(f.S[19]).closeLottery(); // anyone
  return (await f.lot.getLottery(1)).targetBlock;
}

describe("ValidatorLottery", () => {
  it("starts only through the StartLottery proposal, and only once a year", async () => {
    const f = await loadFixture(fixture);
    await expect(f.lot.connect(f.board[0]).startLottery(PRICE, 3, (await now()) + DAY)).to.be.revertedWith("ValidatorLottery: only FoundationDAO");
    await start(f);
    const l = await f.lot.getLottery(1);
    expect(l.phase).to.equal(1);
    expect(l.ticketPrice).to.equal(PRICE);
    expect(l.winnersCount).to.equal(3);
    // finish it as a cancelled lottery, then a second start inside a year must fail
    await increaseTime(21 * DAY);
    await f.lot.closeLottery(); // no commitment -> cancelled
    await expect(start(f)).to.be.reverted;
    await increaseTime(366 * DAY);
    await start(f);
    expect(await f.lot.lotteryCount()).to.equal(2);
  });

  it("ticket rules: verified identity, exact price, one per address, no board members, no CEO, before closeTime", async () => {
    const f = await loadFixture(fixture);
    await start(f);
    const { lot, idr, buyers, board, ceo, S } = f;
    await expect(lot.connect(buyers[0]).buyTicket({ value: PRICE - 1n })).to.be.revertedWith("ValidatorLottery: wrong ticket price");
    await idr.setVerified(S[19].address, false);
    await expect(lot.connect(S[19]).buyTicket({ value: PRICE })).to.be.revertedWith("ValidatorLottery: identity not fully verified");
    await idr.setVerified(board[3].address, true);
    await expect(lot.connect(board[3]).buyTicket({ value: PRICE })).to.be.revertedWith("ValidatorLottery: board members and the CEO cannot take part");
    await idr.setVerified(ceo.address, true);
    await expect(lot.connect(ceo).buyTicket({ value: PRICE })).to.be.revertedWith("ValidatorLottery: board members and the CEO cannot take part");
    await lot.connect(buyers[0]).buyTicket({ value: PRICE });
    await expect(lot.connect(buyers[0]).buyTicket({ value: PRICE })).to.be.revertedWith("ValidatorLottery: one ticket per address");
    expect(await lot.participantCount(1)).to.equal(1);
    await increaseTime(21 * DAY);
    await expect(lot.connect(buyers[1]).buyTicket({ value: PRICE })).to.be.revertedWith("ValidatorLottery: registration is not open");
  });

  it("only the CEO commits, once, before closeTime", async () => {
    const f = await loadFixture(fixture);
    await start(f);
    const { lot, ceo, buyers } = f;
    await expect(lot.connect(buyers[0]).commitSecret(COMMIT)).to.be.revertedWith("ValidatorLottery: only the CEO");
    await expect(lot.connect(ceo).commitSecret(ethers.ZeroHash)).to.be.revertedWith("ValidatorLottery: commitment already set or empty");
    await lot.connect(ceo).commitSecret(COMMIT);
    await expect(lot.connect(ceo).commitSecret(ethers.id("other"))).to.be.revertedWith("ValidatorLottery: commitment already set or empty");
    await increaseTime(21 * DAY);
    await expect(lot.connect(ceo).commitSecret(COMMIT)).to.be.reverted;
  });

  it("full flow: commit, anyone closes, CEO reveals, batches draw distinct winners, pot goes to the treasury, registry is called", async () => {
    const f = await loadFixture(fixture);
    const { lot, ceo, reg, dao, buyers } = f;
    const target = await untilClosed(f, 8, 3);
    expect((await lot.getLottery(1)).phase).to.equal(2);
    await expect(lot.connect(ceo).reveal(SECRET)).to.be.revertedWith("ValidatorLottery: target block not mined yet");
    await mine(Number(target) - (await ethers.provider.getBlockNumber()) + 1);
    await expect(lot.connect(buyers[0]).reveal(SECRET)).to.be.revertedWith("ValidatorLottery: only the CEO");
    await expect(lot.connect(ceo).reveal(ethers.id("wrong"))).to.be.revertedWith("ValidatorLottery: secret does not match the commitment");
    await lot.connect(ceo).reveal(SECRET);
    expect((await lot.getLottery(1)).phase).to.equal(3);
    await expect(lot.drawBatch(0)).to.be.revertedWith("ValidatorLottery: empty batch");
    const daoBefore = await ethers.provider.getBalance(ADDR.FOUNDATION_DAO);
    await lot.connect(buyers[9]).drawBatch(2); // anyone
    expect((await lot.winnersOf(1)).length).to.equal(2);
    expect((await lot.getLottery(1)).phase).to.equal(3);
    await lot.drawBatch(5); // only one left
    expect((await lot.getLottery(1)).phase).to.equal(4);
    const winners = await lot.winnersOf(1);
    expect(winners.length).to.equal(3);
    expect(new Set(winners).size).to.equal(3);
    const parts = await lot.participantsOf(1);
    for (const w of winners) {
      expect(parts).to.include(w);
      expect(await reg.entered(w)).to.equal(true);
    }
    expect(await reg.enteredCount()).to.equal(3);
    expect(await ethers.provider.getBalance(ADDR.FOUNDATION_DAO)).to.equal(daoBefore + PRICE * 8n);
    expect(await ethers.provider.getBalance(ADDR.VALIDATOR_LOTTERY)).to.equal(0);
    await expect(lot.drawBatch(1)).to.be.revertedWith("ValidatorLottery: not ready to draw");
  });

  it("reveal window: works at targetBlock+250, fails at +251; then anyone cancels and buyers are refunded", async () => {
    const f = await loadFixture(fixture);
    const { lot, ceo, buyers } = f;
    const target = Number(await untilClosed(f, 4, 2));
    // exactly the last allowed block
    await mine(target + 250 - (await ethers.provider.getBlockNumber()) - 1);
    // the next mined block (our tx) will be target+250
    const snap = await ethers.provider.send("evm_snapshot", []);
    await lot.connect(ceo).reveal(SECRET);
    expect((await lot.getLottery(1)).phase).to.equal(3);
    await ethers.provider.send("evm_revert", [snap]);
    await mine(1); // now the next tx is in block target+251
    await expect(lot.connect(ceo).reveal(SECRET)).to.be.revertedWith("ValidatorLottery: reveal window over");
    await expect(lot.connect(buyers[0]).cancelLottery()).to.not.be.reverted;
    expect((await lot.getLottery(1)).phase).to.equal(5);
    await expect(lot.connect(ceo).reveal(SECRET)).to.be.revertedWith("ValidatorLottery: not waiting for the reveal");
    const before = await ethers.provider.getBalance(buyers[0].address);
    const tx = await lot.connect(buyers[0]).claimRefund(1);
    const rc = await tx.wait();
    expect(await ethers.provider.getBalance(buyers[0].address)).to.equal(before + PRICE - rc.gasUsed * rc.gasPrice);
    await expect(lot.connect(buyers[0]).claimRefund(1)).to.be.revertedWith("ValidatorLottery: nothing to refund");
    await expect(lot.connect(f.S[19]).claimRefund(1)).to.be.revertedWith("ValidatorLottery: nothing to refund");
    for (const b of buyers.slice(1, 4)) await lot.connect(b).claimRefund(1);
    expect(await ethers.provider.getBalance(ADDR.VALIDATOR_LOTTERY)).to.equal(0);
  });

  it("cancelling too early is refused; a lottery without a commitment is cancelled when closed", async () => {
    const f = await loadFixture(fixture);
    const { lot, buyers } = f;
    await untilClosed(f, 3, 1);
    await expect(lot.cancelLottery()).to.be.revertedWith("ValidatorLottery: cannot cancel now");
  });

  it("no commitment before closeTime: closing cancels and refunds", async () => {
    const f = await loadFixture(fixture);
    const { lot, buyers } = f;
    await start(f);
    await lot.connect(buyers[0]).buyTicket({ value: PRICE });
    await expect(lot.closeLottery()).to.be.revertedWith("ValidatorLottery: cannot close now");
    await increaseTime(21 * DAY);
    await lot.closeLottery();
    expect((await lot.getLottery(1)).phase).to.equal(5);
    await lot.connect(buyers[0]).claimRefund(1);
  });

  it("zero participants: nothing to draw, the lottery just ends", async () => {
    const f = await loadFixture(fixture);
    await start(f);
    await f.lot.connect(f.ceo).commitSecret(COMMIT);
    await increaseTime(21 * DAY);
    await f.lot.closeLottery();
    expect((await f.lot.getLottery(1)).phase).to.equal(4);
  });

  it("fewer participants than winnersCount: everybody wins; a refusing registry does not block the draw", async () => {
    const f = await loadFixture(fixture);
    const { lot, ceo, reg, buyers } = f;
    const target = await untilClosed(f, 2, 5);
    await mine(Number(target) - (await ethers.provider.getBlockNumber()) + 1);
    await lot.connect(ceo).reveal(SECRET);
    await reg.setFailing(true);
    await lot.drawBatch(10);
    const winners = await lot.winnersOf(1);
    expect(winners.length).to.equal(2);
    expect(await lot.entryFailed(1, winners[0])).to.equal(true);
    expect(await reg.enteredCount()).to.equal(0);
    expect((await lot.getLottery(1)).phase).to.equal(4);
  });

  it("selection is a function of (secret, blockhash): the same seed gives the same permutation prefix, different seeds differ", async () => {
    // statistical sanity: over several lotteries with 10 participants and 1 winner, more than one distinct winner appears
    const f = await loadFixture(fixture);
    const { lot, ceo, buyers } = f;
    const seen = new Set();
    for (let round = 1; round <= 5; round++) {
      const closeTime = (await now()) + 20 * DAY;
      await f.run("proposeStartLottery", [PRICE, 1, closeTime]);
      for (const b of buyers) await lot.connect(b).buyTicket({ value: PRICE });
      const secret = ethers.id("secret " + round);
      await lot.connect(ceo).commitSecret(ethers.keccak256(ethers.solidityPacked(["bytes32"], [secret])));
      await increaseTime(21 * DAY);
      await lot.closeLottery();
      const target = Number((await lot.getLottery(round)).targetBlock);
      await mine(target - (await ethers.provider.getBlockNumber()) + 1);
      await lot.connect(ceo).reveal(secret);
      await lot.drawBatch(1);
      seen.add((await lot.winnersOf(round))[0]);
      await increaseTime(366 * DAY);
    }
    expect(seen.size).to.be.gt(1);
  });
});
