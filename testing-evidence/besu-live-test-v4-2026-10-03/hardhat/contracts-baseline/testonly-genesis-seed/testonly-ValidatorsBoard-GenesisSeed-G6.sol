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
// seeding logic inside a real, NO-ARGUMENT constructor — the founding board members' addresses
// are hardcoded directly below, not passed in as constructor arguments — so that running it once
// on a temporary local chain (Anvil/Hardhat) lets the EVM itself perform the keccak256
// storage-slot math required for the mapping/array.
//
// How the genesis-building tool should use this file:
//   1. 🔶 FILL_IN: replace every placeholder address below with the real, final address for
//      each founding board member before deploying this file anywhere.
//   2. Deploy this file (no constructor arguments) on a temporary local chain.
//   3. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   4. Write that storage — together with the REAL ValidatorsBoard.sol's compiled runtime
//      bytecode (NOT this file's bytecode) — under address 0x4444...4444 in genesis.json's
//      `alloc` section.
//
// WARNING: the field order and types below must exactly match the real ValidatorsBoard.sol, or
// the extracted storage slots will not line up with the final contract. Whenever the real
// ValidatorsBoard.sol changes, this file must be manually kept in sync.
// ============================================================================
contract Testonly_ValidatorsBoard_GenesisSeed_G6 {
    // --- Exact copy of the real ValidatorsBoard.sol, up to the point where mappings/arrays start ---
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    constructor() {
        address[BOARD_SIZE] memory initialBoardMembers = [
            0xDBa45cFa5bb3Acd3ddaFfe53537a786640e7aF2c, // TESTONLY g6_v1
            0xc5e7c05f442c270e917c42Ae7DDD9b456b0cB5cC, // TESTONLY g6_v2
            0xA0379A0bf817877535Bfd43c58278B765bE85618, // TESTONLY g6_v3
            0xba033D94774c12E26855c61d3f2FBc9098E7dCeb, // TESTONLY g6_v4
            0xd01B11074080932823A66e212f2B1ceFD63887aA // TESTONLY g6_v5
        ];

        for (uint256 i = 0; i < BOARD_SIZE; i++) {
            address m = initialBoardMembers[i];
            require(m != address(0), "GenesisSeed: zero address - fill in real values first");
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
