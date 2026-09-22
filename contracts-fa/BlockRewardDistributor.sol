// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
    function getActiveValidatorCount() external view returns (uint256); // ✅ تازه: برای آستانه‌ی ۲/۳ رأی‌گیری دومجلسی پایین لازم است.
}

/// @notice ✅ تازه: اینترفیس حداقلی روی ValidatorsBoard، فقط برای چک عضویت هیأت‌مدیره در
///         رأی‌گیری دومجلسی پایین لازم است.
interface IValidatorsBoard {
    function isBoardMember(address who) external view returns (bool);
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
///         قواعد توزیع (✅ دوباره به‌روزشده — به sur-tokenomics.md بخش ۶.۵/۶/۱۱ برای استدلال
///         کامل اقتصادی و حکمرانی هر بخش مراجعه کنید):
///           - از کل ریوارد: سهم ۱۵٪ بنیاد (FOUNDATION_SHARE_BPS) اکنون مستقیم از بالای کل
///             ریوارد کسر می‌شود — برای همیشه ثابت، خودکار، بدون رأی‌گیری، و عمداً به‌عنوان
///             درصدی از هیچ‌چیز دیگری محاسبه **نمی‌شود** (نسخه‌های قبلی این قرارداد آن را
///             ۱۵٪ از یک «سهم خزانه‌ی ۵۰٪» حساب می‌کردند، یعنی درآمد بنیاد بی‌سروصدا با هر
///             تغییر آینده‌ی نسبت خزانه/ولیدیتور پایین جابه‌جا می‌شد — دقیقاً همان گره‌خوردگی‌ای
///             که طراحی ۱۵٪-ثابت-از-کل ازش جلوگیری می‌کند).
///           - از ۸۵٪ باقی‌مانده، تقسیم بین ولیدیتورها (مستقیم، به‌نسبت بلاک) و
///             ValidatorsTreasury توسط `validatorDirectShareBps` حکمرانی می‌شود — ✅ تازه:
///             قابل‌تغییر فقط از طریق یک رأی‌گیری دومجلسی (به proposeShareChange/
///             boardVoteShareChange/validatorVoteShareChange پایین مراجعه کنید)، محدود به
///             بازه‌ی [۴۰٪, ۶۵٪] از کل ریوارد، با یک دوره‌ی خنک‌سازی اجباری ۶ماهه بین
///             تغییرات موفق متوالی. هر دو مجلس — اکثریت ساده‌ی ValidatorsBoard **و** اکثریت
///             دوسوم کل مجمع ولیدیتورهای فعال — باید مستقلاً همان یک پیشنهاد را تصویب کنند
///             تا اجرا شود. این عمداً از انگیزه‌های متضاد این دو مجلس (ولیدیتورهای عادی به
///             سمت سهم مستقیم بزرگ‌تر کشیده می‌شوند؛ هیأت‌مدیره به سمت خزانه‌ی بزرگ‌تر، چون
///             خزانه‌ی بزرگ‌تر یعنی اختیار خرج صلاحدیدی بیشتر زیر قدرت تصویب هزینه‌ی کوچک
///             خودش) به‌عنوان یک بازدارنده‌ی داخلی در برابر تخلیه‌ی یک‌طرفه‌ی سهم دیگری توسط
///             هرکدام از این دو مجلس در طول زمان استفاده می‌کند.
///           - از کل فی: ✅ تازه — یک ۳۰٪ ثابت (FEE_BURN_BPS) اکنون هر epoch برای همیشه
///             سوزانده می‌شود (به BURN_ADDRESS = address(0) فرستاده می‌شود)؛ ۷۰٪ باقی‌مانده
///             دقیقاً مثل قبل به نسبت بلاک تولیدی بین ولیدیتورها تقسیم می‌شود (همچنان بدون
///             سهم خزانه یا بنیاد از بخش توزیع‌شده). به کامنت خودِ FEE_BURN_BPS و
///             sur-tokenomics.md بخش ۷ مراجعه کن که چرا فی (نه ریوارد) به‌عنوان هدف سوزاندن
///             انتخاب شد، و چرا دقیقاً ۳۰٪.
///           - کارمزد عضویت معلق: ValidatorsRegistry.requestMembership() دیگر کارمزد عضویت
///             را به ValidatorsTreasury نمی‌فرستد. به‌جایش آن را از طریق
///             receiveMembershipFee() به همین قرارداد می‌فرستد، جایی که در
///             `pendingMembershipFees` انباشته و در *epoch بعدی* به استخر فی همان epoch اضافه
///             می‌شود — ✅ کاملاً از سوزاندن ۳۰٪ بالا معاف (۱۰۰٪ آن به ولیدیتورها می‌رسد،
///             برخلاف فی معمولی)، ولی از نظر نحوه‌ی تقسیم بین ولیدیتورها همان رفتار
///             ۱۰۰٪-به‌نسبت-بلاک فی‌های معمولی را دارد — به sur-tokenomics.md بخش
///             ۶ مراجعه کنید که چرا: این یک انگیزه‌ی نقدی مستقیم و قابل‌ردیابی به ولیدیتورهای
///             موجود برای هر ولیدیتور تازه‌ای که می‌پیوندد می‌دهد). یعنی کارمزد عضو تازه در
///             همان بلاک ثبت‌نامش پرداخت نمی‌شود — در epoch بعدی distributionOracle (~۲۳
///             ساعت بعد) پرداخت می‌شود، دقیقاً مثل فی‌های معمولی.
///           - هر ولیدیتور دقیقاً یک پرداخت در هر فراخوانی دریافت می‌کند (یک انتقال ترکیبی
///             از سهم ریوارد + سهم فی، که «سهم فی» اکنون شامل هر کارمزد عضویت معلق تجمیع‌شده
///             در همان epoch هم می‌شود).
///
///         صلاحیت ولیدیتور مستقیم و on-chain در برابر ValidatorsRegistry چک می‌شود — هیچ
///         لیست سفید داخلی و هیچ «اوراکل همگام‌سازی ولیدیتور» دومی وجود ندارد (آن طراحی وقتی
///         انتخاب ولیدیتور به حالت contract-mode رفت و خودِ ValidatorsRegistry مرجع واحد هم
///         برای اجماع هم برای پرداخت شد، کنار گذاشته شد؛ بخش ۵ سند طراحی را ببین).
///
///         دیپلوی genesis: این قرارداد constructor ندارد — مستقیم در alloc genesis تزریق
///         می‌شود، پس constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود. آدرس‌های
///         ValidatorsRegistry، ValidatorsTreasury، و ValidatorsBoard ثابت (constant) هستند
///         (به SurAddresses.sol مراجعه کن)، چون هر شش قرارداد ساختاری یک نقشه‌ی آدرس مشترک و
///         از‌پیش‌توافق‌شده در genesis دارند. کلید اولیه‌ی distributionOracle (یک اعتبارنامه‌ی
///         عملیاتی واقعاً قابل‌چرخش، نه یک قرارداد ساختاری) و genesis timestamp واقعی، به‌جایش
///         با ابزار genesis آف‌چین پر می‌شوند (یادداشت‌های 🔶 پرکردنِ genesis پایین را ببین، و
///         "sur-contracts-deploy-notes.md" را برای این‌که چرا genesis timestamp واقعی را
///         نمی‌شود مستقیم از `block.timestamp` یک محیط شبیه‌سازی‌شده خواند).
contract BlockRewardDistributor {
    // ------------------------------------------------------------------
    // ثابت‌ها و تنظیمات
    // ------------------------------------------------------------------

    /// @notice سهم بنیاد از کل ریوارد (نه از هیچ زیرمجموعه‌ای) — بیسیس‌پوینت از ۱۰۰۰۰ = ۱۰۰٪.
    ///         ✅ تغییر کرد: برای همیشه ثابت، مستقیم روی totalRewards اعمال می‌شود، و عمداً
    ///         مستقل از validatorDirectShareBps پایین — به sur-tokenomics.md بخش ۶.۵ و کامنت
    ///         سطح قرارداد بالا مراجعه کنید که چرا این باید از نسبت حکمرانی‌شونده‌ی
    ///         خزانه/ولیدیتور جدا بماند.
    uint256 public constant FOUNDATION_SHARE_BPS = 1500; // ۱۵٪ از کل ریوارد، همیشه

    /// @notice ✅ تازه (جایگزین ثابت قدیمی TREASURY_SHARE_BPS): سهم مستقیم و به‌نسبت‌بلاک
    ///         ولیدیتورها از کل ریوارد — بیسیس‌پوینت از ۱۰۰۰۰. با همون ۵۰٪ ثابت قدیمی شروع
    ///         می‌شود، ولی اکنون یک متغیر state حکمرانی‌شونده است، فقط از طریق رأی‌گیری
    ///         دومجلسی پایین (proposeShareChange / boardVoteShareChange /
    ///         validatorVoteShareChange) قابل‌تغییر، محدود به [VALIDATOR_SHARE_MIN_BPS,
    ///         VALIDATOR_SHARE_MAX_BPS]. ValidatorsTreasury هرچه بعد از سهم ثابت ۱۵٪ بنیاد و
    ///         این سهم باقی بماند را دریافت می‌کند:
    ///         treasuryShare = 10000 - FOUNDATION_SHARE_BPS - validatorDirectShareBps.
    uint256 public validatorDirectShareBps = 5000; // ۵۰٪ در ابتدا — همون نقطه‌ی شروع قبلی

    uint256 public constant VALIDATOR_SHARE_MIN_BPS = 4000; // کف ۴۰٪
    uint256 public constant VALIDATOR_SHARE_MAX_BPS = 6500; // سقف ۶۵٪
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice ✅ تازه: بخش ثابتی از **فی معمولی تراکنش** (نه کارمزد عضویت — به کامنت
    ///         distributeRewards() مراجعه کن که چرا عمداً معافه) که هر epoch، قبل از توزیع
    ///         ۷۰٪ باقی‌مانده دقیقاً مثل قبل بین ولیدیتورها، برای همیشه سوزانده می‌شود. به
    ///         sur-tokenomics.md بخش ۷ برای استدلال کامل مراجعه کن: چون
    ///         منبع غالب تورم سورن خودِ ریوارده نه فی، سوزاندن فی به‌تنهایی تورم را خنثی
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

    /// @notice حداقل دوره‌ی تولید بلاک در شبکه (از genesis: qbft.blockperiodseconds).
    ///         برای بررسی سلامتی تعداد بلاک گزارش‌شده توسط اوراکل استفاده می‌شود.
    uint256 public constant MIN_BLOCK_PERIOD_SECONDS = 3;

    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — دریافت‌کننده‌ی هرچه از استخر ریوارد باقی بماند بعد از کسر
    ///         سهم ثابت ۱۵٪ بنیاد و سهم مستقیم حکمرانی‌شونده‌ی ولیدیتورها (دیگر یک «سهم ثابت
    ///         ۵۰٪» نیست — به validatorDirectShareBps مراجعه کن).
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice FoundationDAO — سهم تازه‌ی خودکار ۱۵٪-از-سهم-خزانه را هر epoch دریافت می‌کند.
    ///         این تنها اتصال ورودی بنیاد به جریان ریوارد است؛ هیچ‌وقت نیازی به فراخوانی
    ///         چیزی برای دریافتش ندارد (کامنت‌های FoundationDAO.sol را ببینید).
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

    /// @notice ✅ تازه: نمای فقط‌خواندنی روی ValidatorsBoard، فقط برای چک عضویت هیأت‌مدیره در
    ///         رأی‌گیری دومجلسی پایین لازم است.
    IValidatorsBoard public constant BOARD_CONTRACT = IValidatorsBoard(SurAddresses.VALIDATORS_BOARD);

    /// @notice معادل ValidatorsBoard.BOARD_SIZE — هیأت‌مدیره همیشه دقیقاً همین تعداد عضو
    ///         دارد، پس اکثریت ساده یعنی BOARD_SIZE/2 + 1 (یعنی ۳ از ۵).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice ✅ تازه: حداقل فاصله‌ی زمانی بین دو تغییر موفق متوالی validatorDirectShareBps —
    ///         عمداً کند (~۶ ماه) تا این پارامتر نتواند به‌سرعت و پشت‌سرهم توسط هیچ‌کدام از دو
    ///         مجلس تکان بخورد. به sur-tokenomics.md بخش ۱۱ مراجعه کنید که چرا.
    uint256 public constant SHARE_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastShareChangeTime;


    /// @notice آدرس اوراکلی که مجاز به فراخوانی تابع توزیع دوره‌ای است. تنها وظیفه‌اش گزارش
    ///         تعداد بلاک و مجموع ریوارد/فی است؛ نمی‌تواند به هیچ آدرسی که ValidatorsRegistry
    ///         الان به‌عنوان فعال نمی‌شناسد پرداخت کند.
    /// @dev ✅ پرشده: آدرس اولیه‌ی distributionOracle، خوانده‌شده از SurAddresses.sol (منبع
    ///      واحد صحت برای هر چهار آدرس اوراکل — دلیلش را در آن فایل ببین).
    address public distributionOracle = SurAddresses.DISTRIBUTION_ORACLE;

    /// @dev 🔶 FILL_IN: genesis timestamp واقعی شبکه‌ی زنده (نه block.timestamp هر ماشین/لحظه‌ای
    ///      که شبیه‌سازی رویش اجرا می‌شود — به sur-contracts-deploy-notes.md مراجعه کن که چرا
    ///      block.timestamp اینجا غیرقابل‌اتکاست). به‌صورت `immutable` اعلان شده تا این مقدار
    ///      مستقیم در بایت‌کد دیپلوی‌شده جاسازی شود، دقیقاً مثل حالتی که در constructor
    ///      تنظیم می‌شد.
    uint256 public immutable deployTime = 0;
    uint256 public lastDistributionTime;
    uint256 public epochCount;

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

    /// @notice ✅ تازه: یک پیشنهاد دومجلسی برای تغییر validatorDirectShareBps. نیازمند تأیید
    ///         مستقل از **هردو**: اکثریت ساده‌ی ValidatorsBoard **و** اکثریت دوسوم کل مجمع
    ///         ولیدیتورهای فعال، پیش از اجرا شدن — به proposeShareChange/boardVoteShareChange/
    ///         validatorVoteShareChange پایین مراجعه کنید.
    /// @dev ✅ اصلاح‌شده (باگ بحرانی رأی مانده‌شده‌ی پیداشده در بازبینی): `requiredValidatorApprovals`
    ///      حالا فقط یک‌بار در لحظه‌ی ثبت پیشنهاد snapshot می‌شه (از تعداد ولیدیتور فعال همون
    ///      لحظه)، نه این‌که هر بار رأی زنده دوباره محاسبه بشه. قبلاً `validatorApprovals` یه
    ///      شمارنده‌ی ساده بود که فقط زیاد می‌شد (هرگز کم نمی‌شد وقتی یه ولیدیتورِ رأی‌داده بعداً
    ///      خارج می‌شد)، درحالی‌که `required` هر بار از تعداد فعال *فعلی* دوباره حساب می‌شد. این
    ///      یعنی یه پیشنهاد که به نصاب نرسیده بود، می‌تونست بعداً، بدون هیچ رأی تازه‌ای، فقط
    ///      به‌خاطر کوچیک‌شدن شبکه، خودبه‌خود قابل‌اجرا بشه — یه باگ کلاسیک حکمرانی. snapshot
    ///      گرفتن آستانه در لحظه‌ی ثبت، این رو می‌بنده: سقفی که یه پیشنهاد باید ازش رد بشه،
    ///      همون لحظه‌ی ثبتش قفل می‌شه. همراه با `expiresAt` پایین (که اونم تازه‌ست)، یه
    ///      پیشنهاد که نتونه توی یه پنجره‌ی محدود به آستانه‌ی *خودش* برسه، ساده منقضی می‌شه،
    ///      نه این‌که بی‌نهایت باز بمونه و منتظر کوچیک‌شدن جمعیت رأی‌دهنده باشه.
    struct ShareProposal {
        uint256 newValidatorShareBps;
        uint256 createdAt;
        uint256 expiresAt; // ✅ تازه — بعد از این، دیگه قابل‌رأی یا اجرا نیست
        uint256 requiredValidatorApprovals; // ✅ تازه — در لحظه‌ی ثبت snapshot می‌شه، هرگز دوباره محاسبه نمی‌شه
        uint256 boardApprovals;
        uint256 validatorApprovals;
        bool boardPassed;
        bool validatorPassed;
        bool executed;
    }

    /// @notice ✅ تازه: مدت زمانی که یه پیشنهاد بعد از ثبت هنوز قابل‌رأی/اجراست. عمداً به‌وضوح
    ///         کوتاه‌تر از SHARE_CHANGE_MIN_INTERVAL (۱۸۰ روز) — پیشنهادی که ظرف ۳۰ روز نتونه
    ///         رأی لازم رو جمع کنه، باید دوباره از نو (با یه snapshot تازه از جمعیت) ثبت بشه،
    ///         نه این‌که بی‌نهایت باز بمونه.
    uint256 public constant PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ShareProposal) public shareProposals;
    mapping(uint256 => mapping(address => bool)) private shareBoardVoted;
    mapping(uint256 => mapping(address => bool)) private shareValidatorVoted;
    uint256 public shareProposalCount;

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
    ///         ولیدیتور تازه را اینجا بفرستد، به‌جای مستقیم به ValidatorsTreasury (رفتار
    ///         قبلی). مبلغ صرفاً انباشته می‌شود تا فراخوانی distributeRewards() بعدی، جایی که
    ///         به استخر فی همان epoch اضافه می‌شود — ✅ کاملاً از سوزاندن ۳۰٪ معاف (برخلاف فی
    ///         معمولی)، ولی از نظر نحوه‌ی تقسیم بین ولیدیتورها دقیقاً ۱۰۰٪-به‌نسبت-بلاک
    ///         پرداخت می‌شود — به sur-tokenomics.md بخش ۶ مراجعه کنید که چرا این طراحی (یک
    ///         انگیزه‌ی نقدی مستقیم و قابل‌ردیابی به‌ازای هر عضویت تازه) به‌جای پرداخت فوری
    ///         همان‌لحظه انتخاب شد — پرداخت فوری نیازمند یک حلقه‌ی نامحدود روی همه‌ی
    ///         ولیدیتورهای فعال درون خودِ requestMembership() می‌بود؛ یک ریسک واقعی سقف گس/DoS
    ///         با رشد جمعیت ولیدیتور، و تکرار منطقی که همین‌جا از قبل درست پیاده شده.
    function receiveMembershipFee() external payable {
        require(msg.sender == REGISTRY_ADDRESS, "BlockRewardDistributor: only ValidatorsRegistry may forward membership fees");
        pendingMembershipFees += msg.value;
        emit MembershipFeeReceived(msg.value, pendingMembershipFees);
    }

    // ------------------------------------------------------------------
    // ✅ تازه: حکمرانی دومجلسی برای validatorDirectShareBps (نسبت خزانه در برابر ولیدیتور —
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
            executed: false
        });
        emit ShareChangeProposed(id, newValidatorShareBps, msg.sender);
    }

    /// @notice یکی از دو رأی لازم — مجلس ValidatorsBoard. اکثریت ساده از BOARD_SIZE ثابت
    ///         (۵)، یعنی ۳ رأی.
    function boardVoteShareChange(uint256 id) external {
        require(BOARD_CONTRACT.isBoardMember(msg.sender), "BlockRewardDistributor: caller is not a board member");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
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

    /// @notice رأی لازم دیگر — مجلس کل مجمع ولیدیتورها. ✅ اصلاح‌شده: حالا در برابر
    ///         `requiredValidatorApprovals` چک می‌شه که یک‌بار در لحظه‌ی ثبت پیشنهاد
    ///         snapshot شده — به کامنت struct ShareProposal مراجعه کن که چرا محاسبه‌ی زنده
    ///         (رفتار قبلی) یه آسیب‌پذیری رأی-مانده‌شده بود.
    function validatorVoteShareChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");

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
            p.executed = true;
            validatorDirectShareBps = p.newValidatorShareBps;
            lastShareChangeTime = block.timestamp;
            emit ShareChangeApplied(id, p.newValidatorShareBps);
        }
    }

    // تابع اصلی توزیع دوره‌ای — فقط توسط اوراکل توزیع قابل‌فراخوانی است
    //
    // ✅ بازنویسی‌شده (دیگر نیازی به viaIR برای کامپایل ندارد): نسخه‌ی اولیه‌ی این تابع
    // (یک تابع بزرگ و یکپارچه) هم‌زمان متغیر محلی بیشتری از پنجره‌ی ۱۶لایه‌ای دستکاری استک
    // EVM در پایپ‌لاین کدسازی قدیمی (غیر-IR) داشت — یک خطای واقعی کامپایلر «Stack too deep»،
    // که دقیقاً یکسان هم در نسخه‌ی انگلیسی هم در نسخه‌ی فارسی این فایل تأیید شد. به‌جای نیاز
    // به viaIR (که خیلی از سرویس‌های وریفای، از جمله Blockscout، نمی‌توانند در برابرش وریفای
    // کنند — sur-contracts-deploy-notes.md را ببین)، منطق به سه تابع تقسیم شده، هرکدام با
    // stack frame مستقل خودشان و در نتیجه متغیر هم‌زمان بسیار کمتر. رفتار، ترتیب event، و هر
    // شرط require() نسبت به نسخه‌ی تک‌تابعی اصلی بدون تغییر است.
    // ------------------------------------------------------------------
    /// @param validators لیست آدرس ولیدیتورها (بدون تکرار)
    /// @param blocksMined تعداد بلاک تولیدشده توسط هر ولیدیتور از آخرین فراخوانی به بعد (همون ترتیب validators)
    /// @param totalRewards مجموع ریوارد این epoch (به wei) — آف‌چین توسط اوراکل، از ورودی‌های «reward» تابع trace_block محاسبه می‌شود
    /// @param totalFees مجموع فی تراکنش‌های این epoch (به wei) — آف‌چین توسط اوراکل، از eth_getTransactionReceipt.gasUsed ضرب‌در effectiveGasPrice برای هر تراکنش محاسبه می‌شود (هرگز از خروجی trace_*، که برای انتقال‌های ساده gasUsed=0 گزارش می‌کند)
    function distributeRewards(
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

        // هر کارمزد عضویتی که از epoch قبلی ValidatorsRegistry فرستاده به استخر فی همین epoch
        // اضافه می‌شود — از قبل در موجودی این قرارداد هست (از طریق receiveMembershipFee()
        // دریافت شده). ✅ این کارمزد عضویت با فی معمولی یکی نیست: کاملاً از سوزاندن ۳۰٪ زیر
        // معاف است (فقط totalFees معمولی سوزانده می‌شود، نه membershipFeesThisEpoch) — فقط
        // از نظر نحوه‌ی تقسیم نهایی بین ولیدیتورها همان رفتار ۱۰۰٪-به‌نسبت-بلاک را می‌گیرد.
        // به sur-tokenomics.md بخش ۶ مراجعه کنید.
        uint256 membershipFeesThisEpoch = pendingMembershipFees;
        pendingMembershipFees = 0;
        uint256 effectiveTotalFees = totalFees + membershipFeesThisEpoch;

        require(totalRewards + effectiveTotalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalRewards + effectiveTotalFees <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        // ✅ تازه: ۳۰٪ ثابت سوزانده می‌شود — ولی **فقط از فی معمولی تراکنش‌ها** (totalFees)،
        // عمداً نه از کارمزد عضویت. دلیل (به sur-tokenomics.md بخش ۶ مراجعه کن): کارمزد عضویت
        // اصلاً یه فی عمومی شبکه نیست — یه پرداخت هدفمند و یک‌باره‌ی جبران رقیق‌شدن به
        // ولیدیتورهای موجوده، که با ورود ولیدیتور تازه فعال می‌شه. سوزوندن بخشی ازش، این
        // انگیزه‌ی مشخص رو به‌عنوان یه اثر جانبی ناخواسته‌ی یه تصمیم بعدی و بی‌ربط (سوزاندن
        // عمومی فی) ضعیف می‌کنه. فی معمولی چنین هدف‌گذاری‌ای نداره، پس هدف درست — و تنها هدف
        // — سوزاندنه.
        uint256 feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS_DENOMINATOR;
        uint256 feesToDistribute = effectiveTotalFees - feeBurnAmount;

        uint256 totalBlocks = _sumBlocks(blocksMined);
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
        _checkPhysicalMaximum(totalBlocks);

        epochCount++;
        uint256 epochId = epochCount;

        // ✅ تغییر کرد: سهم بنیاد اکنون ۱۵٪ ثابت از کل ریوارد است، مستقل و از بالای کل کسر
        // می‌شود — هرگز تحت‌تأثیر validatorDirectShareBps پایین نیست. فقط ریوارد این‌طور
        // تقسیم می‌شود؛ فی (پایین) هرگز توسط هیچ‌کدام از این سه سهم لمس نمی‌شود.
        uint256 foundationAmount = (totalRewards * FOUNDATION_SHARE_BPS) / BPS_DENOMINATOR;
        // validatorDirectShareBps حکمرانی‌شونده است (رأی دومجلسی، [۴۰٪, ۶۵٪]) — کامنت سطح
        // قرارداد بالا را ببینید. ValidatorsTreasury هرچه بعد از سهم ثابت بنیاد و این سهم
        // حکمرانی‌شونده باقی بماند را دریافت می‌کند.
        uint256 validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS_DENOMINATOR;
        uint256 treasuryAmount = totalRewards - foundationAmount - validatorDirectAmount;

        (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) =
            _payValidators(
                validators,
                blocksMined,
                EpochContext({
                    epochId: epochId,
                    remainingRewards: validatorDirectAmount,
                    totalFees: feesToDistribute,
                    totalBlocks: totalBlocks
                })
            );

        _finalizeEpoch(
            epochId,
            totalRewards,
            effectiveTotalFees,
            feeBurnAmount,
            treasuryAmount,
            foundationAmount,
            totalBlocks,
            validatorCount,
            distributedRewards,
            distributedFees
        );
    }

    /// @dev جمع تعداد بلاک گزارش‌شده‌ی هر ولیدیتور. فقط برای کوچک‌نگه‌داشتن stack frame خودِ
    ///      distributeRewards از آن جدا شده (یادداشت بازنویسی بالا را ببین) — بدون تغییر
    ///      رفتار نسبت به حلقه‌ی inline اصلی.
    function _sumBlocks(uint256[] calldata blocksMined) private pure returns (uint256 totalBlocks) {
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
    }

    /// @dev بررسی سلامتی: تعداد بلاک گزارش‌شده نمی‌تواند از حداکثر فیزیکی این بازه‌ی زمانی
    ///      بیشتر باشد. برای epoch صفر رد می‌شود — کامنت اصلی که از آن منتقل شده، کامل پایین
    ///      حفظ شده. فقط به‌خاطر عمق استک از تابع اصلی جدا شده.
    ///
    ///      برای epoch صفر رد می‌شود: deployTime همان genesis timestamp است، ولی راه
    ///      قابل‌اتکایی برای محدودکردن دقیق‌تر «زمان از genesis» غیر از «از deployTime»
    ///      وجود ندارد، و اولین فراخوانی توزیع یک شبکه ممکن است به‌طور مشروع یک دوره‌ی
    ///      ابتدایی طولانی را پوشش دهد (مثلاً بیشتر از MIN_DISTRIBUTION_INTERVAL اگر اوراکل
    ///      دیر شروع شده باشد) — این محدودیت فقط وقتی معنا دارد که lastDistributionTime یک
    ///      timestamp واقعی و on-chain از یک فراخوانی قبلی باشد.
    function _checkPhysicalMaximum(uint256 totalBlocks) private view {
        if (epochCount > 0) {
            uint256 elapsed = block.timestamp - lastDistributionTime;
            uint256 maxPossibleBlocks = elapsed / MIN_BLOCK_PERIOD_SECONDS;
            require(totalBlocks <= maxPossibleBlocks, "BlockRewardDistributor: reported blocks exceed physical maximum");
        }
    }

    /// @dev بسته‌بندی چهار ورودی مقیاسی موردنیاز `_payValidators` در یک struct در memory —
    ///      یک struct با یک اشاره‌گر (یک slot استک) پاس داده می‌شود، نه چهار slot جدا؛ همین
    ///      چیزی است که اجازه داد stack frame خودِ این تابع زیر سقف ۱۶لایه جا بگیرد (یادداشت
    ///      بازنویسی بالای distributeRewards را ببین).
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
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            require(REGISTRY.isValidator(validator), "BlockRewardDistributor: address is not an active validator");

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
    ///      epoch، و emit کردن event نهایی — دقیقاً همان دنباله‌ی inline اصلی
    ///      distributeRewards، فقط به‌خاطر عمق استک به تابع جدا منتقل شده (یادداشت بازنویسی
    ///      بالا را ببین). بدون تغییر رفتار، event، یا ترتیب.
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
        // ✅ تغییر کرد: totalFees اینجا کل استخر فی *قبل از سوزاندن* است (برای شفافیت رکورد
        // epoch/رویداد — به distributeRewards مراجعه کن). پس feeDust باید هم feeBurnAmount هم
        // distributedFees را کم کند، وگرنه ۳۰٪ سوزانده‌شده به‌اشتباه «خرده‌ریز» حساب و یک بار
        // دیگر (روی سوزاندن قبلی‌اش) به خزانه فرستاده می‌شد.
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

        // ✅ تازه: بخش سوزاندنی فی را واقعاً بسوزان — بعد از انتقال‌های خزانه/بنیاد، صرفاً
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
