require("@nomicfoundation/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      viaIR: false,
      optimizer: { enabled: true, runs: 200 },
      outputSelection: {
        "*": {
          "*": ["evm.deployedBytecode", "storageLayout", "evm.bytecode", "abi"],
        },
      },
    },
  },
  paths: {
    sources: "./contracts-testfork",
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
  },
};
