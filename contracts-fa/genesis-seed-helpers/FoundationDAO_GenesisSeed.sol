// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FoundationDAO.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/FoundationDAO.sol (v2.5). قرارداد واقعی constructor ندارد (در `alloc` بلاک genesis
// تزریق می‌شود). این کمک‌کننده از قرارداد واقعی ارث می‌برد، پس چیدمان storage به‌حکم ساختار یکی است (برخلاف
// کمک‌کننده‌ی مبتنی بر کپی در v2.2 نیازی به همگام‌سازی دستی نیست)، و در constructor خودش هیأت اول،
// بازرس و افسران را seed می‌کند.
//
// نحوه‌ی استفاده (شبیه‌سازی و استخراج؛ به sur-contracts-deploy-notes.md مراجعه کن):
//   ۱. این کمک‌کننده را با آدرس‌های واقعی و نهایی روی یک زنجیره‌ی محلی موقت مستقر کن.
//   ۲. storage نهایی‌اش را بیرون بکش (slotهای لمس‌شده توسط constructor).
//   ۳. این storage را به‌همراه bytecode runtime «واقعی» FoundationDAO (نه bytecode این فایل) زیر
//      SurAddresses.FOUNDATION_DAO در `alloc` فایل genesis.json بنویس، به‌علاوه‌ی موجودی ۲۰٬۰۰۰٬۰۰۰ سورن.
//
// `principalsAndAlternates`: ابتدا ۵ عضو اصلی، سپس حداکثر ۲ علی‌البدل.
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
