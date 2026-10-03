// TESTONLY TOOL — builds genesis.json + node configs for one network.
// Reads its configuration from process.env (set by the orchestrator before invoking
// `npx hardhat run` for this script), since `hardhat run` does not forward argv cleanly.
//
// Required env vars:
//   BUILDER_NET          network name, e.g. "Net-B"
//   BUILDER_FOUNDERS     "G5" or "G6"
//   BUILDER_CANDIDATE    "1" to also fund+prepare C6 (not genesis-active) or "0"
//   BUILDER_CHAINID      numeric
//   BUILDER_GASLIMIT     numeric (wei-free, plain block gas limit)
//   BUILDER_SEED_BOARD   "1" or "0"  (when seeded, lastBoardRefreshAt = genesis timestamp; BUILDER_BOARD_REFRESH_ZERO=1 = old behaviour, negative control only)
//   BUILDER_SEED_FOUNDATION "1" or "0"
//   BUILDER_PROJECT_ROOT absolute path to this hardhat project's parent test dir (besu-test-v4)
//   BUILDER_IS_FORK      "1" if this is the hardhat-fork project (affects which contract names apply, none differ actually)
const { ethers, network } = require("hardhat");
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = process.env.BUILDER_PROJECT_ROOT;
const NET = process.env.BUILDER_NET;
const FOUNDERS = process.env.BUILDER_FOUNDERS;
const INCLUDE_C6 = process.env.BUILDER_CANDIDATE === "1";
const CHAIN_ID = Number(process.env.BUILDER_CHAINID);
const GAS_LIMIT = Number(process.env.BUILDER_GASLIMIT || 30000000);
const SEED_BOARD = process.env.BUILDER_SEED_BOARD !== "0";
const SEED_FOUNDATION = process.env.BUILDER_SEED_FOUNDATION !== "0";
const IS_FORK = process.env.BUILDER_IS_FORK === "1";
// v5 additions (this round's follow-up: Groups E/F, D02 accounting). All optional; unset = identical to the earlier builder.
//   BUILDER_TRANSITIONS   JSON, e.g. [{"block":300,"blockreward":"3000000000000000000"}]  -> config.transitions.qbft
//   BUILDER_RATE_HISTORY  "F300" -> [(300, 3e18)] ; "E399" -> 399 entries (151+i, 2e18) ; or JSON [[startBlock,"rateWei"],...]   (TEST-ONLY-SEED, direct storage write)
//   BUILDER_PAYEES        N -> N deterministic payee addresses with everActivated=true (TEST-ONLY-SEED), written to nets/<NET>/payees.json
const TRANSITIONS = process.env.BUILDER_TRANSITIONS ? JSON.parse(process.env.BUILDER_TRANSITIONS) : null;
const RATE_HISTORY_SPEC = process.env.BUILDER_RATE_HISTORY || "";
const PAYEES = Number(process.env.BUILDER_PAYEES || 0);

const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));

const FIXED = {
  FoundationDAO: "0x1111111111111111111111111111111111111111",
  BlockRewardDistributor: "0x2222222222222222222222222222222222222222",
  ValidatorsRegistry: "0x3333333333333333333333333333333333333333",
  ValidatorsBoard: "0x4444444444444444444444444444444444444444",
  ValidatorsTreasury: "0x5555555555555555555555555555555555555555",
  IdentityRegistry: "0x6666666666666666666666666666666666666666",
};

// ValidatorsRegistry overlay slots (verified against this build's own storageLayout below, not assumed)
const OVERLAY = {
  probationPeriod: 300n,
  recoveryPeriod: 3700n,
  exitCooldown: 600n,
  maxEntriesPerWindow: 10n,
};

function toHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(value)), 32);
}
function mappingSlot(key, baseSlot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "uint256"], [key, baseSlot]));
}
function arrayBaseSlot(lengthSlot) {
  return BigInt(ethers.keccak256(toHex32(lengthSlot)));
}
function shortStringSlotValue(str) {
  const bytes = ethers.toUtf8Bytes(str);
  if (bytes.length >= 32) throw new Error(`string too long for short-string encoding: ${str}`);
  const buf = new Uint8Array(32);
  buf.set(bytes, 0);
  buf[31] = bytes.length * 2;
  return ethers.hexlify(buf);
}
async function dumpSequentialSlots(address, count) {
  const storage = {};
  for (let i = 0; i < count; i++) {
    const slotHex = toHex32(i);
    const value = await network.provider.send("eth_getStorageAt", [address, slotHex, "latest"]);
    if (BigInt(value) !== 0n) storage[slotHex] = value;
  }
  return storage;
}
function slotOf(layout, label) {
  const item = layout.storage.find((s) => s.label === label);
  if (!item) throw new Error(`slot not found for ${label}`);
  return BigInt(item.slot);
}

async function main() {
  const genesisTimestamp = Math.floor(Date.now() / 1000) - 60; // already in the past, avoids the v3 future-timestamp bug
  console.log(`[${NET}] genesisTimestamp = ${genesisTimestamp} (${new Date(genesisTimestamp * 1000).toISOString()})`);

  const founderRoleList = FOUNDERS === "G5" ? ["g5_v1", "g5_v2", "g5_v3", "g5_v4", "g5_v5"] : ["g6_v1", "g6_v2", "g6_v3", "g6_v4", "g6_v5", "g6_v6"];
  const founderAddrs = founderRoleList.map((r) => accounts[r].address);
  const regSeedName = FOUNDERS === "G5" ? "Testonly_ValidatorsRegistry_GenesisSeed_G5" : "Testonly_ValidatorsRegistry_GenesisSeed_G6";
  const boardSeedName = FOUNDERS === "G5" ? "Testonly_ValidatorsBoard_GenesisSeed_G5" : "Testonly_ValidatorsBoard_GenesisSeed_G6";

  const alloc = {};
  const contractNames = Object.keys(FIXED);
  const layouts = {};
  for (const name of contractNames) {
    const factory = await ethers.getContractFactory(name);
    const deployed = await factory.deploy();
    await deployed.waitForDeployment();
    const addr = await deployed.getAddress();
    const artifact = await hre.artifacts.readArtifact(name);
    const storage = await dumpSequentialSlots(addr, 150);
    alloc[FIXED[name]] = { code: artifact.deployedBytecode, storage };
    const sourceGlob = IS_FORK ? "contracts-testfork" : "contracts-baseline";
    const buildInfo = await hre.artifacts.getBuildInfo(`${sourceGlob}/${name}.sol:${name}`);
    layouts[name] = buildInfo.output.contracts[`${sourceGlob}/${name}.sol`][name].storageLayout;
    console.log(`[base] ${name}: ${Object.keys(storage).length} non-zero slots`);
  }

  // --- ValidatorsRegistry: deploy the parameterized-by-copy seed helper exactly as-is, read its
  // real produced storage off the deployed helper via eth_getStorageAt (not hand-reconstructed).
  const seedFactory = await ethers.getContractFactory(regSeedName);
  const seed = await seedFactory.deploy();
  await seed.waitForDeployment();
  const seedAddr = await seed.getAddress();
  const onchainActive = await seed.getActiveValidators();
  if (onchainActive.length !== founderAddrs.length || !onchainActive.every((a, i) => a.toLowerCase() === founderAddrs[i].toLowerCase())) {
    throw new Error(`GenesisSeed mismatch: ${onchainActive} vs expected ${founderAddrs}`);
  }
  for (const addr of founderAddrs) {
    if (!(await seed.everActivated(addr))) throw new Error(`Helper everActivated(${addr}) false`);
  }
  console.log(`[verify] ${regSeedName}.getActiveValidators() + everActivated all true for ${founderAddrs.length} founders`);

  const registryStorage = alloc[FIXED.ValidatorsRegistry].storage;
  const regLayout = layouts.ValidatorsRegistry;
  const everActivatedSlot = slotOf(regLayout, "everActivated");
  const activeIndexSlot = slotOf(regLayout, "activeIndex");
  const activeValidatorsSlot = slotOf(regLayout, "activeValidators");
  const statusNonceSlot = slotOf(regLayout, "statusNonce");
  const activeCheckpointsSlot = slotOf(regLayout, "activeCheckpoints");
  console.log(`[slots] everActivated=${everActivatedSlot} activeIndex=${activeIndexSlot} activeValidators=${activeValidatorsSlot} statusNonce=${statusNonceSlot} activeCheckpoints=${activeCheckpointsSlot}`);

  const lenHex = await network.provider.send("eth_getStorageAt", [seedAddr, toHex32(activeValidatorsSlot), "latest"]);
  registryStorage[toHex32(activeValidatorsSlot)] = lenHex;
  const arrBase = arrayBaseSlot(activeValidatorsSlot);
  for (let i = 0; i < founderAddrs.length; i++) {
    const elemSlot = toHex32(arrBase + BigInt(i));
    registryStorage[elemSlot] = await network.provider.send("eth_getStorageAt", [seedAddr, elemSlot, "latest"]);
  }
  for (const addr of founderAddrs) {
    const validatorsBase = BigInt(mappingSlot(addr, 0));
    for (let offset = 0n; offset < 6n; offset++) {
      const slot = toHex32(validatorsBase + offset);
      const val = await network.provider.send("eth_getStorageAt", [seedAddr, slot, "latest"]);
      if (BigInt(val) !== 0n) registryStorage[slot] = val;
    }
    const activeIdxSlot = mappingSlot(addr, activeIndexSlot);
    const activeIdxVal = await network.provider.send("eth_getStorageAt", [seedAddr, activeIdxSlot, "latest"]);
    if (BigInt(activeIdxVal) !== 0n) registryStorage[activeIdxSlot] = activeIdxVal;

    const everActSlot = mappingSlot(addr, everActivatedSlot);
    const everActVal = await network.provider.send("eth_getStorageAt", [seedAddr, everActSlot, "latest"]);
    if (BigInt(everActVal) !== 1n) throw new Error(`everActivated storage for ${addr} is ${everActVal}`);
    registryStorage[everActSlot] = everActVal;

    // activeCheckpoints[addr] is a dynamic array (length 1) at mapping base -> base slot holds length,
    // element 0 lives at keccak256(baseSlot). Read both directly off the deployed helper.
    const checkpointBaseSlotHex = mappingSlot(addr, activeCheckpointsSlot);
    const checkpointLen = await network.provider.send("eth_getStorageAt", [seedAddr, checkpointBaseSlotHex, "latest"]);
    if (BigInt(checkpointLen) !== 0n) registryStorage[checkpointBaseSlotHex] = checkpointLen;
    const checkpointElemSlot = toHex32(arrayBaseSlot(BigInt(checkpointBaseSlotHex)));
    const checkpointElemVal = await network.provider.send("eth_getStorageAt", [seedAddr, checkpointElemSlot, "latest"]);
    if (BigInt(checkpointElemVal) !== 0n) registryStorage[checkpointElemSlot] = checkpointElemVal;
  }
  // periodStartedAt must reflect the REAL genesis timestamp (helper used its own build-time value) —
  // patch it directly: offset 2 within the ValidatorInfo struct (status=0, lockedStake=1, periodStartedAt=2).
  for (const addr of founderAddrs) {
    const validatorsBase = BigInt(mappingSlot(addr, 0));
    registryStorage[toHex32(validatorsBase + 2n)] = toHex32(genesisTimestamp);
  }

  // Genesis overlays (state-variable overlays, NOT a source change) — per v4 section 4 table.
  registryStorage[toHex32(slotOf(regLayout, "verifier"))] = toHex32(accounts.verifier.address);
  registryStorage[toHex32(slotOf(regLayout, "probationPeriod"))] = toHex32(OVERLAY.probationPeriod);
  registryStorage[toHex32(slotOf(regLayout, "recoveryPeriod"))] = toHex32(OVERLAY.recoveryPeriod);
  registryStorage[toHex32(slotOf(regLayout, "exitCooldown"))] = toHex32(OVERLAY.exitCooldown);
  registryStorage[toHex32(slotOf(regLayout, "maxEntriesPerWindow"))] = toHex32(OVERLAY.maxEntriesPerWindow);
  registryStorage[toHex32(slotOf(regLayout, "windowStart"))] = toHex32(genesisTimestamp);

  // Round-trip verify on a fresh deploy of the REAL contract before ever touching Besu.
  const verifyRegFactory = await ethers.getContractFactory("ValidatorsRegistry");
  const verifyReg = await verifyRegFactory.deploy();
  await verifyReg.waitForDeployment();
  const verifyRegAddr = await verifyReg.getAddress();
  for (const [slot, value] of Object.entries(registryStorage)) {
    await network.provider.send("hardhat_setStorageAt", [verifyRegAddr, slot, value]);
  }
  const rtValidators = await verifyReg.getValidators();
  if (rtValidators.length !== founderAddrs.length || !rtValidators.every((a, i) => a.toLowerCase() === founderAddrs[i].toLowerCase())) {
    throw new Error(`Round-trip FAILED getValidators(): ${rtValidators}`);
  }
  for (const addr of founderAddrs) {
    if (!(await verifyReg.isValidator(addr))) throw new Error(`Round-trip isValidator(${addr}) false`);
    if (!(await verifyReg.everActivated(addr))) throw new Error(`Round-trip everActivated(${addr}) false`);
    if (!(await verifyReg.wasActiveAt(addr, 0))) throw new Error(`Round-trip wasActiveAt(${addr},0) false`);
  }
  if (await verifyReg.wasActiveAt(accounts.fakeAddress.address, 0)) throw new Error("Round-trip wasActiveAt(fakeAddress,0) should be false");
  console.log(`[verify] ${NET}: round-trip getValidators/isValidator/everActivated/wasActiveAt ALL PASSED`);

  // --- ValidatorsBoard (optional) ---
  if (SEED_BOARD) {
    const boardFactory = await ethers.getContractFactory(boardSeedName);
    const boardSeed = await boardFactory.deploy();
    await boardSeed.waitForDeployment();
    const boardSeedAddr = await boardSeed.getAddress();
    const boardStorage = alloc[FIXED.ValidatorsBoard].storage;
    const boardMembersLen = await network.provider.send("eth_getStorageAt", [boardSeedAddr, toHex32(0), "latest"]);
    boardStorage[toHex32(0)] = boardMembersLen;
    const boardArrBase = arrayBaseSlot(0n);
    const boardMembers = founderAddrs.slice(0, 5);
    for (let i = 0; i < boardMembers.length; i++) {
      const slot = toHex32(boardArrBase + BigInt(i));
      boardStorage[slot] = await network.provider.send("eth_getStorageAt", [boardSeedAddr, slot, "latest"]);
    }
    for (const addr of boardMembers) {
      boardStorage[mappingSlot(addr, 1)] = toHex32(1);
    }
    console.log(`[board] seeded ${boardMembers.length} members`);
    // A09 fix (2026-10-04): genesis-builder spec 4.2.1 / P01 — when the board is seeded, lastBoardRefreshAt must equal the genesis timestamp
    // (otherwise refreshBoard() is allowed immediately instead of after BOARD_REFRESH_INTERVAL = 30 days). BUILDER_BOARD_REFRESH_ZERO=1 reproduces the
    // pre-fix behaviour (value 0) and exists ONLY to build a negative-control network.
    if (process.env.BUILDER_BOARD_REFRESH_ZERO !== "1") {
      boardStorage[toHex32(slotOf(layouts.ValidatorsBoard, "lastBoardRefreshAt"))] = toHex32(genesisTimestamp);
      console.log(`[board] lastBoardRefreshAt = genesisTimestamp = ${genesisTimestamp}`);
    } else console.log("[board] NEGATIVE CONTROL build: lastBoardRefreshAt left at 0 (pre-fix behaviour)");
  }

  // --- FoundationDAO (optional) ---
  if (SEED_FOUNDATION) {
    const fdFactory = await ethers.getContractFactory("Testonly_FoundationDAO_GenesisSeed");
    const fdSeed = await fdFactory.deploy();
    await fdSeed.waitForDeployment();
    const foundationAddrs = Array.from({ length: 15 }, (_, i) => accounts[`foundation${i + 1}`].address);
    const names = [];
    for (let i = 0; i < 15; i++) {
      const [name] = await fdSeed.memberList(i);
      names.push(name);
    }
    const fdStorage = alloc[FIXED.FoundationDAO].storage;
    fdStorage[toHex32(0)] = toHex32(15);
    const fdArrBase = arrayBaseSlot(0n);
    for (let i = 0; i < 15; i++) {
      fdStorage[toHex32(fdArrBase + BigInt(2 * i))] = shortStringSlotValue(names[i]);
      fdStorage[toHex32(fdArrBase + BigInt(2 * i) + 1n)] = toHex32(foundationAddrs[i]);
    }
    foundationAddrs.forEach((addr, i) => {
      fdStorage[mappingSlot(addr, 1)] = toHex32(i + 1);
      fdStorage[mappingSlot(addr, 2)] = toHex32(1);
    });
    console.log(`[foundation] seeded 15 members`);
  }

  // --- BlockRewardDistributor overlay: distributionOracle ---
  const distLayout = layouts.BlockRewardDistributor;
  const distStorage = alloc[FIXED.BlockRewardDistributor].storage;
  distStorage[toHex32(slotOf(distLayout, "distributionOracle"))] = toHex32(accounts.distributionOracle.address);

  // --- v5: TEST-ONLY-SEED of the reward-rate history (BlockRewardDistributor.rewardRateChanges, private array of
  // struct{uint128 startBlock; uint128 ratePerBlock} = ONE slot per element, startBlock in the low 128 bits).
  let rateHistory = [];
  if (RATE_HISTORY_SPEC === "F300") rateHistory = [[300, 3000000000000000000n]];
  else if (RATE_HISTORY_SPEC === "E399") rateHistory = Array.from({ length: 399 }, (_, i) => [151 + i, 2000000000000000000n]);
  else if (RATE_HISTORY_SPEC) rateHistory = JSON.parse(RATE_HISTORY_SPEC).map(([s, r]) => [Number(s), BigInt(r)]);
  if (rateHistory.length) {
    const histSlot = slotOf(distLayout, "rewardRateChanges");
    distStorage[toHex32(histSlot)] = toHex32(rateHistory.length);
    const histBase = arrayBaseSlot(histSlot);
    rateHistory.forEach(([s, r], i) => {
      distStorage[toHex32(histBase + BigInt(i))] = toHex32((BigInt(r) << 128n) | BigInt(s));
    });
    // round-trip on a fresh deploy of the REAL distributor (before Besu is ever touched)
    const vf = await ethers.getContractFactory("BlockRewardDistributor");
    const vd = await vf.deploy();
    await vd.waitForDeployment();
    const vdAddr = await vd.getAddress();
    for (const [slot, value] of Object.entries(distStorage)) await network.provider.send("hardhat_setStorageAt", [vdAddr, slot, value]);
    if (Number(await vd.rewardRateChangeCount()) !== rateHistory.length) throw new Error("rate-history round-trip: count mismatch");
    for (const i of [0, rateHistory.length - 1]) {
      const [s, r] = await vd.rewardRateChange(i);
      if (Number(s) !== rateHistory[i][0] || BigInt(r) !== BigInt(rateHistory[i][1])) throw new Error(`rate-history round-trip: entry ${i} mismatch`);
    }
    console.log(`[seed] rewardRateChanges slot=${histSlot}, ${rateHistory.length} entries written + round-tripped (TEST-ONLY-SEED)`);
  }

  // --- v5: TEST-ONLY-SEED of N payee addresses: ValidatorsRegistry.everActivated[addr]=true (they are NOT validators) ---
  let payees = [];
  if (PAYEES > 0) {
    payees = Array.from({ length: PAYEES }, (_, i) => ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes(`SUR-v5-E-payee-${i}`)).slice(26)));
    payees.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
    for (const a of payees) registryStorage[mappingSlot(a, everActivatedSlot)] = toHex32(1);
    const rf = await ethers.getContractFactory("ValidatorsRegistry");
    const rd = await rf.deploy();
    await rd.waitForDeployment();
    const rdAddr = await rd.getAddress();
    for (const [slot, value] of Object.entries(registryStorage)) await network.provider.send("hardhat_setStorageAt", [rdAddr, slot, value]);
    for (const a of payees) {
      if (!(await rd.everActivated(a))) throw new Error(`payee everActivated round-trip false: ${a}`);
      if (await rd.isValidator(a)) throw new Error(`payee unexpectedly a validator: ${a}`);
    }
    console.log(`[seed] ${payees.length} payees everActivated=true, none are validators (round-tripped, TEST-ONLY-SEED)`);
  }

  // --- Genesis JSON assembly ---
  const finalAlloc = {};
  for (const [addr, data] of Object.entries(alloc)) finalAlloc[addr] = { code: data.code, storage: data.storage };

  const BIG_BALANCE = "0x" + ethers.parseEther("5000000").toString(16);
  const ORACLE_BALANCE = "0x" + ethers.parseEther("50000").toString(16);
  for (const role of founderRoleList) finalAlloc[accounts[role].address.toLowerCase()] = { balance: BIG_BALANCE };
  if (INCLUDE_C6) finalAlloc[accounts.g5_c6.address.toLowerCase()] = { balance: BIG_BALANCE };
  for (const role of ["verifier", "distributionOracle"]) finalAlloc[accounts[role].address.toLowerCase()] = { balance: ORACLE_BALANCE };
  for (const role of ["serviceStakingUser1", "serviceStakingUser2"]) finalAlloc[accounts[role].address.toLowerCase()] = { balance: BIG_BALANCE };

  const extraData = ethers.encodeRlp(["0x" + "00".repeat(32), [], [], "0x", []]);

  const genesis = {
    config: {
      chainId: CHAIN_ID,
      homesteadBlock: 0, eip150Block: 0, eip155Block: 0, eip158Block: 0,
      byzantiumBlock: 0, constantinopleBlock: 0, petersburgBlock: 0, istanbulBlock: 0,
      berlinBlock: 0, londonBlock: 0,
      zeroBaseFee: true,
      qbft: {
        blockperiodseconds: 3,
        epochlength: 30000,
        requesttimeoutseconds: 10,
        validatorcontractaddress: FIXED.ValidatorsRegistry,
        miningbeneficiary: FIXED.BlockRewardDistributor,
        blockreward: "2000000000000000000",
      },
      ...(TRANSITIONS ? { transitions: { qbft: TRANSITIONS } } : {}),
    },
    gasLimit: "0x" + GAS_LIMIT.toString(16),
    difficulty: "0x1",
    timestamp: "0x" + genesisTimestamp.toString(16),
    extraData,
    alloc: finalAlloc,
  };

  const netDir = path.join(ROOT, "nets", NET);
  fs.mkdirSync(netDir, { recursive: true });
  fs.writeFileSync(path.join(netDir, "genesis.json"), JSON.stringify(genesis, null, 2));
  if (payees.length) fs.writeFileSync(path.join(netDir, "payees.json"), JSON.stringify(payees, null, 2));
  console.log(`[${NET}] wrote genesis.json, chainId=${CHAIN_ID}, gasLimit=${GAS_LIMIT}, timestamp=${genesisTimestamp}`);

  const evidenceDir = path.join(ROOT, "evidence", "02-genesis", NET);
  fs.mkdirSync(evidenceDir, { recursive: true });
  fs.copyFileSync(path.join(netDir, "genesis.json"), path.join(evidenceDir, "genesis.json"));
  fs.writeFileSync(
    path.join(evidenceDir, "seed-summary.json"),
    JSON.stringify({ NET, FOUNDERS, founderAddrs, INCLUDE_C6, genesisTimestamp, CHAIN_ID, GAS_LIMIT, IS_FORK, TRANSITIONS, RATE_HISTORY_SPEC, RATE_HISTORY_ENTRIES: rateHistory.length, PAYEES: payees.length, TEST_ONLY_SEED: rateHistory.length > 0 || payees.length > 0, OVERLAY: Object.fromEntries(Object.entries(OVERLAY).map(([k, v]) => [k, v.toString()])) }, null, 2)
  );
  console.log(`[${NET}] wrote evidence to ${evidenceDir}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
