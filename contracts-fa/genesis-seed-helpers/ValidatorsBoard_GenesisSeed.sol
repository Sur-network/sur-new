// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  قرارداد کمکی seed کردن genesis — موقت، هرگز روی زنجیره‌ی واقعی دیپلوی نمی‌شود  ⚠️⚠️⚠️
//
// این نسخه‌ی موقتِ ValidatorsBoard.sol است.
// (نسخه‌ی موقتِ متناظر با: contracts/ValidatorsBoard.sol)
//
// هدف: ValidatorsBoard.sol واقعی هیچ constructor ندارد (چون در genesis alloc تزریق می‌شود).
// ولی `boardMembers` (آرایه‌ی پویا) و `isBoardMember` (mapping) با هیچ syntax سطح-قرارداد در
// Solidity قابل‌مقداردهی نیستند. این قرارداد کمکی همان منطق seed کردن را در یک constructor
// واقعی و **بدون هیچ ورودی** پیاده می‌کند — آدرس هر ۵ عضو مؤسس هیأت مستقیم پایین همین فایل
// هاردکد شده‌اند، نه به‌عنوان آرگومان constructor — تا با اجرای واقعی‌اش روی یک زنجیره‌ی محلی
// (Anvil/Hardhat)، خودِ EVM محاسبات keccak256 لازم برای mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. 🔶 FILL_IN: هر آدرس placeholder پایین را با ۵ عضو مؤسس هیأت واقعی و نهایی جایگزین کن،
//      پیش از این‌که این فایل جایی دیپلوی شود.
//   ۲. این فایل را (بدون هیچ آرگومان constructor) روی یک زنجیره‌ی محلی موقت دیپلوی کن.
//   ۳. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۴. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد ValidatorsBoard.sol واقعی — زیر
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
    // constructor بدون ورودی — هر ۵ عضو مؤسس هیأت مستقیم پایین هاردکد شده‌اند.
    // 🔶 FILL_IN: هر آدرس 0x000...000 را با فهرست واقعی و نهایی و توافق‌شده‌ی اعضای مؤسس
    // هیأت جایگزین کن، پیش از این‌که این فایل جایی دیپلوی شود.
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
    }

    // برای راحتی خواندن نتیجه هنگام تست دستی (این تابع خودش هیچ نقشی در استخراج storage ندارد).
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }
}
