// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IBlockRewardDistributor {
    function receiveMembershipFee() external payable;
    function migrateClaimable(address from, address to) external; // مهاجرت صندلی پس از گم‌شدن کلید مالک: آنچه به مالک قدیم بدهکار است را می‌برد
}

interface IValidatorsBoardSync {
    function syncVoter(address voter) external;
    function onSeatMigrated(address oldOwner, address newOwner, bool seatWasValid) external; // مهاجرت صندلی: فراخوان الزامی (شکستش مهاجرت را revert می‌کند)؛ کرسی هیأت و رأی‌های انتخاباتی همراه شخص به آدرس تازه می‌روند
    function hasValidSeat(address who) external view returns (bool); // درست پیش از جابه‌جایی رکورد خوانده می‌شود (جابه‌جایی epoch عضویت آدرس قدیمی را بالا می‌برد): کرسیِ از قبل پایان‌یافته منتقل نمی‌شود
}

interface IValidatorSeatNFT {
    function mintSeat(address to) external returns (uint256);
    function burnSeat(address owner) external;
    function reassignSeat(address from, address to) external returns (uint256 seatId); // مهاجرت صندلی: توکن را می‌برد، بدون hook
    function ownerOf(uint256 tokenId) external view returns (address); // برای توکن ناموجود revert می‌کند
}

interface IBoardAuthority {
    function hasBoardAuthority(address who) external view returns (bool);
}

interface IIdentityFullyVerified {
    function isFullyVerified(address who) external view returns (bool);
    function migratedTo(address who) external view returns (address); // غیرصفر: هویت به آن آدرس مهاجرت کرده (آدرس قدیم سوخته)
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
///           - پارامترهای اقتصادی ورود (entryCollateral، membershipFeeBps) فقط با رأی
///             داخلی ValidatorsBoard تغییر می‌کنند.
///           - بقیهٔ پارامترها (طول پنجرهٔ ورود، دورهٔ بازیابی، دورهٔ خروج) اکثریتِ ولیدیتورهایی را می‌خواهند
///             که هنگام ساخت پیشنهاد Active بوده‌اند (proposeParameterChange / voteParameterChange). حداکثر یک ورود پولی در هر پنجره،
///             probation یک‌هفته‌ای و جریمهٔ ۱٪ ثابت (constant) هستند (تصمیم مالک) و هیچ رأیی نمی‌تواند عوضشان کند.
///
///         پرداخت عضویت: ولیدیتور تازه با requestMembership(operator, agreementHash) دو مبلغ را به ارز بومی (سورن) می‌پردازد
///         (agreementHash = چکیدهٔ نسخه‌ای که پیشاپیش امضا کرده؛ یادداشت بالای requestMembership را ببینید):
///           - وثیقه (= currentEntryThreshold()): اینجا قفل می‌ماند، هنگام خروج برگشت‌پذیر و قابل جریمه است.
///           - کارمزد عضویت (= currentMembershipFee()، درصدی حکمرانی‌شده از وثیقه): به BlockRewardDistributor
///             فرستاده می‌شود و به نسبت تعداد بلاک بین ولیدیتورهای فعال دورهٔ بعد تقسیم می‌شود و از سوزاندن
///             کارمزد عادی معاف است. بخش جریمه‌شدهٔ وثیقه به ValidatorsTreasury می‌رود.
///
///         همگام‌سازی با هیأت: هر بار وضعیت فعال‌بودن یک ولیدیتور عوض شود، این قرارداد
///         `ValidatorsBoard.syncVoter(validator)` را صدا می‌زند تا شمارنده‌های رأی هیأت با مجموعهٔ فعال هماهنگ بماند.
///         این فراخوان بهترین‌تلاش است و نمی‌تواند تغییر وضعیت را مسدود کند.
///
///         یک فراخوان به هیأت بهترین‌تلاش **نیست**: `migrateSeat` تابع `ValidatorsBoard.onSeatMigrated(old, new)` را صدا می‌زند و اگر
///         آن فراخوان شکست بخورد revert می‌کند، چون وگرنه از دست‌رفتن کرسی هیأت یا رأی‌های انتخاباتی بی‌صدا می‌ماند. **فروش** صندلی هرگز
///         آن را صدا نمی‌زند.
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
    ///         (entryCollateral، membershipFeeBps).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    // ------------------------------------------------------------------
    // وضعیت ولیدیتور
    // ------------------------------------------------------------------

    /// @dev RemovedInRecovery (v2.5، در انتها اضافه شده تا مقادیر قبلی رمزگذاری خود را حفظ کنند): پس از خاموش کردن گره
    ///      در جریان بازیابی شبکه از فهرست ولیدیتورها حذف شده است. جریمه نیست: وثیقه تا exitAllowedAt قفل است.
    ///      SelfSuspended (v2.5، در انتها اضافه شده): تعلیق داوطلبانه و رایگان توسط مالک؛ بدون پاداش، بدون رأی، خارج از getValidators().
    enum Status { None, Probation, Active, Demoted, Exiting, RemovedInRecovery, SelfSuspended }

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
    address[] internal activeValidators;
    mapping(address => uint256) internal activeIndex;

    // ------------------------------------------------------------------
    // پارامترهای حکمرانی‌شده (فقط با رأی کامل ولیدیتورها قابل تغییر — در ادامه ببینید)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // پارامترهای اقتصادی ورود: مقادیر اولیه در ادامه؛ فقط ValidatorsBoard می‌تواند تغییرشان دهد (آرگومان constructor نیستند و
    // با رأی کامل ولیدیتورها هم تغییر نمی‌کنند). entryCollateral اولیه ۵۰۰٬۰۰۰ سورن است.
    // ------------------------------------------------------------------

    /// @notice v2.5: وثیقهٔ ورود برای هر واردشوندهٔ پرداخت‌کننده «ثابت» است (منحنی رشد v2.2 با تعداد ولیدیتورهای پرداخت‌کرده
    ///         حذف شده است). فقط ValidatorsBoard (۳ از ۵) می‌تواند آن و کارمزد عضویت را در حدود سخت تغییر دهد:
    ///         هر تغییر حداکثر ±۱۰٪ نسبت به مقدار فعلی، وثیقه بین ۱۰۰٬۰۰۰ و ۲٬۰۰۰٬۰۰۰ سورن، کارمزد
    ///         بین ۱٪ و ۱۰٪ وثیقه، و یک تایمر مشترک ۱۸۰ روزه بین هر دو تغییر. تغییر فقط روی واردشوندگان
    ///         بعدی اثر می‌گذارد.
    uint256 public constant ENTRY_COLLATERAL_MIN = 100_000 ether;
    uint256 public constant ENTRY_COLLATERAL_MAX = 2_000_000 ether;
    uint256 public constant MEMBERSHIP_FEE_BPS_MIN = 100;  // ۱٪
    uint256 public constant MEMBERSHIP_FEE_BPS_MAX = 1000;  // ۱۰٪
    uint256 public constant ECONOMIC_PARAM_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastEconomicParamChangeTime;

    /// @notice وثیقه‌ای که هر واردشوندهٔ پرداخت‌کننده اینجا قفل می‌کند (هنگام خروج قابل‌استرداد، قابل‌جریمه). مقدار اولیه ۵۰۰٬۰۰۰ سورن.
    uint256 public entryCollateral = 500_000 ether;

    /// @notice کارمزد عضویت به‌صورت کسری از وثیقه، علاوه بر آن پرداخت می‌شود و غیرقابل‌استرداد است. به
    ///         BlockRewardDistributor.receiveMembershipFee() فرستاده می‌شود، در دورهٔ توزیع بعد ادغام می‌شود و به نسبت
    ///         تعداد بلاک بین ولیدیتورهای فعال پرداخت می‌شود (از سوزاندن کارمزد عادی معاف است). ۴۰۰ یعنی ۴٪ وثیقه.
    uint256 public membershipFeeBps = 400;


    /// @notice ثابت (تصمیم مالک؛ دیگر پارامتر نیست و هیچ رأیی عوضش نمی‌کند): حداکثر «یک» عضویت پولی تازه در هر پنجرهٔ ورود. هنگام
    ///         «فعال‌سازی» ورودی پولی توسط Verifier (recordActivation) شمرده می‌شود، نه هنگام درخواست عضویت. با همان نام getter
    ///         قبلی constant مانده تا getter در ABI و چک‌های genesis-builder معتبر بمانند.
    uint256 public constant maxEntriesPerWindow = 1;
    /// @notice پنجرهٔ ورود: در هر پنجره حداکثر یک فعال‌سازی پولی. تنها پارامتر ورودی که ولیدیتورها هنوز می‌توانند عوض کنند
    ///         (۱ تا ۳۰ روز، هر تغییر ±۱ روز، ۶ ماه بین تغییرها، هیچ تغییری در ۶ ماه نخست).
    uint256 public entryWindowSeconds = 7 days; // v2.5: حداکثر یک ولیدیتور پرداخت‌کنندهٔ جدید در هفته

    /// @notice ثابت (تصمیم مالک): حداقل probation ورودی پولی پیش از فعال‌سازی، ۱ هفته. constant با نام getter قبلی.
    uint256 public constant probationPeriod = 7 days;

    /// @notice حداقل فاصلهٔ زمانی بین تعلیق و ثبت بازگشت (در ابتدا ۴۸ ساعت).
    uint256 public recoveryPeriod = 172800;  // ۴۸ ساعت
    /// @notice ثابت (تصمیم مالک؛ هیچ رأیی عوضش نمی‌کند): جریمه ۱٪ (۱۰۰ bps) وثیقهٔ قفل‌شده است. عمداً سبک: آستانهٔ ورود پایین نگه
    ///         داشته شده تا دامنهٔ کسانی که می‌توانند ولیدیتور شوند بازتر باشد؛ پس جریمهٔ سنگین روی آن وثیقهٔ کوچک‌تر یک اشتباه
    ///         زیرساختی صادقانه را بیش از حد سخت مجازات می‌کند. ۱٪ یک پیامد واقعی است بی‌آنکه برای هیچ اندازه وثیقه‌ای فاجعه‌بار باشد.
    ///         constant با نام getter قبلی.
    uint256 public constant slashBps = 100;
    uint256 public exitCooldown = 604800;        // ۱ هفته

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
    // وضعیت پنجرهٔ ورود: زمان آخرین فعال‌سازیِ «پولی» (۰ = هنوز هیچ). برندگان قرعه‌کشی و مؤسسین معافند و هرگز آن را تنظیم نمی‌کنند.
    uint256 public lastPaidActivationAt;

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

    enum DecisionType { Activation, Suspension, Recovery, Resume }
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

    /// @dev «ترتیب» بخشی از ABI است و عوض نمی‌شود. MaxEntriesPerWindow (۰)، ProbationPeriod (۲) و SlashBps (۴) با تصمیم مالک ثابت‌اند و فقط
    ///      برای حفظ شماره‌ی بقیهٔ کلیدها مانده‌اند: هم هنگام پیشنهاد و هم هنگام اعمال رد می‌شوند.
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
    mapping(address => ActiveCheckpoint[]) internal activeCheckpoints;

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
    /// @notice کلیدهای اپراتور (گره) ولیدیتورهای Active — همان چیزی که Besu به‌عنوان مجموعهٔ ولیدیتورهای QBFT می‌خواند.
    function getValidators() external view returns (address[] memory out) {
        out = new address[](activeValidators.length);
        for (uint256 i = 0; i < out.length; i++) out[i] = operatorOf[activeValidators[i]];
    }

    /// @notice آدرس‌های مالک ولیدیتورهای Active.
    function getActiveOwners() external view returns (address[] memory) {
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
    // آستانهٔ ورود / محدودیت نرخ
    // ------------------------------------------------------------------

    /// @notice وثیقه‌ای که همین حالا برای درخواست عضویت لازم است (ثابت؛ entryCollateral را ببین).
    function currentEntryThreshold() public view returns (uint256) {
        return entryCollateral;
    }

    /// @notice کارمزد فعلی عضویت = entryCollateral * membershipFeeBps / 10000، علاوه بر وثیقه پرداخت می‌شود.
    function currentMembershipFee() public view returns (uint256) {
        return (entryCollateral * membershipFeeBps) / BPS_DENOMINATOR;
    }

    // ------------------------------------------------------------------
    // تنظیم‌کننده‌های پارامتر اقتصادی ورود — فقط ValidatorsBoard (۳ از ۵ از قبل تغییر را تصویب کرده‌اند)
    // ------------------------------------------------------------------
    function setEntryCollateral(uint256 newValue) external onlyBoard {
        require(newValue >= ENTRY_COLLATERAL_MIN && newValue <= ENTRY_COLLATERAL_MAX, "ValidatorsRegistry: entryCollateral outside allowed bounds");
        _requireWithinTenPercent(entryCollateral, newValue);
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("entryCollateral", entryCollateral, newValue);
        entryCollateral = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(newValue >= MEMBERSHIP_FEE_BPS_MIN && newValue <= MEMBERSHIP_FEE_BPS_MAX, "ValidatorsRegistry: membershipFeeBps outside allowed bounds");
        _requireWithinTenPercent(membershipFeeBps, newValue);
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    /// @dev هر تغییر حداکثر ±۱۰٪ نسبت به مقدار فعلی است.
    function _requireWithinTenPercent(uint256 current, uint256 proposed) private pure {
        require(proposed * 10 >= current * 9 && proposed * 10 <= current * 11, "ValidatorsRegistry: change exceeds +-10%");
    }

    /// @dev قاعدهٔ پنجرهٔ ورود (تصمیم مالک): حداکثر «یک» عضویت پولی تازه در هر پنجرهٔ ورود، که هنگام «فعال‌سازی» شمرده می‌شود. ورودیِ
    ///      پولی هر زمان می‌تواند درخواست عضویت بدهد و در Probation منتظر می‌ماند؛ recordActivation ی Verifier تا وقتی پنجره پر است
    ///      رد می‌شود (آخرین فعال‌سازی پولی کمتر از entryWindowSeconds پیش بوده). با سقف ثابتِ یک، «در هر پنجره» دقیقاً یعنی «دست‌کم
    ///      entryWindowSeconds پس از فعال‌سازی پولی قبلی». نخستین فعال‌سازی پولی هرگز به تأخیر نمی‌افتد.
    function _enforceEntryWindow() private {
        require(
            lastPaidActivationAt == 0 || block.timestamp >= lastPaidActivationAt + entryWindowSeconds,
            "ValidatorsRegistry: entry window used - only one new paid validator per window"
        );
        lastPaidActivationAt = block.timestamp;
    }

    /// @notice زودترین زمانی که Verifier می‌تواند ورودی پولی بعدی را فعال کند (۰ = هنوز فعال‌سازی پولی نبوده؛ پس هر زمان پس از
    ///         probation). وعده نیست: probation خودِ داوطلب همچنان برقرار است.
    function nextPaidActivationAllowedAt() external view returns (uint256) {
        return lastPaidActivationAt == 0 ? 0 : lastPaidActivationAt + entryWindowSeconds;
    }

    // ------------------------------------------------------------------
    // درخواست عضویت -> probation
    //
    // payable: فرستنده سورن بومی را در msg.value می‌فرستد که باید دقیقاً مجموع دو مبلغ باشد:
    //   ۱. `threshold` (currentEntryThreshold()): اینجا به‌عنوان وثیقهٔ قابل‌استرداد و قابل‌جریمه می‌ماند.
    //   ۲. `fee` (currentMembershipFee()): به BlockRewardDistributor فرستاده می‌شود.
    //
    // نسخهٔ منشور و تعهدنامهٔ ولیدیتور (تصمیم مالک ۲۰۲۶-۱۱-۲۳): متقاضی آن را «پیش از» درخواست عضویت به‌صورت الکترونیکی با بنیاد امضا می‌کند (بنیاد
    // بعداً ممهور می‌کند؛ متن امضاشده و امضای هر دو طرف در یک بایگانی آف‌چین می‌ماند). درخواست، hash متن امضاشده را می‌آورد که به‌عنوان
    // چکیدهٔ نسخهٔ جایگاه ذخیره می‌شود (seatAgreementHash) و emit می‌شود (EntryAgreementRecorded). زنجیره نمی‌تواند بررسی کند که
    // سندِ پشت hash وجود دارد یا امضا شده است: Verifier پیش از فعال‌سازی ورودی، بایگانی آف‌چین را با این hash تطبیق می‌دهد.
    // ------------------------------------------------------------------
    /// @notice ورود مستقیم: فرستنده (کیف‌پول معمولی) وثیقه + کارمزد را می‌پردازد، `operator` را کلید گرهٔ خود می‌کند و با یک NFT
    ///         جایگاه تازه وارد Probation می‌شود. `agreementHash` چکیدهٔ متن نسخه‌ای است که فرستنده پیش از درخواست با بنیاد امضا
    ///         کرده (غیرصفر، وگرنه revert می‌شود)؛ به‌عنوان چکیدهٔ نسخهٔ جایگاه ثبت می‌شود (`seatAgreementHash(seatId)`) و در
    ///         EntryAgreementRecorded emit می‌شود. برندگان قرعه‌کشی (enterAsLotteryWinner) و مؤسسین genesis در اینجا hash نمی‌دهند:
    ///         برگ قبولی‌شان را Verifier در بایگانی آف‌چین پیش از فعال‌سازی بررسی می‌کند و هنگام ورود روی زنجیره ثبت نمی‌شود.
    function requestMembership(address operator, bytes32 agreementHash) external payable nonReentrant {
        require(msg.sender.code.length == 0 && msg.sender == tx.origin, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12: مالک صندلی فقط کیف‌پول معمولی
        require(agreementHash != bytes32(0), "ValidatorsRegistry: empty agreement hash");
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");
        require(!permanentlyExited[msg.sender], "ValidatorsRegistry: this address has exited before and may not rejoin");
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(msg.sender), "ValidatorsRegistry: identity not fully verified");
        _claimOperator(msg.sender, operator);

        uint256 collateral = entryCollateral;
        uint256 fee = currentMembershipFee();
        require(msg.value == collateral + fee, "ValidatorsRegistry: incorrect payment amount");

        if (fee > 0) {
            DISTRIBUTOR.receiveMembershipFee{value: fee}();
        }
        // `collateral` عمداً در موجودی بومی همین قرارداد به‌عنوان وثیقهٔ قفل‌شده می‌ماند.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: collateral,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: true
        });
        paidValidatorCount++;
        uint256 seatId = IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).mintSeat(msg.sender);
        seatAgreementHash[seatId] = agreementHash;

        emit MembershipRequested(msg.sender, collateral, fee);
        emit EntryAgreementRecorded(msg.sender, seatId, agreementHash);
    }

    // ------------------------------------------------------------------
    // v2.5: دو کلید برای هر ولیدیتور. «مالک» پاداش، وثیقه، رأی، هویت و جایگاه را نگه می‌دارد؛ «اپراتور» فقط کلید گرهٔ
    // امضاکنندهٔ بلاک‌هاست. getValidators() کلیدهای اپراتور را برمی‌گرداند.
    // ------------------------------------------------------------------
    /// @notice مالکی که الان این کلید اپراتور را دارد. وقتی آدرسی یک بار اپراتور شد، هرگز برای شخص دیگری آزاد نمی‌شود، پس
    ///         تعویض کلید نود توسط همان مالک، کلیدهای قدیمی را به همان مالک وصل نگه می‌دارد. اما انتقال صندلی کلید اپراتور
    ///         را به خریدار منتقل می‌کند، پس این نگاشت به‌تنهایی نمی‌گوید در یک بلاک قدیمی‌تر مالک کلید چه کسی بوده:
    ///         RewardRouter باید رویدادهای SeatTransferred و OperatorSet و OperatorChangeConfirmed را بازپخش کند تا هر بلاک را
    ///         به مالکِ همان بلاک نسبت دهد (تصمیم مالک ۲۰۲۶-۱۱-۱۹).
    mapping(address => address) public ownerOfOperator;
    /// @notice اپراتور «فعلی» (کلید گره) یک مالک (تا تعیین نشده صفر).
    mapping(address => address) public operatorOf;
    /// @notice مؤسسین genesis: بدون وثیقه، خارج از پنجرهٔ ورود، بدون انتظار probation پیش از فعال‌سازی.
    mapping(address => bool) public isFounder;
    /// @notice زمان‌مهر genesis (توسط seed helper تنظیم می‌شود).
    uint256 public genesisTime;
    uint256 public lastEntryWindowChange;
    /// @notice مجموع سورنی که با جریمه سوزانده شده است (به address(0) فرستاده شده).
    uint256 public totalSlashBurned;

    event OperatorSet(address indexed owner, address indexed operator);

    function _claimOperator(address owner_, address operator) internal {
        require(operator != address(0), "ValidatorsRegistry: zero operator");
        require(!_reservedForOther(operator, owner_), "ValidatorsRegistry: operator reserved by another owner's pending change");
        address attached = ownerOfOperator[operator];
        require(attached == address(0) || attached == owner_, "ValidatorsRegistry: operator belongs to another owner");
        require(operator == owner_ || validators[operator].status == Status.None, "ValidatorsRegistry: operator is another owner");
        require(ownerOfOperator[owner_] == address(0) || ownerOfOperator[owner_] == owner_, "ValidatorsRegistry: this address is an operator key");
        ownerOfOperator[operator] = owner_;
        operatorOf[owner_] = operator;
        emit OperatorSet(owner_, operator);
    }

    // ------------------------------------------------------------------
    // تغییر کلید گره.
    //   * Probation، Demoted، SelfSuspended (خارج از مجموعهٔ QBFT): `setOperator` بلافاصله اعمال می‌شود. اکنون هیچ چیزی
    //     برای شبکه خراب نمی‌شود؛ Verifier پیش از (باز)ورود ولیدیتور به مجموعه، گره را بررسی می‌کند.
    //   * ACTIVE (گره بلاک امضا می‌کند): دو مرحله‌ای (تصمیم مالک ۲۰۲۶-۱۱-۱۹، برگرفته از یافتهٔ Besu با شناسهٔ F-5):
    //       1. proposeOperator(newKey)            مالک کلید جدید را رزرو می‌کند؛ هنوز چیزی در اجماع تغییر نمی‌کند؛
    //       2. confirmOperatorReady(owner, newOperator, hash)  Verifier بررسی می‌کند که گرهٔ جدید بالا، همگام و توانای امضا است و سپس
    //                                             جابه‌جایی را در یک تراکنش اعمال می‌کند.
    //     به این ترتیب جابه‌جایی به گرهٔ روشن‌نشده هرگز به مجموعهٔ QBFT نمی‌رسد (گرهٔ خاموش در هر نوبت خود یک
    //     round change بیش از ۱۰ ثانیه هزینه دارد و به تعداد کافی از آن‌ها می‌تواند زنجیره را متوقف کند).
    //     cancelOperatorChange() پیشنهاد را کنار می‌گذارد؛ پیشنهاد پس از OPERATOR_PROPOSAL_EXPIRY هم منقضی می‌شود.
    // ------------------------------------------------------------------
    mapping(address => address) public pendingOperator;
    mapping(address => uint256) public pendingOperatorExpiresAt;
    /// @dev کلید جدید => مالکی که آن را در یک پیشنهاد هنوز باز رزرو کرده است
    mapping(address => address) public operatorReservedBy;
    uint256 public constant OPERATOR_PROPOSAL_EXPIRY = 7 days;

    event OperatorChangeProposed(address indexed owner, address indexed newOperator, uint256 expiresAt);
    event OperatorChangeConfirmed(address indexed owner, address indexed newOperator, bytes32 evidenceHash);
    event OperatorChangeCancelled(address indexed owner, address indexed newOperator);

    function _reservedForOther(address operator, address owner_) private view returns (bool) {
        address r = operatorReservedBy[operator];
        return r != address(0) && r != owner_ && pendingOperator[r] == operator && pendingOperatorExpiresAt[r] > block.timestamp;
    }

    /// @notice تغییر بلافاصلهٔ کلید گره برای مالکی که در مجموعهٔ اجماع نیست (Probation، Demoted، SelfSuspended).
    function setOperator(address newOperator) external {
        Status st = validators[msg.sender].status;
        require(st != Status.Active, "ValidatorsRegistry: an Active validator changes the node key in two steps (proposeOperator)");
        require(
            st == Status.Probation || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: cannot change the operator in this status"
        );
        require(newOperator != address(0), "ValidatorsRegistry: zero operator");
        require(operatorOf[msg.sender] != newOperator, "ValidatorsRegistry: same operator");
        _claimOperator(msg.sender, newOperator);
    }

    /// @notice مرحلهٔ ۱ برای ولیدیتور ACTIVE: کلید گرهٔ جدید را رزرو می‌کند. تا تأیید Verifier اجماع دست‌نخورده می‌ماند.
    function proposeOperator(address newOperator) external {
        require(validators[msg.sender].status == Status.Active, "ValidatorsRegistry: only an Active validator proposes (others use setOperator)");
        require(operatorOf[msg.sender] != newOperator, "ValidatorsRegistry: same operator");
        require(
            pendingOperator[msg.sender] == address(0) || pendingOperatorExpiresAt[msg.sender] <= block.timestamp,
            "ValidatorsRegistry: a proposal is already open"
        );
        _checkOperatorFree(msg.sender, newOperator);
        pendingOperator[msg.sender] = newOperator;
        pendingOperatorExpiresAt[msg.sender] = block.timestamp + OPERATOR_PROPOSAL_EXPIRY;
        operatorReservedBy[newOperator] = msg.sender;
        emit OperatorChangeProposed(msg.sender, newOperator, pendingOperatorExpiresAt[msg.sender]);
    }

    /// @notice مرحلهٔ ۲، فقط Verifier، پس از بررسی سلامت گرهٔ جدید: جابه‌جایی را اعمال می‌کند (بلافاصله در
    ///         getValidators() و در نتیجه در QBFT دیده می‌شود).
    ///         VD-13: Verifier کلیدی را که بررسی کرده نام می‌برد (`newOperator`)؛ اگر مالک بین بررسی و این تراکنش
    ///         پیشنهاد را لغو و کلید دیگری پیشنهاد داده باشد، فراخوانی revert می‌شود و کلید سنجیده‌نشده اعمال نمی‌شود.
    function confirmOperatorReady(address owner_, address newOperator, bytes32 evidenceHash) external onlyVerifier {
        address newOp = pendingOperator[owner_];
        require(newOp != address(0), "ValidatorsRegistry: no open proposal");
        require(newOp == newOperator, "ValidatorsRegistry: operator differs from the open proposal");
        require(pendingOperatorExpiresAt[owner_] > block.timestamp, "ValidatorsRegistry: proposal expired");
        require(validators[owner_].status == Status.Active, "ValidatorsRegistry: owner is no longer Active");
        require(evidenceHash != bytes32(0), "ValidatorsRegistry: empty evidence hash");
        delete pendingOperator[owner_];
        delete pendingOperatorExpiresAt[owner_];
        delete operatorReservedBy[newOp];
        _claimOperator(owner_, newOp);
        emit OperatorChangeConfirmed(owner_, newOp, evidenceHash);
    }

    function cancelOperatorChange() external {
        address newOp = pendingOperator[msg.sender];
        require(newOp != address(0), "ValidatorsRegistry: no open proposal");
        delete pendingOperator[msg.sender];
        delete pendingOperatorExpiresAt[msg.sender];
        delete operatorReservedBy[newOp];
        emit OperatorChangeCancelled(msg.sender, newOp);
    }

    /// @dev همان قواعد یکتایی _claimOperator، بدون نوشتن (هنگام ثبت پیشنهاد به کار می‌رود).
    function _checkOperatorFree(address owner_, address operator) private view {
        require(operator != address(0), "ValidatorsRegistry: zero operator");
        require(!_reservedForOther(operator, owner_), "ValidatorsRegistry: operator reserved by another owner's pending change");
        address attached = ownerOfOperator[operator];
        require(attached == address(0) || attached == owner_, "ValidatorsRegistry: operator belongs to another owner");
        require(operator == owner_ || validators[operator].status == Status.None, "ValidatorsRegistry: operator is another owner");
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
        require(operatorOf[candidate] != address(0), "ValidatorsRegistry: operator key not set");
        require(isFounder[candidate] || block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        // پنجرهٔ ورود همین‌جا، هنگام فعال‌سازی، شمرده می‌شود. فقط ورودیِ «پولی» (isPaidEntrant، پس از فروش صندلی هم) یک جای پنجره را
        // مصرف می‌کند: مؤسسین و برندگان قرعه‌کشی با تصمیم معافند (رکوردشان isPaidEntrant == false دارد).
        if (v.isPaidEntrant) _enforceEntryWindow();
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
            totalSlashBurned += slashAmount;
            (bool success, ) = address(0).call{value: slashAmount}(""); // ۱۰۰٪ سوزانده می‌شود (v2.5)، به خزانه پرداخت نمی‌شود
            require(success, "ValidatorsRegistry: slash burn failed");
        }
        emit SlashResolved(decisionId, d.validator, outcome, slashAmount);
    }

    /// @dev seed کردن genesis (فقط توسط genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol استفاده می‌شود که از این قرارداد
    ///      ارث می‌برد، پس چیدمان storage به‌حکم ساختار یکی است؛ هرگز روی زنجیرهٔ واقعی در دسترس نیست). ولیدیتور «نخست» (راه‌انداز
    ///      genesis) با کلید اپراتورش Active است؛ مؤسسین دیگر با آدرس مالک، بدون وثیقه و با وضعیت Probation ثبت می‌شوند و
    ///      پس از تعیین کلید اپراتور و تأیید Verifier مبنی بر بالا بودن گره‌شان Active می‌شوند.
    function _seedFirstValidator(address owner_, address operator, uint256 genesisTimestamp) internal {
        require(genesisTime == 0, "seed: first validator already seeded");
        genesisTime = genesisTimestamp;
        _seedFounderEntry(owner_, genesisTimestamp, Status.Active);
        ownerOfOperator[operator] = owner_;
        operatorOf[owner_] = operator;
        activeIndex[owner_] = activeValidators.length + 1;
        activeValidators.push(owner_);
        everActivated[owner_] = true;
        activationSeq[owner_] = ++activationCount;
        activeCheckpoints[owner_].push(ActiveCheckpoint({nonce: 0, active: true}));
    }

    function _seedFounder(address owner_, uint256 genesisTimestamp) internal {
        _seedFounderEntry(owner_, genesisTimestamp, Status.Probation);
    }

    /// @dev چکیدهٔ نسخهٔ مؤسس روی زنجیره ثبت نمی‌شود (اینجا NFT جایگاه mint نمی‌شود و چکیده‌ای هم داده نمی‌شود): Verifier بایگانی آف‌چین را پیش از
    ///      فعال‌سازی مؤسس بررسی می‌کند.
    function _seedFounderEntry(address owner_, uint256 genesisTimestamp, Status status) private {
        require(owner_ != address(0), "seed: zero address");
        require(validators[owner_].status == Status.None, "seed: duplicate founder");
        validators[owner_] = ValidatorInfo({
            status: status,
            lockedStake: 0,
            periodStartedAt: genesisTimestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: false
        });
        isFounder[owner_] = true;
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
        _recordActiveCheckpoint(who, true); // L04
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
        if (v.status == Status.RemovedInRecovery) {
            _exitAfterRecoveryRemoval(v);
            return;
        }
        require(
            v.status == Status.Active || v.status == Status.Probation || v.status == Status.Demoted || v.status == Status.SelfSuspended,
            "ValidatorsRegistry: nothing to exit"
        );

        if (v.status == Status.Active) {
            require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - exit blocked");
            // درخواست خروج وظیفهٔ اعتبارسنجی را فوراً پایان می‌دهد: حذف از مجموعهٔ فعال (و در نتیجه از مجموعهٔ ولیدیتور QBFT
            // و از اختیار هیأت). مسئولیت‌پذیری را پاک نمی‌کند: تا PRE_EXIT_CLAIM_WINDOW (‏۷۲ ساعت) verifier هنوز می‌تواند
            // دربارهٔ رفتار پیشین پرونده بسازد (recordPreExitViolation) و مبلغ در معرض خطر تا تعیین‌تکلیف هر پرونده توسط
            // withdrawStake() رزرو می‌ماند.
            _removeFromActive(msg.sender);
            _recordActiveCheckpoint(msg.sender, false); // L04
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
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).burnSeat(msg.sender);

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
        require(
            key != ParamKey.MaxEntriesPerWindow && key != ParamKey.ProbationPeriod && key != ParamKey.SlashBps,
            "ValidatorsRegistry: this parameter is fixed and cannot be changed"
        );
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
        if (key == ParamKey.EntryWindowSeconds) {
            // v2.5: ۱ تا ۳۰ روز، هر تغییر حداکثر ±۱ روز، دست‌کم ۶ ماه بین تغییرها، و هیچ تغییری در ۶ ماه نخست
            require(value >= 1 days && value <= 30 days, "ValidatorsRegistry: entryWindowSeconds outside 1-30 days");
            require(
                value + 1 days >= entryWindowSeconds && value <= entryWindowSeconds + 1 days,
                "ValidatorsRegistry: entryWindowSeconds may change by at most one day"
            );
            require(block.timestamp >= genesisTime + 180 days, "ValidatorsRegistry: no change in the first 6 months after genesis");
            require(block.timestamp >= lastEntryWindowChange + 180 days, "ValidatorsRegistry: at least 6 months between changes");
            lastEntryWindowChange = block.timestamp;
            entryWindowSeconds = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            require(value > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
            recoveryPeriod = value;
        } else if (key == ParamKey.ExitCooldown) {
            require(value > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
            exitCooldown = value;
        } else {
            revert("ValidatorsRegistry: this parameter is fixed and cannot be changed"); // MaxEntriesPerWindow، ProbationPeriod، SlashBps
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

    // ------------------------------------------------------------------
    // v2.5: حذف از فهرست ولیدیتورها در جریان بازیابی شبکه (تصمیم ۲۰۲۶-۱۱-۱۹)
    //
    // «اخراج» وجود ندارد. ولیدیتوری که گره‌اش را خاموش کرد و در نتیجه شبکه را متوقف کرد، پس از بازگشت شبکه به
    // حالت `contract`، با ثبت Verifier از فهرست حذف می‌شود. این یک جریمه نیست:
    //   * وثیقه هرگز slash نمی‌شود؛ تا recoveryTimestamp + 90 روز قفل می‌ماند، سپس مالک requestExit() را صدا می‌زند
    //     (و مثل همیشه exitCooldown را صبر می‌کند)؛
    //   * ممنوعیت دائمی ولیدیتور اعمال می‌شود (permanentlyExited)، دقیقاً مثل پس از خروج داوطلبانه؛
    //   * ولیدیتورِ حذف‌شده ۷۲ ساعت برای اعتراض فرصت دارد؛ اعتراض‌ها ظرف ۷ روز با ValidatorsBoard (۳ از ۵، موضوع
    //     رأی ندارد) تصمیم‌گیری می‌شوند؛ با کمتر از ۳ عضو بی‌طرف هیأت، پرونده به ولیدیتورها می‌رود (دو‌سوم
    //     ولیدیتورهای واجد شرایط در لحظه‌ی ارجاع)؛ نبودِ تصمیم در موعد = حذف لغو می‌شود و ولیدیتور بازگردانده می‌شود
    //     (VD-4: به SelfSuspended با درخواست ازسرگیریِ باز؛ فقط recordResume از Verifier، پس از سنجش سلامت گره، او را دوباره Active می‌کند).
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // v2.5: برندگان قرعه‌کشی (ValidatorEntryDraw.drawBatch برای هر برنده این را صدا می‌زند)
    // ------------------------------------------------------------------
    /// @notice تنها فراخواننده‌ی enterAsLotteryWinner(): قرارداد ValidatorEntryDraw.
    address public constant LOTTERY = SurAddresses.VALIDATOR_ENTRY_DRAW;

    event LotteryWinnerEntered(address indexed winner);

    /// @notice برنده‌ی قرعه‌کشی «بدون» وثیقه و «بدون» حق عضویت، خارج از پنجرهٔ ورود (فعال‌سازی‌اش نه منتظرش می‌ماند نه جایی از آن را مصرف می‌کند)، و بدون شمرده‌شدن به‌عنوان ورودی
    ///         پولی جایگاه می‌گیرد. جایگاه مثل هر ورودی در Probation شروع می‌شود: گره هنوز باید راستی‌آزمایی شود
    ///         (و برگ قبولی امضا شود) تا Verifier آن را فعال کند، پس رأی پیش از آن زنده نیست. آدرسی که
    ///         قبلاً ثبت شده یا هرگز خارج شده باشد نمی‌تواند جایگاه بگیرد (یک جایگاه برای هر نفر، ممنوعیت دائمی).
    ///         هنگام این ورود هیچ چکیدهٔ نسخه‌ای روی زنجیره ثبت نمی‌شود (امضا آف‌چین است؛ Verifier بایگانی را پیش از فعال‌سازی بررسی می‌کند).
    function enterAsLotteryWinner(address winner) external {
        require(msg.sender == LOTTERY, "ValidatorsRegistry: caller is not the entry draw");
        require(winner != address(0) && validators[winner].status == Status.None, "ValidatorsRegistry: already registered");
        require(winner.code.length == 0, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12 (try/catch قرعه‌کشی ورود ولیدیتور جدید entryFailed را ثبت می‌کند)
        require(!permanentlyExited[winner], "ValidatorsRegistry: this address has exited before and may not rejoin");
        validators[winner] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: 0,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: false
        });
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).mintSeat(winner);
        emit LotteryWinnerEntered(winner);
    }

    enum RecoveryRemovalState { None, Recorded, Objected, ReferredToAssembly, Upheld, Cancelled }

    struct RecoveryRemoval {
        RecoveryRemovalState state;
        uint256 recoveryTimestamp;   // زمانی که شبکه به حالت contract بازگشت (توسط Verifier داده می‌شود)
        bytes32 evidenceHash;        // هش بسته‌ی شواهد (مثلاً خروجی qbft_getSignerMetrics)
        uint256 recordedAt;
        uint256 objectionDeadline;   // recordedAt + ۷۲ ساعت
        uint256 resolutionDeadline;  // وقتی تنظیم می‌شود که یک اعتراض (یا ارجاع به مجمع) بازه‌ی تصمیم ۷روزه را باز کند
        uint256 exitAllowedAt;       // recoveryTimestamp + ۹۰ روز
        uint256 referralNonce;       // statusNonce در لحظه‌ی ارجاع به مجمع (فقط ولیدیتورهای آن لحظه Active حق رأی دارند)
        uint256 eligibleCount;       // ولیدیتورهای فعال در لحظه‌ی ارجاع = اندازه‌ی رأی‌دهندگان مجمع
    }

    uint256 public constant RECOVERY_OBJECTION_WINDOW = 72 hours;
    uint256 public constant RECOVERY_RESOLUTION_WINDOW = 7 days;
    uint256 public constant RECOVERY_COLLATERAL_LOCK = 90 days;
    /// @dev 🔶 در تصمیم تعیین نشده: recoveryTimestamp هنگام ثبت حذف توسط Verifier حداکثر چقدر می‌تواند قدیمی باشد.
    uint256 public constant RECOVERY_RECORD_MAX_AGE = 30 days;

    mapping(address => RecoveryRemoval) public recoveryRemovals;

    event RecoveryRemovalRecorded(address indexed validator, uint256 recoveryTimestamp, bytes32 evidenceHash, uint256 exitAllowedAt);
    event RecoveryRemovalObjected(address indexed validator, uint256 resolutionDeadline);
    event RecoveryCaseReferredToAssembly(address indexed validator, uint256 referralNonce, uint256 eligibleCount, uint256 resolutionDeadline);
    event RecoveryRemovalUpheld(address indexed validator);
    event RecoveryRemovalCancelled(address indexed validator, bool expired);

    /// @notice فقط Verifier، و فقط پس از بازگشت شبکه به حالت contract. یک ولیدیتور Active را از فهرست اجماع حذف
    ///         می‌کند (بدون پاداش، بدون رأی، بدون اختیار در هیأت) بی‌آن‌که به وثیقه‌اش دست بزند.
    function recordRecoveryRemoval(address validator, uint256 recoveryTimestamp, bytes32 evidenceHash) external onlyVerifier nonReentrant {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: validator is not active");
        require(evidenceHash != bytes32(0), "ValidatorsRegistry: empty evidence hash");
        require(
            recoveryTimestamp <= block.timestamp && block.timestamp - recoveryTimestamp <= RECOVERY_RECORD_MAX_AGE,
            "ValidatorsRegistry: recoveryTimestamp out of range"
        );
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count");
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(r.state == RecoveryRemovalState.None || r.state == RecoveryRemovalState.Cancelled, "ValidatorsRegistry: removal case exists");

        _removeFromActive(validator);
        _recordActiveCheckpoint(validator, false);
        if (v.isPaidEntrant) paidValidatorCount--;
        v.status = Status.RemovedInRecovery;
        v.periodStartedAt = block.timestamp;
        permanentlyExited[validator] = true; // ممنوعیت دائمی اعمال می‌شود
        membershipEpoch[validator]++;        // هر صندلی هیأت را پایان می‌دهد

        r.state = RecoveryRemovalState.Recorded;
        r.recoveryTimestamp = recoveryTimestamp;
        r.evidenceHash = evidenceHash;
        r.recordedAt = block.timestamp;
        r.objectionDeadline = block.timestamp + RECOVERY_OBJECTION_WINDOW;
        r.resolutionDeadline = 0;
        r.exitAllowedAt = recoveryTimestamp + RECOVERY_COLLATERAL_LOCK;
        r.referralNonce = 0;
        r.eligibleCount = 0;
        emit RecoveryRemovalRecorded(validator, recoveryTimestamp, evidenceHash, r.exitAllowedAt);
        _notifyBoard(validator);
    }

    /// @notice ولیدیتورِ حذف‌شده ظرف ۷۲ ساعت اعتراض می‌کند؛ این کار بازه‌ی تصمیم ۷روزه را باز می‌کند.
    function objectRecoveryRemoval() external {
        RecoveryRemoval storage r = recoveryRemovals[msg.sender];
        require(validators[msg.sender].status == Status.RemovedInRecovery && r.state == RecoveryRemovalState.Recorded, "ValidatorsRegistry: nothing to object to");
        require(block.timestamp <= r.objectionDeadline, "ValidatorsRegistry: objection window over");
        r.state = RecoveryRemovalState.Objected;
        r.resolutionDeadline = block.timestamp + RECOVERY_RESOLUTION_WINDOW;
        emit RecoveryRemovalObjected(msg.sender, r.resolutionDeadline);
    }

    /// @notice فقط ValidatorsBoard: کمتر از ۳ عضو بی‌طرف هیأت هست، پس ولیدیتورها تصمیم می‌گیرند. یک بازه‌ی ۷روزه‌ی جدید آغاز می‌شود.
    function setRecoveryCaseReferred(address validator) external onlyBoard {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(r.state == RecoveryRemovalState.Objected && block.timestamp <= r.resolutionDeadline, "ValidatorsRegistry: case cannot be referred");
        r.state = RecoveryRemovalState.ReferredToAssembly;
        r.referralNonce = statusNonce;
        r.eligibleCount = activeValidators.length;
        r.resolutionDeadline = block.timestamp + RECOVERY_RESOLUTION_WINDOW;
        emit RecoveryCaseReferredToAssembly(validator, r.referralNonce, r.eligibleCount, r.resolutionDeadline);
    }

    /// @notice فقط ValidatorsBoard، با تصمیم هیأت (۳ از ۵) یا ولیدیتورها (دو‌سوم).
    ///         upheld = حذف پابرجاست؛ در غیر این صورت حذف لغو می‌شود و ولیدیتور به SelfSuspended برمی‌گردد (VD-4).
    function resolveRecoveryRemoval(address validator, bool upheld) external onlyBoard nonReentrant {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(
            (r.state == RecoveryRemovalState.Objected || r.state == RecoveryRemovalState.ReferredToAssembly) && block.timestamp <= r.resolutionDeadline,
            "ValidatorsRegistry: no open case"
        );
        if (upheld) {
            r.state = RecoveryRemovalState.Upheld;
            emit RecoveryRemovalUpheld(validator);
        } else {
            _cancelRecoveryRemoval(validator, false);
        }
    }

    /// @notice هر کسی، پس از پایان بازه‌ی تصمیم بدون تصمیم: حذف لغو می‌شود.
    function expireRecoveryRemoval(address validator) external nonReentrant {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(
            (r.state == RecoveryRemovalState.Objected || r.state == RecoveryRemovalState.ReferredToAssembly) && block.timestamp > r.resolutionDeadline,
            "ValidatorsRegistry: nothing to expire"
        );
        _cancelRecoveryRemoval(validator, true);
    }

    function _cancelRecoveryRemoval(address validator, bool expired) private {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.RemovedInRecovery, "ValidatorsRegistry: not removed");
        recoveryRemovals[validator].state = RecoveryRemovalState.Cancelled;
        permanentlyExited[validator] = false;
        if (v.isPaidEntrant) paidValidatorCount++;
        // VD-4: مستقیم به Active برنمی‌گردد (گره پس از حذف هرگز سنجیده نشده). ولیدیتور با درخواست ازسرگیریِ باز به
        // SelfSuspended برمی‌گردد و تنها راه بازگشت به فهرست ولیدیتورها recordResume از Verifier (سنجش سلامت گره) است.
        v.status = Status.SelfSuspended;
        v.periodStartedAt = block.timestamp;
        resumeRequested[validator] = true;
        emit ResumeRequested(validator);
        emit RecoveryRemovalCancelled(validator, expired);
        _notifyBoard(validator);
    }

    /// @dev requestExit() برای ولیدیتوری که در بازیابی حذف شده: فقط وقتی پرونده بسته شده و قفل ۹۰ روزه‌ی وثیقه
    ///      گذشته باشد. بقیه (exitCooldown، withdrawStake) همان خروج عادی است.
    function _exitAfterRecoveryRemoval(ValidatorInfo storage v) private {
        RecoveryRemoval storage r = recoveryRemovals[msg.sender];
        require(
            r.state == RecoveryRemovalState.Upheld ||
            (r.state == RecoveryRemovalState.Recorded && block.timestamp > r.objectionDeadline),
            "ValidatorsRegistry: removal case still open"
        );
        require(block.timestamp >= r.exitAllowedAt, "ValidatorsRegistry: collateral locked for 90 days after recovery");
        statusBeforeExit[msg.sender] = uint8(Status.RemovedInRecovery);
        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).burnSeat(msg.sender);
        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
    }

    /// @notice viewهای باریک برای ValidatorsBoard (رمزگشایی موضعی): state، recordedAt، resolutionDeadline.
    function recoveryCaseInfo(address validator) external view returns (uint8 state, uint256 recordedAt, uint256 resolutionDeadline) {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        return (uint8(r.state), r.recordedAt, r.resolutionDeadline);
    }

    function recoveryReferral(address validator) external view returns (uint256 referralNonce, uint256 eligibleCount) {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        return (r.referralNonce, r.eligibleCount);
    }

    // ------------------------------------------------------------------
    // v2.5: تعلیق داوطلبانه (SelfSuspended) — رایگان، بدون محدودیت زمانی یا تعدادی
    //   selfSuspend()      مالک، Active -> SelfSuspended: فوراً از getValidators() خارج می‌شود؛ وثیقه قفل می‌ماند؛ بدون پاداش، بدون رأی
    //   requestResume()    مالک، SelfSuspended: از Verifier می‌خواهد گره را بررسی کند
    //   recordResume()     فقط Verifier، پس از بررسی سلامت موفق گره: SelfSuspended -> Active، «بدون» probation
    // عضو هیأت ولیدیتورها نمی‌تواند داوطلبانه تعلیق شود (نصاب هیأت را بی‌صدا کوچک می‌کند)، و هیچ‌کس نمی‌تواند زیر
    // MIN_ACTIVE_VALIDATORS تعلیق شود. تعلیق داوطلبانه هرگز تخلف نیست و هرگز به جریمه نمی‌رسد.
    // ------------------------------------------------------------------
    mapping(address => bool) public resumeRequested;

    event SelfSuspendedEvent(address indexed validator);
    event ResumeRequested(address indexed validator);
    event ResumeRecorded(address indexed validator, bytes32 evidenceHash);

    function selfSuspend() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - suspension blocked");
        require(!IBoardAuthority(BOARD).hasBoardAuthority(msg.sender), "ValidatorsRegistry: a board member cannot suspend voluntarily");
        _removeFromActive(msg.sender);
        _recordActiveCheckpoint(msg.sender, false);
        v.status = Status.SelfSuspended;
        v.periodStartedAt = block.timestamp;
        resumeRequested[msg.sender] = false;
        emit SelfSuspendedEvent(msg.sender);
        _notifyBoard(msg.sender);
    }

    function requestResume() external {
        require(validators[msg.sender].status == Status.SelfSuspended, "ValidatorsRegistry: not self-suspended");

        resumeRequested[msg.sender] = true;
        emit ResumeRequested(msg.sender);
    }

    function recordResume(address validator, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        require(validators[validator].status == Status.SelfSuspended, "ValidatorsRegistry: not self-suspended");
        require(resumeRequested[validator], "ValidatorsRegistry: no resume request");
        require(operatorOf[validator] != address(0), "ValidatorsRegistry: operator key not set");
        resumeRequested[validator] = false;
        _activate(validator);
        decisionId = _recordDecision(validator, DecisionType.Resume, evidenceHash, 0);
        emit ResumeRecorded(validator, evidenceHash);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // v2.5: NFT جایگاه. مالک توکن ValidatorSeatNFT = مالک جایگاه (سند مرجع §9).
    // ------------------------------------------------------------------
    // قبولی نسخهٔ منشور و تعهدنامه توسط خریدار «شرط» است (تصمیم مالک): جایگاه به آدرسی منتقل نمی‌شود که پیش از انتقال، پذیرش خود را
    // «برای همان جایگاه» ثبت نکرده باشد؛ پس هیچ‌کس بدون پذیرش مالک جایگاه نمی‌شود.
    //
    // روند حقوقی (تصمیم مالک): خریدار برگ قبولی را «پیش از» انتقال با بنیاد امضا می‌کند و از لحظهٔ انتقال مؤثر است؛ بنیاد «پس از» انتقال
    // ممهور می‌کند و موظف به امضاست، پس روی زنجیره «هیچ چیز» منتظر بنیاد نمی‌ماند. خود امضا آف‌چین می‌ماند؛ زنجیره فقط ثبت می‌کند که
    // «کلید خودِ خریدار» سندی با hash داده‌شده را برای این شناسهٔ جایگاه پذیرفته است (acceptSeatAgreement). پذیرش «پیش از انتقال» انجام می‌شود،
    // به یک شناسهٔ جایگاه و یک چکیدهٔ نسخه بسته است و با انتقالی که از آن استفاده می‌کند «مصرف» می‌شود (انتقال بعدیِ همان جایگاه به
    // همان آدرس پذیرش تازه می‌خواهد). hash وارد انتقال می‌شود: به‌عنوان چکیدهٔ نسخهٔ آن جایگاه ذخیره و emit می‌شود (SeatAgreementBound)
    // تا سندی که مالک فعلی را متعهد می‌کند همیشه پیدا شود.
    // جایگاه‌هایی که در ورود، توسط قرعه‌کشی یا در genesis mint می‌شوند از hook انتقال نمی‌گذرند؛ پس این شرط به آن مسیرها کاری ندارد و
    // آن‌ها هرگز از پذیرش پس از انتقالِ قدیمی هم استفاده نمی‌کردند. متقاضیِ ورود مستقیم همین نسخه را «پیش از» درخواست عضویت امضا می‌کند
    // و hash آن همراه requestMembership می‌آید (EntryAgreementRecorded)؛ برندگان قرعه‌کشی و مؤسسین genesis هنگام ورود چکیده‌ای ثبت‌شده ندارند.

    /// @notice شناسهٔ جایگاهی که `buyer` قبولی نسخهٔ منشور و تعهدنامه را برای آن ثبت کرده است (۰ = هیچ). هر آدرس هر زمان فقط یک
    ///         پذیرش دارد: پذیرفتن جایگاه دیگر آن را جایگزین می‌کند. شناسه‌ها از ۱ شروع می‌شوند و هرگز دوباره استفاده نمی‌شوند؛ پس
    ///         پذیرش هرگز روی جایگاهی غیر از آنچه نام برده نمی‌نشیند. فقط با کلید خود خریدار ثبت می‌شود (acceptSeatAgreement)، با
    ///         revokeSeatAcceptance پاک می‌شود یا با انتقال مصرف می‌شود.
    mapping(address => uint256) public seatAcceptedFor;
    /// @notice چکیدهٔ نسخهٔ امضاشده که همراه همان پذیرش ثبت شده (تا وقتی پذیرشی باز است غیرصفر است).
    mapping(address => bytes32) public seatAcceptedAgreementHash;
    /// @notice چکیدهٔ نسخهٔ امضاشده‌ای که «مالک فعلی» یک جایگاه را متعهد می‌کند، با هر مسیری: در ورود مستقیم ثبت می‌شود
    ///         (requestMembership)، با هر انتقال بازنویسی می‌شود (hash پذیرفته‌شدهٔ خریدار)، و مهاجرت پس از گم‌شدن کلید مالک آن را نگه
    ///         می‌دارد (همان شخص، همان نسخه). ۰ = چکیده‌ای روی زنجیره نیست: جایگاهی که با قرعه‌کشی یا در genesis آمده هنگام ورود hash
    ///         نمی‌دهد (Verifier بایگانی آف‌چین را پیش از فعال‌سازی بررسی می‌کند) و تا وقتی انتقالی hash ببندد ندارد. تاریخچهٔ کامل در
    ///         رویدادهای EntryAgreementRecorded و SeatAgreementBound است.
    mapping(uint256 => bytes32) public seatAgreementHash;

    event SeatTransferred(uint256 indexed seatId, address indexed from, address indexed to, Status statusAfter);
    /// @notice با requestMembership emit می‌شود: `owner` مستقیم و با جایگاه `seatId` زیر نسخه‌ای با این چکیده وارد شد.
    event EntryAgreementRecorded(address indexed owner, uint256 indexed seatId, bytes32 agreementHash);
    event SeatAgreementAccepted(address indexed buyer, uint256 indexed seatId, bytes32 agreementHash);
    event SeatAcceptanceRevoked(address indexed buyer, uint256 indexed seatId);
    /// @notice با انتقالی emit می‌شود که یک پذیرش را مصرف کرد: `owner` اکنون `seatId` را زیر نسخه‌ای با این چکیده دارد.
    event SeatAgreementBound(uint256 indexed seatId, address indexed owner, bytes32 agreementHash);

    /// @notice خریدارِ آینده، با کلید خودش و «پیش از» انتقال جایگاه به او، ثبت می‌کند که نسخهٔ منشور و تعهدنامهٔ ولیدیتور را برای جایگاه
    ///         `seatId` می‌پذیرد؛ `agreementHash` چکیدهٔ نسخهٔ امضاشده است (غیرصفر؛ خود امضا آف‌چین است). هیچ‌کس نمی‌تواند
    ///         آن را برای آدرس دیگری ثبت کند. جایگاه باید وجود داشته باشد و از قبل مال فراخواننده نباشد. این ثبت فقط انتقال «همین»
    ///         جایگاه را به فراخواننده مجاز می‌کند؛ بقیهٔ قواعد انتقال هنگام جابه‌جایی جایگاه همچنان بررسی می‌شوند. هر پذیرش قبلی
    ///         فراخواننده را جایگزین می‌کند.
    function acceptSeatAgreement(uint256 seatId, bytes32 agreementHash) external {
        require(agreementHash != bytes32(0), "ValidatorsRegistry: empty agreement hash");
        require(IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).ownerOf(seatId) != msg.sender, "ValidatorsRegistry: caller already owns this seat");
        seatAcceptedFor[msg.sender] = seatId;
        seatAcceptedAgreementHash[msg.sender] = agreementHash;
        emit SeatAgreementAccepted(msg.sender, seatId, agreementHash);
    }

    /// @notice خریدار پذیرش ثبت‌شدهٔ خود را پس می‌گیرد (مثلاً معامله به هم خورد)؛ پس جایگاه دیگر تا پذیرش دوباره به او منتقل
    ///         نمی‌شود.
    function revokeSeatAcceptance() external {
        uint256 seatId = seatAcceptedFor[msg.sender];
        require(seatId != 0, "ValidatorsRegistry: no acceptance recorded");
        delete seatAcceptedFor[msg.sender];
        delete seatAcceptedAgreementHash[msg.sender];
        emit SeatAcceptanceRevoked(msg.sender, seatId);
    }

    /// @notice ValidatorSeatNFT پس از جابه‌جایی توکن آن را صدا می‌زند؛ اگر انتقال مجاز نباشد revert می‌کند (پس انتقال توکن هم
    ///         revert می‌شود). کل رکورد ولیدیتور را از `from` به `to` منتقل می‌کند. افزون بر قواعد وضعیت جایگاه و پروندهٔ جریمه،
    ///         خریدار باید تازه‌وارد، کاملاً احراز هویت شده و غیر از کلید اپراتور باشد و قبولی نسخه را «دقیقاً برای همین
    ///         جایگاه» ثبت کرده باشد (acceptSeatAgreement)؛ آن پذیرش همین‌جا مصرف می‌شود و چکیدهٔ نسخه‌اش به جایگاه بسته می‌شود.
    function onSeatTransferred(uint256 seatId, address from, address to) external nonReentrant {
        require(msg.sender == SurAddresses.VALIDATOR_SEAT_NFT, "ValidatorsRegistry: caller is not the seat NFT");
        ValidatorInfo storage v = validators[from];
        Status st = v.status;
        require(
            st == Status.Probation || st == Status.Active || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: seat cannot be transferred in this status"
        );
        require(v.pendingSlashEpoch == 0 && pendingSlashDecisionId[from] == 0, "ValidatorsRegistry: open penalty case - transfer blocked");
        // خریدار: هرگز ولیدیتور نبوده، کاملاً احراز هویت شده، کلید اپراتور نیست، مالک جایگاه دیگری نیست
        require(validators[to].status == Status.None && !permanentlyExited[to] && !everActivated[to], "ValidatorsRegistry: buyer was a validator before");
        require(ownerOfOperator[to] == address(0) && operatorOf[to] == address(0), "ValidatorsRegistry: buyer is an operator key");
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(to), "ValidatorsRegistry: buyer identity not fully verified");
        require(to != from, "ValidatorsRegistry: same owner");
        // خریدار باید پیش از انتقال نسخهٔ منشور و تعهدنامهٔ ولیدیتور را «برای همین جایگاه» پذیرفته باشد؛ پذیرش همین‌جا مصرف می‌شود
        require(seatAcceptedFor[to] == seatId, "ValidatorsRegistry: buyer has not accepted the validators' agreement for this seat");
        bytes32 agreementHash = seatAcceptedAgreementHash[to];
        delete seatAcceptedFor[to];
        delete seatAcceptedAgreementHash[to];

        _moveSeatRecord(from, to, st, false);

        seatAgreementHash[seatId] = agreementHash;
        emit SeatAgreementBound(seatId, to, agreementHash);
        emit SeatTransferred(seatId, from, to, st);
    }

    /// @dev کل رکورد ولیدیتور یک جایگاه را از `from` به `to` می‌برد (مشترک بین فروش و مهاجرت پس از گم‌شدن کلید مالک؛ فراخواننده‌ها همهٔ
    ///      قواعد را از قبل سنجیده‌اند). جایگاه Active، Active «می‌ماند» (تصمیم ۱۹ نوامبر ۲۰۲۶): مالک تازه جای مالک را در مجموعهٔ فعال با همان
    ///      جایگاه ترتیبی و همان کلید اپراتور می‌گیرد، پس گره بدون وقفه به اعتبارسنجی ادامه می‌دهد. رأی مالک قدیم پایان می‌یابد و مالک تازه از
    ///      همین لحظه رأی‌دهندهٔ جدید است (checkpointهای تازه)، پس نمی‌تواند در پیشنهادهای پیش از آن رأی دهد. آدرس قدیم permanentlyExited
    ///      می‌شود (دیگر هرگز ولیدیتور نمی‌شود) و اختیار هیأتش پایان می‌یابد. `keepResumeRequest`: مهاجرت درخواست ازسرگیریِ باز را نگه
    ///      می‌دارد (همان شخص)، فروش نه. در «فروش» همین است و بس (خریدار شخص دیگری است و کرسی هیأت نمی‌گیرد)؛ در «مهاجرت»
    ///      شخص همان است، پس migrateSeat پس از آن کرسی هیأت و رأی‌های انتخاباتی آدرس قدیم را به آدرس تازه می‌دهد (ValidatorsBoard.onSeatMigrated).
    function _moveSeatRecord(address from, address to, Status st, bool keepResumeRequest) private {
        ValidatorInfo storage v = validators[from];
        if (st == Status.Active) {
            uint256 idx = activeIndex[from];
            activeValidators[idx - 1] = to;
            activeIndex[to] = idx;
            delete activeIndex[from];
            _recordActiveCheckpoint(from, false);
            _recordActiveCheckpoint(to, true);
        }

        // جابه‌جایی رکورد
        validators[to] = v;
        delete validators[from];
        address op = operatorOf[from];
        if (op != address(0)) {
            operatorOf[to] = op;
            ownerOfOperator[op] = to; // کلید گره با جایگاه می‌ماند
            delete operatorOf[from];
        }
        if (isFounder[from]) {
            isFounder[to] = true;
            delete isFounder[from];
        }
        everActivated[to] = everActivated[from];
        activationSeq[to] = activationSeq[from];
        resumeRequested[to] = keepResumeRequest && resumeRequested[from];
        resumeRequested[from] = false;
        {
            // باقیماندهٔ مالک قدیم نباید جان به در ببرد: پیشنهاد باز کلید نود (و رزرو آن کلید) و هر پذیرشی که به‌عنوان خریدار
            // احتمالی ثبت کرده بود؛ مالک تازه تمیز شروع می‌کند و اگر کلید نود دیگری بخواهد باید پیشنهاد خودش را بدهد
            address proposed = pendingOperator[from];
            if (proposed != address(0)) {
                delete operatorReservedBy[proposed];
                delete pendingOperator[from];
                delete pendingOperatorExpiresAt[from];
            }
            delete seatAcceptedFor[from];
            delete seatAcceptedAgreementHash[from];
            // پذیرشِ باز خودِ مالک تازه (شاید به‌عنوان خریدار احتمالیِ جایگاهی دیگر ثبت کرده باشد) هم نباید پس از جابه‌جایی بماند: کسی که
            // مالک جایگاه شد دیگر خریدار نمی‌شود و پذیرش مانده فقط گمراه‌کننده است. فروش پذیرش خریدار را از قبل مصرف کرده (اینجا صفر
            // است)؛ فقط مهاجرت ممکن است پذیرشی بیابد.
            uint256 staleSeatId = seatAcceptedFor[to];
            if (staleSeatId != 0) {
                delete seatAcceptedFor[to];
                delete seatAcceptedAgreementHash[to];
                emit SeatAcceptanceRevoked(to, staleSeatId);
            }
        }

        // مالک قدیم خروج‌کرده محسوب می‌شود: ممنوعیت دائمی، اختیار هیأت از او سلب می‌شود (در مهاجرت، کرسی هیأت بعداً به آدرس تازه داده می‌شود)
        permanentlyExited[from] = true;
        membershipEpoch[from]++;

        _notifyBoard(from);
        _notifyBoard(to);
    }

    // ------------------------------------------------------------------
    // گم‌شدن کلید مالک: کل صندلی پس از مهاجرت مجاز هویت به آدرس تازهٔ همان شخص می‌رود (ایراد حسابرسی A4)
    // ------------------------------------------------------------------
    /// @notice یک صندلی پس از گم‌شدن کلید مالک به آدرس تازهٔ «همان شخص» رفت.
    event SeatMigrated(uint256 indexed seatId, address indexed from, address indexed to, Status statusAfter);

    /// @notice گم‌شدن کلید مالک (تعهدنامهٔ ولیدیتور ۵-۵، طرح ۳۲ پاسخ ۶): «کل» صندلی را از `oldOwner` به `newOwner` می‌برد (رکورد ولیدیتور
    ///         با وثیقه و وضعیتش، پیوند کلید اپراتور (کلید نود)، پرچم مؤسس، تاریخچهٔ فعال‌سازی، جایگاه در مجموعهٔ فعال و رأی به‌عنوان
    ///         رأی‌دهندهٔ جدید از همین لحظه، NFT صندلی، و آنچه BlockRewardDistributor به مالک قدیم بدهکار است). تنها استثنای ممنوعیت
    ///         دائم است: شخص همان است، پس آدرس تازه «خروج‌کرده» شمرده نمی‌شود، ولی آدرس قدیم دائماً خروج‌کرده می‌شود.
    ///
    ///         کرسی هیأت همراه شخص می‌رود (ValidatorsBoard.onSeatMigrated، فراخوان **الزامی**: اگر revert کند مهاجرت revert می‌شود): اگر آدرس
    ///         قدیم در هیأت ولیدیتورها کرسیِ «معتبر» دارد (کرسی‌ای که پیش‌تر پایان نیافته، مثلاً با خروج یا حذف در بازیابی)، آدرس تازه همان کرسی را «در همان جا» تا پایان ماهِ هیأت می‌گیرد (همان جایگاه، بدون جای
    ///         خالی، بدون تغییر نسخهٔ هیأت) و رأی‌های انتخاباتی که آدرس قدیم داده و گرفته با آن می‌روند. یک شخص دوبار شمرده نمی‌شود: رأی او
    ///         به یک اقدام هیأت یا یک اتاق هیأتیِ Distributor روی مجموع آدرس قدیم و تازه فقط یک بار ثبت می‌شود، ولی رأی ولیدیتوریِ او از
    ///         لحظهٔ مهاجرت از نو شروع می‌شود (رأی‌دهندهٔ جدید از همین لحظه). **فروش** صندلی هیچ‌کدام از این‌ها را انجام نمی‌دهد: خریدار
    ///         شخص دیگری است، اختیار هیأتیِ فروشنده پایان می‌یابد و کرسی هیأتی تحویل نمی‌شود.
    ///
    ///         مجوز (دو کلید مستقل، سخت‌ترین خوانش اسناد): (۱) اوراکل هویت باید پیش‌تر پس از بررسی آف‌چین هویت
    ///         IdentityRegistry.migrateIdentity(oldOwner, newOwner) را اجرا کرده باشد (این قرارداد migratedTo(oldOwner) == newOwner را
    ///         می‌خواند)، و (۲) این فراخوان را Verifier می‌زند. هیچ‌کدام از دو کلید به‌تنهایی صندلی را نمی‌برد: اوراکل هویت به Registry
    ///         دسترسی ندارد و Verifier نمی‌تواند آدرسی را نام ببرد که اوراکل به آن مهاجرت نداده است. مالک قدیم نمی‌تواند صدایش بزند (کلیدش
    ///         گم شده). آدرس تازه باید کاملاً احراز هویت شده باشد (مهاجرت پرچم‌ها را کپی می‌کند)، کیف‌پول معمولی (EOA)، هرگز ولیدیتور
    ///         یا کلید اپراتور نبوده باشد و صندلی نداشته باشد. صندلی قدیم باید Probation، Active، Demoted یا SelfSuspended و بدون پروندهٔ
    ///         جریمهٔ باز باشد؛ صندلی Exiting یا RemovedInRecovery مهاجرت نمی‌کند.
    function migrateSeat(address oldOwner, address newOwner) external onlyVerifier nonReentrant {
        require(newOwner != address(0) && newOwner != oldOwner, "ValidatorsRegistry: bad new owner");
        ValidatorInfo storage v = validators[oldOwner];
        Status st = v.status;
        require(
            st == Status.Probation || st == Status.Active || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: seat cannot be migrated in this status"
        );
        require(v.pendingSlashEpoch == 0 && pendingSlashDecisionId[oldOwner] == 0, "ValidatorsRegistry: open penalty case - migration blocked");
        require(
            IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).migratedTo(oldOwner) == newOwner,
            "ValidatorsRegistry: the identity of the old owner was not migrated to this address"
        );
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(newOwner), "ValidatorsRegistry: new owner identity not fully verified");
        require(newOwner.code.length == 0, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12
        require(validators[newOwner].status == Status.None && !permanentlyExited[newOwner] && !everActivated[newOwner], "ValidatorsRegistry: new owner was a validator before");
        require(ownerOfOperator[newOwner] == address(0) && operatorOf[newOwner] == address(0), "ValidatorsRegistry: new owner is an operator key");

        bool seatWasValid = IValidatorsBoardSync(BOARD).hasValidSeat(oldOwner); // پیش از جابه‌جایی: جابه‌جایی epoch قدیم را بالا می‌برد و هر کرسی را باطل نشان می‌دهد
        uint256 seatId = IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).reassignSeat(oldOwner, newOwner);
        _moveSeatRecord(oldOwner, newOwner, st, true);
        IValidatorsBoardSync(BOARD).onSeatMigrated(oldOwner, newOwner, seatWasValid); // الزامی (بر خلاف _notifyBoard بهترین‌تلاش): کرسی هیأت و رأی‌های انتخاباتی آدرس قدیم به آدرس تازه می‌رود، وگرنه هیچ‌چیز جابه‌جا نمی‌شود
        DISTRIBUTOR.migrateClaimable(oldOwner, newOwner);

        emit SeatMigrated(seatId, oldOwner, newOwner, st);
    }
}
