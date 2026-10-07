// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
    function statusNonce() external view returns (uint256);
    function wasActiveAt(address who, uint256 nonce) external view returns (bool);
    function everActivated(address who) external view returns (bool); // پرچم دائمی: درست است اگر آدرس هرگز به‌طور مشروع فعال شده باشد
    function getActiveValidatorCount() external view returns (uint256); // برای آستانه‌ی دوسوم مجمع در رأی‌گیری تغییر سهم
}

/// @notice اینترفیس حداقلی روی ValidatorsBoard برای چک اختیار هیأت‌مدیره در رأی‌گیری‌های دومجلسی پایین
///         (به proposeShareChange و proposeRateChange مراجعه کنید).
interface IValidatorsBoard {
    function isBoardMember(address who) external view returns (bool);
    /// @dev اختیار «زنده» — بلافاصله پس از requestExit() نادرست می‌شود، حتی وقتی پرچم خام
    ///      کرسی (isBoardMember) تا اجرای syncBoard() هنوز درست است. عضو معلق (Demoted) تا پایان ماهِ هیأت اختیارش را حفظ
    ///      می‌کند. Distributor دقیقاً به همین تعریف تکیه می‌کند و آن را دوباره پیاده نمی‌کند.
    function hasBoardAuthority(address who) external view returns (bool);
    /// @dev ValidatorsBoard این عدد را فقط با تغییر واقعی ترکیب (refresh/sync/جانشینی) بالا می‌برد، نه با refreshی
    ///      که ترکیب را تغییر نمی‌دهد.
    function boardVersion() external view returns (uint256);
}

/// @title BlockRewardDistributor
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.BLOCK_REWARD_DISTRIBUTOR
///         (0x2222...2222) — همان آدرسی که باید به‌عنوان `qbft.miningbeneficiary` در
///         genesis.json تنظیم شود. بلاک‌ریوارد و فی تراکنش‌ها را به‌طور خودکار و در سطح
///         پروتکل از شبکه دریافت می‌کند (طبق آزمایش تجربی، این یک اعتبار مستقیم روی
///         state-trie است، بدون فراخوانی EVM، بدون event؛ به «یافته‌های آزمایش Besu QBFT»،
///         آزمایش ۱ مراجعه کن) و به‌صورت دوره‌ای، بر اساس داده‌ی گزارش‌شده توسط یک اوراکل
///         مجاز، بین ولیدیتورها و ValidatorsTreasury توزیع می‌کند.
///
///         قواعد توزیع (به sur-tokenomics.md بخش‌های ۶.۵، ۶ و ۱۱ برای استدلال اقتصادی و حکمرانی
///         هر بخش مراجعه کنید):
///           - از کل ریوارد: سهم ۱۵٪ بنیاد (FOUNDATION_SHARE_BPS) مستقیم از بالای کل ریوارد کسر
///             می‌شود — ثابت، خودکار، بدون رأی‌گیری، و عمداً به‌عنوان درصدی از هیچ‌چیز دیگری
///             محاسبه نمی‌شود تا درآمد بنیاد با تغییر نسبت خزانه/ولیدیتور پایین جابه‌جا نشود.
///           - از ۸۵٪ باقی‌مانده، تقسیم بین ولیدیتورها (مستقیم، به‌نسبت بلاک) و
///             ValidatorsTreasury توسط `validatorDirectShareBps` حکمرانی می‌شود: قابل‌تغییر فقط از
///             طریق رأی‌گیری دومجلسی (proposeShareChange/boardVoteShareChange/
///             validatorVoteShareChange)، محدود به بازه‌ی [۴۰٪, ۶۵٪] از کل ریوارد، با دوره‌ی
///             خنک‌سازی اجباری ۶ماهه بین تغییرات موفق. هر دو مجلس — اکثریت ساده‌ی ValidatorsBoard
///             **و** اکثریت دوسوم کل مجمع ولیدیتورهای فعال — باید مستقلاً همان یک پیشنهاد را
///             تصویب کنند تا اجرا شود. این از انگیزه‌های متضاد دو مجلس (ولیدیتورهای عادی به سمت
///             سهم مستقیم بزرگ‌تر کشیده می‌شوند؛ هیأت‌مدیره به سمت خزانه‌ی بزرگ‌تر، چون خزانه‌ی
///             بزرگ‌تر یعنی اختیار خرج صلاحدیدی بیشتر) به‌عنوان بازدارنده‌ی داخلی در برابر
///             تخلیه‌ی یک‌طرفه‌ی سهم دیگری در طول زمان استفاده می‌کند.
///           - از کل فی معمولی (نه کارمزد عضویت — پایین را ببینید): یک ۳۰٪ ثابت (FEE_BURN_BPS)
///             هر epoch برای همیشه سوزانده می‌شود (به BURN_ADDRESS = address(0) فرستاده می‌شود)؛
///             ۷۰٪ باقی‌مانده به نسبت بلاک تولیدی بین ولیدیتورها تقسیم می‌شود (بدون سهم خزانه
///             یا بنیاد از بخش توزیع‌شده). به کامنت FEE_BURN_BPS و sur-tokenomics.md بخش ۷
///             مراجعه کنید که چرا فی (نه ریوارد) هدف سوزاندن است و چرا ۳۰٪.
///           - کارمزد عضویت معلق: ValidatorsRegistry.requestMembership() کارمزد عضویت را از طریق
///             receiveMembershipFee() به همین قرارداد می‌فرستد، جایی که در `pendingMembershipFees`
///             انباشته و در *epoch بعدی* به استخر فی اضافه می‌شود: کاملاً از سوزاندن ۳۰٪ معاف
///             (۱۰۰٪ آن به ولیدیتورها می‌رسد) و از نظر تقسیم مثل فی معمولی به‌نسبت بلاک
///             پرداخت می‌شود — به sur-tokenomics.md بخش ۶ مراجعه کنید: این یک انگیزه‌ی نقدی
///             مستقیم و قابل‌ردیابی به ولیدیتورهای موجود برای هر ولیدیتور تازه‌ای که می‌پیوندد
///             می‌دهد. پس کارمزد عضو تازه در همان بلاک ثبت‌نامش پرداخت نمی‌شود، بلکه در epoch
///             بعدی distributionOracle (~۲۳ ساعت بعد) پرداخت می‌شود.
///           - هر ولیدیتور دقیقاً یک پرداخت در هر فراخوانی دریافت می‌کند (یک انتقال ترکیبی
///             از سهم ریوارد + سهم فی، که «سهم فی» شامل هر کارمزد عضویت معلقِ تجمیع‌شده در
///             همان epoch هم می‌شود).
///
///         صلاحیت ولیدیتور مستقیم و on-chain در برابر ValidatorsRegistry چک می‌شود — هیچ
///         لیست سفید داخلی و هیچ اوراکل همگام‌سازی جداگانه‌ای وجود ندارد: ValidatorsRegistry
///         مرجع واحد هم برای اجماع هم برای پرداخت است.
///
///         دیپلوی genesis: این قرارداد constructor ندارد — مستقیم در alloc genesis تزریق
///         می‌شود، پس constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود. آدرس‌های
///         ValidatorsRegistry، ValidatorsTreasury، و ValidatorsBoard ثابت (constant) هستند
///         (به SurAddresses.sol مراجعه کن)، چون هر شش قرارداد ساختاری یک نقشه‌ی آدرس مشترک و
///         از‌پیش‌توافق‌شده در genesis دارند. کلید اولیه‌ی distributionOracle (یک اعتبارنامه‌ی
///         عملیاتی واقعاً قابل‌چرخش، نه یک قرارداد ساختاری) به‌جایش با ابزار genesis آف‌چین پر
///         می‌شود (یادداشت پرکردنِ genesis پایین را ببین، و "sur-contracts-deploy-notes.md").
contract BlockRewardDistributor {
    // ------------------------------------------------------------------
    // ثابت‌ها و تنظیمات
    // ------------------------------------------------------------------

    /// @notice سهم بنیاد از کل ریوارد (نه از هیچ زیرمجموعه‌ای) — بیسیس‌پوینت از ۱۰۰۰۰ = ۱۰۰٪.
    ///         برای همیشه ثابت، مستقیم روی totalRewards اعمال می‌شود، و عمداً
    ///         مستقل از validatorDirectShareBps پایین — به sur-tokenomics.md بخش ۶.۵ و کامنت
    ///         سطح قرارداد بالا مراجعه کنید که چرا این باید از نسبت حکمرانی‌شونده‌ی
    ///         خزانه/ولیدیتور جدا بماند.
    uint256 public constant FOUNDATION_SHARE_BPS = 1500; // ۱۵٪ از کل ریوارد، همیشه

    /// @notice سهم مستقیم و به‌نسبت‌بلاک ولیدیتورها از کل ریوارد — بیسیس‌پوینت از ۱۰۰۰۰. از ۵۰٪ شروع
    ///         می‌شود و یک متغیر state حکمرانی‌شونده است، فقط از طریق رأی‌گیری دومجلسی پایین
    ///         (proposeShareChange / boardVoteShareChange / validatorVoteShareChange) قابل‌تغییر،
    ///         محدود به [VALIDATOR_SHARE_MIN_BPS, VALIDATOR_SHARE_MAX_BPS]. ValidatorsTreasury هرچه بعد
    ///         از سهم ثابت ۱۵٪ بنیاد و این سهم باقی بماند را دریافت می‌کند:
    ///         treasuryShare = 10000 - FOUNDATION_SHARE_BPS - validatorDirectShareBps.
    uint256 public validatorDirectShareBps = 5000; // ۵۰٪ در ابتدا

    uint256 public constant VALIDATOR_SHARE_MIN_BPS = 4000; // کف ۴۰٪
    uint256 public constant VALIDATOR_SHARE_MAX_BPS = 6500; // سقف ۶۵٪
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice بخش ثابتی از **فی معمولی تراکنش** (نه کارمزد عضویت — به کامنت
    ///         distributeRewards() مراجعه کن که چرا عمداً معاف است) که هر epoch، قبل از توزیع
    ///         ۷۰٪ باقی‌مانده بین ولیدیتورها، برای همیشه سوزانده می‌شود. به
    ///         sur-tokenomics.md بخش ۷ برای استدلال کامل مراجعه کن: چون
    ///         منبع غالب تورم سورن خودِ ریوارد است نه فی، سوزاندن فی به‌تنهایی تورم را خنثی
    ///         نمی‌کند، ولی یک مکانیزم کمیابی مرتبط با کاربرد واقعی می‌سازد — نزدیک‌ترین
    ///         معادلی که طراحی `gasPrice` ثابت این پروژه (نه پویا مثل EIP-1559) اجازه می‌دهد،
    ///         بدون قربانی‌کردن هدف «هزینه‌ی قابل‌پیش‌بینی به سورن».
    uint256 public constant FEE_BURN_BPS = 3000; // ۳۰٪

    /// @notice سوزاندن سورن بومی یعنی ارسالش به آدرس صفر — هیچ کلید خصوصی‌ای برایش وجود
    ///         ندارد، پس هر مبلغ ارسال‌شده اینجا برای همیشه و به‌طور قابل‌راستی‌آزمایی
    ///         بازیابی‌ناپذیر است. یک انتقال ساده به address(0) روی Besu/EVM دقیقاً مثل
    ///         انتقال به هر حساب برون‌زنجیره‌ی دیگری موفق می‌شود.
    address public constant BURN_ADDRESS = address(0);

    /// @notice مجموع تجمعی سورن سوزانده‌شده از فی از زمان دیپلوی — برای داشبوردهای آف‌چین و
    ///         حسابرسی (مثل totalDistributedToValidators/Treasury/Foundation پایین).
    uint256 public totalFeesBurned;

    /// @notice حداقل فاصله‌ی مجاز بین دو فراخوانی متوالی توزیع.
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 23 hours;

    // تعداد بلاک هر توزیع با کنترل بازه‌ی _settleRange محدود می‌شود، نه با زمان سپری‌شده.

    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — دریافت‌کننده‌ی هرچه از استخر ریوارد باقی بماند بعد از کسر
    ///         سهم ثابت ۱۵٪ بنیاد و سهم مستقیم حکمرانی‌شونده‌ی ولیدیتورها (دیگر یک «سهم ثابت
    ///         ۵۰٪» نیست — به validatorDirectShareBps مراجعه کن).
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice FoundationDAO — سهم خودکار ۱۵٪ از کل ریوارد را هر epoch دریافت می‌کند
    ///         (FOUNDATION_SHARE_BPS، مستقیم از بالای کل کسر می‌شود — به کامنت هدر بالا مراجعه
    ///         کن که چرا عمداً به‌عنوان درصدی از سهم خزانه محاسبه نمی‌شود). این تنها اتصال
    ///         ورودی بنیاد به جریان ریوارد است؛ هیچ‌وقت نیازی به فراخوانی چیزی برای دریافتش
    ///         ندارد (کامنت‌های FoundationDAO.sol را ببینید).
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @notice ValidatorsRegistry تنها آدرسی است که مجاز به ارسال کارمزد عضویت معلق از
    ///         طریق receiveMembershipFee() پایین است.
    address public constant REGISTRY_ADDRESS = SurAddresses.VALIDATORS_REGISTRY;

    /// @notice ValidatorsBoard — تنها آدرس مجاز به چرخش distributionOracle (یک اختیار تفویضی
    ///         که صریح به هیأت داده شده؛ بخش ۴ سند طراحی را ببین).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    /// @notice ValidatorsRegistry — مرجع واحد صلاحیت ولیدیتور، مستقیم در هر پرداخت چک می‌شود،
    ///         بدون اوراکل واسط.
    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice نمای فقط‌خواندنی روی ValidatorsBoard برای چک اختیار هیأت‌مدیره در رأی‌گیری‌های دومجلسی پایین.
    IValidatorsBoard public constant BOARD_CONTRACT = IValidatorsBoard(SurAddresses.VALIDATORS_BOARD);

    /// @notice معادل ValidatorsBoard.BOARD_SIZE — هیأت‌مدیره همیشه دقیقاً همین تعداد عضو
    ///         دارد، پس اکثریت ساده یعنی BOARD_SIZE/2 + 1 (یعنی ۳ از ۵).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice حداقل فاصله‌ی زمانی بین دو تغییر موفق متوالی validatorDirectShareBps —
    ///         عمداً کند (~۶ ماه) تا این پارامتر نتواند به‌سرعت و پشت‌سرهم توسط هیچ‌کدام از دو
    ///         مجلس تکان بخورد. به sur-tokenomics.md بخش ۱۱ مراجعه کنید که چرا.
    uint256 public constant SHARE_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastShareChangeTime;


    /// @notice آدرس اوراکلی که مجاز به فراخوانی تابع توزیع دوره‌ای است. تنها وظیفه‌اش گزارش
    ///         تعداد بلاک و مجموع ریوارد/فی است؛ نمی‌تواند به هیچ آدرسی که ValidatorsRegistry
    ///         الان به‌عنوان فعال نمی‌شناسد پرداخت کند.
    /// @dev آدرس اولیه‌ی distributionOracle، خوانده‌شده از SurAddresses.sol (منبع
    ///      واحد صحت برای هر چهار آدرس اوراکل — دلیلش را در آن فایل ببین).
    address public distributionOracle = SurAddresses.DISTRIBUTION_ORACLE;

    // این قرارداد هیچ immutableی ندارد؛ پس سازنده‌ی genesis چیزی برای patch در بایت‌کد ندارد.
    uint256 public lastDistributionTime;
    uint256 public epochCount;

    // ------------------------------------------------------------------
    // کنترل بازه: هر توزیع، بازه‌ی **واقعی** بلاک‌هایی را که تسویه می‌کند اعلام می‌کند؛ قرارداد آخرین بلاک تسویه‌شده
    // را نگه می‌دارد و فقط بازه‌ای را می‌پذیرد که دقیقاً بعد از آن شروع شود. شماره‌ی افزایشی دوره به‌تنهایی کافی نیست —
    // کنترل به شماره‌ی واقعی بلاک‌ها متصل است، پس بازه‌ی تکراری، هم‌پوشان و دارای فاصله‌ی توضیح‌نداده‌شده رد می‌شود.
    // ------------------------------------------------------------------
    struct BlockRange {
        uint256 fromBlock;
        uint256 toBlock;
    }
    /// @notice بالاترین شماره‌ی بلاکی که قبلاً با یک توزیع تسویه شده (۰ = فقط genesis؛ اولین بازه باید از بلاک ۱ شروع شود).
    uint256 public lastSettledBlock;
    /// @notice بازه‌ی بلاکی که هر epoch تسویه کرده.
    mapping(uint256 => BlockRange) public epochBlockRanges;
    event EpochRangeSettled(uint256 indexed epochId, uint256 fromBlock, uint256 toBlock);

    bool private locked; // نگهبان ساده‌ی reentrancy

    // ------------------------------------------------------------------
    // 🔶 پرکردنِ genesis — این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis
    // تزریق می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). ابزار genesis آف‌چین
    // باید دیپلوی این قرارداد را (با دو مقدار واقعی بالا پرشده، روی یک زنجیره‌ی محلی موقت)
    // شبیه‌سازی کند و کد+storage نتیجه را در فایل نهایی genesis کپی کند. برای دستورالعمل
    // کامل به "sur-contracts-deploy-notes.md" مراجعه کن.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // ساختار گزارش‌گیری هر epoch
    // ------------------------------------------------------------------
    struct Epoch {
        uint256 timestamp;
        uint256 totalRewards;
        uint256 totalFees;
        uint256 treasuryAmount;
        uint256 totalBlocksMined;
        uint256 validatorCount;
    }

    mapping(uint256 => Epoch) public epochs;

    mapping(uint256 => mapping(address => uint256)) public epochValidatorRewardShare;
    mapping(uint256 => mapping(address => uint256)) public epochValidatorFeeShare;
    mapping(uint256 => mapping(address => uint256)) public epochValidatorBlocks;

    mapping(address => uint256) public totalRewardsPaid;
    mapping(address => uint256) public totalFeesPaid;
    mapping(address => uint256) public totalBlocksRecorded;

    uint256 public totalDistributedToValidators;
    uint256 public totalDistributedToTreasury;
    uint256 public totalDistributedToFoundation;

    /// @notice کارمزدهای عضویتی که ValidatorsRegistry از epoch توزیع قبلی تا الان فرستاده،
    ///         در انتظار تجمیع در استخر فی ۱۰۰٪-به‌نسبت-بلاک همان epoch. در انتهای هر
    ///         فراخوانی distributeRewards() صفر می‌شود.
    uint256 public pendingMembershipFees;

    /// @notice یک پیشنهاد دومجلسی برای تغییر validatorDirectShareBps. نیازمند تأیید
    ///         مستقل از **هردو**: اکثریت ساده‌ی ValidatorsBoard **و** اکثریت دوسوم کل مجمع
    ///         ولیدیتورهای فعال، پیش از اجرا شدن — به proposeShareChange/boardVoteShareChange/
    ///         validatorVoteShareChange پایین مراجعه کنید.
    /// @dev `requiredValidatorApprovals` فقط یک‌بار در لحظه‌ی ثبت پیشنهاد snapshot می‌شود (از
    ///      تعداد ولیدیتور فعال همان لحظه)، نه این‌که با هر رأی دوباره محاسبه شود. پس آستانه‌ای
    ///      که یک پیشنهاد باید از آن رد شود همان لحظه‌ی ثبتش قفل می‌شود: پیشنهادی که به نصاب
    ///      نرسیده بدون هیچ رأی تازه‌ای صرفاً به‌خاطر کوچک‌شدن شبکه قابل‌اجرا نمی‌شود. همراه با
    ///      `expiresAt`، پیشنهادی که در یک پنجره‌ی محدود به آستانه‌ی خودش نرسد منقضی می‌شود.
    struct ShareProposal {
        uint256 newValidatorShareBps;
        uint256 createdAt;
        uint256 expiresAt; // بعد از این، دیگر قابل‌رأی یا اجرا نیست
        uint256 requiredValidatorApprovals; // در لحظه‌ی ثبت snapshot می‌شود، هرگز دوباره محاسبه نمی‌شود
        uint256 boardApprovals;
        uint256 validatorApprovals;
        bool boardPassed;
        bool validatorPassed;
        bool executed;
        /// @dev مقدار ValidatorsBoard.boardVersion() هنگام ساخت پیشنهاد. رأی هیأت و اجرای نهایی
        ///      فقط تا وقتی پذیرفته می‌شوند که ترکیب هیأت همان باشد — همان قاعده‌ای که ValidatorsBoard برای اقدام‌های خودش
        ///      دارد (boardVersionAtCreation). تغییر واقعی ترکیب، پیشنهاد را باطل می‌کند و باید دوباره پیشنهاد شود.
        uint256 boardVersionAtCreation;
        // مقدار statusNonce در ValidatorsRegistry هنگام ساخت؛ رأی‌دهنده باید دقیقاً در همان نقطه Active بوده باشد.
        uint256 validatorNonceAtCreation;
    }

    /// @notice مدت زمانی که یه پیشنهاد بعد از ثبت هنوز قابل‌رأی/اجراست. عمداً به‌وضوح
    ///         کوتاه‌تر از SHARE_CHANGE_MIN_INTERVAL (۱۸۰ روز) — پیشنهادی که ظرف ۳۰ روز نتونه
    ///         رأی لازم رو جمع کنه، باید دوباره از نو (با یه snapshot تازه از جمعیت) ثبت بشه،
    ///         نه این‌که بی‌نهایت باز بمونه.
    uint256 public constant PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ShareProposal) public shareProposals;
    mapping(uint256 => mapping(address => bool)) private shareBoardVoted;
    mapping(uint256 => mapping(address => bool)) private shareValidatorVoted;
    uint256 public shareProposalCount;

    // تاریخچه‌ی نرخ مصوب پاداش بلاک، برای سقف totalRewards هر بازه‌ی تسویه.
    // نرخ اولیه‌ی INITIAL_REWARD_PER_BLOCK از بلاک ۱ تا اولین ورودی اعمال می‌شود. ورودی‌ها فقط‌افزودنی‌اند و فقط از نقطه‌ای «آینده»
    // اثر می‌گذارند؛ تاریخچه‌ی مؤثر گذشته هرگز بازنویسی نمی‌شود.
    //
    // هر ورودی از یک پیشنهاد ساخته می‌شود که لحظه‌ی اثر تغییر را به‌صورت یک TIMESTAMP یونیکس (`activationTime`؛ همان مقداری که
    // اپراتورها در `transitions.qbft` در genesis Besu می‌نویسند، و در genesis حالت Shanghai/Cancun آن فیلد timestamp است نه شماره
    // بلاک) همراه با یک ارتفاع شروع «برآوردی» می‌نامد. اولین بلاکی که timestamp آن برابر یا بیشتر از `activationTime` باشد از پیش
    // معلوم نیست؛ پس ورودی «موقت» است تا اوراکل توزیع ارتفاع واقعی شروع را با certifyRateStart گواهی کند. ارتفاع گواهی‌شده باید در
    // RATE_START_TOLERANCE_BLOCKS بلاکِ برآورد باشد.
    // تا وقتی ورودی موقت است، بلاک‌های داخل [برآورد − تحمل، برآورد + تحمل) با «بزرگ‌تر» از نرخ قدیم و جدید سقف می‌خورند؛ بلاک‌های
    // پیش از این پنجره نرخ قدیم و بلاک‌های از انتهای آن نرخ جدید را می‌گیرند. پس از گواهی، تغییر دقیقاً در بلاک گواهی‌شده است. بنابراین
    // سقف بازه هرگز شبکه‌ی درست‌پیکربندی‌شده را رد نمی‌کند و اثر اوراکل برای هر تغییر از تحمل × |نرخ جدید − نرخ قدیم| بیشتر نیست.
    // مرز اعتماد: این قرارداد نه پاداش واقعی بلاک در Besu را می‌خواند و نه زمان بلاک‌ها را. نرخ‌های مصوب و زمان‌های اثر باید از نظر
    // عملیاتی با transitionهای genesis شبکه هماهنگ نگه داشته شوند؛ این سقف صحت کارمزد، انتساب بلاک یا برابری نرخ ثبت‌شده با Besu را
    // اثبات نمی‌کند و فقط پاداش ناخالصی را که اوراکل می‌تواند برای یک بازه گزارش کند محدود می‌کند.
    // اگر اپراتورها transitionی تنظیم کنند که ارتفاع واقعی شروع آن بیرون از پنجره‌ی تحمل بیفتد، گواهی رد می‌شود و بازه‌هایی که
    // پاداش واقعی بلاک‌هایشان از نرخ مصوب بیشتر است قابل‌توزیع نیستند.
    // حکمرانی: پیشنهاد به ۳ رأی از ۵ عضو هیأت (اختیار زنده + محافظ نسخه‌ی ترکیب هیأت) و همچنین دوسوم ولیدیتورهای واجد هنگام ساخت
    // پیشنهاد نیاز دارد. انقضای ۳۰روزه فقط برای مرحله‌ی رأی‌گیری است؛ پس از تکمیل هر دو مجلس تأخیر ۷روزه شروع می‌شود و اجرا
    // همه‌چیز را دوباره بررسی می‌کند (executeRateChange را ببینید). اوراکل توزیع نمی‌تواند نرخی اضافه، عوض یا حذف کند؛ فقط می‌تواند
    // ارتفاع شروع یک ورودی مصوب را در پنجره‌ی تحمل گواهی کند.
    uint256 public constant INITIAL_REWARD_PER_BLOCK = 2 ether;
    struct RewardRateChange {
        uint128 startBlock; // تا پیش از گواهی: ارتفاع برآوردی اولین بلاک نرخ جدید؛ پس از آن: ارتفاع واقعی
        uint128 ratePerBlock; // wei به‌ازای هر بلاک
        uint64 activationTime; // ثانیه‌ی یونیکس؛ لحظه‌ای که در transition ی Besu تنظیم شده
        bool certified; // پس از گواهی ارتفاع واقعی شروع توسط اوراکل true است
    }
    RewardRateChange[] private rewardRateChanges;

    // ------------------------------------------------------------------
    // حکمرانی — تغییر نرخ مصوب پاداش
    // ------------------------------------------------------------------
    /// @notice تعداد تأیید لازم از هیأت: ۳ از ۵ عضو (برابر BOARD_SIZE / 2 + 1).
    uint256 public constant RATE_CHANGE_BOARD_APPROVALS = 3;
    /// @notice فقط مرحله‌ی رأی‌گیری. پیشنهاد تصویب‌شده‌ای که منتظر تأخیر یا اجراست با این انقضا حذف نمی‌شود.
    uint256 public constant RATE_VOTING_EXPIRY = 30 days;
    /// @notice از لحظه‌ای شروع می‌شود که «هر دو» مجلس تکمیل شده باشند.
    uint256 public constant RATE_CHANGE_DELAY = 7 days;
    /// @notice حداقل فاصله، به «ثانیه»، بین بلاکی که تغییر را اجرا می‌کند و زمان اثر آن. یک زمان است، از RATE_CHANGE_DELAY جداست،
    ///         و به هر اپراتور یک هفته وقت می‌دهد genesis همه‌ی نودها را به‌روز کند.
    uint256 public constant MIN_RATE_CHANGE_LEAD_SECONDS = 7 days;
    /// @notice نیم‌پهنای پنجره، به بلاک، دور ارتفاع برآوردی شروع که تا گواهی‌شدن ارتفاع شروع، «بزرگ‌تر» از دو نرخ در آن مجاز است؛
    ///         و بیشترین فاصله‌ی ارتفاع گواهی‌شده از برآورد.
    uint256 public constant RATE_START_TOLERANCE_BLOCKS = 10_000;

    struct RateProposal {
        uint128 startBlock; // ارتفاع برآوردی اولین بلاک نرخ جدید
        uint128 ratePerBlock;
        uint64 activationTime; // ثانیه‌ی یونیکس
        uint256 createdAt;
        uint256 votingExpiresAt;
        uint256 requiredValidatorApprovals; // ceil(2/3) ولیدیتورهای فعال هنگام ساخت، ثابت‌شده
        uint256 boardApprovals;
        uint256 validatorApprovals;
        uint256 approvedAt; // تا تکمیل هر دو مجلس صفر است
        bool executed;
        uint256 boardVersionAtCreation; // تغییر واقعی ترکیب هیأت پیشنهاد را باطل می‌کند
        uint256 validatorNonceAtCreation; // snapshot واجدان ولیدیتور
    }
    mapping(uint256 => RateProposal) public rateProposals;
    mapping(uint256 => mapping(address => bool)) private rateBoardVoted;
    mapping(uint256 => mapping(address => bool)) private rateValidatorVoted;
    uint256 public rateProposalCount;

    event RateChangeProposed(uint256 indexed id, uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock, address indexed proposer);
    event RateChangeBoardVoted(uint256 indexed id, address indexed boardMember, uint256 approvals, uint256 required);
    event RateChangeValidatorVoted(uint256 indexed id, address indexed validator, uint256 approvals, uint256 required);
    event RateChangeApproved(uint256 indexed id, uint256 approvedAt, uint256 executableAt);
    event RateChangeExecuted(uint256 indexed id, uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock);
    event RateStartCertified(uint256 indexed index, uint256 activationTime, uint256 actualStartBlock);

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event DistributionOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RewardsReceived(address indexed from, uint256 amount);
    event MembershipFeeReceived(uint256 amount, uint256 newPendingTotal);
    event FoundationFunded(uint256 indexed epochId, uint256 amount);
    event FeesBurned(uint256 indexed epochId, uint256 amount, uint256 totalBurnedToDate);
    event ShareChangeProposed(uint256 indexed id, uint256 newValidatorShareBps, address indexed proposer);
    event ShareChangeBoardVoted(uint256 indexed id, address indexed boardMember, uint256 approvals, uint256 required);
    event ShareChangeValidatorVoted(uint256 indexed id, address indexed validator, uint256 approvals, uint256 required);
    event ShareChangeApplied(uint256 indexed id, uint256 newValidatorShareBps);
    event RewardsDistributed(
        uint256 indexed epochId,
        uint256 totalRewards,
        uint256 totalFees,
        uint256 treasuryAmount,
        uint256 totalBlocksMined,
        uint256 validatorCount
    );
    event ValidatorRewarded(
        uint256 indexed epochId,
        address indexed validator,
        uint256 blocksMined,
        uint256 rewardShare,
        uint256 feeShare,
        uint256 totalPayout
    );

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyDistributionOracle() {
        require(msg.sender == distributionOracle, "BlockRewardDistributor: caller is not the distribution oracle");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "BlockRewardDistributor: caller is not the validators board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "BlockRewardDistributor: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // چرخش کلید اوراکل — فقط هیأت (اختیار تفویضی، به ValidatorsBoard مراجعه کن)
    // ------------------------------------------------------------------
    function setDistributionOracle(address newOracle) external onlyBoard {
        require(newOracle != address(0), "BlockRewardDistributor: zero distribution oracle address");
        emit DistributionOracleUpdated(distributionOracle, newOracle);
        distributionOracle = newOracle;
    }

    // ------------------------------------------------------------------
    // دریافت خودکار بلاک‌ریوارد و فی
    // ------------------------------------------------------------------
    /// @notice هر انتقال ساده‌ی سورن به این قرارداد (بلاک‌ریوارد/فی سطح پروتکل) اینجا دریافت
    ///         می‌شود. نکته: طبق تأیید تجربی، اعتبار سطح پروتکلِ miningbeneficiary در واقع این
    ///         تابع را فراخوانی نمی‌کند — یک نوشتن مستقیم موجودی روی state-trie است. این
    ///         receive() فقط برای انتقال‌های معمولی (مثلاً شارژ دستی یا تست) فعال می‌شود.
    receive() external payable {
        emit RewardsReceived(msg.sender, msg.value);
    }

    /// @notice توسط ValidatorsRegistry.requestMembership() فراخوانی می‌شود تا کارمزد عضویت
    ///         ولیدیتور تازه را اینجا بفرستد. مبلغ صرفاً انباشته می‌شود تا فراخوانی
    ///         distributeRewards() بعدی، جایی که به استخر فی همان epoch اضافه می‌شود —
    ///         کاملاً از سوزاندن ۳۰٪ معاف (برخلاف فی معمولی)، ولی از نظر نحوه‌ی تقسیم بین
    ///         ولیدیتورها ۱۰۰٪-به‌نسبت-بلاک پرداخت می‌شود — به sur-tokenomics.md بخش ۶ مراجعه
    ///         کنید که چرا این طراحی (یک انگیزه‌ی نقدی مستقیم و قابل‌ردیابی به‌ازای هر عضویت
    ///         تازه) به‌جای پرداخت فوری انتخاب شد — پرداخت فوری نیازمند یک حلقه‌ی نامحدود روی
    ///         همه‌ی ولیدیتورهای فعال درون خودِ requestMembership() است؛ یک ریسک واقعی سقف
    ///         گس/DoS با رشد جمعیت ولیدیتور.
    function receiveMembershipFee() external payable {
        require(msg.sender == REGISTRY_ADDRESS, "BlockRewardDistributor: only ValidatorsRegistry may forward membership fees");
        pendingMembershipFees += msg.value;
        emit MembershipFeeReceived(msg.value, pendingMembershipFees);
    }

    // ------------------------------------------------------------------
    // حکمرانی دومجلسی برای validatorDirectShareBps (نسبت خزانه در برابر ولیدیتور —
    // کامنت سطح قرارداد بالا و sur-tokenomics.md بخش ۱۱ را برای استدلال کامل ببینید). هر
    // ولیدیتور فعالی می‌تواند پیشنهاد بدهد؛ اکثریت ساده‌ی ValidatorsBoard **و** اکثریت دوسوم
    // کل مجمع ولیدیتورهای فعال باید هردو، مستقلاً، دقیقاً همان یک پیشنهاد را تصویب کنند تا
    // اجرا شود — هرکدام از دو مجلس که دومی به آستانه‌اش برسد، همان اجرا را فعال می‌کند (از
    // طریق _tryExecuteShareChange).
    // ------------------------------------------------------------------

    /// @notice شروع یک پیشنهاد تازه. هر ولیدیتور فعالی می‌تواند این را فراخوانی کند — عمداً
    ///         به اعضای هیأت‌مدیره محدود نشده، چون ولیدیتورهای عادی خودشان یکی از دو مجلسی
    ///         هستند که تأییدشان لازم است.
    function proposeShareChange(uint256 newValidatorShareBps) external returns (uint256 id) {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: only an active validator may propose a share change");
        require(
            newValidatorShareBps >= VALIDATOR_SHARE_MIN_BPS && newValidatorShareBps <= VALIDATOR_SHARE_MAX_BPS,
            "BlockRewardDistributor: proposed share is outside the allowed [40%, 65%] range"
        );
        require(
            block.timestamp >= lastShareChangeTime + SHARE_CHANGE_MIN_INTERVAL,
            "BlockRewardDistributor: too soon since the last successful share change"
        );

        shareProposalCount++;
        id = shareProposalCount;
        uint256 activeCountAtProposal = REGISTRY.getActiveValidatorCount();
        shareProposals[id] = ShareProposal({
            newValidatorShareBps: newValidatorShareBps,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + PROPOSAL_EXPIRY,
            requiredValidatorApprovals: (activeCountAtProposal * 2 + 2) / 3, // سقف(۲/۳)، از همین لحظه ثابت‌شده
            boardApprovals: 0,
            validatorApprovals: 0,
            boardPassed: false,
            validatorPassed: false,
            executed: false,
            boardVersionAtCreation: BOARD_CONTRACT.boardVersion(),
            validatorNonceAtCreation: REGISTRY.statusNonce()
        });
        emit ShareChangeProposed(id, newValidatorShareBps, msg.sender);
    }

    /// @notice یکی از دو رأی لازم — مجلس ValidatorsBoard. اکثریت ساده از BOARD_SIZE ثابت
    ///         (۵)، یعنی ۳ رأی.
    function boardVoteShareChange(uint256 id) external {
        // اختیار زنده، نه پرچم خام کرسی — عضوی که درخواست خروج داده، حق رأی را فوراً از دست
        // می‌دهد، حتی پیش از آن‌که syncBoard() کرسی را پاک کند.
        require(BOARD_CONTRACT.hasBoardAuthority(msg.sender), "BlockRewardDistributor: caller has no live board authority");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareBoardVoted[id][msg.sender], "BlockRewardDistributor: board member already voted");

        shareBoardVoted[id][msg.sender] = true;
        p.boardApprovals++;
        uint256 required = (BOARD_SIZE / 2) + 1; // ۳ از ۵ — BOARD_SIZE یه ثابته، پس برخلاف
        // آستانه‌ی سمت ولیدیتور، نیازی به snapshot نداره: هرگز جابه‌جا نمی‌شه.
        emit ShareChangeBoardVoted(id, msg.sender, p.boardApprovals, required);

        if (p.boardApprovals >= required) {
            p.boardPassed = true;
        }
        _tryExecuteShareChange(id);
    }

    /// @notice رأی لازم دیگر — مجلس کل مجمع ولیدیتورها. در برابر
    ///         `requiredValidatorApprovals` چک می‌شود که یک‌بار در لحظه‌ی ثبت پیشنهاد
    ///         snapshot شده — به کامنت struct ShareProposal مراجعه کن.
    function validatorVoteShareChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");
        // رأی‌دهنده باید هنگام ساخت پیشنهاد Active بوده باشد (snapshot واجدان) و اکنون هم Active باشد (onlyActiveValidator).
        // تعلیق موقت او را از مجموعه‌ی اولیه حذف نمی‌کند؛ فقط در دوره‌ی تعلیق مانع رأی است.
        require(REGISTRY.wasActiveAt(msg.sender, p.validatorNonceAtCreation), "BlockRewardDistributor: not eligible - not Active when this proposal was created");

        shareValidatorVoted[id][msg.sender] = true;
        p.validatorApprovals++;
        emit ShareChangeValidatorVoted(id, msg.sender, p.validatorApprovals, p.requiredValidatorApprovals);

        if (p.validatorApprovals >= p.requiredValidatorApprovals) {
            p.validatorPassed = true;
        }
        _tryExecuteShareChange(id);
    }

    /// @dev فقط وقتی **هردو** مجلس مستقلاً همان پیشنهاد را تصویب کرده باشند اجرا می‌کند.
    ///      بعد از هر رأی تازه در هر دو تابع رأی‌گیری فراخوانی می‌شود، پس هرکدام از دو مجلس
    ///      که دومی به آستانه‌اش برسد، همین را فعال می‌کند.
    function _tryExecuteShareChange(uint256 id) private {
        ShareProposal storage p = shareProposals[id];
        if (p.boardPassed && p.validatorPassed && !p.executed) {
            // مجلس هیأتی که با ترکیب قدیمی پاس شده، بعداً با رأی مجلس ولیدیتورها کامل نمی‌شود — ترکیب هنگام اجرا هم
            // دوباره بررسی می‌شود، نه فقط هنگام رأی هیأت.
            require(
                p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
                "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
            );
            // حداقل فاصله‌ی بین تغییرهای موفق همین‌جا، در نقطه‌ی اعمال تغییر، اجرا می‌شود. رأیی که پیشنهاد
            // زودهنگام را کامل کند revert می‌شود؛ چون PROPOSAL_EXPIRY (۳۰ روز) کوتاه‌تر از
            // SHARE_CHANGE_MIN_INTERVAL (۱۸۰ روز) است، چنین پیشنهادی هرگز اجرا نمی‌شود و فقط منقضی می‌شود.
            require(
                block.timestamp >= lastShareChangeTime + SHARE_CHANGE_MIN_INTERVAL,
                "BlockRewardDistributor: too soon since the last successful share change"
            );
            p.executed = true;
            validatorDirectShareBps = p.newValidatorShareBps;
            lastShareChangeTime = block.timestamp;
            emit ShareChangeApplied(id, p.newValidatorShareBps);
        }
    }

    // تابع اصلی توزیع دوره‌ای — فقط توسط اوراکل توزیع قابل‌فراخوانی است
    //
    // منطق به سه تابع تقسیم شده، هرکدام با stack frame مستقل خودشان، تا قرارداد بدون viaIR کامپایل شود
    // (که خیلی از سرویس‌های وریفای نمی‌توانند در برابرش وریفای کنند — sur-contracts-deploy-notes.md را ببین).
    // ------------------------------------------------------------------
    /// @param validators لیست آدرس ولیدیتورها (بدون تکرار)
    /// @param blocksMined تعداد بلاک تولیدشده توسط هر ولیدیتور از آخرین فراخوانی به بعد (همون ترتیب validators)
    /// @param totalRewards مجموع ریوارد این epoch (به wei) — آف‌چین توسط اوراکل، از ورودی‌های «reward» تابع trace_block محاسبه می‌شود
    /// @param totalFees مجموع فی تراکنش‌های این epoch (به wei) — آف‌چین توسط اوراکل، از eth_getTransactionReceipt.gasUsed ضرب‌در effectiveGasPrice برای هر تراکنش محاسبه می‌شود (هرگز از خروجی trace_*، که برای انتقال‌های ساده gasUsed=0 گزارش می‌کند)
    /// @notice `range` بازه‌ی شامل (inclusive) بلاک‌هایی است که این توزیع تسویه می‌کند. باید دقیقاً از lastSettledBlock + 1
    ///         شروع شود (نه تکرار، نه هم‌پوشانی، نه فاصله — قطعی سرویس با بازه‌ی **بعدی‌ِ بزرگ‌تر** پوشش داده می‌شود، هرگز
    ///         رد نمی‌شود)، باید قبل از بلاک جاری تمام شود، و تعداد بلاک‌های گزارش‌شده‌ی هر ولیدیتور (بعد از فیلتر سرویس روی
    ///         بلاک‌هایی که تولیدکننده‌شان دیگر معتبر نیست) نمی‌تواند از اندازه‌ی آن بیشتر باشد.
    function distributeRewards(
        BlockRange calldata range,
        address[] calldata validators,
        uint256[] calldata blocksMined,
        uint256 totalRewards,
        uint256 totalFees
    )
        external
        onlyDistributionOracle
        nonReentrant
    {
        require(validators.length > 0, "BlockRewardDistributor: empty validator list");
        require(validators.length == blocksMined.length, "BlockRewardDistributor: length mismatch");
        require(
            block.timestamp >= lastDistributionTime + MIN_DISTRIBUTION_INTERVAL || epochCount == 0,
            "BlockRewardDistributor: too soon since last distribution"
        );

        // پیش‌محاسبه در _prepareEpoch() نگه داشته شده تا stack frame خودِ این تابع کوچک بماند:
        // ۴ مقدار نتیجه در یک struct حافظه (`prep`) جمع می‌شوند، نه ۴ متغیر local جدا.
        EpochPrep memory prep = _prepareEpoch(blocksMined, totalRewards, totalFees);
        _settleRange(range, prep.totalBlocks);
        // totalRewards نباید از پاداش مصوب بلاک‌های این بازه (که پیوستگی‌اش تأیید شده) بیشتر باشد.
        // کارمزد عادی و کارمزد عضویت خارج از این سقف‌اند؛ قواعد تقسیم و سوزاندن بدون تغییر است.
        require(totalRewards <= maxRewardsForRange(range.fromBlock, range.toBlock), "BlockRewardDistributor: totalRewards exceed approved reward for range");

        epochCount++;
        uint256 epochId = epochCount;
        epochBlockRanges[epochId] = range;
        emit EpochRangeSettled(epochId, range.fromBlock, range.toBlock);

        // foundationAmount/treasuryAmount *بعد* از فراخوان _payValidators محاسبه می‌شوند (به آن وابسته نیستند)، که تعداد
        // متغیرهای local زنده در آن فراخوان را کم می‌کند.
        // validatorDirectShareBps حکمرانی‌شونده است (رأی دومجلسی، [۴۰٪, ۶۵٪]) — کامنت سطح
        // قرارداد بالا را ببینید. ValidatorsTreasury هرچه بعد از سهم ثابت بنیاد و این سهم
        // حکمرانی‌شونده باقی بماند را دریافت می‌کند.
        uint256 validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS_DENOMINATOR;

        (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) =
            _payValidators(
                validators,
                blocksMined,
                EpochContext({
                    epochId: epochId,
                    remainingRewards: validatorDirectAmount,
                    totalFees: prep.feesToDistribute,
                    totalBlocks: prep.totalBlocks
                })
            );

        // سهم بنیاد ۱۵٪ ثابت از کل ریوارد است، مستقل و از بالای کل کسر
        // می‌شود — هرگز تحت‌تأثیر validatorDirectShareBps بالا نیست. فقط ریوارد این‌طور
        // تقسیم می‌شود؛ فی هرگز توسط هیچ‌کدام از این سه سهم لمس نمی‌شود.
        uint256 foundationAmount = (totalRewards * FOUNDATION_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 treasuryAmount = totalRewards - foundationAmount - validatorDirectAmount;

        _finalizeEpoch(
            epochId,
            totalRewards,
            prep.effectiveTotalFees,
            prep.feeBurnAmount,
            treasuryAmount,
            foundationAmount,
            prep.totalBlocks,
            validatorCount,
            distributedRewards,
            distributedFees
        );
    }

    /// @notice پیشنهاد تغییر نرخ مصوب که در `activationTime` (ثانیه‌ی یونیکس، زمان transition ی Besu) اثر می‌کند، همراه با برآورد
    ///         پیشنهاددهنده از اولین بلاکِ برابر یا بعد از آن زمان. فقط ولیدیتور فعال می‌تواند پیشنهاد دهد. این فقط ردِ زودهنگام است:
    ///         همه‌ی شرط‌ها هنگام اجرا دوباره بررسی می‌شوند. پیشنهادها مستقل‌اند؛ چند پیشنهاد می‌توانند هم‌زمان باز باشند و هرکدام
    ///         زودتر اجرا شود ممکن است دیگری را غیرقابل‌اجرا کند (آن‌گاه همان‌طور که هست می‌ماند).
    function proposeRateChange(uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock) external returns (uint256 id) {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: only an active validator may propose a rate change");
        require(
            activationTime <= type(uint64).max && estimatedStartBlock <= type(uint128).max && ratePerBlock <= type(uint128).max,
            "BlockRewardDistributor: value does not fit its type"
        );
        _requireRateStartOk(activationTime, estimatedStartBlock);
        id = ++rateProposalCount;
        RateProposal storage p = rateProposals[id];
        p.startBlock = uint128(estimatedStartBlock);
        p.ratePerBlock = uint128(ratePerBlock);
        p.activationTime = uint64(activationTime);
        p.createdAt = block.timestamp;
        p.votingExpiresAt = block.timestamp + RATE_VOTING_EXPIRY;
        p.requiredValidatorApprovals = (REGISTRY.getActiveValidatorCount() * 2 + 2) / 3; // ceil(2/3), frozen now
        p.boardVersionAtCreation = BOARD_CONTRACT.boardVersion();
        p.validatorNonceAtCreation = REGISTRY.statusNonce();
        emit RateChangeProposed(id, activationTime, estimatedStartBlock, ratePerBlock, msg.sender);
    }

    /// @notice مجلس هیأت: اختیار زنده لازم است؛ پیشنهاد باید هنوز متعلق به ترکیب فعلی هیأت باشد.
    function boardVoteRateChange(uint256 id) external {
        require(BOARD_CONTRACT.hasBoardAuthority(msg.sender), "BlockRewardDistributor: caller has no live board authority");
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        _requireRateVotable(p);
        require(!rateBoardVoted[id][msg.sender], "BlockRewardDistributor: board member already voted");
        rateBoardVoted[id][msg.sender] = true;
        p.boardApprovals++;
        emit RateChangeBoardVoted(id, msg.sender, p.boardApprovals, RATE_CHANGE_BOARD_APPROVALS);
        _markRateApprovedIfComplete(id, p);
    }

    /// @notice مجلس ولیدیتورها: واجد = هنگام ساخت پیشنهاد Active بوده و اکنون هم Active است.
    function validatorVoteRateChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        _requireRateVotable(p);
        require(!rateValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");
        require(REGISTRY.wasActiveAt(msg.sender, p.validatorNonceAtCreation), "BlockRewardDistributor: not eligible - not Active when this proposal was created");
        rateValidatorVoted[id][msg.sender] = true;
        p.validatorApprovals++;
        emit RateChangeValidatorVoted(id, msg.sender, p.validatorApprovals, p.requiredValidatorApprovals);
        _markRateApprovedIfComplete(id, p);
    }

    /// @notice هرکس می‌تواند اجرا کند، پس از تکمیل هر دو مجلس و گذشتن RATE_CHANGE_DELAY از آن لحظه. دوباره بررسی می‌شود: ترکیب
    ///         هیأت، دست‌کم MIN_RATE_CHANGE_LEAD_SECONDS فاصله‌ی زمان اثر، آینده‌بودن ارتفاع برآوردی شروع، و تاریخچه‌ی اکیداً
    ///         صعودی با پنجره‌های تحمل بدون هم‌پوشانی. اگر هر بررسی شکست بخورد پیشنهاد دقیقاً همان‌طور که هست می‌ماند: هیچ زمان یا
    ///         ارتفاعی خودکار جابه‌جا نمی‌شود. ورودی تازه تا certifyRateStart موقت است.
    function executeRateChange(uint256 id) external {
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(p.approvedAt != 0, "BlockRewardDistributor: not approved by both chambers");
        require(block.timestamp >= p.approvedAt + RATE_CHANGE_DELAY, "BlockRewardDistributor: execution delay has not elapsed");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        _requireRateStartOk(p.activationTime, p.startBlock);
        p.executed = true;
        rewardRateChanges.push(
            RewardRateChange({startBlock: p.startBlock, ratePerBlock: p.ratePerBlock, activationTime: p.activationTime, certified: false})
        );
        emit RateChangeExecuted(id, p.activationTime, p.startBlock, p.ratePerBlock);
    }

    /// @notice اوراکل توزیع، اولین بلاکی را که timestamp آن برابر یا بیشتر از زمان اثر ورودی است گواهی می‌کند. فقط پس از رسیدن به
    ///         آن زمان، فقط یک‌بار برای هر ورودی، و فقط در RATE_START_TOLERANCE_BLOCKS بلاکِ برآورد ممکن است. قرارداد نمی‌تواند
    ///         زمان بلاک‌های قدیمی را بخواند؛ پس مقدار در همین پنجره قابل اعتماد است. گواهی فقط سقف را از «بزرگ‌تر از هر دو نرخ در
    ///         پنجره» به «دقیق در ارتفاع گواهی‌شده» تنگ می‌کند.
    function certifyRateStart(uint256 index, uint256 actualStartBlock) external onlyDistributionOracle {
        require(index < rewardRateChanges.length, "BlockRewardDistributor: no such rate change");
        RewardRateChange storage c = rewardRateChanges[index];
        require(!c.certified, "BlockRewardDistributor: start block already certified");
        require(block.timestamp >= c.activationTime, "BlockRewardDistributor: activation time has not been reached");
        require(actualStartBlock <= block.number, "BlockRewardDistributor: start block is in the future");
        uint256 estimate = c.startBlock;
        uint256 distance = actualStartBlock > estimate ? actualStartBlock - estimate : estimate - actualStartBlock;
        require(distance <= RATE_START_TOLERANCE_BLOCKS, "BlockRewardDistributor: start block is outside the tolerance window");
        c.startBlock = uint128(actualStartBlock);
        c.certified = true;
        emit RateStartCertified(index, c.activationTime, actualStartBlock);
    }

    /// @notice وضعیت در آخرین بلاک. status: ۰ یافت نشد، ۱ در حال رأی‌گیری، ۲ رأی‌گیری منقضی (هرگز تصویب نشد)، ۳ اجراشده،
    ///         ۴ تصویب‌شده و منتظر تأخیر، ۵ اکنون قابل اجرا، ۶ تصویب‌شده ولی فعلاً غیرقابل‌اجرا،
    ///         ۷ هنوز تصویب‌نشده و غیرقابل‌ادامه (رأی‌گیری دیگر به تغییر قابل‌اجرا نمی‌رسد).
    ///         problem (برای status ۶ یا ۷): ۱ ترکیب هیأت تغییر کرده، ۲ زمان اثر در آینده نیست، ۳ زمان اثر نزدیک‌تر از
    ///         MIN_RATE_CHANGE_LEAD_SECONDS، ۴ پس از آخرین تغییر مصوب نیست (زمان، یا پنجره‌های تحمل هم‌پوشانی پیدا می‌کنند)، ۵ ارتفاع
    ///         برآوردی شروع در آینده نیست. هر مشکل دائمی است (زمان و شماره‌ی بلاک فقط بالا می‌رود، تاریخچه فقط بزرگ می‌شود، و تغییر هیأت
    ///         برای یک پیشنهاد برگشت‌پذیر نیست)؛ پس status ۷ هرگز به ۱ برنمی‌گردد. اجرا در بلاکی بعدی رخ می‌دهد؛ پس این فقط راهنماست.
    function rateChangeStatus(uint256 id) external view returns (uint8 status, uint8 problem) {
        RateProposal storage p = rateProposals[id];
        if (p.createdAt == 0) return (0, 0);
        if (p.executed) return (3, 0);
        problem = BOARD_CONTRACT.boardVersion() != p.boardVersionAtCreation ? 1 : _rateStartProblem(p.activationTime, p.startBlock);
        if (p.approvedAt == 0) {
            if (block.timestamp > p.votingExpiresAt) return (2, 0);
            if (problem != 0) return (7, problem);
            return (1, 0);
        }
        if (problem != 0) return (6, problem);
        return (block.timestamp >= p.approvedAt + RATE_CHANGE_DELAY ? 5 : 4, 0);
    }

    function _requireRateVotable(RateProposal storage p) private view {
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(p.approvedAt == 0, "BlockRewardDistributor: voting closed - already approved by both chambers");
        require(block.timestamp <= p.votingExpiresAt, "BlockRewardDistributor: voting period has expired");
    }

    function _markRateApprovedIfComplete(uint256 id, RateProposal storage p) private {
        if (p.boardApprovals >= RATE_CHANGE_BOARD_APPROVALS && p.validatorApprovals >= p.requiredValidatorApprovals) {
            // تکمیل هر دو مجلس فقط وقتی معتبر است که پیشنهاد هنوز متعلق به ترکیب «فعلی» هیأت باشد. رأی هیأت خودش این را بررسی
            // می‌کند؛ رأی تکمیل‌کننده‌ی ولیدیتورها نباید برای پیشنهادی که هیأتش از آن پس تغییر کرده تصویب (و رویداد RateChangeApproved) ثبت
            // کند — اجرا هم به هر حال آن را رد می‌کند. این رأی ثبت نمی‌شود؛ پیشنهاد دیگر نمی‌تواند موفق شود.
            require(
                p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
                "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
            );
            p.approvedAt = block.timestamp;
            emit RateChangeApproved(id, block.timestamp, block.timestamp + RATE_CHANGE_DELAY);
        }
    }

    function _rateStartProblem(uint256 activationTime, uint256 estimatedStartBlock) private view returns (uint8) {
        if (activationTime <= block.timestamp) return 2;
        if (activationTime < block.timestamp + MIN_RATE_CHANGE_LEAD_SECONDS) return 3;
        if (estimatedStartBlock <= block.number) return 5;
        uint256 n = rewardRateChanges.length;
        if (n > 0) {
            RewardRateChange storage last = rewardRateChanges[n - 1];
            if (activationTime <= last.activationTime) return 4;
            uint256 lastEnd = last.certified ? last.startBlock : uint256(last.startBlock) + RATE_START_TOLERANCE_BLOCKS;
            if (estimatedStartBlock <= lastEnd + RATE_START_TOLERANCE_BLOCKS) return 4;
        }
        return 0;
    }

    function _requireRateStartOk(uint256 activationTime, uint256 estimatedStartBlock) private view {
        uint8 r = _rateStartProblem(activationTime, estimatedStartBlock);
        require(r != 2, "BlockRewardDistributor: activation time is not in the future");
        require(r != 3, "BlockRewardDistributor: activation time is closer than MIN_RATE_CHANGE_LEAD_SECONDS");
        require(r != 5, "BlockRewardDistributor: estimated start block is not in the future");
        require(r != 4, "BlockRewardDistributor: activation time and start block must be after the last approved rate change");
    }

    /// @dev جست‌وجوی دودویی: تعداد ورودی‌های تاریخچه که اثرشان تا `blockNumber` تمام شده است. اثر یک ورودی در ارتفاع گواهی‌شده‌ی
    ///      شروع آن، یا تا وقتی موقت است در برآورد + تحمل تمام می‌شود. انتهای اثرها اکیداً صعودی است.
    function _rateEntriesEnded(uint256 blockNumber) private view returns (uint256 lo) {
        uint256 hi = rewardRateChanges.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            RewardRateChange storage c = rewardRateChanges[mid];
            uint256 end = c.certified ? c.startBlock : uint256(c.startBlock) + RATE_START_TOLERANCE_BLOCKS;
            if (end <= blockNumber) lo = mid + 1;
            else hi = mid;
        }
    }

    /// @notice پاداش ناخالص مصوب بلاک‌های [fromBlock, toBlock]، قطعه‌به‌قطعه روی تاریخچه‌ی نرخ جمع‌شده. داخل پنجره‌ی تحمل یک ورودی
    ///         موقت، «بزرگ‌تر» از نرخ قدیم و جدید اعمال می‌شود؛ ورودی گواهی‌شده دقیق است. هزینه = O(log n) برای پیداکردن نرخ در
    ///         fromBlock + تعداد ثابتی گام برای هر تغییر نرخ «داخل» بازه؛ نه به شمار بلاک‌ها بستگی دارد و نه به تعداد تغییرهای قدیمی‌تر.
    function maxRewardsForRange(uint256 fromBlock, uint256 toBlock) public view returns (uint256 total) {
        require(fromBlock <= toBlock, "BlockRewardDistributor: invalid range");
        uint256 n = rewardRateChanges.length;
        uint256 i = _rateEntriesEnded(fromBlock);
        uint256 rate = i == 0 ? INITIAL_REWARD_PER_BLOCK : rewardRateChanges[i - 1].ratePerBlock;
        uint256 cursor = fromBlock;
        for (; i < n; i++) {
            RewardRateChange memory c = rewardRateChanges[i];
            if (c.certified) {
                if (c.startBlock > toBlock) break;
                if (c.startBlock > cursor) {
                    total += (c.startBlock - cursor) * rate;
                    cursor = c.startBlock;
                }
                rate = c.ratePerBlock;
            } else {
                uint256 windowStart = c.startBlock > RATE_START_TOLERANCE_BLOCKS ? c.startBlock - RATE_START_TOLERANCE_BLOCKS : 0;
                uint256 windowEnd = uint256(c.startBlock) + RATE_START_TOLERANCE_BLOCKS;
                if (windowStart > toBlock) break;
                if (windowStart > cursor) {
                    total += (windowStart - cursor) * rate;
                    cursor = windowStart;
                }
                if (c.ratePerBlock > rate) rate = c.ratePerBlock; // inside the window: the larger of the two rates
                if (windowEnd > toBlock) break;
                total += (windowEnd - cursor) * rate;
                cursor = windowEnd;
                rate = c.ratePerBlock;
            }
        }
        total += (toBlock - cursor + 1) * rate;
    }

    /// @notice بیشترین پاداش مصوب به‌ازای هر بلاک که در `blockNumber` می‌تواند اعمال شود (داخل پنجره‌ی تحمل یک ورودی موقت،
    ///         «بزرگ‌تر» از نرخ قدیم و جدید است).
    function rewardRateAt(uint256 blockNumber) external view returns (uint256) {
        return maxRewardsForRange(blockNumber, blockNumber);
    }

    /// @notice تعداد تغییرهای نرخ مصوب و یک ورودی، برای داشبوردها و حسابرسی.
    function rewardRateChangeCount() external view returns (uint256) {
        return rewardRateChanges.length;
    }

    function rewardRateChange(uint256 index) external view returns (uint256 startBlock, uint256 ratePerBlock, uint256 activationTime, bool certified) {
        RewardRateChange memory c = rewardRateChanges[index];
        return (c.startBlock, c.ratePerBlock, c.activationTime, c.certified);
    }

    /// @dev کنترل بازه (کامنت BlockRange را ببینید). در stack frame جدای خودش نگه داشته شده.
    ///
    ///      چرا سقف زمان‌محور وجود ندارد: کنترلی به شکل totalBlocks <= (block.timestamp - lastDistributionTime) / 3
    ///      دو چیز متفاوت را مقایسه می‌کرد: تعداد بلاک مربوط به بازه‌ی بعد از lastSettledBlock است، ولی lastDistributionTime
    ///      زمان اجرای «تراکنش» توزیع قبلی است که ممکن است فقط تا بلاکی عقب‌تر تسویه کرده باشد. هر تسویه‌ی عقب‌تر از head
    ///      (تأخیر عادی اوراکل) یا هر آهنگ سریع‌تر از ۳ ثانیه، پرداخت درست را revert می‌کرد، و پس از رد یک چرخه، همه‌ی
    ///      بازه‌های بعدیِ بلندتر هم رد می‌شدند.
    ///      آنچه به‌جای آن تعداد را کاملاً on-chain و دقیق محدود می‌کند:
    ///        (۱) پیوستگی   fromBlock == lastSettledBlock + 1           -> بدون فاصله، هم‌پوشانی یا بازه‌ی تکراری؛
    ///        (۲) فقط گذشته  toBlock < block.number                      -> هرگز بلاک جاری یا آینده تسویه نمی‌شود؛
    ///        (۳) اندازه    sum(blocksMined) <= toBlock - fromBlock + 1 -> هرگز بیش از بلاک‌های واقعی بازه.
    ///      (۳) حد بالاست، نه تساوی. طبق sur-reward-router-spec.md بخش ۳ این مجموع باید «معمولاً» برابر طول بازه
    ///      باشد؛ خروج/تعلیقِ بعدیِ تولیدکننده هرگز دلیل حذف بلاک‌هایش نیست (سیاست everActivated). توجه: تقسیم بر
    ///      sum(blocksMined) انجام می‌شود، نه طول بازه؛ پس این‌که پاداش/کارمزد بلاک حذف‌شده در این قرارداد بماند یا بین
    ///      تولیدکنندگان فهرست‌شده بازتوزیع شود، فقط به totalRewards/totalFees گزارش‌شده‌ی اوراکل بستگی دارد — قرارداد هیچ‌کدام
    ///      را الزام نمی‌کند. وقتی lastSettledBlock از بلاک حذف‌شده عبور کند، هیچ مسیر on-chainی برای پرداخت آن بلاک به
    ///      تولیدکننده‌اش نمی‌ماند.
    ///      مرز اعتماد — این کنترل‌ها انتساب را اثبات نمی‌کنند. قرارداد به هدر بلاک‌های تاریخی و state تاریخی Registry دسترسی
    ///      ندارد؛ پس فقط اوراکل توزیع برای این موارد مورد اعتماد است: این‌که کدام آدرس هر بلاک را تولید کرده؛ فعال‌بودن
    ///      تولیدکننده در ارتفاع N-1؛ تقسیم بین ولیدیتورها؛ تفکیک totalRewards/totalFees (که این‌جا فقط به موجودی همین قرارداد
    ///      محدود است)؛ و تکرارنکردن آدرس در فهرست. پشتیبان‌های on-chain محدودند به: کلید اوراکل، فاصله‌ی ۲۳ ساعته، سه قاعده‌ی
    ///      بازه‌ی بالا، everActivated برای هر آدرس پرداختی و کفایت موجودی. انتساب نادرست بین آدرس‌های everActivated فقط
    ///      off-chain و با بازپخش بازه‌ی تسویه‌شده از داده‌ی زنجیره قابل کشف است (EpochRangeSettled بازه‌ی دقیق را می‌دهد).
    function _settleRange(BlockRange calldata range, uint256 totalBlocks) private {
        require(range.fromBlock == lastSettledBlock + 1, "BlockRewardDistributor: range must start right after the last settled block");
        require(range.toBlock >= range.fromBlock, "BlockRewardDistributor: empty or inverted block range");
        require(range.toBlock < block.number, "BlockRewardDistributor: range includes blocks that are not yet produced");
        require(totalBlocks <= range.toBlock - range.fromBlock + 1, "BlockRewardDistributor: reported blocks exceed the range size");
        lastSettledBlock = range.toBlock;
    }

    struct EpochPrep {
        uint256 effectiveTotalFees;
        uint256 feeBurnAmount;
        uint256 feesToDistribute;
        uint256 totalBlocks;
    }

    /// @dev تابع کمکی پیش‌محاسبه‌ی distributeRewards(): در stack frame جدای خودش ایزوله شده تا
    ///      distributeRewards() متغیرهای local هم‌زمان زنده‌ی کمتری در لحظه‌ی فراخوان
    ///      _payValidators داشته باشد.
    function _prepareEpoch(uint256[] calldata blocksMined, uint256 totalRewards, uint256 totalFees)
        private
        returns (EpochPrep memory prep)
    {
        // هر کارمزد عضویتی که از epoch قبلی ValidatorsRegistry فرستاده به استخر فی همین epoch
        // اضافه می‌شود — از قبل در موجودی این قرارداد هست (از طریق receiveMembershipFee()
        // دریافت شده). این کارمزد عضویت با فی معمولی یکی نیست: کاملاً از سوزاندن ۳۰٪ زیر
        // معاف است (فقط totalFees معمولی سوزانده می‌شود، نه membershipFeesThisEpoch) — فقط
        // از نظر نحوه‌ی تقسیم نهایی بین ولیدیتورها همان رفتار ۱۰۰٪-به‌نسبت-بلاک را می‌گیرد.
        // به sur-tokenomics.md بخش ۶ مراجعه کنید.
        uint256 membershipFeesThisEpoch = pendingMembershipFees;
        pendingMembershipFees = 0;
        prep.effectiveTotalFees = totalFees + membershipFeesThisEpoch;

        require(totalRewards + prep.effectiveTotalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalRewards + prep.effectiveTotalFees <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        // ۳۰٪ ثابت سوزانده می‌شود — ولی **فقط از فی معمولی تراکنش‌ها** (totalFees)،
        // عمداً نه از کارمزد عضویت. دلیل (به sur-tokenomics.md بخش ۶ مراجعه کن): کارمزد عضویت
        // اصلاً یه فی عمومی شبکه نیست — یه پرداخت هدفمند و یک‌باره‌ی جبران رقیق‌شدن به
        // ولیدیتورهای موجوده، که با ورود ولیدیتور تازه فعال می‌شه. سوزوندن بخشی ازش، این
        // انگیزه‌ی مشخص رو به‌عنوان یه اثر جانبی ناخواسته‌ی یه تصمیم بعدی و بی‌ربط (سوزاندن
        // عمومی فی) ضعیف می‌کنه. فی معمولی چنین هدف‌گذاری‌ای نداره، پس هدف درست — و تنها هدف
        // — سوزاندنه.
        prep.feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS_DENOMINATOR;
        prep.feesToDistribute = prep.effectiveTotalFees - prep.feeBurnAmount;

        prep.totalBlocks = _sumBlocks(blocksMined);
        require(prep.totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
    }

    /// @dev جمع تعداد بلاک گزارش‌شده‌ی هر ولیدیتور. برای کوچک‌نگه‌داشتن stack frame خودِ
    ///      distributeRewards از آن جدا شده.
    function _sumBlocks(uint256[] calldata blocksMined) private pure returns (uint256 totalBlocks) {
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
    }

    /// @dev بسته‌بندی چهار ورودی مقیاسی موردنیاز `_payValidators` در یک struct در memory —
    ///      یک struct با یک اشاره‌گر (یک slot استک) پاس داده می‌شود، نه چهار slot جدا؛ همین
    ///      باعث می‌شود stack frame خودِ این تابع زیر سقف ۱۶لایه جا بگیرد.
    struct EpochContext {
        uint256 epochId;
        uint256 remainingRewards;
        uint256 totalFees;
        uint256 totalBlocks;
    }

    /// @dev پرداخت یک انتقال ترکیبی واحد (سهم ریوارد + سهم فی) به هر ولیدیتور واجدشرایط، به
    ///      نسبت بلاک. رفتار دقیقاً همان بدنه‌ی حلقه‌ی inline اصلی در distributeRewards است؛
    ///      نوشتن‌های storage، انتقال، و event هر ولیدیتور حالا در `_payOneValidator` (با
    ///      stack frame مستقل خودشان) هستند تا حتی frame خودِ این حلقه هم کوچک بماند — بدون
    ///      تغییر رفتار، event، یا ترتیب.
    function _payValidators(
        address[] calldata validators,
        uint256[] calldata blocksMined,
        EpochContext memory ctx
    ) private returns (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) {
        for (uint256 i = 0; i < validators.length; i++) {
            // آدرس‌ها باید اکیداً صعودی باشند. این شرط آدرس تکراری (که رکوردهای هر-epoch را بازنویسی می‌کرد در حالی که
            // همه‌ی ورودی‌ها پرداخت می‌شدند) و فهرست نامرتب را رد می‌کند. RewardRouter باید بلاک‌ها را برای هر تولیدکننده
            // تجمیع و پیش از ارسال بر اساس آدرس مرتب کند.
            if (i > 0) {
                require(validators[i] > validators[i - 1], "BlockRewardDistributor: validators must be strictly ascending");
            }
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            // کار مشروع گذشته همیشه پرداخت می‌شود، صرف‌نظر از وضعیت **فعلی** ولیدیتور. `isValidator()`
            // ولیدیتوری را که از آن‌موقع خروج داده یا معلق شده رد می‌کرد، حتی برای بلاک‌هایی که
            // واقعاً در دوره‌ی Active تولید کرده. `everActivated()` یک پرچم دائمی و فقط-اضافه‌شونده‌ی Registry است که از
            // پاک‌شدن در `withdrawStake()` جان سالم به‌در می‌برد؛ فقط «حداقل یک‌بار به‌طور مشروع
            // فعال شده» را ثابت می‌کند، نه «دقیقاً هنگام تولید همین بلاک فعال بوده» — آن
            // راستی‌آزمایی زمانی نه ممکن است و نه روی زنجیره انجام می‌شود (Solidity به تاریخچه‌ی
            // state دسترسی ندارد) و کاملاً مسئولیت RewardRouter می‌ماند: باید از داده‌ی زنجیره
            // هم تولیدکننده‌ی واقعی هر بلاک را در بازه‌ی تسویه (`eth_getBlockByNumber`) تعیین کند،
            // هم اینکه آن تولیدکننده دقیقاً در همان ارتفاع بلاک واقعاً Active بوده (با `eth_call`ی
            // تاریخی روی نود آرشیوی، یا بازپخش رویدادهای `StatusDecisionRecorded`) — پیش از
            // این‌که اینجا بگنجاندش. این چک فقط یک سدِ حداقلی در برابر آدرسی است که هرگز واقعاً
            // ولیدیتور نبوده؛ جایگزین آن اثبات سمت اوراکل نیست و این پرداخت را خودش-تأییدشونده
            // نمی‌کند.
            require(REGISTRY.everActivated(validator), "BlockRewardDistributor: address was never a legitimate validator");

            uint256 rewardShare = (ctx.remainingRewards * blocksMined[i]) / ctx.totalBlocks;
            uint256 feeShare = (ctx.totalFees * blocksMined[i]) / ctx.totalBlocks;

            bool paid = _payOneValidator(ctx.epochId, validator, blocksMined[i], rewardShare, feeShare);
            if (paid) {
                distributedRewards += rewardShare;
                distributedFees += feeShare;
                validatorCount++;
            }
        }
    }

    /// @dev ثبت سهم‌های epoch یک ولیدیتور، انتقال پرداخت ترکیبی‌اش، و emit event مخصوص همان
    ///      ولیدیتور. از `_payValidators` جدا شده فقط تا این متغیرهای محلی (payout، success)
    ///      در stack frame حداقلی خودشان زندگی کنند — بدون تغییر رفتار، event، یا ترتیب نسبت
    ///      به نسخه‌ی تک‌تابعی اصلی.
    function _payOneValidator(
        uint256 epochId,
        address validator,
        uint256 blocksMinedByValidator,
        uint256 rewardShare,
        uint256 feeShare
    ) private returns (bool paid) {
        uint256 payout = rewardShare + feeShare;
        if (payout == 0) return false;

        epochValidatorRewardShare[epochId][validator] = rewardShare;
        epochValidatorFeeShare[epochId][validator] = feeShare;
        epochValidatorBlocks[epochId][validator] = blocksMinedByValidator;
        totalRewardsPaid[validator] += rewardShare;
        totalFeesPaid[validator] += feeShare;
        totalBlocksRecorded[validator] += blocksMinedByValidator;

        // یک انتقال ترکیبی واحد برای هر ولیدیتور در کل این فراخوانی
        (bool success, ) = validator.call{value: payout}("");
        require(success, "BlockRewardDistributor: validator transfer failed");

        emit ValidatorRewarded(epochId, validator, blocksMinedByValidator, rewardShare, feeShare, payout);
        return true;
    }

    /// @dev رند کردن خرده‌ریز به خزانه، انتقال سهم خزانه، به‌روزرسانی مجموع‌های تاریخی، ثبت
    ///      epoch، و emit کردن event نهایی — دنباله‌ی پایانی distributeRewards، که فقط به‌خاطر عمق
    ///      استک به تابع جدا منتقل شده است.
    function _finalizeEpoch(
        uint256 epochId,
        uint256 totalRewards,
        uint256 totalFees,
        uint256 feeBurnAmount,
        uint256 treasuryAmount,
        uint256 foundationAmount,
        uint256 totalBlocks,
        uint256 validatorCount,
        uint256 distributedRewards,
        uint256 distributedFees
    ) private {
        // خرده‌ریز رند شده از تقسیم ریوارد و فی، به مبلغ خزانه اضافه می‌شود تا هیچ wei ای
        // توی قرارداد گیر نکند. فرمول خرده‌ریز سمت ریوارد treasuryAmount، foundationAmount، و
        // distributedRewards را از totalRewards کم می‌کند — چون totalRewards از نظر جبری
        // دقیقاً برابر foundationAmount + validatorDirectAmount + treasuryAmount است
        // (treasuryAmount به‌عنوان باقی‌مانده تعریف شده، پس در آن سطح خرده‌ریزی نیست)، آنچه
        // اینجا باقی می‌ماند دقیقاً validatorDirectAmount - distributedRewards است — باقی‌مانده‌ی
        // تقسیم صحیح‌عددی هنگام تقسیم به نسبت بلاک.
        uint256 rewardDust = totalRewards - treasuryAmount - foundationAmount - distributedRewards;
        // totalFees اینجا کل استخر فی *قبل از سوزاندن* است (برای شفافیت رکورد epoch/رویداد — به
        // distributeRewards مراجعه کن). پس feeDust باید هم feeBurnAmount هم distributedFees را کم کند، وگرنه ۳۰٪
        // سوزانده‌شده به‌اشتباه «خرده‌ریز» حساب و یک بار دیگر به خزانه فرستاده می‌شد.
        uint256 feeDust = totalFees - feeBurnAmount - distributedFees;
        uint256 totalTreasuryAmount = treasuryAmount + rewardDust + feeDust;

        if (totalTreasuryAmount > 0) {
            (bool tsuccess, ) = TREASURY.call{value: totalTreasuryAmount}("");
            require(tsuccess, "BlockRewardDistributor: treasury transfer failed");
        }

        if (foundationAmount > 0) {
            (bool fsuccess, ) = FOUNDATION.call{value: foundationAmount}("");
            require(fsuccess, "BlockRewardDistributor: foundation transfer failed");
            emit FoundationFunded(epochId, foundationAmount);
        }

        // بخش سوزاندنی فی را بسوزان — بعد از انتقال‌های خزانه/بنیاد، صرفاً
        // برای ترتیب فراخوانی یکدست؛ این مبلغ از قبل، پیش از اجرای _payValidators، از
        // feesToDistribute کنار گذاشته شده بود، پس اینجا فقط سورنی را که هرگز به کسی پرداخت
        // نشده به یک عدم‌گردش دائمی و قابل‌راستی‌آزمایی منتقل می‌کنیم.
        if (feeBurnAmount > 0) {
            (bool bsuccess, ) = BURN_ADDRESS.call{value: feeBurnAmount}("");
            require(bsuccess, "BlockRewardDistributor: fee burn transfer failed");
            totalFeesBurned += feeBurnAmount;
            emit FeesBurned(epochId, feeBurnAmount, totalFeesBurned);
        }

        totalDistributedToValidators += (distributedRewards + distributedFees);
        totalDistributedToTreasury += totalTreasuryAmount;
        totalDistributedToFoundation += foundationAmount;
        lastDistributionTime = block.timestamp;

        epochs[epochId] = Epoch({
            timestamp: block.timestamp,
            totalRewards: totalRewards,
            totalFees: totalFees,
            treasuryAmount: totalTreasuryAmount,
            totalBlocksMined: totalBlocks,
            validatorCount: validatorCount
        });

        emit RewardsDistributed(epochId, totalRewards, totalFees, totalTreasuryAmount, totalBlocks, validatorCount);
    }

    // ------------------------------------------------------------------
    // توابع view / گزارش‌گیری
    // ------------------------------------------------------------------

    function getEpoch(uint256 epochId) external view returns (
        uint256 timestamp,
        uint256 totalRewards,
        uint256 totalFees,
        uint256 treasuryAmount,
        uint256 totalBlocksMined,
        uint256 validatorCount
    ) {
        Epoch storage e = epochs[epochId];
        return (e.timestamp, e.totalRewards, e.totalFees, e.treasuryAmount, e.totalBlocksMined, e.validatorCount);
    }

    function getValidatorEpochReward(uint256 epochId, address validator)
        external
        view
        returns (uint256 rewardShare, uint256 feeShare, uint256 blocks)
    {
        return (
            epochValidatorRewardShare[epochId][validator],
            epochValidatorFeeShare[epochId][validator],
            epochValidatorBlocks[epochId][validator]
        );
    }

    function getValidatorTotals(address validator)
        external
        view
        returns (uint256 totalReward, uint256 totalFee, uint256 totalBlocks)
    {
        return (totalRewardsPaid[validator], totalFeesPaid[validator], totalBlocksRecorded[validator]);
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getDistributionOracle() external view returns (address) {
        return distributionOracle;
    }

    function getLastEpochId() external view returns (uint256) {
        return epochCount;
    }

    function timeUntilNextDistribution() external view returns (uint256) {
        uint256 nextAllowed = lastDistributionTime + MIN_DISTRIBUTION_INTERVAL;
        if (block.timestamp >= nextAllowed) return 0;
        return nextAllowed - block.timestamp;
    }
}
