// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SurAddresses
/// @notice آدرس‌های ثابت و genesis-محور شش قرارداد ساختاری شبکه‌ی سور.
///         هر شش قرارداد مستقیماً در بخش `alloc` بلاک genesis دیپلوی می‌شوند (بایت‌کد + storage
///         مستقیم تزریق می‌شود، نه از طریق یک تراکنش دیپلوی معمولی — برای دستورالعمل دقیق به
///         "sur-contracts-deploy-notes.md" مراجعه کن). چون آدرس هر یک از این قراردادها از قبل
///         و پیش از شبیه‌سازی هر constructor‌ای مشخص است، هر قرارداد می‌تواند آدرس بقیه را
///         به‌صورت ثابت (constant) در سورس خودش هاردکد کند — بدون نیاز به یک مرحله‌ی اجرایی
///         "wire()" بعد از دیپلوی (روش قبلی پروژه، که الان کنار گذاشته شده).
///
///         این مقادیر بعد از تولید genesis نباید تغییر کنند — چون به‌صورت ثابت داخل بایت‌کد
///         تمام قراردادهای دیگر جاسازی شده‌اند، نه در یک state قابل‌تغییر.
library SurAddresses {
    /// @dev FoundationDAO — حکمرانی بنیاد سور (۱۵ عضو)
    address internal constant FOUNDATION_DAO = 0x1111111111111111111111111111111111111111;

    /// @dev BlockRewardDistributor — دریافت‌کننده‌ی بلاک‌ریوارد و فی به‌عنوان miningbeneficiary،
    ///      پرداخت‌کننده‌ی دوره‌ای به ولیدیتورها + ValidatorsTreasury
    address internal constant BLOCK_REWARD_DISTRIBUTOR = 0x2222222222222222222222222222222222222222;

    /// @dev ValidatorsRegistry — مرجع اجماع (getValidators()) و مرجع صلاحیت پرداخت
    ///      (isValidator()). این همان آدرسی است که باید به‌عنوان qbft.validatorcontractaddress
    ///      در genesis.json هم تنظیم شود.
    address internal constant VALIDATORS_REGISTRY = 0x3333333333333333333333333333333333333333;

    /// @dev ValidatorsBoard — هیأت کوچک منتخب/قابل‌عزل با اختیارات تفویضی محدود
    address internal constant VALIDATORS_BOARD = 0x4444444444444444444444444444444444444444;

    /// @dev ValidatorsTreasury — نگه‌دارنده و خرج‌کننده‌ی سهم ولیدیتورها از استخر ریوارد
    ///      (باقی‌مانده بعد از کسر سهم ثابت ۱۵٪ بنیاد و سهم مستقیم حکمرانی‌شونده‌ی
    ///      ولیدیتورها — دیگر یک سهم ثابت ۵۰٪ نیست؛ به
    ///      BlockRewardDistributor.validatorDirectShareBps مراجعه کن)
    address internal constant VALIDATORS_TREASURY = 0x5555555555555555555555555555555555555555;

    /// @dev IdentityRegistry — ششمین قرارداد ساختاری (در یک بازنگری بعدی اضافه شد). مرجع واحد
    ///      هویت خوداظهاری (نام/نوع شخصیت) و وضعیت وریفای (موبایل/تلگرام/KYC کامل) برای
    ///      **کل کاربران شبکه**، نه فقط ولیدیتورها — به همین دلیل از ValidatorsRegistry
    ///      مستقل نگه داشته شده است.
    address internal constant IDENTITY_REGISTRY = 0x6666666666666666666666666666666666666666;

    // ------------------------------------------------------------------
    // قراردادهای ساختاری v2.5 (آدرس‌ها در اینجا پیشنهاد شده‌اند؛ سند مرجع هنوز آن‌ها را 🔶
    // نامشخص علامت می‌زند — تثبیت آن‌ها بخشی از طراحی genesis است، با همان الگوی 0xNNNN...NNNN).
    // ------------------------------------------------------------------

    /// @dev FoundationMembers — دفتر اعضا و حساب‌های سهم‌الشرکه‌ی بنیاد.
    address internal constant FOUNDATION_MEMBERS = 0x7777777777777777777777777777777777777777;

    /// @dev ValidatorSeatNFT — جایگاه‌های ولیدیتور به‌صورت ERC-721 (هنوز پیاده‌سازی نشده).
    address internal constant VALIDATOR_SEAT_NFT = 0x8888888888888888888888888888888888888888;

    /// @dev GenesisClaimsVault — مطالبات genesis که در ۲۴ قسط ماهانه آزاد می‌شوند.
    address internal constant GENESIS_CLAIMS_VAULT = 0x9999999999999999999999999999999999999999;

    /// @dev ValidatorLottery — قرعه‌کشی جایگاه ولیدیتور برای مقابله با انحصار ولیدیتورها.
    address internal constant VALIDATOR_LOTTERY = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;

    /// @dev KmsDirectives — کلید قطع هر کلید سرویس امضای SurKMS (verifier، distributionOracle، identityOracle).
    ///      بدون constructor و بدون seed حافظه: فقط بایت‌کد اجرایی در `alloc` genesis گذاشته می‌شود.
    address internal constant KMS_DIRECTIVES = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    /// @dev StandbyValidators — فهرست آمادهٔ ولیدیتورها برای بازیابی اضطراری اجماع (مقصد گذار `contract` به `contract` در genesis).
    ///      بدون constructor و بدون seed: فقط بایت‌کد runtime در `alloc` ژنزیس می‌رود.
    address internal constant STANDBY_VALIDATORS = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;

    // ------------------------------------------------------------------
    // آدرس‌های oracle عملیاتی — برخلاف شش آدرس قراردادِ ساختاری بالا، این‌ها ثابت‌های تغییرناپذیری
    // نیستند که برای همیشه در همه‌ی مصرف‌کنندگان جاسازی شوند: هر قرارداد همچنان آدرس oracle خودش را در
    // state معمولی (قابل‌تغییر) نگه می‌دارد، از همین‌جا مقداردهی اولیه می‌شود، و بعداً می‌تواند از مسیر
    // حکمرانی خودش آن را عوض کند (ValidatorsBoard برای distributionOracle/verifier، FoundationDAO برای
    // identityOracle). متمرکز کردن مقدار *اولیه* در یک فایل یعنی به‌روزرسانی یک oracle پیش از genesis
    // فقط ویرایش یک خط است، نه جست‌وجو در چند فایل قرارداد. هر سه آدرس طبق EIP-55 checksum شده‌اند.
    // (v2.5 دقیقاً سه oracle دارد: verifier، distributionOracle، identityOracle.)
    // ------------------------------------------------------------------

    /// @dev آدرس اولیه‌ی distributionOracle برای BlockRewardDistributor.sol.
    address internal constant DISTRIBUTION_ORACLE = 0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6;

    /// @dev آدرس اولیه‌ی verifier برای ValidatorsRegistry.sol.
    address internal constant VERIFIER = 0x1A5E86f3333291B3332C0f9Eddb04269940566bc;

    /// @dev آدرس اولیه‌ی identityOracle برای IdentityRegistry.sol.
    address internal constant IDENTITY_ORACLE = 0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9;

    // (v2.5: PAYMENT_ORACLE سابق حذف شد — SurenSale هیچ oracle ندارد؛ فروش از طریق صرافی‌های دارای مجوز انجام می‌شود.)
}
