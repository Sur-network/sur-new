// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FoundationDAO.sol";

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// Counterpart of contracts/FoundationDAO.sol (v2.5). The real contract has no constructor (it is
// injected into the genesis `alloc`). This helper INHERITS the real contract, so the storage
// layout is identical by construction (no manual sync needed, unlike the v2.2 copy-based helper),
// and seeds the first board, inspector and officers in its constructor.
//
// Use (simulate-and-extract, see sur-contracts-deploy-notes.md):
//   1. Deploy this helper on a temporary local chain with the real, final addresses.
//   2. Extract its final storage (slots touched by the constructor).
//   3. Write that storage together with the REAL FoundationDAO runtime bytecode (not this file's)
//      under SurAddresses.FOUNDATION_DAO in genesis.json `alloc`, plus 20,000,000 Suren balance.
//
// `principalsAndAlternates`: 5 principal members first, then up to 2 alternates.
// ============================================================================
contract FoundationDAO_GenesisSeed is FoundationDAO {
    constructor(
        address[] memory principalsAndAlternates,
        address inspector_,
        address chair_,
        address treasurer_,
        address ceo_,
        uint256 termEnd
    ) {
        require(principalsAndAlternates.length >= BOARD_SIZE && principalsAndAlternates.length <= BOARD_SIZE + ALTERNATES_SIZE, "seed: 5 to 7 addresses");
        _seedBoard(principalsAndAlternates, inspector_, chair_, treasurer_, ceo_, termEnd);
    }
}
