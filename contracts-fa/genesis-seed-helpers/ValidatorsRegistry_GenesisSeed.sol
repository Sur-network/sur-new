// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  قرارداد کمکی seed کردن genesis — موقت، هرگز روی زنجیره‌ی واقعی دیپلوی نمی‌شود  ⚠️⚠️⚠️
//
// این نسخه‌ی موقتِ ValidatorsRegistry.sol است.
// (نسخه‌ی موقتِ متناظر با: contracts/ValidatorsRegistry.sol)
//
// ✅ اصلاح‌شده (باگ بحرانی پیداشده در بازبینی): این فایل به دو شکل از قرارداد واقعی عقب
// افتاده بود که اگر همین‌طور استفاده می‌شد، storage genesis رو خراب می‌کرد:
//   ۱. struct ValidatorInfo اینجا فیلد isPaidEntrant (که بعداً به قرارداد واقعی اضافه شد) رو
//      نداشت.
//   ۲. قرارداد واقعی الان **دو متغیر اسکالر** (paidValidatorCount، verifier) بین validators و
//      activeValidators/activeIndex اعلام می‌کنه — ولی این فایل قبلاً activeValidators/
//      activeIndex رو بلافاصله بعد از validators می‌ذاشت، بدون هیچی وسطش. چون یه نوع mapping
//      یا آرایه‌ی dynamic دقیقاً یک storage slot برای «پایه»ی خودش اشغال می‌کنه (خودِ
//      ورودی‌ها توی آفست‌های محاسبه‌شده‌ی keccak256 از همون پایه ذخیره می‌شن)، هر متغیری که
//      بعد از mapping/آرایه اعلام بشه، به‌ازای هر اسکالر اضافه‌شده‌ی قبلش، یه slot جابه‌جا
//      می‌شه. بدون این دو placeholder پایین در همون موقعیت نسبی، slot محاسبه‌شده‌ی این فایل
//      برای activeValidators.length نسبت به قرارداد واقعی ۲ تا آف بود — یعنی کپی‌کردن ساده‌ی
//      «slot N فایل کمکی → slot N قرارداد واقعی»، داده‌ی آرایه‌ی ولیدیتورهای مؤسس رو توی
//      چیزی می‌نوشت که قرارداد واقعی به‌عنوان paidValidatorCount/verifier می‌خونه، و برعکس.
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
//      (فعلاً ۷ تا، هم‌راستا با تعداد واقعی ولیدیتورهای مؤسس) اگه این عدد عوض شد باید
//      هماهنگ بشه — عنصر اضافه/کم کن، هرجا طول آرایه نوشته شده (هم در نوع، هم در فهرست
//      مقادیر) به‌روزرسانی کن.
//   ۲. این فایل را (بدون هیچ آرگومان constructor) روی یک زنجیره‌ی محلی موقت دیپلوی کن.
//   ۳. کل storage نهایی‌اش را با eth_getStorageAt (یا state-dump) استخراج کن.
//   ۴. این storage را — نه بایت‌کد این فایل، بلکه بایت‌کد ValidatorsRegistry.sol واقعی —
//      زیر آدرس 0x3333...3333 در alloc genesis.json بگذار. ⚠️ دو اسلات placeholder
//      paidValidatorCount و verifier از این فایل کمکی، صفر / آدرس‌صفر استخراج می‌شن (چون
//      constructor این فایل هرگز بهشون دست نمی‌زنه) — این دو اسلات رو عیناً کپی **نکن**.
//      paidValidatorCount واقعاً باید صفر بمونه (مؤسسین توی منحنی پرداختی حساب نمی‌شن —
//      کامنت خودِ قرارداد واقعی را ببین)، که نیاز به هیچ اقدامی نداره (صفر پیش‌فرض
//      storage در Solidity است، پس صرفاً حذف این اسلات از نوشتن در alloc genesis همین
//      نتیجه‌ی درست رو می‌ده). verifier باید مستقیماً در alloc genesis، در اسلات خودش
//      (بلافاصله بعد از اسلات paidValidatorCount)، به آدرس واقعی و نهایی کلید عملیاتی‌اش
//      تنظیم بشه — دقیقاً مثل هر اسکالر ساده‌ی دیگه (entryThresholdBase،
//      growthFactorPerValidator، membershipFeeBps، و بقیه)، که هیچ‌کدومشون هم به این فایل
//      کمکی نیاز ندارن، طبق کامنت «GENESIS FILL-IN» خودِ قرارداد واقعی.
//
// ⚠️ ترتیب و نوع فیلدهای زیر باید دقیقاً همان ترتیب ValidatorsRegistry.sol واقعی باشد، وگرنه
// storage slotهای استخراج‌شده با قرارداد نهایی هم‌راستا نمی‌شوند. هر بار ValidatorsRegistry.sol
// واقعی تغییر کرد، این فایل هم باید دستی هماهنگ شود.
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
        uint256 totalLivenessChecksInPeriod; // ✅ اضافه شد — باید دقیقاً با struct واقعی یکی
        // باشه (همون استدلال isPaidEntrant پایین: اندازه‌ی struct روی محاسبه‌ی slot هر
        // ورودی بعدی mapping اثر می‌ذاره).
        uint256 lastCheckedAt; // ✅ اضافه شد — همون استدلال
        uint256 demotedAt;
        bool isPaidEntrant; // ✅ اضافه شد — باید دقیقاً با struct واقعی یکی باشه، وگرنه اندازه‌ی
        // هر ورودی struct (و درنتیجه محاسبه‌ی slot هر ورودی بعدی mapping) حتی برای خودِ
        // mapping «validators» هم غلط می‌شه، نه فقط اسکالرهای بعدش.
    }

    mapping(address => ValidatorInfo) public validators;

    // ✅ اضافه شد — فقط placeholder، برای رزرو موقعیت نسبی درست (توضیح کامل در هشدار بالا).
    // constructor این فایل عمداً هرگز بهش دست نمی‌زنه — باید روی مقدار پیش‌فرض Solidity
    // (صفر) بمونه، که دقیقاً همون مقدار درستِ genesis برای ولیدیتورهای مؤسسه (به کامنت خودِ
    // قرارداد واقعی روی همین فیلد مراجعه کن).
    uint256 public paidValidatorCount;

    // ✅ اضافه شد — placeholder، همون استدلال paidValidatorCount بالا. آدرس واقعی verifier
    // مستقیم در alloc genesis روی همین اسلات تنظیم می‌شه، نه از طریق این فایل کمکی — این
    // اعلان صرفاً برای اشغال موقعیت درست اسلاته تا activeValidators/activeIndex پایین دقیقاً
    // همون‌جایی بیفتن که قرارداد واقعی انتظار داره.
    address public verifier;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // constructor بدون ورودی — genesis timestamp و مجموعه‌ی ولیدیتورهای اولیه مستقیم
    // پایین هاردکد شده‌اند.
    // 🔶 FILL_IN: عدد صفر (timestamp) و هر آدرس 0x000...000 را با مقادیر واقعی و نهایی و
    // توافق‌شده‌ی ولیدیتورهای مؤسس جایگزین کن، پیش از این‌که این فایل جایی دیپلوی شود.
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
                totalLivenessChecksInPeriod: 0,
                lastCheckedAt: 0,
                demotedAt: 0,
                isPaidEntrant: false // مؤسسین همیشه رایگانند، هرگز پرداخت‌کننده نیستند
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
        }
        // paidValidatorCount و verifier عمداً دست‌نخورده می‌مانند — کامنت اعلانشان بالا را ببین.
    }

    // برای راحتی خواندن نتیجه هنگام تست دستی (این تابع خودش هیچ نقشی در استخراج storage ندارد).
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
