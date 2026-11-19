// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorSeatNFT.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/ValidatorSeatNFT.sol. Inherits the real contract (identical storage layout) and mints the founders'
// seats in its constructor, in the SAME ORDER in which the founders are seeded in ValidatorsRegistry_GenesisSeed (first
// validator first), so token ids 1..n match. Genesis tool: deploy on a temporary chain, extract the touched storage (this also
// captures the initial baseURI), write it with the REAL contract's runtime code under SurAddresses.VALIDATOR_SEAT_NFT.
// ============================================================================
contract ValidatorSeatNFT_GenesisSeed is ValidatorSeatNFT {
    constructor(address[] memory founderOwners) {
        for (uint256 i = 0; i < founderOwners.length; i++) _mintSeat(founderOwners[i]);
    }
}
