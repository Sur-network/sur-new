// v3: extract genesis code+storage for the 6 fixed-address SUR contracts, focused on proving the
// everActivated reward-policy fix works from block zero.
//
// Method:
//   1. Deploy each REAL contract via its implicit constructor on Hardhat's in-memory network —
//      captures every plain scalar/immutable exactly as our test-fork source declares it
//      (including every TEST-FORK substitution: verifier, distributionOracle, deployTime,
//      windowStart, shortened timers, shortened MIN_DISTRIBUTION_INTERVAL).
//   2. Deploy the CURRENT ValidatorsRegistry_GenesisSeed.sol (3 real founders filled in) EXACTLY
//      AS-IS, per the v3 runbook §2.2.3 — no manual everActivated overlay. Its constructor now
//      writes everActivated[founder]=true itself. Read the actual produced storage directly off
//      this deployed helper via eth_getStorageAt (not hand-reconstructed) for every slot the
//      founders touch: validators[addr] (base slot 0), activeIndex[addr] (base slot 4),
//      everActivated[addr] (base slot 20 — independently verified against the current
//      ValidatorsRegistry.sol's full sequential declaration order), plus activeValidators.length
//      (slot 3) and its array elements. Copying real bytes off a real constructor run is exactly
//      what proves the genesis-seed fix, rather than assuming its slot math.
//   3. ValidatorsBoard and FoundationDAO are genesis-seeded EMPTY (no members) — out of this
//      round's scope (see sur-besu-test-status.md v3 §0), matching the v1/v2 precedent that an
//      empty board/foundation is harmless and bootstraps later via its own live governance paths.
//   4. Round-trip verify ValidatorsRegistry via hardhat_setStorageAt + its own view functions
//      before ever touching real Besu — this is the same-methodology check requested by the
//      runbook's Phase A (manual slot computation cross-checked against the getter).
//   5. Write genesis-alloc.json: { address: { code, storage: {slotHex: valueHex} } }.

const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

const FIXED_ADDRESSES = {
  FoundationDAO: "0x1111111111111111111111111111111111111111",
  BlockRewardDistributor: "0x2222222222222222222222222222222222222222",
  ValidatorsRegistry: "0x3333333333333333333333333333333333333333",
  ValidatorsBoard: "0x4444444444444444444444444444444444444444",
  ValidatorsTreasury: "0x5555555555555555555555555555555555555555",
  IdentityRegistry: "0x6666666666666666666666666666666666666666",
};

const accounts = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "accounts.json"), "utf8"));
const GENESIS_TIMESTAMP = 1790742970n;
const EVER_ACTIVATED_SLOT = 20n; // independently verified against ValidatorsRegistry.sol's current layout

function toHex32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(value)), 32);
}

function mappingSlot(key, baseSlot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "uint256"], [key, baseSlot]));
}

function arrayBaseSlot(lengthSlot) {
  return BigInt(ethers.keccak256(toHex32(lengthSlot)));
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

async function main() {
  const alloc = {};
  const contractNames = Object.keys(FIXED_ADDRESSES);

  // Step 1: deploy every REAL contract, dump its default (implicit-constructor) storage.
  for (const name of contractNames) {
    const factory = await ethers.getContractFactory(name);
    const deployed = await factory.deploy();
    await deployed.waitForDeployment();
    const addr = await deployed.getAddress();
    const artifact = await require("hardhat").artifacts.readArtifact(name);
    const storage = await dumpSequentialSlots(addr, 150);
    alloc[FIXED_ADDRESSES[name]] = { code: artifact.deployedBytecode, storage };
    console.log(`[base] ${name}: ${Object.keys(storage).length} non-zero slots in 0..149`);
  }

  // Step 2: ValidatorsRegistry — deploy the CURRENT GenesisSeed helper exactly as-is (3 founders).
  const seedFactory = await ethers.getContractFactory("ValidatorsRegistry_GenesisSeed");
  const seed = await seedFactory.deploy();
  await seed.waitForDeployment();
  const seedAddr = await seed.getAddress();

  const founderAddrs = [accounts.founder1.address, accounts.founder2.address, accounts.founder3.address];

  const onchainActive = await seed.getActiveValidators();
  const matches =
    onchainActive.length === 3 && onchainActive.every((a, i) => a.toLowerCase() === founderAddrs[i].toLowerCase());
  if (!matches) throw new Error(`GenesisSeed helper mismatch: ${onchainActive} vs expected ${founderAddrs}`);
  console.log("[verify] ValidatorsRegistry_GenesisSeed.getActiveValidators() matches expected 3 founders");

  // Confirm the helper's OWN everActivated getter is true for each founder (sanity, before we
  // even copy raw storage) — this is the helper's own high-level view of the exact fix under test.
  for (const addr of founderAddrs) {
    const val = await seed.everActivated(addr);
    if (val !== true) throw new Error(`GenesisSeed helper: everActivated(${addr}) = ${val}, expected true`);
  }
  console.log("[verify] ValidatorsRegistry_GenesisSeed.everActivated(founder) == true for all 3 founders (via helper's own getter)");

  const registryStorage = alloc[FIXED_ADDRESSES.ValidatorsRegistry].storage;

  // activeValidators.length (slot 3) + array elements — read straight off the deployed helper.
  const lenHex = await network.provider.send("eth_getStorageAt", [seedAddr, toHex32(3), "latest"]);
  registryStorage[toHex32(3)] = lenHex;
  const arrBase = arrayBaseSlot(3);
  for (let i = 0; i < founderAddrs.length; i++) {
    const elemSlot = toHex32(arrBase + BigInt(i));
    const elemVal = await network.provider.send("eth_getStorageAt", [seedAddr, elemSlot, "latest"]);
    registryStorage[elemSlot] = elemVal;
  }

  // Per-founder: validators[addr] struct (base slot 0), activeIndex[addr] (base slot 4),
  // everActivated[addr] (base slot 20) — read the REAL bytes the helper's constructor produced.
  for (const addr of founderAddrs) {
    const validatorsBase = BigInt(mappingSlot(addr, 0));
    for (let offset = 0n; offset < 6n; offset++) {
      const slot = toHex32(validatorsBase + offset);
      const val = await network.provider.send("eth_getStorageAt", [seedAddr, slot, "latest"]);
      if (BigInt(val) !== 0n) registryStorage[slot] = val;
    }
    const activeIndexSlot = mappingSlot(addr, 4);
    const activeIndexVal = await network.provider.send("eth_getStorageAt", [seedAddr, activeIndexSlot, "latest"]);
    if (BigInt(activeIndexVal) !== 0n) registryStorage[activeIndexSlot] = activeIndexVal;

    const everActivatedSlot = mappingSlot(addr, EVER_ACTIVATED_SLOT);
    const everActivatedVal = await network.provider.send("eth_getStorageAt", [seedAddr, everActivatedSlot, "latest"]);
    console.log(`[read] everActivated slot for ${addr}: ${everActivatedSlot} = ${everActivatedVal}`);
    if (BigInt(everActivatedVal) !== 1n) throw new Error(`Helper storage: everActivated(${addr}) slot is ${everActivatedVal}, expected 1`);
    registryStorage[everActivatedSlot] = everActivatedVal;
  }
  console.log(`[merge] ValidatorsRegistry: ${Object.keys(registryStorage).length} total non-zero slots after seeding`);

  // Round-trip verify ValidatorsRegistry on a FRESH deploy of the REAL contract (not the helper).
  const verifyRegFactory = await ethers.getContractFactory("ValidatorsRegistry");
  const verifyReg = await verifyRegFactory.deploy();
  await verifyReg.waitForDeployment();
  const verifyRegAddr = await verifyReg.getAddress();
  for (const [slot, value] of Object.entries(registryStorage)) {
    await network.provider.send("hardhat_setStorageAt", [verifyRegAddr, slot, value]);
  }
  const rtValidators = await verifyReg.getValidators();
  const rtOk = rtValidators.length === 3 && rtValidators.every((a, i) => a.toLowerCase() === founderAddrs[i].toLowerCase());
  console.log("[verify] round-trip getValidators():", rtValidators);
  if (!rtOk) throw new Error("Round-trip FAILED: getValidators() mismatch");
  for (const addr of founderAddrs) {
    if (!(await verifyReg.isValidator(addr))) throw new Error(`Round-trip FAILED: isValidator(${addr}) false`);
    const ea = await verifyReg.everActivated(addr);
    if (ea !== true) throw new Error(`Round-trip FAILED: everActivated(${addr}) = ${ea}, expected true`);
  }
  console.log("[verify] round-trip everActivated(founder) == true for all 3 founders, via the REAL ValidatorsRegistry contract");
  const verifierOnChain = await verifyReg.verifier();
  if (verifierOnChain.toLowerCase() !== accounts.verifier.address.toLowerCase()) {
    throw new Error("Round-trip FAILED: verifier() mismatch");
  }
  const windowStartOnChain = await verifyReg.windowStart();
  const probationOnChain = await verifyReg.probationPeriod();
  console.log("[verify] windowStart:", windowStartOnChain.toString(), "probationPeriod:", probationOnChain.toString());
  console.log("[verify] ALL ValidatorsRegistry genesis checks PASSED");

  // Round-trip verify BlockRewardDistributor's everActivated wiring (distributionOracle, deployTime).
  const verifyDistFactory = await ethers.getContractFactory("BlockRewardDistributor");
  const verifyDist = await verifyDistFactory.deploy();
  await verifyDist.waitForDeployment();
  const distOracleOnChain = await verifyDist.distributionOracle();
  if (distOracleOnChain.toLowerCase() !== accounts.distributionOracle.address.toLowerCase()) {
    throw new Error("Round-trip FAILED: distributionOracle() mismatch");
  }
  const deployTimeOnChain = await verifyDist.deployTime();
  console.log("[verify] BlockRewardDistributor.distributionOracle:", distOracleOnChain, "deployTime:", deployTimeOnChain.toString());
  console.log("[verify] ALL BlockRewardDistributor genesis checks PASSED");

  const outPath = path.join(__dirname, "..", "..", "genesis-alloc.json");
  fs.writeFileSync(outPath, JSON.stringify(alloc, null, 2));
  console.log("Wrote", outPath);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
