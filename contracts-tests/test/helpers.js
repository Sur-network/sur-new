// Test helpers: reproduce the genesis "simulate-and-extract" recipe on the Hardhat network.
const hre = require("hardhat");
const { ethers } = hre;

const ADDR = {
  FOUNDATION_DAO: "0x1111111111111111111111111111111111111111",
  BLOCK_REWARD_DISTRIBUTOR: "0x2222222222222222222222222222222222222222",
  VALIDATORS_BOARD: "0x4444444444444444444444444444444444444444",
  VERIFIER: "0x1A5E86f3333291B3332C0f9Eddb04269940566bc",
  VALIDATOR_SEAT_NFT: "0x8888888888888888888888888888888888888888",
  VALIDATORS_REGISTRY: "0x3333333333333333333333333333333333333333",
  IDENTITY_REGISTRY: "0x6666666666666666666666666666666666666666",
  FOUNDATION_MEMBERS: "0x7777777777777777777777777777777777777777",
  VALIDATOR_LOTTERY: "0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa",
  KMS_DIRECTIVES: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
  STANDBY_VALIDATORS: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
};

const hex = (n) => "0x" + BigInt(n).toString(16);

/// Deploy `helperName` (which inherits the real contract and seeds state in its constructor), copy
/// every storage slot touched during that deployment, together with the REAL contract's runtime code,
/// to the fixed `address`. Mirrors what the genesis builder does.
async function deployAtFixed(realName, helperName, address, args = [], balance = 0n) {
  const helperFactory = await ethers.getContractFactory(helperName);
  const helper = await helperFactory.deploy(...args);
  const receipt = await helper.deploymentTransaction().wait();
  const trace = await hre.network.provider.send("debug_traceTransaction", [receipt.hash, { disableMemory: true, disableStack: true }]);
  const slots = new Set();
  for (const step of trace.structLogs) {
    if (step.storage) for (const k of Object.keys(step.storage)) slots.add(k);
  }
  const art = await hre.artifacts.readArtifact(realName);
  await hre.network.provider.send("hardhat_setCode", [address, art.deployedBytecode]);
  for (const k of slots) {
    const key = k.startsWith("0x") ? k : "0x" + k;
    const val = await ethers.provider.getStorage(await helper.getAddress(), key);
    await hre.network.provider.send("hardhat_setStorageAt", [address, hex(BigInt(key)), val]);
  }
  if (balance > 0n) await hre.network.provider.send("hardhat_setBalance", [address, hex(balance)]);
  return ethers.getContractAt(realName, address);
}

async function setCodeOf(mockName, address) {
  const art = await hre.artifacts.readArtifact(mockName);
  await hre.network.provider.send("hardhat_setCode", [address, art.deployedBytecode]);
  return ethers.getContractAt(mockName, address);
}

async function mine(blocks) {
  await hre.network.provider.send("hardhat_mine", [hex(blocks)]);
}

async function increaseTime(seconds) {
  await hre.network.provider.send("evm_increaseTime", [seconds]);
  await hre.network.provider.send("evm_mine", []);
}

async function setTime(ts) {
  await hre.network.provider.send("evm_setNextBlockTimestamp", [ts]);
  await hre.network.provider.send("evm_mine", []);
}

async function now() {
  return (await ethers.provider.getBlock("latest")).timestamp;
}

const DAY = 86400;

/// A fresh non-zero agreement hash for requestMembership (the hash of the signed validators' agreement; tests only need a distinct non-zero value).
const agr = () => ethers.hexlify(ethers.randomBytes(32));

module.exports = { ADDR, deployAtFixed, setCodeOf, increaseTime, mine, setTime, now, DAY, agr };

/// RD-18: one paginated distribution = open + pages + close (the RewardRouter does the same). Returns the sent transactions.
async function distribute(dist, oracle, range, addrs, blocks, rewards, fees, pageSize = 1000, overrides = {}) {
  const total = blocks.reduce((a, b) => a + BigInt(b), 0n);
  const d = dist.connect(oracle);
  const out = { open: await d.openDistribution(range, total, rewards, fees, overrides), pages: [] };
  for (let i = 0; i < addrs.length; i += pageSize) {
    out.pages.push(await d.payPage(addrs.slice(i, i + pageSize), blocks.slice(i, i + pageSize), overrides));
  }
  out.close = await d.closeDistribution(overrides);
  return out;
}
module.exports.distribute = distribute;
