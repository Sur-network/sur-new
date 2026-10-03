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
//   1. 🔶 FILL_IN: replace every placeholder address below with the real, final address for
//      each founding member before deploying this file anywhere.
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
contract Testonly_FoundationDAO_GenesisSeed {
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
    // 🔶 FILL_IN: replace every 0x000...000 address with the real, final address for each
    // founding member before this file is ever deployed anywhere.
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
            0x1d3419D1ba10CdfCE6a137130C002b5441278674,
            0x1Bd552985D620F96030Da2f3E2161a269Ca1b7E7,
            0x7E85257f965a31d1157FD5aE540C9A0686bF9fa3,
            0xA500eCbCd8ac3Cd21520E1b8Fe8B5cd7b7BF0B8F,
            0x495F319d34832eA7Be6A385e8D4983dd2eD91115,
            0xdFa4FF4Ed03A219dEF7D23827A8e9CE51278183a,
            0xF5D6528b6233D560039EF83D8390B348ce3D7077,
            0x3af97848C86cB31AeCe53eED39F974F4cAd9cD2f,
            0x075d4A9d73DE61efB4371faF9f9EDBAB4EFfb704,
            0xf1cB3CBB625b470B09f5992eD0472ffE48229f70,
            0xB7D27FBDf075531c431A2d5e53D23C0EA4006966,
            0x183774E2e6Cf9e78Fd4b40d75e40CBE680A60Ee4,
            0xA1D271b5D4C5b5e14685373C4564736E09502d2D,
            0x0aeD318c70D7b6ACB50c0126c55F635a388b7587,
            0xA9e2D7AfE5701278F704B70256c8479c85213ed8
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
