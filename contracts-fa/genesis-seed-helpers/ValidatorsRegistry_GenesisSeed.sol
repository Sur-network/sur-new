// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorsRegistry.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/ValidatorsRegistry.sol. تغییر v2.5: این کمک‌کننده اکنون از قرارداد واقعی ارث می‌برد، پس چیدمان storage
// به‌حکم ساختار یکی است (کمک‌کننده‌ی مبتنی بر کپی در v2.2 با جای‌گیرهای __gap را باید دستی همگام نگه می‌داشتیم). وضعیت
// مؤسس را در constructor خودش seed می‌کند؛ سپس ابزار genesis slotهای storage لمس‌شده را بیرون می‌کشد (شبیه‌سازی و استخراج،
// به sur-contracts-deploy-notes.md مراجعه کن) و آن‌ها را به‌همراه bytecode runtime «قرارداد واقعی» در `alloc` می‌نویسد.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed is ValidatorsRegistry {
    /// @param firstOwner راه‌انداز genesis: تنها ولیدیتوری که در genesis فعال (Active) است
    /// @param firstOperator کلید گره (اپراتور) آن، همان که در genesis کلید QBFT نوشته می‌شود
    /// @param otherFounders مالکان مؤسس دیگر: بدون وثیقه، در Probation تا وقتی اپراتور تعیین کنند و Verifier فعالشان کند
    /// @param genesisTimestamp باید برابر `timestamp` فایل genesis.json باشد
    constructor(address firstOwner, address firstOperator, address[] memory otherFounders, uint256 genesisTimestamp) {
        _seedFirstValidator(firstOwner, firstOperator, genesisTimestamp);
        for (uint256 i = 0; i < otherFounders.length; i++) _seedFounder(otherFounders[i], genesisTimestamp);
    }
}
