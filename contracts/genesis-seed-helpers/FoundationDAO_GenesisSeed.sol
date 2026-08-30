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
// seeding logic inside a real constructor, so that running it once on a temporary local chain
// (Anvil/Hardhat) lets the EVM itself perform the keccak256 storage-slot math required for each
// mapping/array entry.
//
// How the genesis-building tool should use this file:
//   1. Deploy this file on a temporary local chain, with the real names/addresses of the 15
//      founding members.
//   2. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   3. Write that storage — together with the REAL FoundationDAO.sol's compiled runtime
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
    // This constructor is the exact equivalent of the "Reference logic" documented in a comment
    // above the `memberList` declaration in the real FoundationDAO.sol.
    // ------------------------------------------------------------------
    constructor(string[] memory names, address[] memory accounts) {
        require(names.length == accounts.length, "GenesisSeed: length mismatch");
        require(names.length > 0, "GenesisSeed: empty initial member list");
        for (uint256 i = 0; i < names.length; i++) {
            require(bytes(names[i]).length > 0, "GenesisSeed: empty name");
            address account = accounts[i];
            require(account != address(0), "GenesisSeed: zero address");
            require(!isMember[account], "GenesisSeed: duplicate initial member");

            memberList.push(Member({name: names[i], account: account}));
            memberIndex[account] = memberList.length; // 1-based
            isMember[account] = true;
        }
    }
}
