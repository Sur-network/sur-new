// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// GENESIS SEEDING HELPER: temporary, never deployed on the real chain.
//
// Counterpart of contracts/ValidatorsBoard.sol. The real contract has no constructor (it is injected into the genesis
// `alloc`), but `boardMembers` (a dynamic array) and `isBoardMember` (a mapping) cannot be populated with contract-level
// Solidity syntax. This helper runs that seeding logic in a no-argument constructor (the founding members' addresses and the
// genesis timestamp are written directly below), so that running it once on a temporary local chain (Anvil or Hardhat) lets
// the EVM perform the keccak256 storage-slot arithmetic for the array and the mapping.
//
// It also writes `boardVersion` (1) and `boardMonthId` (the calendar month, UTC, of the genesis timestamp). Without
// boardMonthId the founding board would have no authority until the first refreshBoard(). The founders' seatMembershipEpoch
// stays 0, equal to their membershipEpoch in the registry.
//
// How the genesis tool uses this file:
//   1. FILL_IN: replace every placeholder address with the final address of each founding board member and the placeholder
//      GENESIS_TIMESTAMP with the real genesis timestamp (it must equal genesis.json `timestamp`).
//   2. Deploy this file (no constructor arguments) on a temporary local chain.
//   3. Extract its final storage (eth_getStorageAt for every touched slot, or a state-dump tool).
//   4. Write that storage, together with the REAL ValidatorsBoard.sol runtime bytecode (not this file's bytecode), under
//      address 0x4444...4444 in genesis.json `alloc`.
//   5. Assert after the build: boardMonthId equals the month of the genesis timestamp and boardVersion equals 1.
//
// Storage-layout rule: the variable order and types below must match the real ValidatorsBoard.sol exactly. Whenever the real
// contract changes, this file must be updated by hand.
// ============================================================================
contract ValidatorsBoard_GenesisSeed {
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // Slots 2-5 of the real contract (voterCandidates, hasVotedFor, candidateVoters, voterIndexInCandidateVoters): placeholder only.
    uint256[4] private __gap1;

    // Slots 6 and 7 of the real contract. The founding board serves the calendar month of the genesis timestamp; without
    // boardMonthId it would have no authority until the first refreshBoard().
    uint256 public boardVersion;
    uint256 public boardMonthId;

    // FILL_IN: the real genesis timestamp of the live network (it must equal genesis.json `timestamp`).
    uint256 internal constant GENESIS_TIMESTAMP = 0;

    // ------------------------------------------------------------------
    // No-argument constructor: the founding board members (exactly BOARD_SIZE = 5) are written directly below.
    // FILL_IN: replace every address(0) with the final address of each founding board member before this file is deployed.
    // ------------------------------------------------------------------
    constructor() {
        address[BOARD_SIZE] memory initialBoardMembers = [
            address(0), // Alireza Zojaji
            address(0), // Citex Corp.
            address(0), // Mahkameh Sharifzad
            //address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0) // Siavash Tafazzoli
        ];

        for (uint256 i = 0; i < BOARD_SIZE; i++) {
            address m = initialBoardMembers[i];
            require(m != address(0), "GenesisSeed: zero address - fill in real values first");
            require(!isBoardMember[m], "GenesisSeed: duplicate initial board member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }

        boardVersion = 1;
        boardMonthId = _monthIdOf(GENESIS_TIMESTAMP);
    }

    /// @dev Same civil-calendar algorithm as ValidatorsBoard.monthIdOf: year * 12 + (month - 1), UTC.
    function _monthIdOf(uint256 timestamp) internal pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    // Convenience view for manual inspection during testing — plays no role in storage
    // extraction itself.
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }
}
