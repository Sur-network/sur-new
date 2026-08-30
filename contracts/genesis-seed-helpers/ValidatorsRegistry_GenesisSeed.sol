// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// This is the TEMPORARY counterpart of: contracts/ValidatorsRegistry.sol
//
// Purpose: the real ValidatorsRegistry.sol has no constructor (it is injected directly into the
// genesis alloc). But `validators` (a mapping to a struct), `activeValidators` (a dynamic
// array), and `activeIndex` (a mapping) cannot be populated with any contract-level Solidity
// syntax. This helper contract implements that exact seeding logic inside a real constructor,
// so that running it once on a temporary local chain (Anvil/Hardhat) lets the EVM itself
// perform the keccak256 storage-slot math required for each mapping/array entry.
//
// How the genesis-building tool should use this file:
//   1. Deploy this file on a temporary local chain, with the real initial validator addresses
//      and the real genesis timestamp.
//   2. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   3. Write that storage — together with the REAL ValidatorsRegistry.sol's compiled runtime
//      bytecode (NOT this file's bytecode) — under address 0x3333...3333 in genesis.json's
//      `alloc` section.
//
// WARNING: the field order and types below must exactly match the real ValidatorsRegistry.sol,
// or the extracted storage slots will not line up with the final contract. Whenever the real
// ValidatorsRegistry.sol changes, this file must be manually kept in sync. Note: the security
// and economic parameters (which are simple scalar values, not mappings/arrays) are NOT
// repeated here — those are filled directly in the real contract's source with 🔶 FILL_IN
// markers and don't need this helper.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed {
    // --- Exact copy of the real ValidatorsRegistry.sol, up to the point where mappings/arrays start ---
    enum Status { None, Probation, Active, Demoted, Exiting }

    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;
        uint256 lastLivenessConfirmation;
        uint256 livenessConfirmationsInPeriod;
        uint256 demotedAt;
    }

    mapping(address => ValidatorInfo) public validators;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // This constructor is the exact equivalent of the "Reference logic" documented in a comment
    // above the `activeValidators` declaration in the real ValidatorsRegistry.sol.
    // ------------------------------------------------------------------
    constructor(uint256 genesisTimestamp, address[] memory initialValidators) {
        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "GenesisSeed: zero address");
            require(validators[v].status == Status.None, "GenesisSeed: duplicate initial validator");

            validators[v] = ValidatorInfo({
                status: Status.Active,
                lockedStake: 0,
                periodStartedAt: genesisTimestamp,
                lastLivenessConfirmation: genesisTimestamp,
                livenessConfirmationsInPeriod: 0,
                demotedAt: 0
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
        }
    }

    // Convenience view for manual inspection during testing — plays no role in storage
    // extraction itself.
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
