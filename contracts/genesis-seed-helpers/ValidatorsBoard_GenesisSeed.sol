// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorsBoard.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/ValidatorsBoard.sol. v2.5 change: this helper now INHERITS the real contract, so the storage layout is
// identical by construction (the v2.2 copy-based helper with __gap placeholders had to be kept in sync by hand). It seeds
// the founding state in its constructor; the genesis tool then extracts the touched storage slots (simulate-and-extract,
// see sur-contracts-deploy-notes.md) and writes them together with the REAL contract's runtime bytecode into `alloc`.
// ============================================================================
contract ValidatorsBoard_GenesisSeed is ValidatorsBoard {
    /// @param members exactly BOARD_SIZE (5) founding board members
    /// @param genesisTimestamp must equal genesis.json `timestamp`
    constructor(address[] memory members, uint256 genesisTimestamp) {
        _seedBoard(members, genesisTimestamp);
        boardVersion = 1;
    }
}
