// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorsRegistry.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/ValidatorsRegistry.sol. v2.5 change: this helper now INHERITS the real contract, so the storage layout is
// identical by construction (the v2.2 copy-based helper with __gap placeholders had to be kept in sync by hand). It seeds
// the founding state in its constructor; the genesis tool then extracts the touched storage slots (simulate-and-extract,
// see sur-contracts-deploy-notes.md) and writes them together with the REAL contract's runtime bytecode into `alloc`.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed is ValidatorsRegistry {
    /// @param firstOwner the genesis launcher: the only validator Active at genesis
    /// @param firstOperator its node (operator) key, the one written into the QBFT genesis
    /// @param otherFounders the other founding owners: no collateral, Probation until they set an operator and the Verifier activates them
    /// @param genesisTimestamp must equal genesis.json `timestamp`
    constructor(address firstOwner, address firstOperator, address[] memory otherFounders, uint256 genesisTimestamp) {
        _seedFirstValidator(firstOwner, firstOperator, genesisTimestamp);
        for (uint256 i = 0; i < otherFounders.length; i++) _seedFounder(otherFounders[i], genesisTimestamp);
    }
}
