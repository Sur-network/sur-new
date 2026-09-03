// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title ValidatorsRegistry
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.VALIDATORS_REGISTRY
///         (0x3333...3333). دو نقش دارد:
///
///         ۱) اجماع: اینترفیس هاردکدشده‌ی حالت contract-mode در QBFT بسو را پیاده می‌کند —
///            `getValidators() external view returns (address[] memory)`. این آدرس باید
///            همچنین به‌عنوان `qbft.validatorcontractaddress` در genesis.json تنظیم شود. هر
///            تغییری در لیست برگشتی، از همان بلاکی که تغییر توش مین شده، بلافاصله اثر می‌کند
///            (تأیید تجربی — «یافته‌های آزمایش Besu QBFT»، آزمایش ۲ را ببین).
///
///         ۲) صلاحیت پرداخت: `BlockRewardDistributor` مستقیم `isValidator(address)` را روی
///            این قرارداد چک می‌کند قبل از پرداخت به هرکسی. هیچ اوراکل واسطی برای همگام‌سازی
///            مجموعه‌ی ولیدیتور وجود ندارد (طراحی قدیمی `validatorSyncOracle` کنار گذاشته
///            شده — بخش ۲.۹ / ۵ سند طراحی را ببین).
///
///         عمداً از `ValidatorsTreasury` جدا نگه داشته شده: یک باگ در منطق خرج خزانه هرگز
///         نباید بتواند روی این‌که چه کسی به‌عنوان ولیدیتور شناخته می‌شود اثر بگذارد.
///
///         دیپلوی genesis: این قرارداد، همراه با چهار قرارداد ساختاری دیگر، مستقیم در بخش
///         `alloc` بلاک genesis (کد + storage نهایی) تزریق می‌شود، نه با یک تراکنش دیپلوی —
///         و به همین دلیل، اصلاً constructor ندارد (یک constructor هرگز روی زنجیره‌ی واقعی
///         اجرا نمی‌شد). مجموعه‌ی اولیه‌ی ولیدیتورها، genesis timestamp واقعی، و هر پارامتر
///         امنیتی به‌جایش با ابزار genesis آف‌چین seed می‌شوند (یادداشت‌های 🔶 پرکردنِ genesis
///         در سراسر این فایل را ببین)؛ برای دستورالعمل دقیق و این‌که چرا genesis timestamp
///         واقعی را نمی‌شود قابل‌اتکا از `block.timestamp` یک محیط شبیه‌سازی‌شده خواند، و چرا
///         این برای پنجره‌ی نرخ محدودیت و timestamp های تأیید لایوینس هر ولیدیتور اولیه اهمیت
///         دارد، به "sur-contracts-deploy-notes.md" مراجعه کن.
///
///         چرخه‌ی عمر یک آدرس ولیدیتور:
///           None -> Probation (قفل‌کردن استیک، تأیید همگام‌سازی نود توسط verifier، هنوز در
///                   getValidators() نیست)
///                -> Active (در getValidators()، واجد شرایط پرداخت)
///                -> [غیرفعالی پیوسته] -> Demoted (از getValidators() حذف شده، بخشی از
///                   استیک اسلش شده)
///                -> [تأییدهای لایوینس دوره‌ی بازگشت] -> دوباره Active
///           از Probation، Active، یا Demoted، یک آدرس می‌تواند به‌جایش Exiting را انتخاب کند
///           (خروج داوطلبانه، منوط به یک cooldown) تا باقی‌مانده‌ی استیکش را پس بگیرد.
///
///         حکمرانی — به دو مسیر تقسیم شده (تصمیم به‌روزشده: رسیدن به اجماع کامل ولیدیتورها
///         روی هر پارامتری، در عمل با رشد جمعیت ولیدیتورها غیرعملی ثابت شد):
///           - پارامترهای اقتصادی ورود (entryThresholdBase، growthFactorPerValidator،
///             membershipFeeBps): فقط با رأی اکثریت داخلی خودِ ValidatorsBoard قابل‌تغییرند
///             (به proposeSetEntryThresholdBase/proposeSetGrowthFactorPerValidator/
///             proposeSetMembershipFeeBps در ValidatorsBoard.sol مراجعه کن). اعضای هیأت با
///             رأی‌گیری تأییدی مستمر بین ولیدیتورهای فعال انتخاب می‌شوند (به
///             voteFor/unvoteFor/refreshBoard در ValidatorsBoard.sol مراجعه کن — بدون مرحله‌ی
///             عزل؛ یک عضو به‌محض از‌دست‌دادن حمایت کافی یا غیرفعال‌شدن، صرفاً دیگر دوباره
///             انتخاب نمی‌شود)، پس این کنترل بنیاد یا اوراکل نیست؛ یک تفویض عمدی به یک نهاد
///             کوچک، مدام‌تازه‌شونده، و منتخب ولیدیتورهاست برای پارامترهایی که انتظار می‌رود
///             با تغییر تعداد ولیدیتور و ارزش بازار سورن نیاز به تنظیم مکرر داشته باشند.
///           - همه‌چیز دیگر (نرخ محدودیت، طول probation، آستانه‌ی لایوینس/غیرفعالی، دوره‌ی
///             بازگشت، درصد اسلش، cooldown خروج): همچنان نیازمند رأی اکثریت کامل
///             ولیدیتورهای فعلاً فعال است، از طریق proposeParameterChange/
///             voteParameterChange خودِ این قرارداد — هرگز بنیاد، هرگز هیأت. این‌ها همچنان
///             آستانه‌ی سخت‌تر و با اعتماد بالاتر باقی می‌مانند چون فرضیات امنیتی خودِ مجموعه‌ی
///             ولیدیتور را تعریف می‌کنند، نه تنظیم اقتصادی‌اش را.
///
///         کارمزد عضویت (مدل ترکیبی استیک): پرداخت یک ولیدیتور تازه در requestMembership، به
///         شکل ارز بومی (سورن — توکن پایه/گس خودِ زنجیره، دقیقاً مثل ETH روی اتریوم؛ نه یک
///         ERC20)، به دو بخش تقسیم می‌شود:
///           - وثیقه (= currentEntryThreshold()): در موجودی بومی همین قرارداد قفل می‌ماند،
///             کاملاً قابل‌استرداد در خروج داوطلبانه (به withdrawStake مراجعه کن)، بخشی
///             قابل‌اسلش در دموت به‌خاطر غیرفعالی. این پول خودِ آدرس است، هرگز با رأی مجمع
///             ولیدیتورها قابل‌خرج نیست.
///           - کارمزد عضویت (= currentMembershipFee()، درصدی حکمرانی‌شده از وثیقه): بلافاصله
///             و برگشت‌ناپذیر در ورود به ValidatorsTreasury فوروارد می‌شود، دقیقاً مثل بخش
///             اسلش‌شده‌ی وثیقه. این همان چیزی است که باعث می‌شود ورود ولیدیتور تازه بلافاصله
///             به خزانه‌ی مشترک مجمع وجه خرج‌شدنی اضافه کند، بدون این‌که خودِ وثیقه را به
///             دارایی عمومی تبدیل کند (که تضمین خروج را می‌شکند و اسلش را به‌عنوان بازدارنده‌ی
///             شخصی کند می‌کند — به بحث طراحی حکمرانی پروژه مراجعه کن که چرا تقسیم ترکیبی به‌جای
///             خزانه‌ای‌کردن کل استیک انتخاب شد).
contract ValidatorsRegistry {
    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — مقصد استیک اسلش‌شده.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

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
        uint256 periodStartedAt;   // شروع پنجره‌ی probation یا بازگشت یا cooldown خروج فعلی
        uint256 lastLivenessConfirmation;
        uint256 livenessConfirmationsInPeriod; // گزارش‌های لایوینس مثبت از periodStartedAt به بعد (هر دوره ریست می‌شود)
        uint256 demotedAt;          // اگه هرگز دموت نشده/الان در وضعیت Demoted نیست، صفر است
    }

    mapping(address => ValidatorInfo) public validators;

    // ------------------------------------------------------------------
    // یادداشت معماری: هویت (نام/نوع شخصیت، وریفای موبایل/تلگرام/KYC) دیگر اینجا نیست — به یک
    // قرارداد کاملاً مستقل، `IdentityRegistry.sol`، منتقل شده است. دلیل: جمعیت هدف هویت (کل
    // کاربران شبکه) کاملاً از جمعیت ولیدیتورها جداست؛ `ValidatorsBoard.voteFor` الان مستقیم
    // `IdentityRegistry.hasIdentity(...)` را چک می‌کند، نه از طریق این قرارداد.
    //
    // `verifier` اینجا باقی مانده، ولی فقط برای یک هدف: گزارش `reportLiveness` (پایین‌تر در
    // همین فایل). این یک کلید کاملاً جدا از `identityOracle` در `IdentityRegistry.sol` است —
    // این دو نقش (زنده‌بودن نود در مقابل احراز هویت) عمداً مستقل نگه داشته شده‌اند.
    // ------------------------------------------------------------------

    /// @notice کلید عملیاتی مورد اعتماد برای گزارش لایوینس ولیدیتور — reportLiveness پایین را
    ///         ببین. با ValidatorsBoard قابل‌چرخش است — setVerifier را ببین.
    /// @dev ✅ پرشده: آدرس اولیه‌ی verifier (چک‌سام‌شده طبق EIP-55).
    address public verifier = 0x1A5E86f3333291B3332C0f9Eddb04269940566bc;

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
    // 🔶 پرکردنِ genesis: مجموعه‌ی اولیه‌ی ولیدیتورهای مؤسس. `activeValidators` یک آرایه‌ی
    // پویاست و `activeIndex`/`validators` هر دو mapping هستند — Solidity هیچ syntax ای برای
    // پرکردن هیچ‌کدام با یک حلقه خارج از تابع ندارد، پس این state اولیه اینجا نمی‌تواند
    // به‌صورت یک مقداردهی ساده‌ی متغیر state بیان شود. ابزار genesis آف‌چین باید یا (الف)
    // دیپلوی این قرارداد را با منطق seed کردن واقعی پایین، روی یک زنجیره‌ی محلی موقت شبیه‌سازی
    // کند و storage نتیجه را در فایل نهایی genesis کپی کند، یا (ب) مستقیم storage slot های
    // متناظر را در alloc genesis محاسبه و بنویسد. برای دستورالعمل کامل به
    // "sur-contracts-deploy-notes.md" مراجعه کن.
    //
    // منطق مرجع (کد زنده نیست — برای این‌که ابزار genesis آن را، چه با شبیه‌سازی چه با
    // محاسبه‌ی مستقیم storage، بازتولید کند) — برای هر آدرس ولیدیتور مؤسس v:
    //   validators[v] = ValidatorInfo({ status: Active, lockedStake: 0,
    //     periodStartedAt: GENESIS_TIMESTAMP, lastLivenessConfirmation: GENESIS_TIMESTAMP,
    //     livenessConfirmationsInPeriod: 0, demotedAt: 0 });
    //   activeIndex[v] = activeValidators.length + 1;
    //   activeValidators.push(v);
    // ------------------------------------------------------------------
    // مجموعه‌ی ولیدیتورهای فعال، از طریق getValidators() افشا می‌شود. حذف با swap-and-pop از
    // طریق اندیس یک‌مبنایی.
    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // پارامترهای تحت حکمرانی (فقط با رأی کامل ولیدیتورها قابل‌تغییر — پایین را ببین)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // پارامترهای اقتصادی ورود — مقادیر اولیه‌ی هاردکد، فقط با ValidatorsBoard قابل‌تغییر
    // (نه آرگومان constructor، نه تحت حکمرانی رأی کامل ولیدیتورها — یادداشت حکمرانی در کامنت
    // مستندات سطح قرارداد بالا را ببین). مقادیر اولیه‌ی پایین یک نقطه‌ی شروع عمدی است، نه
    // مشتق‌شده از هیچ داده‌ی on-chain: با فرض قیمت اولیه‌ی سورن حدود ۰.۰۰۰۵ دلار،
    // ۲,۰۰۰,۰۰۰ سورن ~= ۱۰۰۰ دلار وثیقه به‌ازای هر کرسی ولیدیتور.
    // ------------------------------------------------------------------

    /// @notice استیک پایه‌ی لازم برای درخواست عضویت وقتی صفر ولیدیتور فعال وجود دارد.
    uint256 public entryThresholdBase = 2_000_000 ether; // ۲,۰۰۰,۰۰۰ سورن (۱۸ رقم اعشار، مثل ETH)

    /// @notice آستانه‌ی ورود به‌طور پیوسته رشد می‌کند (مرکب به‌ازای هر ولیدیتور فعال اضافی،
    ///         نه در پله‌های گسسته): آستانه‌ی فعلی =
    ///         entryThresholdBase * growthFactorPerValidator^activeValidators.length.
    ///         `growthFactorPerValidator` یک عدد fixed-point با ۱۸ رقم اعشار است (FIXED_POINT_ONE
    ///         پایین را ببین)؛ مثلاً 1_044273782427413840 (~۱.۰۴۴۲۷۴) یعنی آستانه به‌ازای هر
    ///         ولیدیتور فعال اضافی حدود ۴.۴۲۷۴٪ رشد می‌کند — طوری انتخاب شده که ۱۶ ولیدیتور
    ///         پیوسته‌ی تازه، آستانه را دقیقاً ۲برابر می‌کند (2^(1/16) ≈ 1.044274)، یعنی آستانه
    ///         هر ۱۶ ولیدیتور فعال، به‌طور نرم (نه با یک پرش در دقیقاً شانزدهمین) دوبرابر
    ///         می‌شود. این همان «منحنی هزینه‌ی صعودی» سند طراحی است: خرید هم‌زمان بیش از ۱/۳
    ///         کرسی‌ها را نمایی، نه خطی، گران می‌کند.
    uint256 public growthFactorPerValidator = 1_044273782427413840;

    /// @notice دقت fixed-point استفاده‌شده توسط growthFactorPerValidator و _fixedPow (۱۸ رقم
    ///         اعشار، مثل خودِ سورن/ETH). 1_000000000000000000 معادل ۱.۰ (بدون رشد) است.
    uint256 private constant FIXED_POINT_ONE = 1_000000000000000000;

    /// @notice سقف امنیتی/گس: تعداد ولیدیتور فعال هنگام محاسبه‌ی آستانه‌ی ورود به همین مقدار
    ///         محدود می‌شود، تا توان — و در نتیجه ضریب — هرگز نامحدود رشد نکند. ۵۱۲ = ۱۶ * ۳۲،
    ///         همان حداکثر ضریبی (2^32) که این سقف همیشه نمایندگی کرده را حفظ می‌کند، حالا با
    ///         مقیاس دوره‌ی دوبرابرشدن ۱۶ولیدیتوری.
    uint256 private constant MAX_GROWTH_VALIDATORS = 512;

    /// @notice کارمزد عضویت، به‌عنوان کسری از currentEntryThreshold()، **علاوه بر** وثیقه
    ///         پرداخت می‌شود و بلافاصله به ValidatorsTreasury فرستاده می‌شود (غیرقابل‌استرداد
    ///         — یادداشت «کارمزد عضویت» بالا را ببین). ۴۰۰ = ۴٪ مبلغ وثیقه.
    uint256 public membershipFeeBps = 400;

    /// @notice حداکثر تعداد درخواست عضویت تازه‌ی مجاز در entryWindowSeconds.
    /// @dev 🔶 FILL_IN: همه‌ی پارامترهای امنیتی پایین قبل از genesis نیازمند یک تصمیم معادل
    ///      رأی کامل ولیدیتورها هستند — sur-master-open-items.md را ببین.
    uint256 public maxEntriesPerWindow = 0;
    uint256 public entryWindowSeconds = 0;

    uint256 public probationPeriod = 0;          // 🔶 FILL_IN — مثلاً ۱ هفته
    uint256 public minLivenessConfirmationsToActivate = 0;  // 🔶 FILL_IN — تعداد گزارش لایوینس مثبت لازم در طول probation قبل از فعال‌سازی
    uint256 public inactivityThreshold = 0;      // 🔶 FILL_IN — غیبت پیوسته‌ی گزارش لایوینس مثبت قبل از این‌که دموت مجاز شود
    uint256 public recoveryPeriod = 0;           // 🔶 FILL_IN — دوره‌ی پیوسته‌ی گزارش لایوینس مثبت لازم بعد از دموت
    uint256 public slashBps = 0;                 // 🔶 FILL_IN — کسری از استیک قفل‌شده که در دموت به‌خاطر غیرفعالی اسلش می‌شود (باید <= BPS_DENOMINATOR باشد)
    uint256 public exitCooldown = 0;             // 🔶 FILL_IN — زمان انتظار بین requestExit() و withdrawStake()

    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @dev 🔶 FILL_IN: genesis timestamp واقعی شبکه‌ی زنده (نه block.timestamp هر ماشین/لحظه‌ای
    ///      که شبیه‌سازی رویش اجرا می‌شود — به sur-contracts-deploy-notes.md مراجعه کن).
    // وضعیت پنجره‌ی چرخشی نرخ محدودیت
    uint256 public windowStart = 0;
    uint256 public entriesInWindow;

    bool private locked; // نگهبان reentrancy

    // ------------------------------------------------------------------
    // حکمرانی پارامتر (رأی کامل ولیدیتورها) — همه‌چیز **به‌جز** سه پارامتر اقتصادی ورود بالا
    // (آن‌ها تحت حکمرانی ValidatorsBoard هستند؛ به ValidatorsBoard.sol مراجعه کن).
    // ------------------------------------------------------------------

    enum ParamKey {
        MaxEntriesPerWindow,
        EntryWindowSeconds,
        ProbationPeriod,
        MinLivenessConfirmationsToActivate,
        InactivityThreshold,
        RecoveryPeriod,
        SlashBps,
        ExitCooldown
    }

    struct ParamProposal {
        ParamKey key;
        uint256 newValue;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event MembershipRequested(address indexed validator, uint256 collateralAmount, uint256 feeAmount);
    event ValidatorActivated(address indexed validator);
    event ValidatorDemoted(address indexed validator, uint256 slashedAmount);
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
    ///         هر ولیدیتور فعال اضافی، نه در پرش‌های گسسته) — growthFactorPerValidator بالا را
    ///         ببین. سقف‌گذاری‌شده روی رشد معادل MAX_GROWTH_VALIDATORS ولیدیتور فعال، برای
    ///         جلوگیری از overflow/گس نامحدود.
    function currentEntryThreshold() public view returns (uint256) {
        uint256 n = activeValidators.length;
        if (n > MAX_GROWTH_VALIDATORS) n = MAX_GROWTH_VALIDATORS;
        uint256 multiplier = _fixedPow(growthFactorPerValidator, n);
        return (entryThresholdBase * multiplier) / FIXED_POINT_ONE;
    }

    /// @dev توان‌رسانی fixed-point (FIXED_POINT_ONE = 1e18) با روش exponentiation by squaring:
    ///      برمی‌گرداند base1e18^exponent، به همان بازنمایی fixed-point با مبنای 1e18.
    ///      O(log2(exponent)) ضرب — حتی برای توان‌های بزرگ ارزان.
    function _fixedPow(uint256 base1e18, uint256 exponent) private pure returns (uint256 result1e18) {
        result1e18 = FIXED_POINT_ONE; // ۱.۰
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

    /// @notice کارمزد عضویت فعلی — کسری حکمرانی‌شده از currentEntryThreshold()، علاوه بر
    ///         وثیقه پرداخت می‌شود و مستقیم به ValidatorsTreasury فرستاده می‌شود. یادداشت
    ///         «کارمزد عضویت» در کامنت مستندات سطح قرارداد بالا را ببین.
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
        emit EconomicParamUpdatedByBoard("entryThresholdBase", entryThresholdBase, newValue);
        entryThresholdBase = newValue;
    }

    function setGrowthFactorPerValidator(uint256 newValue) external onlyBoard {
        require(newValue > FIXED_POINT_ONE, "ValidatorsRegistry: growth factor must be > 1.0 (must actually grow)");
        emit EconomicParamUpdatedByBoard("growthFactorPerValidator", growthFactorPerValidator, newValue);
        growthFactorPerValidator = newValue;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(newValue <= BPS_DENOMINATOR, "ValidatorsRegistry: membershipFeeBps too high");
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
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
    // Payable: فراخوان مستقیم سورن بومی را همراه تراکنش می‌فرستد (msg.value)، که به دو مبلغ
    // تقسیم می‌شود:
    //   ۱. `threshold` (currentEntryThreshold()) — اینجا به‌عنوان وثیقه‌ی قابل‌استرداد/قابل‌اسلش نگه داشته می‌شود.
    //   ۲. `fee` (currentMembershipFee()) — مستقیم به ValidatorsTreasury فوروارد می‌شود، غیرقابل‌استرداد.
    // msg.value باید دقیقاً برابر مجموع هر دو باشد — بدون باقی‌مانده/پرداخت‌اضافه‌ای که نیاز به توضیح داشته باشد.
    // ------------------------------------------------------------------
    function requestMembership() external payable nonReentrant {
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");

        uint256 threshold = currentEntryThreshold();
        uint256 fee = currentMembershipFee();
        require(msg.value == threshold + fee, "ValidatorsRegistry: incorrect payment amount");

        _enforceRateLimit();

        if (fee > 0) {
            (bool success, ) = TREASURY.call{value: fee}("");
            require(success, "ValidatorsRegistry: membership fee transfer failed");
        }
        // `threshold` عمداً در موجودی بومی همین قرارداد به‌عنوان وثیقه‌ی قفل‌شده می‌ماند — نیازی
        // به انتقال نیست، همراه همین فراخوانی از طریق msg.value رسیده است.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: threshold,
            periodStartedAt: block.timestamp,
            lastLivenessConfirmation: block.timestamp,
            livenessConfirmationsInPeriod: 0,
            demotedAt: 0
        });

        emit MembershipRequested(msg.sender, threshold, fee);
    }

    // ------------------------------------------------------------------
    // گزارش لایوینس — کاملاً **جایگزین** طراحی قدیمی heartbeat() خوداظهاری می‌شود. heartbeat
    // خوداظهاری فقط ثابت می‌کرد یک کیف‌پول می‌تواند یک تراکنش امضا کند، نه این‌که یک نود واقعی
    // در حال اجرا یا واقعاً بلاک تولید می‌کند. حالا، فقط `verifier` (همان نقش عملیاتی
    // استفاده‌شده برای وریفای موبایل/تلگرام — بخش هویت بالا را ببین) می‌تواند لایوینس را تأیید
    // کند، بعد از این‌که واقعاً ولیدیتور را آف‌چین چک کرده باشد:
    //   - Probation / Demoted (بازگشت): verifier چک می‌کند آیا نودِ خودِ کاندید بالاست و
    //     همگام‌سازی شده (مثلاً مقایسه‌ی head گزارش‌شده‌ی زنجیره‌اش با head واقعی شبکه).
    //   - Active: verifier تولید واقعی و on-chain بلاک را چک می‌کند (فیلد `miner`/`coinbase`
    //     بلاک‌های اخیر — «یافته‌های آزمایش Besu QBFT»، آزمایش ۱، که تأیید کرد این فیلد همیشه
    //     پیشنهاددهنده‌ی واقعی بلاک را نشان می‌دهد) روی یک پنجره‌ی اخیر، نه فقط این‌که آیا آدرس
    //     می‌تواند یک تراکنش امضا کند.
    // این‌که verifier از کدام روش استفاده کرده یک جزئیات پیاده‌سازی آف‌چین است؛ این قرارداد
    // فقط تأیید بله/خیر نهایی را ثبت می‌کند. نقاط پایانی نود (IP) عمداً اینجا on-chain ذخیره
    // **نمی‌شوند** (برای جلوگیری از قرارگرفتن ولیدیتورها در معرض DDoS) — در همان اپ همراه
    // آف‌چینی می‌مانند که برای داده‌ی موبایل/تلگرام استفاده می‌شود، در دسترس هرکسی که کلید
    // `verifier` را داشته باشد.
    // ------------------------------------------------------------------

    event LivenessReported(address indexed validator, bool isLive, uint256 timestamp);

    /// @notice گزارش این‌که آیا `validator` زنده تأیید شد (یادداشت‌های روش بالا را ببین). فقط
    ///         در تأیید مثبت state را به‌روز می‌کند — یک گزارش منفی ثبت می‌شود (برای
    ///         شفافیت/حسابرسی) ولی شمارنده‌های ذخیره‌شده را دست نمی‌زند، چون کل هدف تشخیص
    ///         غیرفعالی، **غیبت** تأییدهای مثبت در طول زمان است.
    function reportLiveness(address validator, bool isLive) external onlyVerifier {
        ValidatorInfo storage v = validators[validator];
        require(
            v.status == Status.Probation || v.status == Status.Active || v.status == Status.Demoted,
            "ValidatorsRegistry: validator not eligible for liveness reporting"
        );
        if (isLive) {
            v.lastLivenessConfirmation = block.timestamp;
            v.livenessConfirmationsInPeriod++;
        }
        emit LivenessReported(validator, isLive, block.timestamp);
    }

    // ------------------------------------------------------------------
    // فعال‌سازی بعد از probation — بدون نیاز به مجوز
    // ------------------------------------------------------------------
    function promoteAfterProbation(address candidate) external {
        ValidatorInfo storage v = validators[candidate];
        require(v.status == Status.Probation, "ValidatorsRegistry: not in probation");
        require(block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        require(v.livenessConfirmationsInPeriod >= minLivenessConfirmationsToActivate, "ValidatorsRegistry: insufficient liveness confirmations");
        require(block.timestamp - v.lastLivenessConfirmation <= inactivityThreshold, "ValidatorsRegistry: liveness confirmation stale");

        _activate(candidate);
    }

    // ------------------------------------------------------------------
    // دموت به‌خاطر غیرفعالی — بدون نیاز به مجوز
    // ------------------------------------------------------------------
    function demoteForInactivity(address validator) external nonReentrant {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(block.timestamp - v.lastLivenessConfirmation >= inactivityThreshold, "ValidatorsRegistry: not yet inactive");

        _removeFromActive(validator);

        uint256 slashAmount = (v.lockedStake * slashBps) / BPS_DENOMINATOR;
        v.lockedStake -= slashAmount;
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp; // دوره‌ی بازگشت از همین الان شروع می‌شود
        v.livenessConfirmationsInPeriod = 0;

        if (slashAmount > 0) {
            (bool success, ) = TREASURY.call{value: slashAmount}("");
            require(success, "ValidatorsRegistry: slash transfer failed");
        }

        emit ValidatorDemoted(validator, slashAmount);
    }

    // ------------------------------------------------------------------
    // فعال‌سازی مجدد بعد از بازگشت — بدون نیاز به مجوز
    // ------------------------------------------------------------------
    function promoteAfterRecovery(address validator) external {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        require(v.livenessConfirmationsInPeriod >= minLivenessConfirmationsToActivate, "ValidatorsRegistry: insufficient recovery liveness confirmations");
        require(block.timestamp - v.lastLivenessConfirmation <= inactivityThreshold, "ValidatorsRegistry: liveness confirmation stale");

        _activate(validator);
        emit ValidatorReactivated(validator);
    }

    function _activate(address who) private {
        ValidatorInfo storage v = validators[who];
        v.status = Status.Active;
        activeIndex[who] = activeValidators.length + 1;
        activeValidators.push(who);
        emit ValidatorActivated(who);
    }

    function _removeFromActive(address who) private {
        uint256 idx = activeIndex[who]; // یک‌مبنایی
        require(idx != 0, "ValidatorsRegistry: not in active set");
        uint256 lastIdx = activeValidators.length; // آخرین موقعیت یک‌مبنایی

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
            _removeFromActive(msg.sender);
        }

        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
    }

    function withdrawStake() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Exiting, "ValidatorsRegistry: not exiting");
        require(block.timestamp >= v.periodStartedAt + exitCooldown, "ValidatorsRegistry: exit cooldown not elapsed");

        uint256 amount = v.lockedStake;
        delete validators[msg.sender];

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
        paramProposalCount++;
        id = paramProposalCount;
        paramProposals[id] = ParamProposal({
            key: key,
            newValue: newValue,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
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
        require(!paramHasVoted[id][voter], "ValidatorsRegistry: already voted");

        paramHasVoted[id][voter] = true;
        p.votes++;

        uint256 required = (getActiveValidatorCount() / 2) + 1;
        emit ParameterChangeVoted(id, voter, p.votes, required);

        if (p.votes >= required) {
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
        } else if (key == ParamKey.MinLivenessConfirmationsToActivate) {
            minLivenessConfirmationsToActivate = value;
        } else if (key == ParamKey.InactivityThreshold) {
            inactivityThreshold = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            recoveryPeriod = value;
        } else if (key == ParamKey.SlashBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: slashBps too high");
            slashBps = value;
        } else if (key == ParamKey.ExitCooldown) {
            exitCooldown = value;
        }
        emit ParameterChangeApplied(key, value);
    }

    // ------------------------------------------------------------------
    // توابع کمکی view
    // ------------------------------------------------------------------
    function getValidatorInfo(address who) external view returns (
        Status status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 lastLivenessConfirmation,
        uint256 livenessConfirmationsInPeriod,
        uint256 demotedAt
    ) {
        ValidatorInfo storage v = validators[who];
        return (v.status, v.lockedStake, v.periodStartedAt, v.lastLivenessConfirmation, v.livenessConfirmationsInPeriod, v.demotedAt);
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
}
