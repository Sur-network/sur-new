// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IBlockRewardDistributor {
    function receiveMembershipFee() external payable;
}

interface IValidatorsBoardSync {
    function syncVoter(address voter) external;
}

/// @title ValidatorsRegistry
/// @notice در آدرس ثابت genesis یعنی SurAddresses.VALIDATORS_REGISTRY (‏0x3333...3333) مستقر است و دو نقش دارد:
///
///         ۱) اجماع: رابط حالت-قرارداد QBFT در Besu را پیاده می‌کند:
///            `getValidators() external view returns (address[] memory)`. این آدرس در genesis.json به‌عنوان
///            `qbft.validatorcontractaddress` تنظیم می‌شود. تغییر لیست برگردانده‌شده از همان بلاکی اعمال می‌شود که
///            تغییر در آن استخراج شده است: پیشنهاددهندهٔ بلاک N از لیستی گرفته می‌شود که بعد از بلاک N-1 برقرار است.
///
///         ۲) صلاحیت پرداخت: `BlockRewardDistributor` پاداش یک بلاک را فقط وقتی به ولیدیتور می‌دهد که
///            `everActivated(validator)` در اینجا true باشد. فعال‌بودنِ آدرس در زمان تولید بلاک را RewardRouter
///            به‌صورت آف‌چین بررسی می‌کند.
///
///         این قرارداد عمداً از `ValidatorsTreasury` جداست: باگ در منطق خرج خزانه هرگز نمی‌تواند تعیین کند
///         چه کسی ولیدیتور شناخته می‌شود.
///
///         استقرار در GENESIS: این قرارداد همراه با قراردادهای ساختاری دیگر مستقیم در `alloc` بلاک genesis تزریق می‌شود
///         (کد و storage) و constructor ندارد. مجموعهٔ ولیدیتورهای مؤسس، زمان genesis و همهٔ پارامترهای امنیتی
///         را ابزار ساخت genesis می‌نویسد (یادداشت‌های GENESIS FILL-IN در همین فایل و
///         "sur-contracts-deploy-notes.md" را ببینید).
///
///         چرخهٔ عمر یک آدرس ولیدیتور:
///           None -> Probation (استیک قفل شده، نود در حال بررسی است و هنوز در getValidators() نیست)
///                -> Active (در getValidators() است و واجد پرداخت)
///                -> Demoted وقتی verifier تعلیق ثبت کند (از getValidators() حذف می‌شود)
///                -> دوباره Active وقتی verifier بازگشت را ثبت کند
///           از Probation، Active یا Demoted آدرس می‌تواند Exiting را انتخاب کند (خروج داوطلبانه پس از دورهٔ انتظار)
///           تا استیکش را پس بگیرد.
///
///         مجموعهٔ فعال هرگز از MIN_ACTIVE_VALIDATORS کمتر نمی‌شود: آخرین ولیدیتور فعال نه تعلیق می‌شود
///         و نه می‌تواند خارج شود.
///
///         حکمرانی دو مسیر دارد:
///           - پارامترهای اقتصادی ورود (entryThresholdBase، growthFactorPerValidator، membershipFeeBps) فقط با رأی
///             داخلی ValidatorsBoard تغییر می‌کنند.
///           - بقیهٔ موارد (نرخ ورود، طول probation، دورهٔ بازیابی، slashBps، دورهٔ خروج) اکثریتِ ولیدیتورهایی را می‌خواهند
///             که هنگام ساخت پیشنهاد Active بوده‌اند (proposeParameterChange / voteParameterChange).
///
///         پرداخت عضویت: ولیدیتور تازه با requestMembership دو مبلغ را به ارز بومی (سورن) می‌پردازد:
///           - وثیقه (= currentEntryThreshold()): اینجا قفل می‌ماند، هنگام خروج برگشت‌پذیر و قابل جریمه است.
///           - کارمزد عضویت (= currentMembershipFee()، درصدی حکمرانی‌شده از وثیقه): به BlockRewardDistributor
///             فرستاده می‌شود و به نسبت تعداد بلاک بین ولیدیتورهای فعال دورهٔ بعد تقسیم می‌شود و از سوزاندن
///             کارمزد عادی معاف است. بخش جریمه‌شدهٔ وثیقه به ValidatorsTreasury می‌رود.
///
///         همگام‌سازی با هیأت: هر بار وضعیت فعال‌بودن یک ولیدیتور عوض شود، این قرارداد
///         `ValidatorsBoard.syncVoter(validator)` را صدا می‌زند تا شمارنده‌های رأی هیأت با مجموعهٔ فعال هماهنگ بماند.
///         این فراخوان بهترین‌تلاش است و نمی‌تواند تغییر وضعیت را مسدود کند.
contract ValidatorsRegistry {
    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — مقصد استیک اسلش‌شده.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice BlockRewardDistributor. کارمزد عضویت به اینجا فرستاده می‌شود (receiveMembershipFee()) و به نسبت تعداد
    ///         بلاک بین ولیدیتورهای فعال دورهٔ بعد پرداخت می‌شود.
    IBlockRewardDistributor public constant DISTRIBUTOR = IBlockRewardDistributor(payable(SurAddresses.BLOCK_REWARD_DISTRIBUTOR));

    /// @notice ValidatorsBoard — تنها آدرس مجاز به تغییر پارامترهای اقتصادی ورود پایین
    ///         (entryThresholdBase، growthFactorPerValidator، membershipFeeBps).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    // ------------------------------------------------------------------
    // وضعیت ولیدیتور
    // ------------------------------------------------------------------

    enum Status { None, Probation, Active, Demoted, Exiting }

    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;  // شروع پنجره‌ی probation یا بازگشت یا cooldown خروج فعلی
        // تغییر وضعیت را verifier به‌صورت آف‌چین تصمیم می‌گیرد و با هش بستهٔ شواهد روی زنجیره ثبت می‌شود
        // (StatusDecision را در ادامه ببینید)؛ هیچ نسبت liveness‌ای روی زنجیره نگهداری نمی‌شود.
        uint256 pendingSlashEpoch;  // ناصفر تا وقتی این ولیدیتور یک
        // تصمیم جریمهٔ بی‌فعالیتی حل‌نشده (بررسی خرابی جمعی در انتظار، یا تحویل/اعتراض در جریان —
        // سازوکار کامل را در StatusDecision و DemotionEpoch در ادامه ببینید). صفر یعنی «جریمهٔ در انتظار نیست».
        // تا وقتی مقدار دارد، withdrawStake() را مسدود می‌کند.
        uint256 demotedAt;  // اگر هرگز تعلیق نشده یا اکنون در وضعیت Demoted نیست، صفر است
        bool isPaidEntrant;  // فقط برای ولیدیتورهایی که با requestMembership() پرداخت کرده‌اند true؛ برای
        // ولیدیتورهای مؤسس genesis (با lockedStake = 0)، پس منحنی رشد فقط ورودی‌های پرداختی را منعکس می‌کند.
    }

    mapping(address => ValidatorInfo) public validators;

    /// @notice تعداد ورودی‌های پرداختی (واردشده با requestMembership()) که هنوز requestExit() نزده‌اند. این عدد Probation،
    ///         Active و Demoted را با هم شامل می‌شود: ولیدیتور پرداختی که فقط در probation است یا موقتاً Demoted شده
    ///         همچنان شمرده می‌شود؛ فقط خروج کامل آن را برمی‌دارد. مؤسسان genesis شمرده نمی‌شوند (هرگز
    ///         requestMembership() را صدا نمی‌زنند)، پس ورود رایگانشان هزینهٔ ورودی بعدی‌ها را بالا نمی‌برد.
    ///         currentEntryThreshold() از این مقدار به‌عنوان توان استفاده می‌کند.
    uint256 public paidValidatorCount;

    // ------------------------------------------------------------------
    // هویت (نام/نوع شخص، تأیید موبایل/تلگرام/KYC) در قرارداد مستقل `IdentityRegistry.sol` است، چون جمعیتش (همهٔ کاربران شبکه)
    // از جمعیت ولیدیتورها جداست؛ `ValidatorsBoard.voteFor` مستقیم `IdentityRegistry.hasIdentity(...)` را چک می‌کند.
    //
    // `verifier` اینجا برای یک هدف به کار می‌رود: ثبت تصمیم‌های وضعیت ولیدیتور (recordActivation، recordSuspension،
    // recordRecovery، recordPreExitViolation). این کلید کاملاً جدا از `identityOracle` در `IdentityRegistry.sol` است:
    // زنده‌بودن نود و احراز هویت دو نقش مستقل‌اند.
    // ------------------------------------------------------------------

    /// @notice کلید عملیاتی مورد اعتماد برای ثبت تصمیم‌های وضعیت ولیدیتور (recordActivation، recordSuspension،
    ///         recordRecovery، recordPreExitViolation). ValidatorsBoard با setVerifier آن را می‌چرخاند. مقدار اولیه
    ///         از SurAddresses.sol می‌آید.
    address public verifier = SurAddresses.VERIFIER;

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    modifier onlyVerifier() {
        require(msg.sender == verifier, "ValidatorsRegistry: caller is not the verifier");
        _;
    }

    /// @notice چرخش کلید verifier. فقط هیأت — دقیقاً مثل نحوه‌ی چرخش distributionOracle روی
    ///         BlockRewardDistributor (یک چرخش روتین کلید عملیاتی، نه تغییر پارامتر امنیتی).
    function setVerifier(address newVerifier) external onlyBoard {
        require(newVerifier != address(0), "ValidatorsRegistry: zero verifier address");
        emit VerifierUpdated(verifier, newVerifier);
        verifier = newVerifier;
    }

    // ------------------------------------------------------------------
    // GENESIS FILL-IN: مجموعهٔ ولیدیتورهای مؤسس. `activeValidators` آرایهٔ پویا و `activeIndex` / `validators` mapping هستند،
    // پس وضعیت اولیه را نمی‌شود با مقداردهی متغیر state نوشت. ابزار genesis یا منطق seed را روی یک زنجیرهٔ محلی موقت
    // شبیه‌سازی می‌کند و storage حاصل را در `alloc` می‌گذارد، یا slotهای storage را مستقیم می‌نویسد
    // ("sur-contracts-deploy-notes.md" و genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol را ببینید). برای هر مؤسس v:
    //   validators[v] = ValidatorInfo({ status: Active, lockedStake: 0, periodStartedAt: GENESIS_TIMESTAMP,
    //     pendingSlashEpoch: 0, demotedAt: 0, isPaidEntrant: false });
    //   activeIndex[v] = activeValidators.length + 1;  activeValidators.push(v);
    //   everActivated[v] = true;  activationSeq[v] = ++activationCount;
    //   paidValidatorCount برای مؤسسان افزایش نمی‌یابد.
    // ------------------------------------------------------------------
    // مجموعهٔ ولیدیتورهای فعال که با getValidators() عرضه می‌شود. حذف با swap-and-pop از طریق اندیس ۱-پایه انجام می‌شود.
    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // پارامترهای حکمرانی‌شده (فقط با رأی کامل ولیدیتورها قابل تغییر — در ادامه ببینید)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // پارامترهای اقتصادی ورود: مقادیر اولیه در ادامه؛ فقط ValidatorsBoard می‌تواند تغییرشان دهد (آرگومان constructor نیستند و
    // با رأی کامل ولیدیتورها هم تغییر نمی‌کنند). entryThresholdBase اولیه ۵۰۰٬۰۰۰ سورن است.
    // ------------------------------------------------------------------

    /// @notice حدود سخت و یک دورهٔ انتظار مشترک برای اختیار ValidatorsBoard روی سه پارامتر اقتصادی ورود
    ///         (entryThresholdBase، growthFactorPerValidator، membershipFeeBps). حدود، مقادیر افراطی (ورود رایگان،
    ///         رشد بی‌نهایت تند، کارمزد تا ۱۰۰٪) را می‌بندد؛ یک دورهٔ انتظار مشترک برای هر سه جلوی ترکیب چند تغییر
    ///         سریع و رسیدن به اثر افراطی را می‌گیرد.
    uint256 public constant ENTRY_THRESHOLD_BASE_MIN = 100_000 ether;
    uint256 public constant ENTRY_THRESHOLD_BASE_MAX = 2_000_000 ether;
    uint256 public constant MEMBERSHIP_FEE_BPS_MIN = 100;  // ۱٪
    uint256 public constant MEMBERSHIP_FEE_BPS_MAX = 1000;  // ۱۰٪
    /// @dev حدود بر حسب دورهٔ دوبرابرشدنی که القا می‌کنند بیان شده‌اند: ضریب برای دورهٔ p برابر 2^(1/p) است. تندترین مجاز:
    ///      هر ۲۰ ولیدیتور پرداختی دو برابر می‌شود. کندترین مجاز: هر ۸۰ ولیدیتور.
    uint256 public constant GROWTH_FACTOR_MIN = 1_008701983790398976;  // 2^(1/80)، دوبرابر هر ۸۰
    uint256 public constant GROWTH_FACTOR_MAX = 1_035264923841377536;  // 2^(1/20)، دوبرابر هر ۲۰
    uint256 public constant ECONOMIC_PARAM_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastEconomicParamChangeTime;

    /// @notice استیک پایهٔ لازم برای درخواست عضویت وقتی ۰ ولیدیتور پرداختی وجود دارد (نخستین کسی که
    ///         requestMembership() را صدا می‌زند، صرف‌نظر از تعداد مؤسسان رایگان فعال).
    uint256 public entryThresholdBase = 500_000 ether;  // ۵۰۰,۰۰۰ سورن (۱۸ رقم اعشار، مثل ETH)

    /// @notice آستانهٔ ورود پیوسته و مرکب با هر ولیدیتور پرداختیِ بیشتر رشد می‌کند:
    ///         آستانهٔ فعلی = entryThresholdBase * growthFactorPerValidator^paidValidatorCount. مؤسسان در توان شمرده نمی‌شوند.
    ///         ضریب fixed-point با ۱۸ رقم اعشار است؛ ‏1_017479692102686336 (حدود ۱٫۰۱۷۴۸۰) آستانه را با هر ۴۰ ولیدیتور
    ///         پرداختی دو برابر می‌کند. این منحنی خریدن بیش از یک‌سوم کرسی‌ها را نمایی، نه خطی، گران می‌کند.
    uint256 public growthFactorPerValidator = 1_017479692102686336;

    /// @notice دقت fixed-point استفاده‌شده توسط growthFactorPerValidator و _fixedPow (۱۸ رقم
    ///         اعشار، مثل خودِ سورن/ETH). 1_000000000000000000 معادل ۱.۰ (بدون رشد) است.
    uint256 private constant FIXED_POINT_ONE = 1_000000000000000000;

    /// @notice سقف ایمنی و گس: تعداد ولیدیتورهای پرداختی هنگام محاسبهٔ آستانهٔ ورود به این مقدار محدود می‌شود تا
    ///         توان بی‌نهایت رشد نکند. بیشترین ضریب مجاز به growthFactorPerValidator فعلی بستگی دارد: از 2^16 (کندترین
    ///         رشد مجاز) تا 2^64 (تندترین)، که از هر خطر سرریز در حساب ۱۸-رقمی اینجا بسیار دور است.
    uint256 private constant MAX_GROWTH_VALIDATORS = 1280;

    /// @notice کارمزد عضویت، به‌صورت کسری از currentEntryThreshold()، علاوه بر وثیقه و غیرقابل‌استرداد. به
    ///         BlockRewardDistributor.receiveMembershipFee() فرستاده می‌شود، در دورهٔ توزیع بعد ادغام می‌شود و به نسبت
    ///         تعداد بلاک بین ولیدیتورهای فعال پرداخت می‌شود (از سوزاندن کارمزد عادی معاف است).
    ///         ۴۰۰ یعنی ۴٪ وثیقه.
    uint256 public membershipFeeBps = 400;

    /// @notice حداکثر تعداد درخواست عضویت جدید در بازهٔ entryWindowSeconds.
    uint256 public maxEntriesPerWindow = 1;
    uint256 public entryWindowSeconds = 86400;  // ۲۴ ساعت — حداکثر ۱ ولیدیتور تازه در روز

    uint256 public probationPeriod = 604800;  // ۱ هفته

    /// @notice حداقل فاصلهٔ زمانی بین تعلیق و ثبت بازگشت (در ابتدا ۴۸ ساعت).
    uint256 public recoveryPeriod = 172800;  // ۴۸ ساعت
    uint256 public slashBps = 100;  // ۱٪ — عمداً سبک: آستانهٔ ورود پایین نگه داشته شده تا دامنهٔ کسانی که
    // می‌توانند ولیدیتور شوند، پس جریمهٔ سنگین روی آن وثیقهٔ کوچک‌تر یک اشتباه زیرساختی صادقانه را بیش از حد سخت مجازات می‌کند.
    // ۱٪ یک پیامد واقعی است بی‌آنکه برای هیچ اندازه وثیقه‌ای فاجعه‌بار باشد.
    uint256 public exitCooldown = 604800;  // ۱ هفته

    /// @notice یک پنجرهٔ زمانی ثابت (MASS_DEMOTION_WINDOW) که تعلیق‌ها در آن دسته می‌شوند. جریمهٔ یک تعلیق
    ///         هنگام تعلیق تصمیم‌گیری نمی‌شود: وقتی پنجره بسته شد، یک فراخوان بدون مجوز (resolveMassFailureCheck) برای
    ///         همهٔ ولیدیتورهای تعلیق‌شده در آن پنجره یکسان تعیین می‌کند آیا تعداد نهایی تعلیق‌ها از آستانهٔ خرابی جمعی
    ///         بیشتر شده است. پس نتیجه به الگوی کل پنجره بستگی دارد، نه به اینکه کدام تراکنش زودتر نشست. حذف از
    ///         مجموعهٔ فعال هرگز با این سازوکار به تأخیر نمی‌افتد: ولیدیتور تعلیق‌شده فوراً از getValidators() بیرون می‌رود
    ///         و نصاب QBFT می‌تواند با کاهش امضاکنندگان زنده کوچک شود؛ فقط تصمیم جریمه منتظر می‌ماند.
    struct DemotionEpoch {
        uint256 startedAt;
        uint256 referenceCount;  // شمارش ولیدیتورهای فعال که هنگام آغاز دوره ثبت می‌شود؛ در تمام عمر آن دوره ثابت می‌ماند
        uint256 demotionCount;  // تعلیق‌های ثبت‌شده در این دوره؛ فقط تا وقتی دوره باز است زیاد می‌شود
        bool resolved;
        bool wasMassFailure;
    }

    mapping(uint256 => DemotionEpoch) public demotionEpochs;
    uint256 public currentDemotionEpochId;  // صفر یعنی «هنوز هیچ پنجره‌ای باز نشده»

    uint256 public constant MASS_DEMOTION_WINDOW = 1 hours;
    uint256 public constant MASS_DEMOTION_SLASH_PAUSE_BPS = 2000;  // ۲۰٪ — resolveMassFailureCheck() را ببینید

    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @dev ابزار genesis آن را برابر زمان واقعی genesis می‌نویسد (نه block.timestamp ماشینی که شبیه‌سازی seed را اجرا می‌کند)؛
    ///      sur-contracts-deploy-notes.md را ببینید.
    // وضعیت پنجرهٔ نرخ ورود
    uint256 public windowStart = 0;
    uint256 public entriesInWindow;

    // ------------------------------------------------------------------
    // راستی‌آزمایی آف‌چین. verifier زنده‌بودن هر نود را آف‌چین (ساعتی) بررسی می‌کند و روی زنجیره فقط تغییر وضعیت‌ها را
    // ثبت می‌کند: فعال‌سازی پس از probation، تعلیق، یا بازگشت. هر تصمیم هش بستهٔ شواهد آف‌چینی را دارد که آن را توجیه کرده
    // (آدرس ولیدیتور، نوع و دلیل تصمیم، بازهٔ زمانی بررسی‌شده، نسخهٔ قواعد و آستانه، نتایج بررسی با زمان، منبع مشاهده،
    // دادهٔ تولید بلاک و اتصال همتا، نتیجهٔ تشخیص جغرافیایی در جاهایی که مهم بود، امضای verifier، و برای Activation و Recovery
    // تعداد کل و مثبت و محاسبهٔ نسبت ۹۵٪). شواهد خام هرگز روی زنجیره ذخیره نمی‌شوند: آف‌چین، رمزنگاری‌شده، نزد دست‌کم دو
    // نگهدارندهٔ مستقل از اپراتور verifier، به مدت ۹۰ روز یا تا بسته‌شدن پرونده می‌مانند. هش جلوی تغییر روایت verifier پس از
    // اعتراض را می‌گیرد؛ ثابت نمی‌کند روایت از ابتدا درست بوده است.
    //
    // تعلیق تنها نوع تصمیمی است که می‌تواند به جریمه برسد، پس فقط آن سازوکار تحویل / اعتراض / رأی در ادامه را دارد.
    // Activation و Recovery کاملاً مثبت‌اند و فقط هش شواهد را لازم دارند.
    //
    // جریان تصمیم جریمهٔ یک تعلیق:
    //   ۱. recordSuspension(): ولیدیتور فوراً و بی‌قیدوشرط از مجموعهٔ فعال بیرون می‌رود و در پنجرهٔ خرابی جمعی
    //      DemotionEpoch ثبت می‌شود.
    //   ۲. وقتی آن DemotionEpoch بسته شد، resolveMassFailureCheck() (بدون مجوز) اول اجرا می‌شود. خرابی جمعی پرونده را
    //      می‌بندد (SlashOutcome.ExemptMassFailure)؛ وگرنه پرونده به گام تحویل می‌رود.
    //   ۳. ولیدیتور هر زمان می‌تواند دریافت بستهٔ شواهد را تأیید کند (confirmDelivery()). این تحویل را ثابت می‌کند
    //      (deliveryProvenAt) و پنجرهٔ ۷۲ساعتهٔ ثبت اعتراض را شروع می‌کند. اعتراف به درستی اتهام نیست.
    //   ۴. اگر ولیدیتور ظرف DELIVERY_DISPUTE_GRACE_PERIOD تأیید نکند، هر کسی (معمولاً verifier) می‌تواند
    //      assertDeliveryDisputed() را صدا بزند: مجمع رأی می‌دهد (voteOnDelivery()). این رأی باید پیش از ثبت هر رأی جریمه
    //      تعیین‌تکلیف شود. اگر تحویل واقعاً انجام نشده بود، جریمه باطل می‌شود (SlashOutcome.VoidedNoDelivery)؛
    //      خود تعلیق می‌ماند.
    //   ۵. وقتی تحویل ثابت شد، ولیدیتور تا ۷۲ ساعت می‌تواند fileAppeal() بزند. سپس مجمع confirmSlash() رأی می‌دهد:
    //      اکثریت ساده از ولیدیتورهایی که هنگام ثبت اعتراض فعال بودند، بدون احتساب موضوع پرونده، با مهلت ۷ روزه. بدون
    //      اکثریت تا مهلت، جریمه رد می‌شود ولی تعلیق برنمی‌گردد: بازگشت به اجماع همچنان مسیر بازگشت را می‌خواهد.
    //   ۶. اگر ظرف ۷۲ ساعت اعتراضی ثبت نشود، هر کسی می‌تواند executeUncontestedSlash() را صدا بزند.
    // ------------------------------------------------------------------

    enum DecisionType { Activation, Suspension, Recovery }
    enum DeliveryStatus { NotApplicable, Pending, Confirmed, Disputed }
    enum SlashOutcome { Undetermined, ExemptMassFailure, VoidedNoDelivery, Confirmed, RejectedByVote, RejectedNoQuorum, ExecutedUncontested }

    struct StatusDecision {
        address validator;
        DecisionType decisionType;
        uint256 decidedAt;
        bytes32 evidenceHash;  // هش کل بستهٔ شواهد آف‌چین — برای محتوای دقیق آن بسته
        // یادداشت راستی‌آزمایی آف‌چین بالا را ببینید.
        uint256 demotionEpochId;  // فقط برای Suspension معنادار — به DemotionEpoch بالا لینک می‌شه
        DeliveryStatus delivery;
        uint256 deliveryProvenAt;  // تا وقتی ثابت نشده (با خودتأییدی یا رأی اختلاف تحویل)، صفره
        bool appealFiled;
        uint256 appealFiledAt;
        uint256 appealVotingDeadline;
        uint256 confirmVotes;
        uint256 requiredConfirmVotes;  // در لحظه‌ی ثبت، از ولیدیتورهای فعال به‌جز خودِ موضوع، snapshot می‌شه
        SlashOutcome slashOutcome;
    }

    /// @notice آیا resolveMassFailureCheck() برای این تصمیم اجرا شده است. برای هر تصمیم جداگانه تنظیم می‌شود،
    ///         چه دورهٔ آن خرابی جمعی بوده باشد چه نه، و هر گامی که پروندهٔ تعلیق را جلو می‌برد آن را لازم دارد. به‌جای
    ///         فیلد StatusDecision، mapping جداست تا توابع در حد مجاز عمق پشتهٔ کامپایلر بمانند.
    mapping(uint256 => bool) private massFailureChecked;

    /// @notice ثبت دائمی و فقط‌افزایشی اینکه این آدرس دست‌کم یک‌بار قانونی وارد مجموعهٔ فعال شده است. هنگام نخستین
    ///         فعال‌سازی تنظیم می‌شود (recordActivation و recordRecovery هر دو از _activate() می‌گذرند)، هرگز پاک نمی‌شود
    ///         و از withdrawStake() جان به‌در می‌برد. BlockRewardDistributor به‌جای isValidator() این را می‌خواند تا بفهمد
    ///         آیا آدرس هنوز برای بلاک‌هایی که پیش از خروج یا تعلیق ساخته پرداخت می‌گیرد. فقط «زمانی قانونی فعال شده» را ثابت
    ///         می‌کند، نه «هنگام ساخت بلاک N فعال بود»: آن بررسی زمانی کار RewardRouter است.
    mapping(address => bool) public everActivated;

    /// @notice وقتی آدرسی requestExit() بزند برای همیشه تنظیم می‌شود؛ requestMembership() چنین آدرسی را رد می‌کند. بازگشت
    ///         یعنی عضویت تازه با آدرس تازه: هیچ رأی، کرسی هیأت یا سابقه‌ای منتقل نمی‌شود، حتی برای مؤسس با استیک صفر.
    mapping(address => bool) public permanentlyExited;
    /// @notice هر بار این آدرس داوطلبانه خارج شود یک واحد زیاد می‌شود. ValidatorsBoard هنگام نشاندن آدرس روی کرسی epoch را
    ///         ثبت می‌کند و عدم‌تطابق بعدی را «دیگر این عضویت نیست» می‌داند، مستقل از permanentlyExited.
    mapping(address => uint256) public membershipEpoch;

    // ------------------------------------------------------------------
    // مدیریت خروج، مبلغ رزروشده و اتصال دقیق پرونده
    // ------------------------------------------------------------------
    /// @notice تصمیم دقیقی که اکنون قفل جریمهٔ در انتظار این ولیدیتور را نگه می‌دارد (۰ = هیچ).
    mapping(address => uint256) public pendingSlashDecisionId;
    /// @notice مبلغ در معرض خطر برای یک پرونده، که هنگام ثبت پرونده ثابت می‌شود (استیک × slashBps در همان لحظه). همان است که
    ///         withdrawStake() رزرو می‌کند و _executeSlash() برمی‌دارد (با سقف استیک باقی‌مانده).
    mapping(uint256 => uint256) public decisionSlashAmount;
    /// @notice زمان شروع تخلف ادعاشده در پرونده‌های پیش‌ازخروج (۰ برای تعلیق عادی). بسته‌ی شواهد (هش روی زنجیره) باید آن را
    ///         نشان دهد؛ مجمع از مسیر عادی اعتراض می‌تواند بررسی‌اش کند.
    mapping(uint256 => uint256) public decisionViolationAt;
    /// @notice وضعیت ولیدیتور در لحظه‌ی درخواست خروج (فقط ولیدیتور Active وظیفهٔ اعتبارسنجی دارد که بشود دربارهٔ تخلفش پرونده باز کرد).
    mapping(address => uint8) public statusBeforeExit;
    /// @notice تا چه مدت بعد از درخواست خروج، Verifier هنوز می‌تواند دربارهٔ رفتار **قبل** از درخواست پرونده ثبت کند.
    uint256 public constant PRE_EXIT_CLAIM_WINDOW = 72 hours;

    /// @notice مجموعهٔ فعال هرگز از این اندازه کوچک‌تر نمی‌شود: آخرین ولیدیتور فعال نه تعلیق می‌شود و نه می‌تواند خارج شود.
    uint256 public constant MIN_ACTIVE_VALIDATORS = 1;

    /// @dev گسی که از یک تغییر وضعیت به ValidatorsBoard.syncVoter فرستاده می‌شود. فراخوان بهترین‌تلاش است: شکست نادیده گرفته می‌شود
    ///      و هر کسی بعداً می‌تواند با صدا زدن syncVoter شمارنده‌های هیأت را ترمیم کند.
    uint256 internal constant BOARD_SYNC_GAS = 600_000;
    event PreExitCaseRecorded(uint256 indexed decisionId, address indexed validator, uint256 violationAt, uint256 exitRequestedAt, bytes32 evidenceHash);

    mapping(uint256 => StatusDecision) public statusDecisions;
    uint256 public statusDecisionCount;
    mapping(uint256 => mapping(address => bool)) private hasVotedOnSlash;

    /// @notice یه رأی‌گیری کوچیک‌تر و جدا که فقط وقتی استفاده می‌شه که یه ولیدیتور ظرف
    ///         DELIVERY_DISPUTE_GRACE_PERIOD خودش تحویل رو تأیید نکنه — فقط سؤال محدود
    ///         واقعیت «آیا بسته‌ی شواهد واقعاً در دسترس گذاشته شده» رو حل می‌کنه، هرگز اصل
    ///         موضوع تعلیق رو. حداکثر یکی به‌ازای هر تصمیم (یه فراخوان دوم
    ///         assertDeliveryDisputed() روی همون تصمیم بعد از این‌که یکی از قبل باز/حل شده،
    ///         رد می‌شه).
    struct DeliveryDispute {
        uint256 decisionId;
        uint256 filedAt;
        uint256 votingDeadline;
        uint256 votesConfirmingDelivery;
        uint256 requiredVotes;  // snapshot‌شده، از **همه‌ی** ولیدیتورهای فعال (خودِ ولیدیتور
        // موضوع اینجا exclude نمی‌شه — برخلاف رأی جریمه، این سؤال درباره‌ی گناهکاری اون نیست،
        // درباره‌ی این‌که آیا یه بسته بهش رسیده یا نه، که کاملاً حق داره درباره‌ش نظر بده).
        bool resolved;
        bool deliveryConfirmed;
    }

    mapping(uint256 => DeliveryDispute) public deliveryDisputes;  // با کلید decisionId
    mapping(uint256 => mapping(address => bool)) private hasVotedOnDelivery;

    uint256 public constant APPEAL_FILING_WINDOW = 72 hours;
    uint256 public constant APPEAL_VOTING_PERIOD = 7 days;
    /// @dev مدتی که ولیدیتور خودش می‌تواند تحویل را تأیید کند، پیش از اینکه هر کسی بتواند موضوع را به رأی اختلاف تحویل
    ///      بکشاند (۷ روز). تعیین می‌کند یک پرونده چقدر می‌تواند حل‌نشده بماند.
    uint256 public constant DELIVERY_DISPUTE_GRACE_PERIOD = 7 days;
    uint256 public constant DELIVERY_DISPUTE_VOTING_PERIOD = 7 days;

    // ------------------------------------------------------------------
    // رویدادهای معماری راستی‌آزمایی آف‌چین
    // ------------------------------------------------------------------
    event StatusDecisionRecorded(uint256 indexed decisionId, address indexed validator, DecisionType decisionType, bytes32 evidenceHash);
    event DeliveryConfirmed(uint256 indexed decisionId, address indexed validator, uint256 provenAt);
    event DeliveryDisputeFiled(uint256 indexed decisionId, uint256 votingDeadline);
    event DeliveryDisputeVoted(uint256 indexed decisionId, address indexed voter, uint256 votesConfirming, uint256 required);
    event DeliveryDisputeResolved(uint256 indexed decisionId, bool deliveryConfirmed);
    event AppealFiled(uint256 indexed decisionId, uint256 votingDeadline);
    event SlashVoted(uint256 indexed decisionId, address indexed voter, uint256 votes, uint256 required);
    event SlashResolved(uint256 indexed decisionId, address indexed validator, SlashOutcome outcome, uint256 slashedAmount);

    bool private locked;  // نگهبان reentrancy

    // ------------------------------------------------------------------
    // حکمرانی پارامتر (رأی کامل ولیدیتورها) — همه‌چیز **به‌جز** سه پارامتر اقتصادی ورود بالا
    // (آن‌ها تحت حکمرانی ValidatorsBoard هستند؛ به ValidatorsBoard.sol مراجعه کن).
    // ------------------------------------------------------------------

    enum ParamKey {
        MaxEntriesPerWindow,
        EntryWindowSeconds,
        ProbationPeriod,
        RecoveryPeriod,
        SlashBps,
        ExitCooldown
    }

    /// @dev `requiredVotes` و `expiresAt` هنگام ساخت پیشنهاد ثابت می‌شوند و هرگز بازمحاسبه نمی‌شوند، پس پیشنهاد
    ///      فقط به‌خاطر کوچک‌شدن بعدیِ تعداد فعال‌ها اجراشدنی نمی‌شود.
    struct ParamProposal {
        ParamKey key;
        uint256 newValue;
        uint256 votes;
        uint256 requiredVotes;  // هنگام ساخت ثابت می‌شود و هرگز بازمحاسبه نمی‌شود
        uint256 createdAt;
        uint256 expiresAt;  // پس از این زمان دیگر نمی‌شود روی پیشنهاد رأی داد یا آن را اجرا کرد
        bool executed;
        // statusNonce هنگام ساخت: رأی‌دهنده باید دقیقاً در همان نقطه Active بوده باشد.
        uint256 createdAtNonce;
    }

    /// @notice مدت رأی‌پذیری و اجراپذیری یک پیشنهاد تغییر پارامتر؛ پس از آن باید با رأی‌دهندگان تازه دوباره پیشنهاد شود.
    uint256 public constant PARAM_PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    // ActiveCheckpoint: تاریخچهٔ مرتب Active‌بودن هر ولیدیتور. رأی‌دهندگان هر پیشنهاد مجمع را (اینجا، در ValidatorsTreasury و در
    // BlockRewardDistributor) بدون باطل‌شدن با ورودها و خروج‌های بعدی ثبت می‌کند. statusNonce با هر گذار به Active یا از آن
    // بالا می‌رود و یک checkpoint ‏{nonce, active} اضافه می‌شود. مؤسسان genesis با checkpoint ‏{0, true} کاشته می‌شوند.
    struct ActiveCheckpoint {
        uint64 nonce;
        bool active;
    }
    uint256 public statusNonce;
    mapping(address => ActiveCheckpoint[]) private activeCheckpoints;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event MembershipRequested(address indexed validator, uint256 collateralAmount, uint256 feeAmount);
    event ValidatorActivated(address indexed validator);
    // ValidatorDemoted شناسهٔ DemotionEpoch را می‌آورد (جریمه بعداً تعیین می‌شود)، تا پایش بتواند رویداد SlashResolved
    // همان دوره را پیدا کند.
    event ValidatorDemoted(address indexed validator, uint256 pendingSlashEpoch);
    event ValidatorReactivated(address indexed validator);
    event ExitRequested(address indexed validator, uint256 cooldownEnd);
    event StakeWithdrawn(address indexed validator, uint256 amount);
    event ParameterChangeProposed(uint256 indexed id, ParamKey key, uint256 newValue, address indexed proposer);
    event ParameterChangeVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event ParameterChangeApplied(ParamKey key, uint256 newValue);
    event EconomicParamUpdatedByBoard(string paramName, uint256 oldValue, uint256 newValue);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(validators[msg.sender].status == Status.Active, "ValidatorsRegistry: caller is not an active validator");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "ValidatorsRegistry: caller is not the validators board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "ValidatorsRegistry: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // اینترفیس حالت contract-mode در QBFT بسو — امضا در بسو هاردکد شده، تغییرش نده.
    // ------------------------------------------------------------------
    function getValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    /// @notice آیا `who` در نقطهٔ وضعیت `nonce` Active بود؟ اگر در آن نقطه یا پیش از آن هیچ تاریخچه‌ای ندارد false. جست‌وجوی
    ///         دودویی روی checkpointهای فقط‌افزایشی.
    function wasActiveAt(address who, uint256 nonce) public view returns (bool) {
        ActiveCheckpoint[] storage cps = activeCheckpoints[who];
        uint256 lo = 0;
        uint256 hi = cps.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (cps[mid].nonce <= nonce) lo = mid + 1;
            else hi = mid;
        }
        return lo == 0 ? false : cps[lo - 1].active;
    }

    function _recordActiveCheckpoint(address who, bool active) private {
        statusNonce++;
        activeCheckpoints[who].push(ActiveCheckpoint({nonce: uint64(statusNonce), active: active}));
    }

    /// @notice چک صلاحیت پرداخت که مستقیم توسط BlockRewardDistributor استفاده می‌شود.
    function isValidator(address who) external view returns (bool) {
        return validators[who].status == Status.Active;
    }

    function getActiveValidatorCount() public view returns (uint256) {
        return activeValidators.length;
    }

    // ------------------------------------------------------------------
    // آستانه‌ی ورود / نرخ محدودیت
    // ------------------------------------------------------------------

    /// @notice استیک فعلی موردنیاز برای درخواست عضویت. به‌طور پیوسته رشد می‌کند (مرکب به‌ازای
    ///         هر ولیدیتور *پرداخت‌کرده* اضافی — paidValidatorCount را ببین — نه پرش گسسته، و
    ///         بدون شمردن مؤسسین رایگان genesis-seeded). سقف‌گذاری‌شده روی رشد معادل
    ///         MAX_GROWTH_VALIDATORS، برای جلوگیری از overflow/گس نامحدود.
    function currentEntryThreshold() public view returns (uint256) {
        uint256 n = paidValidatorCount;
        if (n > MAX_GROWTH_VALIDATORS) n = MAX_GROWTH_VALIDATORS;
        uint256 multiplier = _fixedPow(growthFactorPerValidator, n);
        return (entryThresholdBase * multiplier) / FIXED_POINT_ONE;
    }

    /// @dev توان‌رسانی fixed-point (FIXED_POINT_ONE = 1e18) با روش exponentiation by squaring:
    ///      برمی‌گرداند base1e18^exponent، به همان بازنمایی fixed-point با مبنای 1e18.
    ///      O(log2(exponent)) ضرب — حتی برای توان‌های بزرگ ارزان.
    function _fixedPow(uint256 base1e18, uint256 exponent) private pure returns (uint256 result1e18) {
        result1e18 = FIXED_POINT_ONE;  // ۱.۰
        uint256 b = base1e18;
        uint256 e = exponent;
        while (e > 0) {
            if (e & 1 == 1) {
                result1e18 = (result1e18 * b) / FIXED_POINT_ONE;
            }
            b = (b * b) / FIXED_POINT_ONE;
            e >>= 1;
        }
    }

    /// @notice کارمزد فعلی عضویت: کسری حکمرانی‌شده از currentEntryThreshold()، علاوه بر وثیقه پرداخت می‌شود و به
    ///         BlockRewardDistributor فرستاده می‌شود (در دورهٔ بعد به ولیدیتورهای فعال می‌رسد).
    function currentMembershipFee() public view returns (uint256) {
        return (currentEntryThreshold() * membershipFeeBps) / BPS_DENOMINATOR;
    }

    // ------------------------------------------------------------------
    // تنظیم‌کننده‌های پارامتر اقتصادی ورود — فقط ValidatorsBoard (اکثریت داخلی خودِ هیأت قبل
    // از فراخوانی این‌ها از قبل تغییر را تصویب کرده؛ به
    // proposeSetEntryThresholdBase / proposeSetGrowthFactorPerValidator / proposeSetMembershipFeeBps
    // در ValidatorsBoard.sol مراجعه کن).
    // ------------------------------------------------------------------
    function setEntryThresholdBase(uint256 newValue) external onlyBoard {
        require(
            newValue >= ENTRY_THRESHOLD_BASE_MIN && newValue <= ENTRY_THRESHOLD_BASE_MAX,
            "ValidatorsRegistry: entryThresholdBase outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("entryThresholdBase", entryThresholdBase, newValue);
        entryThresholdBase = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setGrowthFactorPerValidator(uint256 newValue) external onlyBoard {
        require(
            newValue >= GROWTH_FACTOR_MIN && newValue <= GROWTH_FACTOR_MAX,
            "ValidatorsRegistry: growthFactorPerValidator outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("growthFactorPerValidator", growthFactorPerValidator, newValue);
        growthFactorPerValidator = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(
            newValue >= MEMBERSHIP_FEE_BPS_MIN && newValue <= MEMBERSHIP_FEE_BPS_MAX,
            "ValidatorsRegistry: membershipFeeBps outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function _enforceRateLimit() private {
        if (block.timestamp >= windowStart + entryWindowSeconds) {
            windowStart = block.timestamp;
            entriesInWindow = 0;
        }
        require(entriesInWindow < maxEntriesPerWindow, "ValidatorsRegistry: entry rate limit reached");
        entriesInWindow++;
    }

    // ------------------------------------------------------------------
    // درخواست عضویت -> probation
    //
    // payable: فرستنده سورن بومی را در msg.value می‌فرستد که باید دقیقاً مجموع دو مبلغ باشد:
    //   ۱. `threshold` (currentEntryThreshold()): اینجا به‌عنوان وثیقهٔ قابل‌استرداد و قابل‌جریمه می‌ماند.
    //   ۲. `fee` (currentMembershipFee()): به BlockRewardDistributor فرستاده می‌شود.
    // ------------------------------------------------------------------
    function requestMembership() external payable nonReentrant {
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");
        require(!permanentlyExited[msg.sender], "ValidatorsRegistry: this address has exited before and may not rejoin");

        uint256 threshold = currentEntryThreshold();
        uint256 fee = currentMembershipFee();
        require(msg.value == threshold + fee, "ValidatorsRegistry: incorrect payment amount");

        _enforceRateLimit();

        if (fee > 0) {
            DISTRIBUTOR.receiveMembershipFee{value: fee}();
        }
        // `threshold` عمداً در موجودی بومی همین قرارداد به‌عنوان وثیقه‌ی قفل‌شده می‌ماند — نیازی
        // به انتقال نیست، همراه همین فراخوانی از طریق msg.value رسیده است.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: threshold,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: true
        });
        paidValidatorCount++;

        emit MembershipRequested(msg.sender, threshold, fee);
    }

    // ------------------------------------------------------------------
    // تصمیم‌های وضعیت. فقط `verifier` آن‌ها را پس از بررسی آف‌چین ولیدیتور ثبت می‌کند:
    //   - Probation / Demoted (بازگشت): آیا نود خودِ نامزد بالا و همگام است.
    //   - Active: تولید واقعی بلاک (فیلد `miner` بلاک‌های اخیر) در یک بازهٔ اخیر.
    // روش به‌کاررفته در بستهٔ شواهد آف‌چین پشت هر هش تصمیم ثبت می‌شود.
    // ------------------------------------------------------------------
    // فعال‌سازی پس از probation — گزارش verifier، راستی‌آزمایی آف‌چین (بدون مسیر اختلاف: نتیجه‌ای کاملاً مثبت که هیچ
    // کسی دلیلی برای اعتراض به آن ندارد).
    // ------------------------------------------------------------------
    function recordActivation(address candidate, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[candidate];
        require(v.status == Status.Probation, "ValidatorsRegistry: not in probation");
        require(block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        _activate(candidate);
        decisionId = _recordDecision(candidate, DecisionType.Activation, evidenceHash, 0);
        _notifyBoard(candidate);
    }

    // ------------------------------------------------------------------
    // بازگشت بعد از recoveryPeriod یه دموت — همون استدلال «بدون مسیر اختلاف» فعال‌سازی.
    // ------------------------------------------------------------------
    function recordRecovery(address validator, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        // pendingSlashEpoch حل‌نشده از تعلیقی که از آن بازمی‌گردد باید اول تعیین‌تکلیف شود، وگرنه یک تعلیق مجدد
        // می‌تواند آن را بازنویسی کند.
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: resolve the pending slash first");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        _activate(validator);
        decisionId = _recordDecision(validator, DecisionType.Recovery, evidenceHash, 0);
        emit ValidatorReactivated(validator);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // تعلیق — گزارش verifier. حذف از مجموعهٔ فعال فوری و بی‌قیدوشرط است (یادداشت راستی‌آزمایی آف‌چین بالا را ببینید)؛
    // فقط تصمیم جریمهٔ نهایی از بررسی خرابی جمعی و بعد سازوکار تحویل/اعتراض/رأی در ادامه می‌گذرد.
    // ------------------------------------------------------------------
    function recordSuspension(address validator, bytes32 evidenceHash) external onlyVerifier nonReentrant returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - suspension blocked");

        _removeFromActive(validator);
        _recordActiveCheckpoint(validator, false);  // L04

        uint256 epochId = _recordDemotion(v, true);  // تصمیم جریمه معلقه — به resolveMassFailureCheck() مراجعه کن
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp;  // دوره‌ی بازگشت از همین الان شروع می‌شود

        decisionId = _recordDecision(validator, DecisionType.Suspension, evidenceHash, epochId);
        emit ValidatorDemoted(validator, epochId);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // پرونده‌ای دربارهٔ رفتار PRIOR به درخواست خروج. درخواست خروج وظیفهٔ اعتبارسنجی را فوراً پایان می‌دهد و انتظار ۱هفته‌ای
    // برداشت را شروع می‌کند؛ تا ۷۲ ساعت verifier هنوز می‌تواند دربارهٔ رفتار پیشین پرونده بسازد. بی‌فعالیتی AFTER درخواست
    // هرگز تخلف نیست. ادعای خالی verifier کافی نیست: هش شواهد، زمان تخلف و سازوکار عادی معافیت خرابی جمعی / تحویل /
    // اعتراض / رأی مجمع همه اعمال می‌شوند.
    // ------------------------------------------------------------------
    function recordPreExitViolation(address validator, bytes32 evidenceHash, uint256 violationAt) external onlyVerifier nonReentrant returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Exiting, "ValidatorsRegistry: validator is not exiting");
        require(statusBeforeExit[validator] == uint8(Status.Active), "ValidatorsRegistry: had no validation duty when exiting");
        uint256 exitRequestedAt = v.periodStartedAt;  // requestExit() این را ثبت می‌کند
        require(block.timestamp <= exitRequestedAt + PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: pre-exit claim window closed");
        require(violationAt < exitRequestedAt, "ValidatorsRegistry: violation must precede the exit request");
        require(violationAt > v.demotedAt, "ValidatorsRegistry: violation predates the last suspension");
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: a case is already pending");

        uint256 epochId = _recordDemotion(v, false);  // همین الان از مجموعه‌ی فعال حذف نشده (در لحظه‌ی درخواست خروج حذف شده)
        decisionId = _recordDecision(validator, DecisionType.Suspension, evidenceHash, epochId);
        decisionViolationAt[decisionId] = violationAt;
        emit PreExitCaseRecorded(decisionId, validator, violationAt, exitRequestedAt, evidenceHash);
    }

    function _recordDecision(address validator, DecisionType dtype, bytes32 evidenceHash, uint256 demotionEpochId) private returns (uint256 id) {
        statusDecisionCount++;
        id = statusDecisionCount;
        statusDecisions[id] = StatusDecision({
            validator: validator,
            decisionType: dtype,
            decidedAt: block.timestamp,
            evidenceHash: evidenceHash,
            demotionEpochId: demotionEpochId,
            delivery: dtype == DecisionType.Suspension ? DeliveryStatus.Pending : DeliveryStatus.NotApplicable,
            deliveryProvenAt: 0,
            appealFiled: false,
            appealFiledAt: 0,
            appealVotingDeadline: 0,
            confirmVotes: 0,
            requiredConfirmVotes: 0,
            slashOutcome: SlashOutcome.Undetermined
        });
        if (dtype == DecisionType.Suspension) {
            pendingSlashDecisionId[validator] = id;
            decisionSlashAmount[id] = (validators[validator].lockedStake * slashBps) / BPS_DENOMINATOR;
        }
        emit StatusDecisionRecorded(id, validator, dtype, evidenceHash);
    }

    // ------------------------------------------------------------------
    // این تعلیق را در DemotionEpoch جاری (یا تازه‌گشوده) ثبت می‌کند و ولیدیتور را دارای تصمیم جریمهٔ در انتظار علامت می‌زند.
    // به lockedStake دست نمی‌زند، چیزی منتقل نمی‌کند و هرگز عضویت مجموعهٔ فعال را عوض نمی‌کند. توسط recordSuspension()
    // و recordPreExitViolation() صدا زده می‌شود.
    // ------------------------------------------------------------------
    function _recordDemotion(ValidatorInfo storage v, bool validatorJustRemovedFromActive) private returns (uint256 epochId) {
        if (currentDemotionEpochId == 0 || block.timestamp >= demotionEpochs[currentDemotionEpochId].startedAt + MASS_DEMOTION_WINDOW) {
            currentDemotionEpochId++;
            DemotionEpoch storage fresh = demotionEpochs[currentDemotionEpochId];
            fresh.startedAt = block.timestamp;
            fresh.referenceCount = activeValidators.length + (validatorJustRemovedFromActive ? 1 : 0);  // +۱: فراخواننده این ولیدیتور را از قبل برداشته؛ برای هر دوره یک‌بار ثبت می‌شود
        }
        epochId = currentDemotionEpochId;
        demotionEpochs[epochId].demotionCount++;
        v.pendingSlashEpoch = epochId;
    }

    /// @notice بدون مجوز: هر کسی می‌تواند پس از بسته‌شدن DemotionEpoch یک ولیدیتور آن را صدا بزند. فقط دروازهٔ خرابی جمعی
    ///         است: اگر معافیت برقرار باشد پرونده همین‌جا بسته می‌شود (ExemptMassFailure)؛ وگرنه پرونده به سازوکار
    ///         تحویل / اعتراض / رأی در ادامه می‌رود.
    function resolveMassFailureCheck(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(!massFailureChecked[decisionId], "ValidatorsRegistry: already checked for this decision");
        DemotionEpoch storage epoch = demotionEpochs[d.demotionEpochId];
        require(block.timestamp >= epoch.startedAt + MASS_DEMOTION_WINDOW, "ValidatorsRegistry: demotion epoch not yet closed");

        if (!epoch.resolved) {
            epoch.resolved = true;
            epoch.wasMassFailure = epoch.demotionCount * BPS_DENOMINATOR > epoch.referenceCount * MASS_DEMOTION_SLASH_PAUSE_BPS;
        }

        // برای هر تصمیم جداگانه و بی‌قیدوشرط تنظیم می‌شود، چه دورهٔ آن خرابی جمعی بوده چه نه؛
        // _massFailureResolved() دقیقاً همین پرچم را چک می‌کند. محاسبهٔ مشترک (epoch.wasMassFailure) تکرار نمی‌شود.
        massFailureChecked[decisionId] = true;

        if (epoch.wasMassFailure) {
            d.slashOutcome = SlashOutcome.ExemptMassFailure;
            _clearPendingSlashIfCurrent(decisionId);  // کاملاً بسته — دیگه هیچ‌وقت تحویل/اعتراض لازم نمی‌شه
            emit SlashResolved(decisionId, d.validator, SlashOutcome.ExemptMassFailure, 0);
        }
        // اگر خرابی جمعی نبود: d.delivery از قبل در _recordDecision روی DeliveryStatus.Pending است، پس اینجا کار دیگری
        // انجام نمی‌شود. pendingSlashEpoch ناصفر می‌ماند و withdrawStake() را تا تعیین‌تکلیف جریان زیر مسدود نگه می‌دارد.
    }

    // ------------------------------------------------------------------
    // تحویل بستهٔ شواهد — تأیید روی زنجیرهٔ خودِ ولیدیتور شاهد اصلی است. دلیل کامل را در یادداشت راستی‌آزمایی آف‌چین
    // بالا ببینید.
    // ------------------------------------------------------------------

    /// @notice قفل جریمهٔ در انتظار روی ولیدیتور است، پس به همان تصمیمی بسته می‌شود که ساختش (`pendingSlashDecisionId`).
    ///         یک تصمیم فقط تا وقتی هنوز نگهدارندهٔ قفل است می‌تواند آن را آزاد کند، پس تعیین‌تکلیف یک پروندهٔ قدیمی هرگز
    ///         قفل پروندهٔ جدیدتر را پاک نمی‌کند. `pendingSlashEpoch` فقط برای ABI بیرونی getValidatorInfo() هماهنگ نگه
    ///         داشته می‌شود.
    function _clearPendingSlashIfCurrent(uint256 decisionId) private {
        address who = statusDecisions[decisionId].validator;
        if (pendingSlashDecisionId[who] == decisionId) {
            pendingSlashDecisionId[who] = 0;
            validators[who].pendingSlashEpoch = 0;
        }
    }

    /// @notice وقتی resolveMassFailureCheck() برای این تصمیم اجرا شده true است. هر تابعی که پروندهٔ تعلیق را جلو می‌برد
    ///         (confirmDelivery، assertDeliveryDisputed، fileAppeal، executeUncontestedSlash) اول آن را می‌خواهد، پس
    ///         معافیت خرابی جمعی همیشه بر هر اختلاف فردی مقدم است.
    function _massFailureResolved(uint256 decisionId) private view returns (bool) {
        return massFailureChecked[decisionId];
    }

    /// @notice فقط دریافت بستهٔ شواهد را تأیید می‌کند، نه درستی اتهام را. پنجرهٔ ۷۲ساعتهٔ ثبت اعتراض را شروع می‌کند
    ///         (جدا از دورهٔ رأی اعتراض که با ثبت اعتراض شروع می‌شود).
    function confirmDelivery(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(msg.sender == d.validator, "ValidatorsRegistry: only the subject validator may confirm delivery");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(d.delivery == DeliveryStatus.Pending || d.delivery == DeliveryStatus.Disputed, "ValidatorsRegistry: delivery already confirmed");

        d.delivery = DeliveryStatus.Confirmed;
        d.deliveryProvenAt = block.timestamp;
        // اگر برای این تصمیم اختلاف تحویل باز است، تأیید خودِ ولیدیتور آن را فوراً و هماهنگ می‌بندد؛ بازگذاشتنش
        // باعث می‌شد resolveDeliveryDisputeIfExpired() بعداً این تأیید را با VoidedNoDelivery بازنویسی کند.
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        if (disp.filedAt != 0 && !disp.resolved) {
            disp.resolved = true;
            disp.deliveryConfirmed = true;
            emit DeliveryDisputeResolved(decisionId, true);
        }
        emit DeliveryConfirmed(decisionId, d.validator, block.timestamp);
    }

    /// @notice اگه ولیدیتور ظرف DELIVERY_DISPUTE_GRACE_PERIOD خودش تأیید نکنه، هرکسی (معمولاً
    ///         Verifier) می‌تونه سؤال رو جلوی مجمع ببره. این خودش هیچی رو تصمیم نمی‌گیره — یه
    ///         رأی‌گیری اختصاصی اختلاف تحویل باز می‌کنه (voteOnDelivery پایین) که **باید** قبل
    ///         از این‌که هر رأی‌گیری تأیید-جریمه‌ای حتی ثبت بشه حل بشه (طبق الزام صریح کاربر
    ///         که مرجع رسیدگی اول تحویل رو تصمیم بگیره، بعد اصل موضوع رو).
    function assertDeliveryDisputed(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        // پرونده‌ای که به نتیجهٔ نهایی رسیده (مثلاً ExemptMassFailure) هرگز بازگشایی نمی‌شود: resolveMassFailureCheck()
        // حتی وقتی پرونده را معاف می‌کند `delivery` را روی Pending می‌گذارد.
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(d.delivery == DeliveryStatus.Pending, "ValidatorsRegistry: delivery not pending");
        require(block.timestamp >= d.decidedAt + DELIVERY_DISPUTE_GRACE_PERIOD, "ValidatorsRegistry: grace period not elapsed");
        require(deliveryDisputes[decisionId].filedAt == 0, "ValidatorsRegistry: delivery dispute already filed");

        d.delivery = DeliveryStatus.Disputed;
        uint256 votingDeadline = block.timestamp + DELIVERY_DISPUTE_VOTING_PERIOD;
        deliveryDisputes[decisionId] = DeliveryDispute({
            decisionId: decisionId,
            filedAt: block.timestamp,
            votingDeadline: votingDeadline,
            votesConfirmingDelivery: 0,
            requiredVotes: (getActiveValidatorCount() / 2) + 1,  // ثبت‌شده؛ مجمع کامل. موضوع پرونده کنار گذاشته نمی‌شود، ولی دیگر Active نیست و نمی‌تواند رأی بدهد.
            resolved: false,
            deliveryConfirmed: false
        });
        deliveryDisputeNonce[decisionId] = statusNonce;
        emit DeliveryDisputeFiled(decisionId, votingDeadline);
    }

    /// @notice رأی مجمع روی سؤال محدود واقعیت «آیا بسته‌ی شواهد واقعاً در دسترس این ولیدیتور
    ///         گذاشته شده» — هرگز اصل موضوع خودِ تعلیق.
    function voteOnDelivery(uint256 decisionId, bool confirmsDelivery) external onlyActiveValidator {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        require(disp.filedAt != 0, "ValidatorsRegistry: no delivery dispute for this decision");
        require(!disp.resolved, "ValidatorsRegistry: delivery dispute already resolved");
        require(block.timestamp <= disp.votingDeadline, "ValidatorsRegistry: delivery-dispute voting period has ended");
        require(wasActiveAt(msg.sender, deliveryDisputeNonce[decisionId]), "ValidatorsRegistry: not eligible - not Active when this dispute was filed");
        require(!hasVotedOnDelivery[decisionId][msg.sender], "ValidatorsRegistry: already voted");
        hasVotedOnDelivery[decisionId][msg.sender] = true;

        if (confirmsDelivery) {
            disp.votesConfirmingDelivery++;
        }
        emit DeliveryDisputeVoted(decisionId, msg.sender, disp.votesConfirmingDelivery, disp.requiredVotes);

        if (disp.votesConfirmingDelivery >= disp.requiredVotes) {
            _resolveDeliveryDispute(decisionId, true);
        }
    }

    /// @notice بدون نیاز به مجوز — اگه دوره‌ی رأی‌گیری اختلاف تحویل بدون رسیدن به نصاب برای
    ///         تأیید تحویل تموم بشه، تحویل به‌عنوان هرگز-ثابت‌نشده درنظر گرفته می‌شه (همون
    ///         پیش‌فرض بار-اثبات که همه‌جای دیگه‌ی این مکانیزم استفاده شده: طرفی که دنبال
    ///         جریمه‌ست، ریسک یه رأی‌گیری بی‌نتیجه رو به عهده می‌گیره).
    function resolveDeliveryDisputeIfExpired(uint256 decisionId) external {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        require(disp.filedAt != 0, "ValidatorsRegistry: no delivery dispute for this decision");
        require(!disp.resolved, "ValidatorsRegistry: already resolved");
        require(block.timestamp > disp.votingDeadline, "ValidatorsRegistry: voting period not yet over");
        _resolveDeliveryDispute(decisionId, false);
    }

    function _resolveDeliveryDispute(uint256 decisionId, bool confirmed) private {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        disp.resolved = true;
        disp.deliveryConfirmed = confirmed;
        StatusDecision storage d = statusDecisions[decisionId];
        // اگر پرونده از مسیر دیگری به نتیجهٔ نهایی رسیده، این اختلاف فقط رکورد خودش را می‌بندد؛ هرگز نتیجه را بازنویسی
        // نمی‌کند و به قفل ولیدیتور دست نمی‌زند.
        if (d.slashOutcome != SlashOutcome.Undetermined) {
            emit DeliveryDisputeResolved(decisionId, confirmed);
            return;
        }
        if (confirmed) {
            d.delivery = DeliveryStatus.Confirmed;
            d.deliveryProvenAt = block.timestamp;
        } else {
            // اختلاف تحویلی که مدعی می‌بازد فقط جریمه را باطل می‌کند. ولیدیتور را به اجماع برنمی‌گرداند: آن همچنان
            // مسیر عادی بازگشت را می‌خواهد.
            d.slashOutcome = SlashOutcome.VoidedNoDelivery;
            _clearPendingSlashIfCurrent(decisionId);
            emit SlashResolved(decisionId, d.validator, SlashOutcome.VoidedNoDelivery, 0);
        }
        emit DeliveryDisputeResolved(decisionId, confirmed);
    }

    // ------------------------------------------------------------------
    // ثبت اعتراض و رأی‌گیری تأیید-جریمه
    // ------------------------------------------------------------------

    /// @notice فقط خودِ ولیدیتور موضوع (کسی که مستقیم‌ترین نفع رو داره، و تنها کسیه که این
    ///         مکانیزم برای محافظتش طراحی شده) می‌تونه ثبت کنه — ظرف ۷۲ ساعت از تحویل
    ///         **ثابت‌شده**، نه ادعای Verifier که فرستادتش.
    function fileAppeal(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(msg.sender == d.validator, "ValidatorsRegistry: only the subject validator may file an appeal");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.delivery == DeliveryStatus.Confirmed, "ValidatorsRegistry: delivery not proven yet");
        require(!d.appealFiled, "ValidatorsRegistry: appeal already filed");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(block.timestamp <= d.deliveryProvenAt + APPEAL_FILING_WINDOW, "ValidatorsRegistry: appeal filing window has passed");

        d.appealFiled = true;
        appealNonce[decisionId] = statusNonce;
        d.appealFiledAt = block.timestamp;
        d.appealVotingDeadline = block.timestamp + APPEAL_VOTING_PERIOD;
        // حداقل رأی لازم: اکثریت ولیدیتورهای فعال — خودِ ولیدیتور موضوع جداگانه exclude
        // نمی‌شه چون از قبل Demoted (نه Active) هست، پس onlyActiveValidator پایین از قبل
        // بیرون نگهش می‌داره.
        d.requiredConfirmVotes = (getActiveValidatorCount() / 2) + 1;
        emit AppealFiled(decisionId, d.appealVotingDeadline);
    }

    /// @notice رأی مجمع برای تأیید جریمه — فقط اگه یه اعتراض واقعاً ثبت شده باشه به اینجا
    ///         می‌رسه. اکثریت ساده، snapshot‌شده در لحظه‌ی ثبت، مهلت سخت ۷روزه جدا از پنجره‌ی
    ///         ثبت ۷۲ساعته‌ی بالا.
    function confirmSlash(uint256 decisionId) external onlyActiveValidator nonReentrant {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.appealFiled, "ValidatorsRegistry: no appeal filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp <= d.appealVotingDeadline, "ValidatorsRegistry: voting period has ended");
        require(wasActiveAt(msg.sender, appealNonce[decisionId]), "ValidatorsRegistry: not eligible - not Active when the appeal was filed");
        require(!hasVotedOnSlash[decisionId][msg.sender], "ValidatorsRegistry: already voted");

        hasVotedOnSlash[decisionId][msg.sender] = true;
        d.confirmVotes++;
        emit SlashVoted(decisionId, msg.sender, d.confirmVotes, d.requiredConfirmVotes);

        if (d.confirmVotes >= d.requiredConfirmVotes) {
            _executeSlash(decisionId, SlashOutcome.Confirmed);
        }
    }

    /// @notice بدون نیاز به مجوز — اگه مهلت رأی‌گیری اعتراض بدون رسیدن به نصاب تأیید تموم
    ///         بشه، جریمه **رد** می‌شه (بار اثبات با کسیه که می‌خواد جریمه کنه). خودِ تعلیقِ
    ///         اجماعی دست‌نخورده می‌مونه — برگشت به Active همچنان نیازمند مسیر مستقل
    ///         recordRecovery() بالاست، صرف‌نظر از این نتیجه.
    function resolveAppealIfExpired(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.appealFiled, "ValidatorsRegistry: no appeal filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp > d.appealVotingDeadline, "ValidatorsRegistry: voting period not yet over");
        d.slashOutcome = SlashOutcome.RejectedNoQuorum;
        _clearPendingSlashIfCurrent(decisionId);
        emit SlashResolved(decisionId, d.validator, SlashOutcome.RejectedNoQuorum, 0);
    }

    /// @notice بدون نیاز به مجوز — اگه تحویل ثابت شده و ۷۲ ساعت گذشته بدون این‌که هیچ‌وقت
    ///         اعتراضی ثبت بشه، جریمه بی‌اعتراض اعمال می‌شه (یه اتهام بی‌چالش همچنان به
    ///         جریمه منجر می‌شه، دقیقاً مثل یه دعوی مدنیِ بی‌پاسخ).
    function executeUncontestedSlash(uint256 decisionId) external nonReentrant {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.delivery == DeliveryStatus.Confirmed, "ValidatorsRegistry: delivery not proven yet");
        require(!d.appealFiled, "ValidatorsRegistry: an appeal was filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp > d.deliveryProvenAt + APPEAL_FILING_WINDOW, "ValidatorsRegistry: appeal filing window still open");

        _executeSlash(decisionId, SlashOutcome.ExecutedUncontested);
    }

    function _executeSlash(uint256 decisionId, SlashOutcome outcome) private {
        StatusDecision storage d = statusDecisions[decisionId];
        d.slashOutcome = outcome;
        ValidatorInfo storage v = validators[d.validator];
        _clearPendingSlashIfCurrent(decisionId);

        uint256 slashAmount = decisionSlashAmount[decisionId];  // در لحظه‌ی ثبت پرونده ثابت شده (P04)
        if (slashAmount > v.lockedStake) slashAmount = v.lockedStake;
        v.lockedStake -= slashAmount;
        if (slashAmount > 0) {
            (bool success, ) = TREASURY.call{value: slashAmount}("");
            require(success, "ValidatorsRegistry: slash transfer failed");
        }
        emit SlashResolved(decisionId, d.validator, outcome, slashAmount);
    }

    function _activate(address who) private {
        ValidatorInfo storage v = validators[who];
        v.status = Status.Active;
        activeIndex[who] = activeValidators.length + 1;
        activeValidators.push(who);
        if (!everActivated[who]) {
            everActivated[who] = true;
            activationSeq[who] = ++activationCount;
        }
        _recordActiveCheckpoint(who, true);  // L04
        emit ValidatorActivated(who);
    }

    /// @dev به ValidatorsBoard خبر می‌دهد وضعیت `who` عوض شده تا رأی‌های آن ولیدیتور را اضافه یا کم کند. فراخوان بهترین‌تلاش با
    ///      سقف گس است: شکست آن هرگز تغییر وضعیت را مسدود نمی‌کند.
    function _notifyBoard(address who) private {
        (bool ok, ) = SurAddresses.VALIDATORS_BOARD.call{gas: BOARD_SYNC_GAS}(
            abi.encodeWithSelector(IValidatorsBoardSync.syncVoter.selector, who)
        );
        ok;  // عمداً نادیده گرفته می‌شود
    }

    function _removeFromActive(address who) private {
        uint256 idx = activeIndex[who];  // یک‌مبنایی
        require(idx != 0, "ValidatorsRegistry: not in active set");
        uint256 lastIdx = activeValidators.length;  // آخرین موقعیت یک‌مبنایی

        if (idx != lastIdx) {
            address lastAddr = activeValidators[lastIdx - 1];
            activeValidators[idx - 1] = lastAddr;
            activeIndex[lastAddr] = idx;
        }
        activeValidators.pop();
        delete activeIndex[who];
    }

    // ------------------------------------------------------------------
    // خروج داوطلبانه
    // ------------------------------------------------------------------
    function requestExit() external {
        ValidatorInfo storage v = validators[msg.sender];
        require(
            v.status == Status.Active || v.status == Status.Probation || v.status == Status.Demoted,
            "ValidatorsRegistry: nothing to exit"
        );

        if (v.status == Status.Active) {
            require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - exit blocked");
            // درخواست خروج وظیفهٔ اعتبارسنجی را فوراً پایان می‌دهد: حذف از مجموعهٔ فعال (و در نتیجه از مجموعهٔ ولیدیتور QBFT
            // و از اختیار هیأت). مسئولیت‌پذیری را پاک نمی‌کند: تا PRE_EXIT_CLAIM_WINDOW (‏۷۲ ساعت) verifier هنوز می‌تواند
            // دربارهٔ رفتار پیشین پرونده بسازد (recordPreExitViolation) و مبلغ در معرض خطر تا تعیین‌تکلیف هر پرونده توسط
            // withdrawStake() رزرو می‌ماند.
            _removeFromActive(msg.sender);
            _recordActiveCheckpoint(msg.sender, false);  // L04
        }

        // ورودی پرداختی که می‌رود جایگاهش را در منحنی رشد آزاد می‌کند. مؤسسان (isPaidEntrant == false) هرگز شمارنده را
        // زیاد نکردند، پس هرگز کم هم نمی‌کنند.
        if (v.isPaidEntrant) {
            paidValidatorCount--;
        }

        statusBeforeExit[msg.sender] = uint8(v.status);  // قبل از تغییر وضعیت پایین خوانده می‌شود
        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;
        // از این لحظه اختیار هیأتِ این عضویت پایان یافته است: permanentlyExited جلوی ثبت‌نام دوبارهٔ آدرس را می‌گیرد
        // و membershipEpoch هر کرسی هیأت با epoch قدیمی را باطل می‌کند.
        permanentlyExited[msg.sender] = true;
        membershipEpoch[msg.sender]++;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
        _notifyBoard(msg.sender);
    }

    /// @notice برداشت پس از exitCooldown. اگر پرونده‌ای در انتظار نباشد کل استیک پرداخت می‌شود. اگر پرونده‌ای در انتظار باشد
    ///         فقط مبلغ در معرض خطر (که هنگام ثبت پرونده ثابت شد) رزرو می‌ماند؛ باقی همین حالا پرداخت می‌شود و باقی‌ماندهٔ
    ///         رزروشده را می‌شود با صدا زدن دوبارهٔ تابع پس از تعیین‌تکلیف پرونده (بعد از هر جریمه) برداشت.
    function withdrawStake() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Exiting, "ValidatorsRegistry: not exiting");
        require(block.timestamp >= v.periodStartedAt + exitCooldown, "ValidatorsRegistry: exit cooldown not elapsed");

        uint256 reserved = 0;
        if (v.pendingSlashEpoch != 0) {
            reserved = decisionSlashAmount[pendingSlashDecisionId[msg.sender]];
            if (reserved > v.lockedStake) reserved = v.lockedStake;
        }
        uint256 amount = v.lockedStake - reserved;
        v.lockedStake = reserved;
        if (v.pendingSlashEpoch == 0) {
            delete validators[msg.sender];
            delete statusBeforeExit[msg.sender];
        }

        if (amount > 0) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ValidatorsRegistry: withdraw transfer failed");
        }

        emit StakeWithdrawn(msg.sender, amount);
    }

    // ------------------------------------------------------------------
    // حکمرانی پارامتر — رأی اکثریت کامل ولیدیتورهای فعال
    // ------------------------------------------------------------------
    function proposeParameterChange(ParamKey key, uint256 newValue) external onlyActiveValidator returns (uint256 id) {
        // recoveryPeriod باید همیشه اکیداً بلندتر از MASS_DEMOTION_WINDOW بماند: _clearPendingSlashIfCurrent() یک پرونده را
        // با DemotionEpoch آن می‌شناسد، که فقط وقتی بی‌ابهام است که یک ولیدیتور هرگز نتواند در یک epoch دو بار تعلیق شود
        // (تعلیق، بازگشت، تعلیق). هم هنگام پیشنهاد اعتبارسنجی می‌شود (تا پیشنهاد نامعتبر نه ساخته شود و نه رأی آخر خودش را
        // قفل کند) و هم دوباره در _applyParam().
        if (key == ParamKey.RecoveryPeriod) {
            require(newValue > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
        } else if (key == ParamKey.ExitCooldown) {
            require(newValue > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
        }
        paramProposalCount++;
        id = paramProposalCount;
        paramProposals[id] = ParamProposal({
            key: key,
            newValue: newValue,
            votes: 0,
            requiredVotes: (getActiveValidatorCount() / 2) + 1,  // همین لحظه ثابت‌شده
            createdAt: block.timestamp,
            expiresAt: block.timestamp + PARAM_PROPOSAL_EXPIRY,
            executed: false,
            createdAtNonce: statusNonce
        });
        emit ParameterChangeProposed(id, key, newValue, msg.sender);
        _voteParam(id, msg.sender);
    }

    function voteParameterChange(uint256 id) external onlyActiveValidator {
        _voteParam(id, msg.sender);
    }

    function _voteParam(uint256 id, address voter) private {
        ParamProposal storage p = paramProposals[id];
        require(p.createdAt != 0, "ValidatorsRegistry: proposal not found");
        require(!p.executed, "ValidatorsRegistry: already executed");
        require(block.timestamp <= p.expiresAt, "ValidatorsRegistry: proposal has expired");
        require(!paramHasVoted[id][voter], "ValidatorsRegistry: already voted");
        // رأی‌دهنده باید هنگام ساخت پیشنهاد Active بوده باشد (رأی‌دهندگانِ ثبت‌شده) و اکنون هم Active باشد
        // (onlyActiveValidator). تعلیق موقت رأی‌دهنده را از رأی‌دهندگان اولیه خارج نمی‌کند؛ فقط تا وقتی تعلیق است رأی دادن
        // را مسدود می‌کند.
        require(wasActiveAt(voter, p.createdAtNonce), "ValidatorsRegistry: not eligible - not Active when this proposal was created");

        paramHasVoted[id][voter] = true;
        p.votes++;

        emit ParameterChangeVoted(id, voter, p.votes, p.requiredVotes);

        if (p.votes >= p.requiredVotes) {
            p.executed = true;
            _applyParam(p.key, p.newValue);
        }
    }

    function _applyParam(ParamKey key, uint256 value) private {
        if (key == ParamKey.MaxEntriesPerWindow) {
            maxEntriesPerWindow = value;
        } else if (key == ParamKey.EntryWindowSeconds) {
            entryWindowSeconds = value;
        } else if (key == ParamKey.ProbationPeriod) {
            probationPeriod = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            require(value > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
            recoveryPeriod = value;
        } else if (key == ParamKey.SlashBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: slashBps too high");
            slashBps = value;
        } else if (key == ParamKey.ExitCooldown) {
            require(value > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
            exitCooldown = value;
        }
        emit ParameterChangeApplied(key, value);
    }

    // ------------------------------------------------------------------
    // توابع کمکی نمایش
    // ------------------------------------------------------------------
    /// @notice ۶ خروجی را دقیقاً با این ترتیب برمی‌گرداند: status، lockedStake، periodStartedAt، demotedAt، pendingSlashEpoch،
    ///         isPaidEntrant. هر رابط بیرونی که این تابع را تعریف کند (مثلاً نسخه‌ای در ValidatorsBoard.sol) باید ترتیب و
    ///         تعداد را رعایت کند، چون Solidity نتیجهٔ فراخوان‌های خارجی را به‌صورت موقعیتی رمزگشایی می‌کند، نه با نام.
    function getValidatorInfo(address who) external view returns (
        Status status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
    ) {
        ValidatorInfo storage v = validators[who];
        return (
            v.status,
            v.lockedStake,
            v.periodStartedAt,
            v.demotedAt,
            v.pendingSlashEpoch,
            v.isPaidEntrant
        );
    }

    function requiredVotesNow() external view returns (uint256) {
        return (getActiveValidatorCount() / 2) + 1;
    }

    // ------------------------------------------------------------------
    // رد هر انتقال ساده‌ی ارز بومی که بخشی از requestMembership() نباشد — موجودی این قرارداد
    // باید همیشه دقیقاً برابر مجموع مبالغ وثیقه‌ی قفل‌شده باشد، بدون هیچ وجه پرت و حسابرسی‌نشده.
    // ------------------------------------------------------------------
    receive() external payable {
        revert("ValidatorsRegistry: use requestMembership() to send funds");
    }

    // ------------------------------------------------------------------
    // وضعیت اضافی. این متغیرها آخر اعلام شده‌اند تا هر slot قبلی (و در نتیجه چیدمان کمک‌کنندهٔ seed genesis) سر جایش بماند.
    // ------------------------------------------------------------------

    /// @notice تعداد آدرس‌هایی که تاکنون فعال شده‌اند؛ نخستین فعال‌سازی بعدی این مقدار + ۱ را می‌گیرد.
    uint256 public activationCount;

    /// @notice ترتیب نخستین فعال‌سازی (۱ = قدیمی‌ترین؛ مؤسسان به ترتیب genesis شماره می‌گیرند؛ ۰ = هرگز فعال نشده).
    ///         ValidatorsBoard از آن برای شکستن تساوی نامزدهای هم‌رأی استفاده می‌کند: ولیدیتور قدیمی‌تر برنده است.
    mapping(address => uint256) public activationSeq;

    /// @notice statusNonce هنگام ثبت اختلاف تحویل، برای هر تصمیم: فقط ولیدیتورهایی که آن زمان Active بودند می‌توانند رأی دهند.
    mapping(uint256 => uint256) public deliveryDisputeNonce;

    /// @notice statusNonce هنگام ثبت اعتراض، برای هر تصمیم: فقط ولیدیتورهایی که آن زمان Active بودند می‌توانند روی جریمه رأی دهند.
    mapping(uint256 => uint256) public appealNonce;
}
