// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  قرارداد کمکی seed کردن genesis — موقت، هرگز روی زنجیره‌ی واقعی دیپلوی نمی‌شود  ⚠️⚠️⚠️
//
// این نسخه‌ی موقتِ FoundationDAO.sol است.
// (نسخه‌ی موقتِ متناظر با: contracts/FoundationDAO.sol)
//
// هدف: FoundationDAO.sol واقعی هیچ constructor ندارد (چون در genesis alloc تزریق می‌شود، پس
// constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). ولی سه فیلد آن (`memberList` که آرایه‌ی
// پویاست، و `memberIndex`/`isMember` که mapping هستند) با هیچ syntax سطح-قرارداد در Solidity
// قابل‌مقداردهی نیستند. این قرارداد کمکی همان منطق seed کردن را در یک constructor واقعی و
// **بدون هیچ ورودی** پیاده می‌کند — نام و آدرس هر ۱۵ عضو مؤسس مستقیم پایین همین فایل هاردکد
// شده‌اند، نه به‌عنوان آرگومان constructor — تا با اجرای واقعی‌اش روی یک زنجیره‌ی محلی
// (Anvil/Hardhat)، خودِ EVM محاسبات keccak256 لازم برای هر mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. 🔶 FILL_IN: هر نام/آدرس placeholder پایین را با ۱۵ عضو مؤسس واقعی و نهایی جایگزین کن،
//      پیش از این‌که این فایل جایی دیپلوی شود.
//   ۲. این فایل را (بدون هیچ آرگومان constructor) روی یک زنجیره‌ی محلی موقت دیپلوی کن.
//   ۳. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۴. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد FoundationDAO.sol واقعی — زیر آدرس
//      0x1111...1111 در alloc genesis.json بگذار.
//
// ⚠️ ترتیب و نوع فیلدهای زیر باید دقیقاً همان ترتیب FoundationDAO.sol واقعی باشد، وگرنه
// storage slotهای استخراج‌شده با قرارداد نهایی هم‌راستا نمی‌شوند. هر بار FoundationDAO.sol
// واقعی تغییر کرد، این فایل هم باید دستی هماهنگ شود.
// ============================================================================
contract FoundationDAO_GenesisSeed {
    // --- دقیقاً کپی از FoundationDAO.sol واقعی، تا نقطه‌ای که به mapping/آرایه می‌رسیم ---
    struct Member {
        string name;
        address account;
    }

    Member[] public memberList;
    mapping(address => uint256) private memberIndex; // اندیس یک‌مبنایی در memberList، صفر یعنی عضو نیست
    mapping(address => bool) public isMember;

    // ------------------------------------------------------------------
    // constructor بدون ورودی — هر ۱۵ عضو مؤسس مستقیم پایین هاردکد شده‌اند.
    // 🔶 FILL_IN: هر نام «عضو N» و هر آدرس 0x000...000 را با فهرست واقعی و نهایی و
    // توافق‌شده‌ی اعضای مؤسس جایگزین کن، پیش از این‌که این فایل جایی دیپلوی شود.
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
            memberIndex[account] = memberList.length; // یک‌مبنایی
            isMember[account] = true;
        }
    }
}
