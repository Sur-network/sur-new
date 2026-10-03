// Phase 0.2.4: hash runtime bytecode + storageLayout for the 6 fixed-address contracts.
const { ethers } = require("hardhat");
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const FIXED = {
  FoundationDAO: "0x1111111111111111111111111111111111111111",
  BlockRewardDistributor: "0x2222222222222222222222222222222222222222",
  ValidatorsRegistry: "0x3333333333333333333333333333333333333333",
  ValidatorsBoard: "0x4444444444444444444444444444444444444444",
  ValidatorsTreasury: "0x5555555555555555555555555555555555555555",
  IdentityRegistry: "0x6666666666666666666666666666666666666666",
};

async function main() {
  const out = {};
  for (const name of Object.keys(FIXED)) {
    const artifact = await hre.artifacts.readArtifact(name);
    const buildInfo = await hre.artifacts.getBuildInfo(`contracts-baseline/${name}.sol:${name}`);
    const contractOutput = buildInfo.output.contracts[`contracts-baseline/${name}.sol`][name];
    const runtimeBytecode = artifact.deployedBytecode;
    const runtimeHash = ethers.keccak256(runtimeBytecode);
    const runtimeSizeBytes = (runtimeBytecode.length - 2) / 2;
    const storageLayout = contractOutput.storageLayout;
    out[name] = {
      address: FIXED[name],
      runtimeHash,
      runtimeSizeBytes,
      storageLayout,
    };
    console.log(`${name} (${FIXED[name]}): runtimeHash=${runtimeHash} size=${runtimeSizeBytes} bytes`);
  }

  const distSize = out.BlockRewardDistributor.runtimeSizeBytes;
  console.log(`\nBlockRewardDistributor runtime size: ${distSize} bytes (doc reference: 18177 bytes)`);
  if (distSize !== 18177) {
    console.log(`DEVIATION: size differs from doc reference (${distSize} vs 18177)`);
  }

  const outPath = path.join(__dirname, "..", "..", "evidence", "00-baseline", "fixed-contracts-fingerprint.json");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("\nWrote", outPath);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
