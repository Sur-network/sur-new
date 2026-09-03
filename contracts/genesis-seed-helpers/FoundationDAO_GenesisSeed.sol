// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// This is the TEMPORARY counterpart of: contracts/FoundationDAO.sol
//
// Purpose: the real FoundationDAO.sol has no constructor (it is injected directly into the
// genesis alloc, so a constructor would never execute on the real chain). But three of its
// fields (`memberList`, a dynamic array; and `memberIndex`/`isMember`, mappings) cannot be
// populated with any contract-level Solidity syntax. This helper contract implements that exact
// seeding logic inside a real, NO-ARGUMENT constructor — the 15 founding members' names and
// addresses are hardcoded directly below, not passed in as constructor arguments — so that
// running it once on a temporary local chain (Anvil/Hardhat) lets the EVM itself perform the
// keccak256 storage-slot math required for each mapping/array entry.
//
// How the genesis-building tool should use this file:
//   1. 🔶 FILL_IN: replace every placeholder name/address below with the real, final 15
//      founding members before deploying this file anywhere.
//   2. Deploy this file (no constructor arguments) on a temporary local chain.
//   3. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   4. Write that storage — together with the REAL FoundationDAO.sol's compiled runtime
//      bytecode (NOT this file's bytecode) — under address 0x1111...1111 in genesis.json's
//      `alloc` section.
//
// WARNING: the field order and types below must exactly match the real FoundationDAO.sol, or
// the extracted storage slots will not line up with the final contract. Whenever the real
// FoundationDAO.sol changes, this file must be manually kept in sync.
// ============================================================================
contract FoundationDAO_GenesisSeed {
    // --- Exact copy of the real FoundationDAO.sol, up to the point where mappings/arrays start ---
    struct Member {
        string name;
        address account;
    }

    Member[] public memberList;
    mapping(address => uint256) private memberIndex; // 1-based index into memberList, 0 means not a member
    mapping(address => bool) public isMember;

    // ------------------------------------------------------------------
    // No-argument constructor — all 15 founding members are hardcoded directly below.
    // 🔶 FILL_IN: replace every "Member N" name and every 0x000...000 address with the real,
    // final, agreed-upon founding member list before this file is ever deployed anywhere.
    // ------------------------------------------------------------------
    constructor() {
        string[15] memory names = [
            unicode"Abbas Ashtiani",
            unicode"Alireza Zojaji",
            unicode"Amirabbas Emami",
            unicode"Citex Corp.",
            unicode"Hojjat Abbasi",
            unicode"Kamyar Sharafi",
            unicode"Kaveh Moshtagh",
            unicode"Mahdi Noori",
            unicode"Mahkameh Sharifzad",
            unicode"Maryam Nemati",
            unicode"Mostafa Naghipoorfar",
            unicode"Sepehr Mohammadi",
            unicode"Siavash Tafazzoli",
            unicode"Soheil Nikzad",
            unicode"Yashar Rashedi"
        ];

        address[15] memory accounts = [
            address(0), // Abbas Ashtiani
            address(0), // Alireza Zojaji
            address(0), // Amirabbas Emami
            address(0), // Citex Corp.
            address(0), // Hojjat Abbasi
            address(0), // Kamyar Sharafi
            address(0), // Kaveh Moshtagh
            address(0), // Mahdi Noori
            address(0), // Mahkameh Sharifzad
            address(0), // Maryam Nemati
            address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0), // Siavash Tafazzoli
            address(0), // Soheil Nikzad
            address(0)  // Yashar Rashedi
        ];

        for (uint256 i = 0; i < 15; i++) {
            address account = accounts[i];
            require(account != address(0), "GenesisSeed: zero address - fill in real values first");
            require(!isMember[account], "GenesisSeed: duplicate initial member");

            memberList.push(Member({name: names[i], account: account}));
            memberIndex[account] = memberList.length; // 1-based
            isMember[account] = true;
        }
    }
}
