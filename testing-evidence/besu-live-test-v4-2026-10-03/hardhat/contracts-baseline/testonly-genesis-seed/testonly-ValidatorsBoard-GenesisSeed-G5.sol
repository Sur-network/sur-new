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
contract Testonly_ValidatorsBoard_GenesisSeed_G5 {
    // --- Exact copy of the real ValidatorsBoard.sol, up to the point where mappings/arrays start ---
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    constructor() {
        address[BOARD_SIZE] memory initialBoardMembers = [
            0xbb0ad6351F7566dAeEF259555874053470e195c7, // TESTONLY g5_v1
            0xa0bE660791823a493b965C325D02527f2CFBFC6c, // TESTONLY g5_v2
            0xeAD76a1d9D569762c57A886BB9b17798dF2Defe1, // TESTONLY g5_v3
            0xcdC464346Bf75a910c6C207CA6280E0bA94060B2, // TESTONLY g5_v4
            0x23d8cDa291b4914Cb7742FA2A5d724495377b1DF // TESTONLY g5_v5
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
