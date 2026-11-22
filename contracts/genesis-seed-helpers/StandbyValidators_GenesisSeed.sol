// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/StandbyValidators.sol. Unlike the other helpers it does NOT inherit the real contract: the real list
// `_members` is private, so a child cannot write it, and the real setStandby() is FoundationDAO-only and checks every member
// against ValidatorsRegistry (which does not exist on the temporary chain). This helper therefore repeats the three state
// variables of StandbyValidators in the SAME ORDER with the SAME types and names, and the genesis tool compares the compiler's
// storage layout of the two (assertSameLayout) and refuses to build if they differ.
//
// It writes exactly what setStandby(members) writes for the first call: `_members = members; version = 1; updatedAt = now`.
// The genesis tool passes `members = [firstValidator.operator]` and `genesisTimestamp` (the genesis.json timestamp, which the
// real setStandby would have read from block.timestamp). Whether the member is a current operator in the seeded
// ValidatorsRegistry is checked afterwards on the finished genesis (isReady(), staleMembers()).
// ============================================================================
contract StandbyValidators_GenesisSeed {
    address[] private _members;
    uint256 public version;
    uint256 public updatedAt;

    /// @param members the standby list, strictly ascending and non-zero (same rule as setStandby)
    /// @param genesisTimestamp must equal genesis.json `timestamp`
    constructor(address[] memory members, uint256 genesisTimestamp) {
        require(members.length >= 1, "StandbyValidators_GenesisSeed: empty list");
        address prev = address(0);
        for (uint256 i = 0; i < members.length; i++) {
            require(members[i] > prev, "StandbyValidators_GenesisSeed: members must be strictly ascending and non-zero");
            prev = members[i];
        }
        _members = members;
        version = 1;
        updatedAt = genesisTimestamp;
    }

    /// @dev Only so the genesis tool can read the seeded list back on the temporary chain (the real contract has the same getter).
    function getValidators() external view returns (address[] memory) {
        return _members;
    }
}
