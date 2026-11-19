// Lottery helpers shared by bg10.js (reveal path, Net-S) and bg10b.js (no-reveal / cancel path, Net-L2)
const { ethers, send, makeManyFullyVerified } = require("./lib");

// off-chain replica of ValidatorLottery._uniform/_drawOne (partial Fisher-Yates with rejection sampling)
function replicaDraw(seed, participants, winnersCount) {
  const total = participants.length;
  const k = Math.min(winnersCount, total);
  const swapped = new Map();
  const MAX = (1n << 256n) - 1n;
  const abi = ethers.AbiCoder.defaultAbiCoder();
  const uniform = (position, range) => {
    const limit = MAX - (MAX % BigInt(range));
    for (let attempt = 0n; ; attempt++) {
      const r = BigInt(ethers.keccak256(abi.encode(["bytes32", "uint256", "uint256"], [seed, position, attempt])));
      if (r < limit) return Number(r % BigInt(range));
    }
  };
  const winners = [];
  for (let i = 0; i < k; i++) {
    const j = i + uniform(i, total - i);
    const atJ = swapped.get(j) || 0; const valueJ = atJ === 0 ? j : atJ - 1;
    const atI = swapped.get(i) || 0; const valueI = atI === 0 ? i : atI - 1;
    swapped.set(j, valueI + 1); swapped.set(i, valueJ + 1);
    winners.push(participants[valueJ]);
  }
  return winners;
}

// board of 5 DAO principals proposes StartLottery and 3 of 5 vote; returns {id, paramsHash, closeTime, txs}
async function startLotteryViaDao(net, ticketPrice, winnersCount, closeInSeconds) {
  const dao = net.c("DAO");
  const lastBlock = await net.block("latest");
  const closeTime = Number(BigInt(lastBlock.timestamp)) + closeInSeconds;
  const p = await send(net, "dao1", "DAO", "proposeStartLottery", [ticketPrice, winnersCount, closeTime]);
  const id = Number(await dao.proposalCount());
  const prop = await dao.getProposal(id);
  const hash = await dao.computeParamsHash(10, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress, ticketPrice, winnersCount, closeTime, "", "0x");
  const txs = { propose: p.hash };
  const v2 = await send(net, "dao2", "DAO", "vote", [id, hash]); txs.vote2 = v2.hash;
  const afterTwo = await dao.getProposal(id);
  const v3 = await send(net, "dao3", "DAO", "vote", [id, hash]); txs.vote3 = v3.hash;
  const done = await dao.getProposal(id);
  return { id, closeTime, paramsHash: hash, hashMatchesStored: hash === prop.paramsHash, votesAfterPropose: Number(prop.votes), votesAfterTwo: Number(afterTwo.votes), statusAfterTwo: Number(afterTwo.status), votesAfterThree: Number(done.votes), statusAfterThree: Number(done.status), requiredVotes: Number(done.requiredVotes), proposeBlock: p.block, executeBlock: v3.block, txs };
}
module.exports = { replicaDraw, startLotteryViaDao, makeManyFullyVerified };
