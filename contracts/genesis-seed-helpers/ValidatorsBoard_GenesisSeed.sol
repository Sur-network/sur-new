// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN  ⚠️⚠️⚠️
//
// این قرارداد نسخه‌ی موقتِ  ValidatorsBoard.sol  است.
// (Temporary counterpart of: contracts/ValidatorsBoard.sol)
//
// هدف: ValidatorsBoard.sol واقعی هیچ constructor ندارد (چون در genesis alloc تزریق می‌شود).
// ولی `boardMembers` (آرایه‌ی پویا) و `isBoardMember` (mapping) با هیچ syntax سطح-قرارداد در
// Solidity قابل‌مقداردهی نیستند. این قرارداد کمکی همان منطق seed کردن را در یک constructor
// واقعی پیاده می‌کند، تا با اجرای واقعی‌اش روی یک زنجیره‌ی محلی (Anvil/Hardhat)، خودِ EVM
// محاسبات keccak256 لازم برای mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. این فایل را روی یک زنجیره‌ی محلی موقت دیپلوی کن (با آدرس‌های واقعی ۵ عضو اولیه‌ی هیأت).
//   ۲. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۳. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد ValidatorsBoard.sol واقعی — زیر
//      آدرس 0x4444...4444 در alloc genesis.json بگذار.
//
// ⚠️ ترتیب و نوع فیلدهای زیر باید دقیقاً همان ترتیب ValidatorsBoard.sol واقعی باشد، وگرنه
// storage slotهای استخراج‌شده با قرارداد نهایی هم‌راستا نمی‌شوند. هر بار ValidatorsBoard.sol
// واقعی تغییر کرد، این فایل هم باید دستی هماهنگ شود.
// ============================================================================
contract ValidatorsBoard_GenesisSeed {
    // --- دقیقاً کپی از ValidatorsBoard.sol واقعی، تا نقطه‌ای که به mapping/آرایه می‌رسیم ---
    uint256 public constant BOARD_SIZE = 5;

    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // ------------------------------------------------------------------
    // این constructor معادل دقیق «Reference logic»ای است که در کامنت‌های
    // ValidatorsBoard.sol واقعی (بالای اعلان boardMembers) نوشته شده.
    // ------------------------------------------------------------------
    constructor(address[] memory initialBoardMembers) {
        require(initialBoardMembers.length == BOARD_SIZE, "GenesisSeed: must supply exactly BOARD_SIZE members");
        for (uint256 i = 0; i < initialBoardMembers.length; i++) {
            address m = initialBoardMembers[i];
            require(m != address(0), "GenesisSeed: zero address");
            require(!isBoardMember[m], "GenesisSeed: duplicate initial board member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }
    }

    // برای راحتی خواندن نتیجه هنگام تست دستی (این تابع خودش هیچ نقشی در استخراج storage ندارد).
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }
}
