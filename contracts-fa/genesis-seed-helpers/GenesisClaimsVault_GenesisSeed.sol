// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../GenesisClaimsVault.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/GenesisClaimsVault.sol. از قرارداد واقعی ارث می‌برد (چیدمان storage یکسان) و در constructor خودش
// طلب‌ها را ثبت می‌کند. ابزار genesis: آن را روی یک زنجیره‌ی موقت مستقر کن، storage لمس‌شده را استخراج کن، آن را همراه با
// runtime code ی قرارداد واقعی زیر SurAddresses.GENESIS_CLAIMS_VAULT بنویس و همان آدرس را در `alloc` دقیقاً با
// `totalHeld()` (مجموع طلب − ۱۰۰ سورن) شارژ کن.
// ============================================================================
contract GenesisClaimsVault_GenesisSeed is GenesisClaimsVault {
    /// @param claimants برای هر آدرس یک طلب جمع‌شده
    /// @param claims طلب کامل هر آدرس، شامل ۱۰۰ سورنی که مستقیماً به کیف‌پولش می‌رود
    /// @param genesisTimestamp باید برابر `timestamp` فایل genesis.json باشد
    constructor(address[] memory claimants, uint256[] memory claims, uint256 genesisTimestamp) {
        _seed(claimants, claims, genesisTimestamp);
    }
}
