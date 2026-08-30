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
// قابل‌مقداردهی نیستند. این قرارداد کمکی همان منطق seed کردن را در یک constructor واقعی پیاده
// می‌کند، تا با اجرای واقعی‌اش روی یک زنجیره‌ی محلی (Anvil/Hardhat)، خودِ EVM محاسبات
// keccak256 لازم برای هر mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. این فایل را روی یک زنجیره‌ی محلی موقت دیپلوی کن (با نام‌ها و آدرس‌های واقعی ۱۵ عضو).
//   ۲. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۳. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد FoundationDAO.sol واقعی — زیر آدرس
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
    // این constructor معادل دقیق «منطق مرجع»ای است که در کامنت‌های
    // FoundationDAO.sol واقعی (بالای اعلان memberList) نوشته شده.
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
            memberIndex[account] = memberList.length; // یک‌مبنایی
            isMember[account] = true;
        }
    }
}
