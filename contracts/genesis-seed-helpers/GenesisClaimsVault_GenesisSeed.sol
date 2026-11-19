// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../GenesisClaimsVault.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/GenesisClaimsVault.sol. Inherits the real contract (identical storage layout) and registers the
// claims in its constructor. Genesis tool: deploy on a temporary chain, extract the touched storage, write it with the REAL
// contract's runtime code under SurAddresses.GENESIS_CLAIMS_VAULT, and credit that address in `alloc` with exactly
// `totalHeld()` (the sum of claim - 100 Suren).
// ============================================================================
contract GenesisClaimsVault_GenesisSeed is GenesisClaimsVault {
    /// @param claimants one merged claim per address
    /// @param claims full claim of each address, including the 100 Suren that go directly to its wallet
    /// @param genesisTimestamp must equal genesis.json `timestamp`
    constructor(address[] memory claimants, uint256[] memory claims, uint256 genesisTimestamp) {
        _seed(claimants, claims, genesisTimestamp);
    }
}
