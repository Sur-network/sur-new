// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// This is the TEMPORARY counterpart of: contracts/ValidatorsBoard.sol
//
// Purpose: the real ValidatorsBoard.sol has no constructor (it is injected directly into the
// genesis alloc). But `boardMembers` (a dynamic array) and `isBoardMember` (a mapping) cannot be
// populated with any contract-level Solidity syntax. This helper contract implements that exact
// seeding logic inside a real constructor, so that running it once on a temporary local chain
// (Anvil/Hardhat) lets the EVM itself perform the keccak256 storage-slot math required for the
// mapping/array.
//
// How the genesis-building tool should use this file:
//   1. Deploy this file on a temporary local chain, with the real addresses of the 5 founding
//      board members.
//   2. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   3. Write that storage — together with the REAL ValidatorsBoard.sol's compiled runtime
//      bytecode (NOT this file's bytecode) — under address 0x4444...4444 in genesis.json's
//      `alloc` section.
//
// WARNING: the field order and types below must exactly match the real ValidatorsBoard.sol, or
// the extracted storage slots will not line up with the final contract. Whenever the real
// ValidatorsBoard.sol changes, this file must be manually kept in sync.
// ============================================================================
contract ValidatorsBoard_GenesisSeed {
    // --- Exact copy of the real ValidatorsBoard.sol, up to the point where mappings/arrays start ---
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // ------------------------------------------------------------------
    // This constructor is the exact equivalent of the "Reference logic" documented in a comment
    // above the `boardMembers` declaration in the real ValidatorsBoard.sol.
    // ------------------------------------------------------------------
    constructor(address[] memory initialBoardMembers) {
        require(initialBoardMembers.length == BOARD_SIZE, "GenesisSeed: must supply exactly BOARD_SIZE members");
        for (uint256 i = 0; i < initialBoardMembers.length; i++) {
            address m = initialBoardMembers[i];
            require(m != address(0), "GenesisSeed: zero address");
            require(!isBoardMember[m], "GenesisSeed: duplicate initial board member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }
    }

    // Convenience view for manual inspection during testing — plays no role in storage
    // extraction itself.
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }
}
