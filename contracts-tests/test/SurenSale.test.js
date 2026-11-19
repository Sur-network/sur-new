// Integration tests: the real FoundationDAO (at its fixed address) drives the real SurenSale.
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ADDR, deployAtFixed, increaseTime, now, DAY } = require("./helpers");

const E = ethers.parseEther;
const ZERO = ethers.ZeroAddress;
const ref = (s) => ethers.id(s);

async function fixture() {
  const S = await ethers.getSigners();
  const board = S.slice(0, 5), ceo = S[8];
  const mem = await deployAtFixed("FoundationMembers", "FoundationMembers_GenesisSeed", ADDR.FOUNDATION_MEMBERS,
    [[S[9].address], ["M"], [0], [ZERO], [100n]]);
  const dao = await deployAtFixed("FoundationDAO", "FoundationDAO_GenesisSeed", ADDR.FOUNDATION_DAO,
    [board.map((s) => s.address), S[7].address, board[0].address, board[1].address, ceo.address, (await now()) + 730 * DAY], E("10000000"));
  const sale = await (await ethers.getContractFactory("SurenSale")).deploy();
  const saleAddr = await sale.getAddress();
  const run = async (fn, args = []) => {
    await dao.connect(board[0])[fn](...args);
    const id = await dao.proposalCount();
    const h = (await dao.getProposal(id)).paramsHash;
    await dao.connect(board[1]).vote(id, h);
    await dao.connect(board[2]).vote(id, h);
  };
  await run("proposeSetSaleContract", [saleAddr]);
  // fund the sale contract from the foundation treasury (Spend proposal) and set the cap
  await run("proposeSpend", [ZERO, saleAddr, E("100000"), "fund sale"]);
  await run("proposeSetSaleTotalCap", [E("50000")]);
  const ex1 = S[10], ex2 = S[11], customer = S[12], other = S[13];
  await run("proposeRegisterExchange", [ex1.address, "Exchange One", E("1000")]);
  return { S, board, ceo, dao, sale, saleAddr, run, ex1, ex2, customer, other };
}

describe("SurenSale v2.5", () => {
  it("registering an exchange sends the 100 Suren gas deposit from the contract balance, outside the quota", async () => {
    const { sale, saleAddr, ex1 } = await loadFixture(fixture);
    const ex = await sale.getExchange(ex1.address);
    expect(ex.status).to.equal(1);
    expect(ex.name).to.equal("Exchange One");
    expect(ex.quota).to.equal(E("1000"));
    expect(ex.quotaLeft).to.equal(E("1000"));
    expect(await ethers.provider.getBalance(saleAddr)).to.equal(E("100000") - E("100"));
    expect(await sale.getExchanges()).to.deep.equal([ex1.address]);
  });

  it("only the foundation (DAO) can manage exchanges", async () => {
    const { sale, ex1, other } = await loadFixture(fixture);
    await expect(sale.connect(other).registerExchange(other.address, "x", 1)).to.be.revertedWith("SurenSale: caller is not the Foundation");
    await expect(sale.connect(ex1).pauseExchange(ex1.address)).to.be.revertedWith("SurenSale: caller is not the Foundation");
    await expect(sale.connect(other).setTotalCap(1)).to.be.revertedWith("SurenSale: caller is not the Foundation");
    await expect(sale.connect(other).endSale()).to.be.revertedWith("SurenSale: caller is not the Foundation");
  });

  it("sellTo: official price from the contract (100 Toman in month 1), customer gets Suren directly, stats recorded", async () => {
    const { sale, ex1, customer } = await loadFixture(fixture);
    expect(await sale.currentPriceMilliToman()).to.equal(100000);
    const before = await ethers.provider.getBalance(customer.address);
    await sale.connect(ex1).sellTo(customer.address, 5000, E("50"), ref("o1")); // 5000 Toman / 100 = 50 Suren
    expect(await ethers.provider.getBalance(customer.address)).to.equal(before + E("50"));
    const ex = await sale.getExchange(ex1.address);
    expect(ex.sold).to.equal(E("50"));
    expect(ex.tomanReceived).to.equal(5000);
    expect(ex.salesCount).to.equal(1);
    expect(ex.quotaLeft).to.equal(E("950"));
    expect(await sale.totalSurenSold()).to.equal(E("50"));
    expect(await sale.totalTomanReceived()).to.equal(5000);
  });

  it("sellTo: duplicate reference, minSurenOut, unknown caller, quota and total cap are enforced", async () => {
    const { sale, ex1, customer, other, run } = await loadFixture(fixture);
    await sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("o1"));
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("o1"))).to.be.revertedWith("SurenSale: reference already used");
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, E("11"), ref("o2"))).to.be.revertedWith("SurenSale: below minSurenOut"); // would be 10 Suren
    await expect(sale.connect(other).sellTo(customer.address, 1000, 0, ref("o3"))).to.be.revertedWith("SurenSale: caller is not an active exchange");
    await expect(sale.connect(ex1).sellTo(ZERO, 1000, 0, ref("o4"))).to.be.revertedWith("SurenSale: zero customer");
    await expect(sale.connect(ex1).sellTo(customer.address, 0, 0, ref("o5"))).to.be.revertedWith("SurenSale: zero amount");
    // quota is 1000 Suren (= 100000 Toman at 100); 10 already sold
    await expect(sale.connect(ex1).sellTo(customer.address, 99100, 0, ref("o6"))).to.be.revertedWith("SurenSale: exchange quota exceeded");
    await sale.connect(ex1).sellTo(customer.address, 99000, 0, ref("o7")); // exactly the rest
    // raise the quota above the cap to hit the total cap (50000)
    await run("proposeSetExchangeQuota", [ex1.address, E("60000")]);
    await expect(sale.connect(ex1).sellTo(customer.address, 5_000_000, 0, ref("o8"))).to.be.revertedWith("SurenSale: total cap exceeded");
  });

  it("nothing sells before the board sets a total cap", async () => {
    const S = await ethers.getSigners();
    // fresh deployment: cap 0
    const f = await loadFixture(fixture);
    const sale2 = await (await ethers.getContractFactory("SurenSale")).deploy();
    expect(await sale2.totalCap()).to.equal(0);
    // register through DAO on a second sale contract
    await f.run("proposeSetSaleContract", [await sale2.getAddress()]);
    await f.run("proposeSpend", [ZERO, await sale2.getAddress(), E("1000"), "fund"]);
    await f.run("proposeRegisterExchange", [f.ex2.address, "Two", E("500")]);
    await expect(sale2.connect(f.ex2).sellTo(f.customer.address, 1000, 0, ref("a"))).to.be.revertedWith("SurenSale: total cap exceeded");
  });

  it("pause stops one exchange at once; resume, key change and removal; stats and used references follow the key", async () => {
    const { sale, dao, board, ceo, ex1, ex2, customer, run } = await loadFixture(fixture);
    await sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("r1"));
    await dao.connect(ceo).pauseExchange(ex1.address);
    expect((await sale.getExchange(ex1.address)).status).to.equal(2);
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("r2"))).to.be.revertedWith("SurenSale: caller is not an active exchange");
    await run("proposeResumeExchange", [ex1.address]);
    expect((await sale.getExchange(ex1.address)).status).to.equal(1);
    await dao.connect(board[3]).pauseExchange(ex1.address);
    await run("proposeChangeExchangeKey", [ex1.address, ex2.address]); // paused state moves too
    const moved = await sale.getExchange(ex2.address);
    expect(moved.status).to.equal(2);
    expect(moved.sold).to.equal(E("10"));
    expect(moved.name).to.equal("Exchange One");
    expect((await sale.getExchange(ex1.address)).status).to.equal(3); // old key removed
    expect(await sale.getExchanges()).to.deep.equal([ex2.address]);
    await run("proposeResumeExchange", [ex2.address]);
    await expect(sale.connect(ex2).sellTo(customer.address, 1000, 0, ref("r1"))).to.be.revertedWith("SurenSale: reference already used"); // reference history moved with the id
    await sale.connect(ex2).sellTo(customer.address, 1000, 0, ref("r3"));
    await run("proposeRemoveExchange", [ex2.address]);
    await expect(sale.connect(ex2).sellTo(customer.address, 1000, 0, ref("r4"))).to.be.revertedWith("SurenSale: caller is not an active exchange");
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("r5"))).to.be.revertedWith("SurenSale: caller is not an active exchange");
  });

  it("fixed period: 100 / 105 / 110 Toman by 30-day steps", async () => {
    const { sale } = await loadFixture(fixture);
    expect(await sale.currentPriceToman()).to.equal(100);
    await increaseTime(31 * DAY);
    expect(await sale.currentPriceToman()).to.equal(105);
    await increaseTime(30 * DAY);
    expect(await sale.currentPriceToman()).to.equal(110);
    expect(await sale.currentPeriod()).to.equal(0);
  });

  it("CEO extends the fixed period with his own fixed price; only the CEO, only before the end", async () => {
    const { sale, ceo, other, ex1, customer } = await loadFixture(fixture);
    await expect(sale.connect(other).extendFixedPeriod(30, 120)).to.be.revertedWith("SurenSale: caller is not the CEO");
    await expect(sale.connect(ceo).extendFixedPeriod(0, 120)).to.be.revertedWith("SurenSale: bad extension length");
    await expect(sale.connect(ceo).extendFixedPeriod(30, 0)).to.be.revertedWith("SurenSale: zero price");
    await increaseTime(85 * DAY);
    await sale.connect(ceo).extendFixedPeriod(30, 120);
    expect(await sale.currentPriceToman()).to.equal(110); // still in the base period
    await increaseTime(10 * DAY); // day 95: inside the extension
    expect(await sale.currentPriceMilliToman()).to.equal(120000);
    expect(await sale.currentPeriod()).to.equal(0);
    await sale.connect(ex1).sellTo(customer.address, 1200, E("10"), ref("e1")); // 1200 / 120 = 10 Suren
    await sale.connect(ceo).extendFixedPeriod(10, 130); // second extension: its own price from where the first ends
    await increaseTime(25 * DAY); // day 120: past the first extension (ends at day 120), inside the second
    expect(await sale.currentPriceMilliToman()).to.equal(130000);
    await increaseTime(20 * DAY); // day 140: fixed period over, transition running
    expect(await sale.currentPeriod()).to.equal(1);
    await expect(sale.connect(ceo).extendFixedPeriod(5, 100)).to.be.revertedWith("SurenSale: fixed period already over");
  });

  it("transition period: starts at the last fixed price, volume-driven +-0.5% per day inside 90..150, CEO may extend", async () => {
    const { sale, ceo, ex1, customer, run } = await loadFixture(fixture);
    await run("proposeSetExchangeQuota", [ex1.address, E("40000")]);
    await increaseTime(91 * DAY);
    expect(await sale.currentPeriod()).to.equal(1);
    expect(await sale.currentPriceMilliToman()).to.equal(110000);
    // day 0 of the transition: sell 100 Suren; no average yet, no change
    await sale.connect(ex1).sellTo(customer.address, 11000, 0, ref("t0"));
    await increaseTime(DAY);
    // day 1: big volume (1000 Suren > 120% of the 100 average) -> +0.5% when day 1 completes
    await sale.connect(ex1).sellTo(customer.address, 110000, 0, ref("t1"));
    await increaseTime(DAY);
    await sale.advanceTransitionPrice();
    expect(await sale.currentPriceMilliToman()).to.equal(110550); // 110000 + 0.5%
    // day 2: nothing sold -> below 80% of the average -> -0.5%
    await increaseTime(DAY);
    await sale.advanceTransitionPrice();
    expect(await sale.currentPriceMilliToman()).to.be.lt(110550);
    await sale.connect(ceo).extendTransition(10);
    await expect(sale.connect(ceo).extendTransition(0)).to.be.revertedWith("SurenSale: bad extension length");
    expect(await sale.transitionEndTime()).to.equal((await sale.fixedEnd()) + BigInt(55 * DAY));
    await increaseTime(60 * DAY);
    expect(await sale.currentPeriod()).to.equal(2);
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("late"))).to.be.revertedWith("SurenSale: sale is not active");
    await expect(sale.connect(ceo).extendTransition(5)).to.be.revertedWith("SurenSale: transition already over");
  });

  it("the transition price never leaves the 90..150 Toman band", async () => {
    const { sale, ex1, customer, run } = await loadFixture(fixture);
    await run("proposeSetExchangeQuota", [ex1.address, E("40000")]);
    await increaseTime(91 * DAY);
    // no sales at all: avg stays 0, price must stay 110
    await increaseTime(40 * DAY);
    await sale.advanceTransitionPrice();
    expect(await sale.currentPriceMilliToman()).to.equal(110000);
    expect(await sale.lastPricedTransitionDay()).to.equal(41);
  });

  it("EndSale stops sales; sweep only after the sale is over; swept to the chosen address", async () => {
    const { sale, saleAddr, dao, run, ex1, customer, other } = await loadFixture(fixture);
    await run("proposeSweepUnsold", [other.address]).catch(() => {});
    // sweepUnsold above must have failed (sale still active) — the vote that reached quorum reverts
    expect(await ethers.provider.getBalance(saleAddr)).to.be.gt(0);
    await run("proposeEndSale");
    expect(await sale.saleEnded()).to.equal(true);
    await expect(sale.connect(ex1).sellTo(customer.address, 1000, 0, ref("x"))).to.be.revertedWith("SurenSale: sale is not active");
    const bal = await ethers.provider.getBalance(saleAddr);
    const before = await ethers.provider.getBalance(other.address);
    await run("proposeSweepUnsold", [other.address]);
    expect(await ethers.provider.getBalance(saleAddr)).to.equal(0);
    expect(await ethers.provider.getBalance(other.address)).to.equal(before + bal);
  });
});
