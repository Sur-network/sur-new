// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN  ⚠️⚠️⚠️
//
// این قرارداد نسخه‌ی موقتِ  ValidatorsRegistry.sol  است.
// (Temporary counterpart of: contracts/ValidatorsRegistry.sol)
//
// هدف: ValidatorsRegistry.sol واقعی هیچ constructor ندارد (چون در genesis alloc تزریق می‌شود).
// ولی `validators` (mapping به یک struct)، `activeValidators` (آرایه‌ی پویا)، و `activeIndex`
// (mapping) با هیچ syntax سطح-قرارداد در Solidity قابل‌مقداردهی نیستند. این قرارداد کمکی همان
// منطق seed کردن را در یک constructor واقعی پیاده می‌کند، تا با اجرای واقعی‌اش روی یک زنجیره‌ی
// محلی (Anvil/Hardhat)، خودِ EVM محاسبات keccak256 لازم برای هر mapping/آرایه را انجام دهد.
//
// نحوه‌ی استفاده‌ی ابزار genesis:
//   ۱. این فایل را روی یک زنجیره‌ی محلی موقت دیپلوی کن (با آدرس‌های واقعی ولیدیتورهای اولیه و
//      genesis timestamp واقعی).
//   ۲. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۳. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد ValidatorsRegistry.sol واقعی — زیر
//      آدرس 0x3333...3333 در alloc genesis.json بگذار.
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
    // این constructor معادل دقیق «Reference logic»ای است که در کامنت‌های
    // ValidatorsRegistry.sol واقعی (بالای اعلان activeValidators) نوشته شده.
    // ------------------------------------------------------------------
    constructor(uint256 genesisTimestamp, address[] memory initialValidators) {
        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "GenesisSeed: zero address");
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

    // برای راحتی خواندن نتیجه هنگام تست دستی (این تابع خودش هیچ نقشی در استخراج storage ندارد،
    // فقط برای دیباگ روی زنجیره‌ی محلی مفید است).
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
