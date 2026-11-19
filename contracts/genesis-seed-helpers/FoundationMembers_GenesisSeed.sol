// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FoundationMembers.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/FoundationMembers.sol. Inherits the real contract (identical storage
// layout) and registers the initial members in its constructor. Same simulate-and-extract recipe
// as FoundationDAO_GenesisSeed; the extracted storage goes under SurAddresses.FOUNDATION_MEMBERS.
// ============================================================================
contract FoundationMembers_GenesisSeed is FoundationMembers {
    constructor(
        address[] memory accounts,
        string[] memory names,
        PersonType[] memory types,
        address[] memory representatives,
        uint256[] memory shares
    ) {
        require(
            accounts.length == names.length && accounts.length == types.length &&
            accounts.length == representatives.length && accounts.length == shares.length,
            "seed: length mismatch"
        );
        for (uint256 i = 0; i < accounts.length; i++) {
            _addMember(accounts[i], names[i], types[i], representatives[i], shares[i]);
        }
    }
}
