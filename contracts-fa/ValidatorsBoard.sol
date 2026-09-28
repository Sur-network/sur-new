// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
    function setEntryThresholdBase(uint256 newValue) external;
    function setGrowthFactorPerValidator(uint256 newValue) external;
    function setMembershipFeeBps(uint256 newValue) external;
    function setVerifier(address newVerifier) external;
    function recoveryPeriod() external view returns (uint256);
    /// @dev `status` معادل ABI-سازگار enum ValidatorsRegistry.Status به صورت uint8 است:
    ///      ۰=None، ۱=Probation، ۲=Active، ۳=Demoted، ۴=Exiting.
    /// @dev ✅ به‌روزشده (بازطراحی معماری راستی‌آزمایی آف‌چین): تابع واقعی
    ///      ValidatorsRegistry.getValidatorInfo() دیگه اصلاً هیچ فیلد نسبت liveness ای نداره
    ///      (کاملاً حذف شدن — liveness الان آف‌چین چک می‌شه). دقیقاً ۶ خروجی به همین ترتیب
    ///      برمی‌گردونه: status، lockedStake، periodStartedAt، demotedAt، pendingSlashEpoch،
    ///      isPaidEntrant. این اینترفیس باید دقیقاً همینو، با همون ترتیب، منعکس کنه — به
    ///      کامنت خودِ تابع واقعی توی ValidatorsRegistry.sol مراجعه کن که چرا یه ناهماهنگی
    ///      اینجا توی یه نسخه‌ی قبلی یه باگ واقعی و بی‌صدای بین‌قراردادی ساخت (اصلاح‌شده
    ///      اون‌موقع، ولی ارزش داره هر بار که امضای تابع واقعی دوباره عوض می‌شه، دوباره چک بشه).
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
    );
}

/// @dev یادداشت معماری: هویت دیگر داخل ValidatorsRegistry نیست — به یک قرارداد ساختاری ششم و
///      کاملاً مستقل، `IdentityRegistry.sol` (آدرس ثابت `0x6666...6666`)، منتقل شده است.
interface IIdentityRegistry {
    function hasIdentity(address who) external view returns (bool);
}

interface IBlockRewardDistributor {
    function setDistributionOracle(address newOracle) external;
}

interface IValidatorsTreasury {
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external;
}

/// @title ValidatorsBoard
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.VALIDATORS_BOARD (0x4444...4444).
///         در مستندات فارسی پروژه «هیأت‌مدیره‌ی ولیدیتورها» نامیده می‌شود.
///
///         عضویت هیأت — رأی‌گیری تأییدی، ۵ کرسی ثابت، بدون عزل (طراحی به‌روزشده؛ کاملاً
///         جایگزین مدل قدیمی انتخاباتِ افزودن/حذف یکی‌یکی):
///           - هر ولیدیتور فعال می‌تواند، هر زمان، تا MAX_VOTES_PER_VOTER (۵) ولیدیتور فعال
///             دیگر را رأی موافق بدهد (`voteFor`)، و هرکدام از این رأی‌ها را هر زمان پس بگیرد
///             (`unvoteFor`). بدون مرحله‌ی نامزدی، بدون بازه‌ی رأی‌گیری، بدون نصاب حداقلی.
///             رأی‌دادن نیاز دارد که رأی‌دهنده اول هویتش را خوداظهاری کرده باشد، روی قرارداد
///             جدای `IdentityRegistry` (`registerIdentity` — فقط نام و نوع شخصیت، خوداظهاری؛
///             شماره‌موبایل، آیدی تلگرام، و مدارک کامل KYC آف‌چین می‌مانند — `IdentityRegistry`
///             فقط ثبت می‌کند کدام‌یک وریفای شده، نه این‌که خودشان شرط رأی‌دادن باشند، فقط
///             `hasIdentity` هست).
///           - `refreshBoard()` — بدون نیاز به مجوز، توسط هرکسی، هر زمان قابل‌فراخوانی —
///             هیأت را از نو به‌عنوان BOARD_SIZE (۵) ولیدیتوری که بیشترین رأی جاری را دارند
///             محاسبه می‌کند، فقط با شمردن رأی‌هایی که توسط ولیدیتورهای فعلاً فعال، به
///             ولیدیتورهای فعلاً فعال داده شده‌اند (هر دو طرف در هر refresh مستقیم و زنده در
///             برابر ValidatorsRegistry دوباره چک می‌شوند، پس یک ولیدیتوری که غیرفعال می‌شود
///             خودکار هم از رأی‌دادن هم از واجدشرایط‌بودن به‌عنوان کاندید باز می‌ماند، بدون
///             نیاز به مرحله‌ی جدای «عزل»).
///           - در صورت تساوی، اولویت با کاندیدی است که زودتر در شمارش دیده شده (ولیدیتورها به
///             ترتیب ValidatorsRegistry.getValidators()، رأی‌های هر رأی‌دهنده به ترتیب ثبتشان)
///             — یعنی در تساوی، اولی که رسیده برنده است.
///           - پاک‌سازی رأی‌های کهنه: اگر یک ولیدیتور بیشتر از
///             `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (۳۰ روز) بدون
///             بازگشت، در وضعیت Demoted (غیرفعال) بماند، هرکسی می‌تواند `clearStaleVotes` را
///             فراخوانی کند تا هر رأیی که او داده و هر رأیی که او گرفته پاک شود، و جای رأی
///             بقیه‌ی ولیدیتورها آزاد شود. قبل از آن نقطه‌ی ۳۰روزه، رأی‌های او در
///             `refreshBoard()` صرفاً دیگر شمرده نمی‌شوند (چون فعال نیست، از هر دو طرف شمارش
///             کنار گذاشته می‌شود) — برای این‌که این اثر بگذارد نیازی به پاک‌سازی نیست،
///             پاک‌سازی فقط برای آزادکردن storage/جای رأی است.
///
///         اختیارات تفویضی هیأت (بدون تغییر نسبت به قبل، همچنان محدود و صریح):
///           ۱. چرخش فوری کلید `distributionOracle` روی BlockRewardDistributor، با یک ثبت
///              شفاف on-chain (برای شرایط اضطراری کلید هک‌شده).
///           ۲. تصویب درخواست‌های روتین و کوچک بودجه‌ی خزانه، زیر یک سقف ثابت.
///           ۳. تنظیم سه پارامتر اقتصادی ورود روی ValidatorsRegistry — entryThresholdBase،
///              growthFactorPerValidator، membershipFeeBps (از مسیر رأی کامل ولیدیتورها خارج
///              شده چون رسیدن به اکثریت کامل ولیدیتورها در عمل با رشد جمعیت ولیدیتورها
///              سخت‌تر می‌شود، و انتظار می‌رود این پارامترها نیاز به تنظیم مکرر و به‌موقع
///              داشته باشند).
///
///         هیأت همچنان **نمی‌تواند** پارامترهای امنیتی دیگر و با اعتماد بالاتر (نرخ محدودیت
///         ورود، طول probation، آستانه‌ی لایوینس/غیرفعالی، دوره‌ی بازگشت، درصد اسلش، cooldown
///         خروج) یا هیچ آدرس قرارداد اصلی را تغییر دهد — این‌ها همیشه نیازمند رأی کامل
///         ولیدیتورها مستقیماً از طریق ValidatorsRegistry هستند، یا (برای آدرس قراردادهای
///         اصلی) یک دیپلوی مجدد کامل genesis، چون آن آدرس‌ها ثابت‌های compile-time هستند (به
///         SurAddresses.sol مراجعه کن). اقدامات فاجعه‌بار/اضطراری ساختاری صراحتاً **جزو
///         اختیارات هیأت نیستند**؛ نیازمند مسیرهای نصاب-بالاتر ولیدیتوری‌اند که در دفترچه‌ی
///         بازیابی سند طراحی مستند شده‌اند، نه یک تابع روی این قرارداد.
///
///         هر اقدام تفویضی هیأت (چرخش اوراکل، تصویب بودجه، تغییر پارامتر اقتصادی) همچنان
///         نیازمند رأی اکثریت داخلی بین اعضای فعلی هیأت است — هیچ عضو منفرد هیأتی نمی‌تواند
///         یک‌طرفه عمل کند. این کاملاً جدا از، و بی‌اثر از، مکانیزم رأی‌گیری عضویت هیأت
///         بالاست.
///
///         دیپلوی genesis: این قرارداد constructor ندارد — مستقیم در alloc genesis تزریق
///         می‌شود، پس constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود. هیأت اولیه (دقیقاً
///         BOARD_SIZE = ۵ عضو) به‌جایش با ابزار genesis آف‌چین seed می‌شود (یادداشت 🔶
///         پرکردنِ genesis پایین را ببین)، به‌جای یک انتخابات جدای بعد از دیپلوی. آدرس‌های
///         BlockRewardDistributor، ValidatorsTreasury، و ValidatorsRegistry ثابت هستند (به
///         SurAddresses.sol مراجعه کن)، نه یک مرحله‌ی اجرایی `wire()`، چون هر پنج قرارداد
///         ساختاری یک نقشه‌ی آدرس مشترک و از‌پیش‌توافق‌شده در genesis دارند.
contract ValidatorsBoard {
    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------
    address public constant DISTRIBUTOR = SurAddresses.BLOCK_REWARD_DISTRIBUTOR;
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);
    IIdentityRegistry public constant IDENTITY_REGISTRY = IIdentityRegistry(SurAddresses.IDENTITY_REGISTRY);

    /// @notice اندازه‌ی ثابت هیأت — همیشه دقیقاً همین تعداد کرسی (فقط به‌طور گذرا کمتر، اگر
    ///         تا الان کمتر از این تعداد کاندید اصلاً رأیی گرفته باشند).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice حداکثر تعداد کاندیدی که یک ولیدیتور می‌تواند هم‌زمان رأی بدهد.
    uint256 public constant MAX_VOTES_PER_VOTER = 5;

    /// @notice چقدر بعد از پایان دوره‌ی بازگشت یک ولیدیتور (همچنان بدون بازگشت)، هرکسی می‌تواند
    ///         رأی‌های او (داده‌شده و گرفته‌شده) را از طریق clearStaleVotes پاک کند.
    uint256 public constant STALE_VOTE_CLEAR_DELAY = 30 days;

    // ------------------------------------------------------------------
    // عضویت هیأت (تصویر لحظه‌ای فعلی، تولیدشده توسط آخرین فراخوانی refreshBoard())
    //
    // 🔶 پرکردنِ genesis: این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis تزریق
    // می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). `boardMembers` یک آرایه‌ی
    // پویاست و `isBoardMember` یک mapping است — Solidity هیچ syntax ای برای پرکردن هیچ‌کدام با
    // یک حلقه خارج از تابع ندارد، پس این state اولیه (دقیقاً BOARD_SIZE = ۵ آدرس) اینجا
    // **نمی‌تواند** به‌صورت یک مقداردهی ساده‌ی متغیر state بیان شود. ابزار genesis آف‌چین
    // باید یا (الف) دیپلوی این قرارداد را با منطق constructor واقعی پایین، روی یک زنجیره‌ی
    // محلی موقت شبیه‌سازی کند و storage نتیجه را در فایل نهایی genesis کپی کند، یا (ب) مستقیم
    // storage slot های متناظر (طول آرایه + هر عنصر، و slot mapping هر عضو — از طریق
    // keccak256(abi.encode(key, slot)) برای mapping) را در alloc genesis محاسبه و بنویسد. برای
    // دستورالعمل کامل به "sur-contracts-deploy-notes.md" مراجعه کن.
    //
    // منطق مرجع (کد زنده نیست — برای این‌که ابزار genesis آن را، چه با شبیه‌سازی چه با
    // محاسبه‌ی مستقیم storage، بازتولید کند) — برای هرکدام از ۵ آدرس عضو اولیه‌ی هیأت:
    //   boardMembers.push(address);
    //   isBoardMember[address] = true;
    // ------------------------------------------------------------------
    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // ------------------------------------------------------------------
    // وضعیت رأی‌گیری تأییدی
    // ------------------------------------------------------------------

    /// @notice کاندیدهایی که یک رأی‌دهنده‌ی مشخص الان بهشان رأی می‌دهد (حداکثر MAX_VOTES_PER_VOTER).
    mapping(address => address[]) private voterCandidates;

    /// @notice رأی‌دهنده => کاندید => آیا آن رأی الان فعال است.
    mapping(address => mapping(address => bool)) public hasVotedFor;

    /// @notice اندیس معکوس: کاندید => لیست رأی‌دهندگانی که الان بهش رأی می‌دهند (لازم برای
    ///         پاک‌سازی کارآمد رأی‌های گرفته‌شده در clearStaleVotes).
    mapping(address => address[]) private candidateVoters;

    /// @notice اندیس یک‌مبنایی `voter` داخل `candidateVoters[candidate]`، برای حذف O(1).
    mapping(address => mapping(address => uint256)) private voterIndexInCandidateVoters;

    // ------------------------------------------------------------------
    // اقدامات داخلی هیأت (چرخش اوراکل، تصویب بودجه، پارامترهای اقتصادی)
    // ------------------------------------------------------------------
    enum ActionType { RotateOracle, ApproveBudget, SetEntryThresholdBase, SetGrowthFactorPerValidator, SetMembershipFeeBps, RotateVerifier }

    /// @dev ✅ تقویت‌شده (مرتبط با کلاس باگ رأی مانده‌شده‌ی پیداشده در بازبینی، هرچند اینجا
    ///      خفیف‌تره چون `required` همیشه از BOARD_SIZE ثابت میاد، نه یه تعداد کوچیک‌شونده):
    ///      بدون یه مهلت انقضا، یه اقدام هیأت‌مدیره می‌تونست به‌اندازه‌ای باز بمونه که ترکیب
    ///      هیأت‌مدیره‌ی اصلی (از طریق _recomputeBoard) قبل از رسیدن رأی کافی عوض بشه — یعنی
    ///      رأی‌های ثبت‌شده توسط اعضای سابقِ عوض‌شده می‌تونستن با رأی یه عضو فعلی ترکیب بشن و
    ///      به اکثریت برسن، حتی اگه هیچ‌وقت یه هیأت‌مدیره‌ی واقعی ۵نفره هم‌زمان روش توافق
    ///      نکرده باشه. `expiresAt` این پنجره رو محدود می‌کنه.
    /// @dev ✅ اصلاح‌شده (این قبلاً فقط نیمه‌کاره اصلاح شده بود — دور قبلی فقط `expiresAt`
    ///      اضافه کرد، ولی این استدلال غلط رو داشت که «نیازی به snapshot نداره چون همیشه از
    ///      BOARD_SIZE ثابت میاد». اون استدلال غلط بود: refreshBoard() پایین هیأت‌مدیره رو با
    ///      هرچقدر کاندیدای *مجزا* که حداقل یک رأی گرفته باشن پر می‌کنه، تا سقف BOARD_SIZE —
    ///      اگه کمتر از ۵ کاندیدا واجد شرایط باشن (واقع‌بینانه در اوایل عمر شبکه، یا بعد از
    ///      یه موج خروج ولیدیتور)، `boardMembers.length` واقعاً کمتر از ۵ است، و
    ///      `_voteAction()` مقدار `required` رو از همین طول زنده و کوچیک‌شونده حساب می‌کرد،
    ///      نه از ثابت. این دقیقاً همون کلاس باگ رأی-مانده‌شده‌ی بقیه‌ی مکانیزم‌های پیشنهاد
    ///      این پروژه‌ست: `votes` فقط زیاد می‌شه، درحالی‌که `required` می‌تونست بین دو رأی،
    ///      با رفرش هیأت‌مدیره، کوچیک بشه. `requiredVotes` حالا در لحظه‌ی ثبت snapshot می‌شه،
    ///      دقیقاً مثل ShareProposal در BlockRewardDistributor، ParamProposal در
    ///      ValidatorsRegistry، Expenditure/ParamProposal در ValidatorsTreasury، و Proposal در
    ///      FoundationDAO.
    struct BoardAction {
        ActionType atype;
        address target;      // آدرس اوراکل جدید، یا گیرنده‌ی بودجه (برای اقدامات پارامتر اقتصادی استفاده نمی‌شود)
        uint256 amount;       // مبلغ بودجه برای ApproveBudget، یا مقدار جدید برای اقدامات پارامتر اقتصادی
        string description;   // فقط برای ApproveBudget استفاده می‌شود
        uint256 votes;
        uint256 requiredVotes; // ✅ تازه — در لحظه‌ی ثبت snapshot می‌شه، هرگز دوباره حساب نمی‌شه
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        /// @notice ✅ اصلاح‌شده (باگی پیداشده در بازبینی مستقل — حیاتی مخصوصاً برای تصمیمات
        ///         خرج): `votes` قبلاً یه شمارنده‌ی ساده بود، بدون هیچ ارتباطی با این‌که کدوم
        ///         آدرس‌ها این رأی‌ها رو زدن یا آیا اون آدرس‌ها هنوز عضو هیأت‌مدیره‌ان یا نه.
        ///         چون refreshBoard() پایین می‌تونه کل عضویت هیأت‌مدیره رو کاملاً عوض کنه، یه
        ///         پیشنهاد ساخته‌شده و نیمه‌رأی‌گرفته زیر هیأت‌مدیره‌ی **قدیمی** همچنان می‌تونست
        ///         به نصابش برسه با استفاده از رأی‌های اعضایی که از اون‌موقع خارج شدن — مثلاً
        ///         دو عضو سابق رأی می‌دن، بعد refreshBoard() جایگزینشون می‌کنه، بعد فقط **یه**
        ///         عضو فعلی رأی «سوم» رو می‌زنه، و اقدام با فقط ۱ رأی از ۳ رأی شمرده‌شده که واقعاً
        ///         از یه عضو *فعلی* هیأت‌مدیره اومده، اجرا می‌شه. اصلاح شد با snapshot‌کردن
        ///         شماره‌ی نسخه‌ی هیأت‌مدیره اینجا در لحظه‌ی ثبت، و باطل‌کردن (نیاز به پیشنهاد
        ///         تازه برای) هر اقدامی که نسخه‌اش دیگه با نسخه‌ی فعلی یکی نیست — boardVersion
        ///         پایین و چک _voteAction() را ببین.
        uint256 boardVersionAtCreation;
    }

    uint256 public constant BOARD_ACTION_EXPIRY = 14 days;

    /// @notice ✅ **فقط** وقتی افزایش پیدا می‌کنه که refreshBoard() پایین عضویتی نصب کنه که
    ///         (به‌عنوان یک **مجموعه**، مستقل از ترتیب) واقعاً با قبلی فرق داشته باشه. refreshBoard
    ///         ای که دقیقاً همون مجموعه‌ی اعضا را دوباره تولید کنه، آن را افزایش **نمی‌دهد**. (یه
    ///         نسخه‌ی قبلی روی هر refresh افزایش می‌داد؛ چون refreshBoard() بدون نیاز به مجوز و
    ///         بدون cooldown است، این به هرکسی اجازه می‌داد اقدامات باز را هر زمان بخواهد باطل
    ///         کند — یه بردار آزار بی‌پایان و تکرارپذیر، پیداشده در بازبینی مستقل و با مقایسه‌ی
    ///         مجموعه در refreshBoard() اصلاح‌شده.) هر اقدام باز نسخه‌ای را که تحتش پیشنهاد شده
    ///         ثبت می‌کند و وقتی نسخه جلو برود باطل می‌شود — boardVersionAtCreation را ببینید.
    uint256 public boardVersion = 1;

    /// @notice P01: تغییر **عادی** ترکیب هیأت (refreshBoard) حداکثر هر ۳۰ روز یک‌بار اعمال می‌شود.
    uint256 public constant BOARD_REFRESH_INTERVAL = 30 days;
    /// @notice زمان آخرین بازتعیین عادی. اگر هیأت در genesis seed شود، genesis باید این را با timestamp genesis overlay کند
    ///         (وگرنه اولین refresh فوراً مجاز است).
    uint256 public lastBoardRefreshAt;
    /// @notice کرسی‌های آزادشده به‌علت قطع اختیار ناشی از خروج که هنوز با جانشینی پر نشده‌اند.
    uint256 public pendingVacancies;
    event BoardMemberAuthorityEnded(address indexed member);
    event BoardSuccession(address indexed newMember);

    mapping(uint256 => BoardAction) public actions;
    mapping(uint256 => mapping(address => bool)) private actionHasVoted;
    uint256 public actionCount;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event VoteCast(address indexed voter, address indexed candidate);
    event VoteWithdrawn(address indexed voter, address indexed candidate);
    event BoardRefreshed(address[] newBoard, uint256[] voteCounts);
    event StaleVotesCleared(address indexed validator, uint256 votesGivenCleared, uint256 votesReceivedCleared);
    event ActionProposed(uint256 indexed id, ActionType atype, address indexed target, uint256 amount, address indexed proposer);
    event ActionVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event OracleRotated(address indexed newOracle);
    event BudgetApproved(address indexed to, uint256 amount, string description);
    event RegistryEconomicParamSet(ActionType indexed atype, uint256 newValue);
    event VerifierRotated(address indexed newVerifier);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsBoard: caller is not an active validator");
        _;
    }

    /// @notice P02: اختیار هیأت = داشتن کرسی **و** درخواست‌نکردنِ خروج اختیاری. لحظه‌ی ثبت درخواست خروج قطع می‌شود (منتظر
    ///         بازتعیین ماهانه نمی‌ماند). تعلیق (Demoted) به‌تنهایی اختیار را در طول دوره قطع **نمی‌کند**. اگر دارنده‌ی یک کرسی
    ///         درخواست خروج داده و کرسی هنوز پاک‌سازی نشده، اقدامات هیأت با پیام روشن **revert** می‌شوند تا کسی
    ///         `syncBoard()` (بدون نیاز به مجوز، تراکنش جدا — پس خودِ پاک‌سازی هرگز برگردانده نمی‌شود) را صدا بزند. یعنی رأی هرگز
    ///         روی پیشنهاد باطل‌شده «بی‌صدا موفق» نمی‌شود: voteAction() را ببینید.
    modifier onlyBoardMember() {
        require(_hasAuthority(msg.sender), "ValidatorsBoard: caller has no board authority");
        require(!_syncNeeded(), "ValidatorsBoard: a seat holder has requested exit - call syncBoard() first");
        _;
    }

    // ------------------------------------------------------------------
    // رأی‌گیری تأییدی برای عضویت هیأت
    // ------------------------------------------------------------------

    /// @notice رأی موافق به `candidate` برای عضویت در هیأت. توسط هر ولیدیتور فعالی، برای هر
    ///         ولیدیتور فعال دیگری قابل‌فراخوانی است (خودرأیی مجاز است — هیچ چیز خاصی درباره‌ش
    ///         نیست). فقط وقتی کسی refreshBoard() را فراخوانی کند اثر می‌گذارد.
    function voteFor(address candidate) external onlyActiveValidator {
        require(IDENTITY_REGISTRY.hasIdentity(msg.sender), "ValidatorsBoard: register identity before voting");
        require(REGISTRY.isValidator(candidate), "ValidatorsBoard: candidate is not an active validator");
        require(!hasVotedFor[msg.sender][candidate], "ValidatorsBoard: already voted for this candidate");
        require(voterCandidates[msg.sender].length < MAX_VOTES_PER_VOTER, "ValidatorsBoard: max votes already used");

        hasVotedFor[msg.sender][candidate] = true;
        voterCandidates[msg.sender].push(candidate);

        candidateVoters[candidate].push(msg.sender);
        voterIndexInCandidateVoters[candidate][msg.sender] = candidateVoters[candidate].length; // یک‌مبنایی

        emit VoteCast(msg.sender, candidate);
    }

    /// @notice پس‌گرفتن یک رأی قبلاً داده‌شده. هر زمان، بدون محدودیت قابل‌فراخوانی است.
    function unvoteFor(address candidate) external {
        require(hasVotedFor[msg.sender][candidate], "ValidatorsBoard: no such active vote");
        _removeVote(msg.sender, candidate);
    }

    function _removeVote(address voter, address candidate) private {
        hasVotedFor[voter][candidate] = false;

        address[] storage vc = voterCandidates[voter];
        for (uint256 i = 0; i < vc.length; i++) {
            if (vc[i] == candidate) {
                vc[i] = vc[vc.length - 1];
                vc.pop();
                break;
            }
        }

        address[] storage cv = candidateVoters[candidate];
        uint256 idx = voterIndexInCandidateVoters[candidate][voter]; // یک‌مبنایی
        uint256 lastIdx = cv.length;
        if (idx != lastIdx) {
            address lastVoter = cv[lastIdx - 1];
            cv[idx - 1] = lastVoter;
            voterIndexInCandidateVoters[candidate][lastVoter] = idx;
        }
        cv.pop();
        delete voterIndexInCandidateVoters[candidate][voter];

        emit VoteWithdrawn(voter, candidate);
    }

    /// @notice P01/P02: بازتعیین عادی — BOARD_SIZE ولیدیتوری که بیشترین رأی جاری را دارند، حداکثر هر ۳۰ روز یک‌بار اعمال
    ///         می‌شود (هیأتِ کاملاً خالی هر زمان قابل‌پرشدن است). ماندن در هیأت مشروط به **فعال‌بودنِ ولیدیتور در همین لحظه** است:
    ///         فقط رأی‌های ولیدیتورهای فعال به کاندیداهای فعال شمرده می‌شود، پس عضو معلق نمی‌تواند از بازتعیین ماهانه عبور کند.
    ///         رأی‌دادن و تغییر رأی همیشه آزاد است (voteFor / unvoteFor).
    function refreshBoard() external {
        require(
            boardMembers.length == 0 || block.timestamp >= lastBoardRefreshAt + BOARD_REFRESH_INTERVAL,
            "ValidatorsBoard: ordinary board changes are applied once every 30 days"
        );
        (address[] memory newBoard, uint256[] memory newBoardVotes, uint256 filled) = _topCandidates(BOARD_SIZE, false);

        // ✅ اصلاح‌شده (باگ پیداشده در بازبینی مستقل — نسخه‌ی قبلی این اصلاح boardVersion رو
        // بی‌قید و شرط توی هر فراخوان موفق refreshBoard() بالا می‌برد، حتی وقتی عضویت نهایی
        // عیناً با قبلش یکسان بود. چون این تابع بدون نیاز به مجوز و بدون هیچ cooldown ای هست،
        // هرکسی می‌تونست پیوسته صداش بزنه — حتی با صفر تغییر واقعی عضویت — فقط برای این‌که هر
        // اقدام هیأت‌مدیره‌ی باز و منتظر رأی رو مدام باطل کنه، یه بردار آزار بی‌پایان و
        // تکرارپذیر). مجموعه‌ی *واقعی* اعضا رو (مستقل از ترتیب) قبل از پاک‌کردن فلگ‌های
        // isBoardMember قدیمی پایین مقایسه می‌کنیم — فقط اگه عضویت واقعاً عوض شده باشه، نسخه
        // رو بالا می‌بریم.
        bool membershipChanged = (boardMembers.length != filled);
        if (!membershipChanged) {
            for (uint256 i = 0; i < filled; i++) {
                if (!isBoardMember[newBoard[i]]) {
                    membershipChanged = true;
                    break;
                }
            }
        }

        // اعمال: پاک‌کردن فلگ‌های عضویت قدیم، نصب مجموعه‌ی تازه
        for (uint256 i = 0; i < boardMembers.length; i++) {
            isBoardMember[boardMembers[i]] = false;
        }
        delete boardMembers;

        address[] memory finalBoard = new address[](filled);
        uint256[] memory finalVotes = new uint256[](filled);
        for (uint256 i = 0; i < filled; i++) {
            boardMembers.push(newBoard[i]);
            isBoardMember[newBoard[i]] = true;
            finalBoard[i] = newBoard[i];
            finalVotes[i] = newBoardVotes[i];
        }

        // ✅ اصلاح‌شده: نسخه‌ی هیأت‌مدیره رو فقط وقتی عضویت **واقعاً** عوض شده باشه (به
        // membershipChanged بالا مراجعه کن) بالا می‌بریم — پس هر اقدامی که زیر عضویت قدیمی
        // پیشنهاد و نیمه‌رأی‌گرفته شده، وقتی هیأت‌مدیره واقعاً عوض بشه درست باطل می‌شه، بدون
        // این‌که به هرکسی یه راه رایگان و تکرارپذیر برای باطل‌کردن اقدامات باز با صدازدن
        // refreshBoard() بدون هیچ اثر واقعی بدیم.
        if (membershipChanged) {
            boardVersion++;
        }


        lastBoardRefreshAt = block.timestamp;
        pendingVacancies = 0; // بازتعیین عادی کل هیأت را از نو محاسبه می‌کند؛ جای خالی‌ها منتقل نمی‌شوند

        emit BoardRefreshed(finalBoard, finalVotes);
    }

    /// @dev storage شمارش گذرای مخصوص هر فراخوانی refreshBoard(). همیشه بین فراخوانی‌ها صفر
    ///      است — حلقه‌ی ریست refreshBoard() را ببین. به‌عنوان storage قرارداد (نه `memory`)
    ///      اعلان شده، فقط چون Solidity هیچ نوع mapping در memory ندارد.
    mapping(address => uint256) private _voteTally;

    // ------------------------------------------------------------------
    // Authority, monthly re-selection, and exit-driven succession (final decisions P01/P02)
    // ------------------------------------------------------------------

    /// @dev آزمون اختیار P02 (کامنت مودیفایر onlyBoardMember را ببینید).
    function _hasAuthority(address who) private view returns (bool) {
        if (!isBoardMember[who]) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        return status != 0 && status != 4; // not None (withdrawn / never a validator), not Exiting
    }

    function hasBoardAuthority(address who) external view returns (bool) {
        return _hasAuthority(who);
    }


    /// @dev اگر دارنده‌ی یک کرسی اختیار را از دست داده (درخواست خروج داده / برداشت کرده) و syncBoard() هنوز اجرا نشده، true.
    function _syncNeeded() private view returns (bool) {
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (!_hasAuthority(boardMembers[i])) return true;
        }
        return false;
    }

    /// @notice بدون نیاز به مجوز. کرسی‌هایی را که دارنده‌شان درخواست خروج داده رها می‌کند (قطع فوری اختیار) و برای آن کرسی‌ها جانشینی را تلاش می‌کند.
    function syncBoard() external {
        _syncBoard();
    }

    function _syncBoard() private {
        uint256 removed = 0;
        uint256 i = 0;
        while (i < boardMembers.length) {
            address m = boardMembers[i];
            if (_hasAuthority(m)) {
                i++;
                continue;
            }
            isBoardMember[m] = false;
            boardMembers[i] = boardMembers[boardMembers.length - 1];
            boardMembers.pop();
            removed++;
            emit BoardMemberAuthorityEnded(m);
        }
        bool changed = removed > 0;
        if (removed > 0) {
            pendingVacancies += removed;
            if (_fillVacancies()) changed = true;
        }
        if (changed) boardVersion++; // real composition change: open actions of the old composition become invalid
    }

    /// @notice جانشینیِ بدون نیاز به مجوز برای کرسی‌های آزادشده به‌علت خروج: بالاترین‌رأی‌ترین کاندیداهای **واجد شرایط** (فعلاً فعال،
    ///         هنوز عضو نبوده) بر اساس شمارش زنده جای خالی‌های معلق را می‌گیرند. فقط کرسی‌های آزادشده به‌علت خروج را پر می‌کند —
    ///         هرگز یک تغییر عادی اضافه نیست. اگر کاندیدای واجد شرایطی نباشد کرسی خالی می‌ماند (و با کمتر از ۳ عضو دارای اختیار،
    ///         پرداخت خزانه متوقف است) تا کاندیدایی پیدا شود یا بازتعیین ماهانه برسد.
    function fillVacancies() external {
        if (_fillVacancies()) boardVersion++;
    }

    function _fillVacancies() private returns (bool filledAny) {
        uint256 room = BOARD_SIZE - boardMembers.length;
        uint256 want = pendingVacancies < room ? pendingVacancies : room;
        if (want == 0) return false;
        (address[] memory picks, , uint256 n) = _topCandidates(want, true);
        for (uint256 i = 0; i < n; i++) {
            boardMembers.push(picks[i]);
            isBoardMember[picks[i]] = true;
            emit BoardSuccession(picks[i]);
        }
        if (n > 0) {
            pendingVacancies -= n;
            return true;
        }
        return false;
    }

    /// @dev Live tally: votes cast BY currently active validators FOR currently active candidates (same rule as before).
    function _tallyVotes() private returns (address[] memory seenCandidates, uint256 seenCount) {
        address[] memory active = REGISTRY.getValidators();
        seenCandidates = new address[](active.length * MAX_VOTES_PER_VOTER);
        for (uint256 i = 0; i < active.length; i++) {
            address[] storage cands = voterCandidates[active[i]];
            uint256 n = cands.length;
            for (uint256 j = 0; j < n; j++) {
                address c = cands[j];
                if (!REGISTRY.isValidator(c)) continue; // candidate must currently be active too
                if (_voteTally[c] == 0) {
                    seenCandidates[seenCount] = c;
                    seenCount++;
                }
                _voteTally[c]++;
            }
        }
    }

    /// @dev Top-k candidates by live tally (ties keep the earlier-inserted one). Resets the ephemeral tally before returning.
    function _topCandidates(uint256 k, bool excludeMembers) private returns (address[] memory picks, uint256[] memory pickVotes, uint256 filled) {
        (address[] memory seen, uint256 seenCount) = _tallyVotes();
        picks = new address[](k);
        pickVotes = new uint256[](k);
        for (uint256 i = 0; i < seenCount && k > 0; i++) {
            address c = seen[i];
            if (excludeMembers && isBoardMember[c]) continue;
            uint256 v = _voteTally[c];
            if (filled < k) {
                picks[filled] = c;
                pickVotes[filled] = v;
                filled++;
            } else {
                uint256 minIdx = 0;
                for (uint256 m = 1; m < k; m++) {
                    if (pickVotes[m] < pickVotes[minIdx]) minIdx = m;
                }
                if (v > pickVotes[minIdx]) {
                    picks[minIdx] = c;
                    pickVotes[minIdx] = v;
                }
            }
        }
        for (uint256 i = 0; i < seenCount; i++) {
            _voteTally[seen[i]] = 0; // reset the ephemeral tally
        }
    }

    /// @notice پاک‌کردن هر رأیی که یک ولیدیتور طولانی‌مدت‌غیرفعال داده (به‌عنوان رأی‌دهنده) و
    ///         هر رأیی که گرفته (به‌عنوان کاندید)، تا جای رأی بقیه‌ی ولیدیتورها آزاد شود. بدون
    ///         نیاز به مجوز. نیاز دارد ولیدیتور حداقل به مدت
    ///         `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (۳۰ روز) پیوسته
    ///         در وضعیت Demoted مانده باشد. قبل از این نقطه، رأی‌های او از قبل در
    ///         refreshBoard() شمرده نمی‌شوند (بالا را ببین) — این تابع فقط storage/جای رأی را
    ///         آزاد می‌کند، خودش تغییری در ترکیب فعلی هیأت نمی‌دهد.
    function clearStaleVotes(address validator) external {
        (uint8 status, , , uint256 demotedAt, , ) = REGISTRY.getValidatorInfo(validator);
        require(status == 3, "ValidatorsBoard: validator is not currently demoted"); // ۳ = Status.Demoted
        uint256 threshold = demotedAt + REGISTRY.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY;
        require(block.timestamp >= threshold, "ValidatorsBoard: stale-vote delay not elapsed");

        address[] memory given = voterCandidates[validator];
        for (uint256 i = 0; i < given.length; i++) {
            _removeVote(validator, given[i]);
        }

        address[] memory received = candidateVoters[validator];
        for (uint256 i = 0; i < received.length; i++) {
            _removeVote(received[i], validator);
        }

        emit StaleVotesCleared(validator, given.length, received.length);
    }

    // ------------------------------------------------------------------
    // اقدامات داخلی هیأت — رأی اکثریت بین اعضای فعلی هیأت
    // ------------------------------------------------------------------
    function proposeRotateOracle(address newOracle) external onlyBoardMember returns (uint256 id) {
        require(newOracle != address(0), "ValidatorsBoard: zero oracle address");
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "", 0);
    }

    /// @notice ✅ تضمین تازه (تصمیم صریح کاربر): برخلاف هر اقدام دیگه‌ی هیأت‌مدیره، یه پیشنهاد
    ///         ApproveBudget نیاز به یه **حداقل سخت ۳ رأی موافق** داره، صرف‌نظر از این‌که
    ///         هیأت‌مدیره‌ی فعلی چقدر کوچیک شده باشه (مثلاً با فقط ۳ عضو، فرمول اکثریت ساده
    ///         فقط ۲ تا لازم داشت — کافی نیست برای یه تصمیم خرج). اگه کمتر از ۳ عضو واجد شرایط
    ///         هیأت‌مدیره الان وجود داشته باشه، خرج کاملاً متوقف می‌شه (این تابع revert می‌کنه)
    ///         تا ترکیب هیأت‌مدیره حداقل به ۳ برگرده — هیچ نصاب کوچیک‌تری هرگز نمی‌تونه یه
    ///         پرداخت رو تصویب کنه، هرچقدرم فوری باشه.
    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        require(boardMembers.length >= 3, "ValidatorsBoard: fewer than 3 board members - spending halted");
        id = _createAction(ActionType.ApproveBudget, to, amount, description, 3);
    }

    /// @notice پیشنهاد یک entryThresholdBase تازه روی ValidatorsRegistry (پارامتر اقتصادی
    ///         ورود — تحت حکمرانی هیأت؛ کامنت مستندات سطح قرارداد را ببین).
    function proposeSetEntryThresholdBase(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryThresholdBase, address(0), newValue, "", 0);
    }

    /// @notice پیشنهاد یک growthFactorPerValidator تازه روی ValidatorsRegistry (fixed-point، ۱۸
    ///         رقم اعشار؛ باید > ۱.۰ باشد، یعنی > 1_000000000000000000).
    function proposeSetGrowthFactorPerValidator(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue > 1_000000000000000000, "ValidatorsBoard: growth factor must be > 1.0");
        id = _createAction(ActionType.SetGrowthFactorPerValidator, address(0), newValue, "", 0);
    }

    /// @notice پیشنهاد یک membershipFeeBps تازه روی ValidatorsRegistry.
    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "", 0);
    }

    /// @notice پیشنهاد چرخش کلید احراز هویت (`verifier`) روی ValidatorsRegistry — یک چرخش
    ///         روتین کلید عملیاتی، دقیقاً همان الگوی proposeRotateOracle.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "", 0);
    }

    function voteAction(uint256 id) external onlyBoardMember {
        // اقدامی که زیر ترکیب قدیمی‌تر پیشنهاد شده باطل است: _voteAction() **revert** می‌کند («board membership changed since this
        // action was proposed - propose again»). تراکنش آشکارا شکست می‌خورد و به‌صورت no-op برنمی‌گردد، تا هیچ‌کس رسید موفق را
        // با «رأی من ثبت شد» اشتباه نگیرد.
        _voteAction(id, msg.sender);
    }

    /// @notice ✅ پارامتر تازه (تصمیم صریح کاربر — ApproveBudget به‌طور خاص هرگز نباید با
    ///         کمتر از ۳ رأی موافق اجرا بشه، حتی اگه هیأت‌مدیره از اندازه‌ی کاملش (۵ نفر)
    ///         کوچیک‌تر شده باشه). `minRequiredVotes` برای هر نوع اقدام *دیگه* صفره (یعنی «از
    ///         فرمول اکثریت ساده استفاده کن، بدون حداقل اضافه») و فقط برای ApproveBudget ۳ه —
    ///         به proposeApproveBudget پایین مراجعه کن که چرا خرج به‌طور خاص به این حداقل
    ///         سخت‌گیرانه‌تر نیاز داره درحالی‌که اقدامات روتینی مثل چرخش کلید نیازی ندارن.
    function _createAction(ActionType atype, address target, uint256 amount, string memory description, uint256 minRequiredVotes) private returns (uint256 id) {
        uint256 majority = (boardMembers.length / 2) + 1;
        actionCount++;
        id = actionCount;
        actions[id] = BoardAction({
            atype: atype,
            target: target,
            amount: amount,
            description: description,
            votes: 0,
            requiredVotes: majority > minRequiredVotes ? majority : minRequiredVotes, // ✅ حداقل
            // سخت، همین لحظه از اندازه‌ی *واقعی* فعلی هیأت‌مدیره ثابت‌شده — به کامنت بالا مراجعه کن
            createdAt: block.timestamp,
            expiresAt: block.timestamp + BOARD_ACTION_EXPIRY,
            executed: false,
            boardVersionAtCreation: boardVersion
        });
        emit ActionProposed(id, atype, target, amount, msg.sender);
        _voteAction(id, msg.sender);
    }

    function _voteAction(uint256 id, address voter) private {
        BoardAction storage a = actions[id];
        require(a.createdAt != 0, "ValidatorsBoard: action not found");
        require(!a.executed, "ValidatorsBoard: already executed");
        require(block.timestamp <= a.expiresAt, "ValidatorsBoard: action has expired");
        // ✅ اصلاح‌شده (باگ پیداشده در بازبینی مستقل — به کامنت boardVersionAtCreation توی
        // struct BoardAction بالا مراجعه کن): اگه عضویت هیأت‌مدیره از وقتی این اقدام پیشنهاد
        // شده عوض شده باشه، باطل می‌شه — رأی‌دهنده‌ها باید دوباره زیر هیأت‌مدیره‌ی فعلی
        // پیشنهادش بدن. این دقیقاً همون چیزیه که واقعاً جلوی شمرده‌شدن رأی‌های مانده از اعضای
        // سابق (که قبل از خروج رأی داده بودن) توی تصمیمات یه هیأت‌مدیره‌ی تازه رو می‌گیره؛
        // فقط چک‌کردن `isBoardMember` در لحظه‌ی رأی (که از قبل بود) کافی نبود، چون فقط
        // رأی‌دهنده‌ی *فعلی* رو معتبر می‌کنه، نه رأی‌های تاریخی‌ای که قبلاً شمرده شدن.
        require(a.boardVersionAtCreation == boardVersion, "ValidatorsBoard: board membership changed since this action was proposed - propose again");
        require(!actionHasVoted[id][voter], "ValidatorsBoard: already voted");

        actionHasVoted[id][voter] = true;
        a.votes++;

        emit ActionVoted(id, voter, a.votes, a.requiredVotes);

        if (a.votes >= a.requiredVotes) {
            a.executed = true;
            if (a.atype == ActionType.RotateOracle) {
                IBlockRewardDistributor(DISTRIBUTOR).setDistributionOracle(a.target);
                emit OracleRotated(a.target);
            } else if (a.atype == ActionType.ApproveBudget) {
                // ✅ تازه: دوباره در لحظه‌ی *اجرا* چک می‌شه، نه فقط لحظه‌ی پیشنهاد — تصمیم
                // کاربر صریحاً «اعضای فعلی» رو گفته، یعنی حتی اگه این اقدام از قبل، وقتی
                // هیأت‌مدیره هنوز ≥۳ عضو داشت، رأی لازمش رو جمع کرده باشه، اجرا باید همچنان
                // متوقف بشه اگه هیأت‌مدیره از اون‌موقع تا این رأی نهایی به کمتر از ۳ رسیده
                // باشه. کل تراکنش رأی (شامل همین رأی) در این حالت revert می‌شه، پس هیچ‌چیزی
                // بی‌صدا رد یا ناقص ثبت نمی‌شه — اول باید ترکیب هیأت‌مدیره درست بشه.
                require(boardMembers.length >= 3, "ValidatorsBoard: fewer than 3 board members - spending halted");
                IValidatorsTreasury(TREASURY).boardApproveExpenditure(a.target, a.amount, a.description);
                emit BudgetApproved(a.target, a.amount, a.description);
            } else if (a.atype == ActionType.SetEntryThresholdBase) {
                REGISTRY.setEntryThresholdBase(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetGrowthFactorPerValidator) {
                REGISTRY.setGrowthFactorPerValidator(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetMembershipFeeBps) {
                REGISTRY.setMembershipFeeBps(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.RotateVerifier) {
                REGISTRY.setVerifier(a.target);
                emit VerifierRotated(a.target);
            }
        }
    }

    // ------------------------------------------------------------------
    // توابع کمکی view
    // ------------------------------------------------------------------
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }

    function getBoardSize() external view returns (uint256) {
        return boardMembers.length;
    }

    function getVotesOf(address voter) external view returns (address[] memory) {
        return voterCandidates[voter];
    }

    function getVotersFor(address candidate) external view returns (address[] memory) {
        return candidateVoters[candidate];
    }
}
