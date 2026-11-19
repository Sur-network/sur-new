// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FoundationMembers.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/FoundationMembers.sol. از قرارداد واقعی ارث می‌برد (چیدمان storage یکسان) و در
// constructor خودش اعضای اولیه را ثبت می‌کند. همان دستورالعمل شبیه‌سازی و استخراج FoundationDAO_GenesisSeed؛
// storage استخراج‌شده زیر SurAddresses.FOUNDATION_MEMBERS قرار می‌گیرد.
// ============================================================================
contract FoundationMembers_GenesisSeed is FoundationMembers {
    constructor(
        address[] memory accounts,
        string[] memory names,
        PersonType[] memory types,
        address[] memory representatives,
        uint256[] memory shares
    ) {
        require(
            accounts.length == names.length && accounts.length == types.length &&
            accounts.length == representatives.length && accounts.length == shares.length,
            "seed: length mismatch"
        );
        for (uint256 i = 0; i < accounts.length; i++) {
            _addMember(accounts[i], names[i], types[i], representatives[i], shares[i]);
        }
    }
}
