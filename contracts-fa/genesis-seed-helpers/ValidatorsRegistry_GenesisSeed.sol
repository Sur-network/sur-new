// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  قرارداد کمکی seed کردن genesis — موقت، هرگز روی زنجیره‌ی واقعی دیپلوی نمی‌شود  ⚠️⚠️⚠️
//
// این نسخه‌ی موقتِ ValidatorsRegistry.sol است.
// (نسخه‌ی موقتِ متناظر با: contracts/ValidatorsRegistry.sol)
//
// هدف: ValidatorsRegistry.sol واقعی هیچ constructor ندارد (چون در genesis alloc تزریق
// می‌شود). ولی `validators` (mapping به یک struct)، `activeValidators` (آرایه‌ی پویا)، و
// `activeIndex` (mapping) با هیچ syntax سطح-قرارداد در Solidity قابل‌مقداردهی نیستند. این
// قرارداد کمکی همان منطق seed کردن را در یک constructor واقعی و **بدون هیچ ورودی** پیاده
// می‌کند — genesis timestamp و آدرس ولیدیتورهای اولیه مستقیم پایین همین فایل هاردکد
// شده‌اند، نه به‌عنوان آرگومان constructor — تا با اجرای واقعی‌اش روی یک زنجیره‌ی محلی
// (Anvil/Hardhat)، خودِ EVM محاسبات keccak256 لازم برای هر mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. 🔶 FILL_IN: genesis timestamp و هر آدرس placeholder پایین را با مقادیر واقعی و
//      نهایی جایگزین کن، پیش از این‌که این فایل جایی دیپلوی شود. **تعداد عناصر آرایه**
//      (فعلاً ۵ تا، فقط به‌عنوان مثال) هم باید با تعداد واقعی و نهایی ولیدیتورهای مؤسس
//      هماهنگ شود — عنصر اضافه/کم کن، هرجا طول آرایه نوشته شده (هم در نوع، هم در فهرست
//      مقادیر) به‌روزرسانی کن.
//   ۲. این فایل را (بدون هیچ آرگومان constructor) روی یک زنجیره‌ی محلی موقت دیپلوی کن.
//   ۳. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۴. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد ValidatorsRegistry.sol واقعی —
//      زیر آدرس 0x3333...3333 در alloc genesis.json بگذار.
//
// ⚠️ ترتیب و نوع فیلدهای زیر باید دقیقاً همان ترتیب ValidatorsRegistry.sol واقعی باشد، وگرنه
// storage slotهای استخراج‌شده با قرارداد نهایی هم‌راستا نمی‌شوند. هر بار ValidatorsRegistry.sol
// واقعی تغییر کرد، این فایل هم باید دستی هماهنگ شود. توجه: پارامترهای امنیتی و اقتصادی (که
// خودشان مقادیر ساده‌اند، نه mapping/آرایه) اینجا تکرار نشده‌اند — آن‌ها مستقیماً در سورس
// اصلی با 🔶 FILL_IN پر می‌شوند، نیازی به این قرارداد کمکی ندارند.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed {
    // --- دقیقاً کپی از ValidatorsRegistry.sol واقعی، تا نقطه‌ای که به mapping/آرایه می‌رسیم ---
    enum Status { None, Probation, Active, Demoted, Exiting }

    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;
        uint256 lastLivenessConfirmation;
        uint256 livenessConfirmationsInPeriod;
        uint256 demotedAt;
    }

    mapping(address => ValidatorInfo) public validators;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // constructor بدون ورودی — genesis timestamp و مجموعه‌ی ولیدیتورهای اولیه مستقیم
    // پایین هاردکد شده‌اند.
    // 🔶 FILL_IN: عدد صفر (timestamp) و هر آدرس 0x000...000 را با مقادیر واقعی و نهایی و
    // توافق‌شده‌ی ولیدیتورهای مؤسس جایگزین کن، پیش از این‌که این فایل جایی دیپلوی شود.
    // اندازه‌ی آرایه (فعلاً ۵ تا، به‌عنوان مثال) را با تعداد واقعی هماهنگ کن.
    // ------------------------------------------------------------------
    constructor() {
        uint256 genesisTimestamp = 0; // 🔶 FILL_IN — genesis timestamp واقعی شبکه‌ی زنده

        address[7] memory initialValidators = [
            address(0), // Alireza Zojaji
            address(0), // Citex Corp. 1
            address(0), // Citex Corp. 2
            address(0), // Mahkameh Sharifzad
            address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0) // Siavash Tafazzoli
        ];

        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "GenesisSeed: zero address - fill in real values first");
            require(validators[v].status == Status.None, "GenesisSeed: duplicate initial validator");

            validators[v] = ValidatorInfo({
                status: Status.Active,
                lockedStake: 0,
                periodStartedAt: genesisTimestamp,
                lastLivenessConfirmation: genesisTimestamp,
                livenessConfirmationsInPeriod: 0,
                demotedAt: 0
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
        }
    }

    // برای راحتی خواندن نتیجه هنگام تست دستی (این تابع خودش هیچ نقشی در استخراج storage ندارد).
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
