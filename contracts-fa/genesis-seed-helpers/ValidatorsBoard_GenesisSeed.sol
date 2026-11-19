// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorsBoard.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/ValidatorsBoard.sol. تغییر v2.5: این کمک‌کننده اکنون از قرارداد واقعی ارث می‌برد، پس چیدمان storage
// به‌حکم ساختار یکی است (کمک‌کننده‌ی مبتنی بر کپی در v2.2 با جای‌گیرهای __gap را باید دستی همگام نگه می‌داشتیم). وضعیت
// مؤسس را در constructor خودش seed می‌کند؛ سپس ابزار genesis slotهای storage لمس‌شده را بیرون می‌کشد (شبیه‌سازی و استخراج،
// به sur-contracts-deploy-notes.md مراجعه کن) و آن‌ها را به‌همراه bytecode runtime «قرارداد واقعی» در `alloc` می‌نویسد.
// ============================================================================
contract ValidatorsBoard_GenesisSeed is ValidatorsBoard {
    /// @param members دقیقاً BOARD_SIZE (۵) عضو مؤسس هیأت
    /// @param genesisTimestamp باید برابر `timestamp` فایل genesis.json باشد
    constructor(address[] memory members, uint256 genesisTimestamp) {
        _seedBoard(members, genesisTimestamp);
        boardVersion = 1;
    }
}
