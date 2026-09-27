// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
}

/// @title ValidatorsTreasury
/// @notice در آدرس ثابت genesis، SurAddresses.VALIDATORS_TREASURY (0x5555...5555) دیپلوی می‌شود.
///         فقط سورن بومی نگه می‌دارد — سورن ارز پایه/گس خودِ زنجیره‌ی سور است (مثل ETH روی
///         اتریوم، از طریق موجودی‌های `alloc` genesis و انتقال‌های ارزشی معمولی اعتبار می‌گیرد)،
///         نه یک توکن ERC20، پس هیچ قرارداد توکن جدا یا `transferFrom`ای هیچ‌جای این سیستم
///         دخیل نیست.
///
///         دو ورودی، هردو ارز بومی:
///           - هرچی از بلاک‌ریوارد بعد از کسر سهم ثابت ۱۵٪ بنیاد (از کل ریوارد) و سهم مستقیم
///             حکمرانی‌شونده‌ی خودِ ولیدیتورها (validatorDirectShareBps، [۴۰٪, ۶۵٪] از کل)
///             باقی می‌مونه — به sur-tokenomics.md بخش‌های ۶.۵/۶.۶ مراجعه کن. فی تراکنش‌ها
///             هرگز به اینجا نمی‌رسه — ۷۰٪ فی مستقیم به‌نسبت بلاک به ولیدیتورها می‌ره، و ۳۰٪
///             باقی‌مانده برای همیشه سوزانده می‌شه (بخش ۷) — خزانه از هیچ‌کدوم سهمی نداره.
///           - وثیقه‌ی جریمه‌شده که مستقیماً توسط ValidatorsRegistry در هر دموت‌شدن به‌خاطر
///             غیرفعالی فوروارد می‌شه. کارمزد عضویت به‌جاش به BlockRewardDistributor می‌ره.
///
///         ✅ بازطراحی‌شده (تصمیم صریح کاربر — خرج مستقیم مجمع کامل کاملاً حذف شد): مجمع (همه‌ی
///         ولیدیتورهای فعال) دیگه هیچ مسیری برای پیشنهاد یا تصویب یه پرداخت مشخص از این خزانه
///         نداره. نقشش الان محدوده به تعیین/تغییرِ **قواعد خرج** که هیأت‌مدیره باید توش کار کنه
///         (سقف هر پرداخت، سقف کل چرخشی ۳۰روزه، و این‌که یه تغییر قاعده چقدر قبل از اجرا صبر
///         کنه) — هرگز یه پرداخت مشخص. الان هر خرج واقعی فقط از طریق ValidatorsBoard می‌گذره،
///         محدود به همین قواعدِ تعیین‌شده‌ی مجمع. دلیل (طبق گفته‌ی کاربر): وجود دو مسیر موازی
///         برای همون یه نوع تصمیم (رأی مجمع در برابر رأی هیأت‌مدیره) باعث «venue shopping»
///         می‌شد — امتحان‌کردن هر مسیری که احتمال تصویب یه پرداخت خاص توش بیشتره. یه مسیر واحد
///         با محدودیت‌های تعیین‌شده‌ی مجمع، این ابهام رو برمی‌داره، درحالی‌که کنترل نهایی مجمع
///         روی این‌که کلاً چقدر می‌شه خرج کرد رو حفظ می‌کنه، فقط نه تصویب هر پرداخت تک‌تک.
///
///         دیپلوی genesis: آدرس ValidatorsBoard یه ثابته (SurAddresses.sol را ببین)، نه یک
///         state متغیر که با یک گام runtime `wire()` تنظیم بشه، چون هر پنج قرارداد ساختاری
///         یک نقشه‌ی آدرس genesis مشترک و از‌پیش‌توافق‌شده دارند.
contract ValidatorsTreasury {
    // ------------------------------------------------------------------
    // آدرس‌های ثابت بین‌قراردادی (SurAddresses.sol را ببین)
    // ------------------------------------------------------------------

    /// @notice تنها آدرسی که مجاز است واقعاً از این خزانه خرج کند.
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    bool private locked; // محافظ reentrancy

    uint256 public totalDistributedToTreasury; // کل ورودی طول عمر (سهم ریوارد + وثیقه‌ی جریمه‌شده)
    uint256 public totalSpent;                 // کل خرج‌شده در طول عمر توسط هیأت‌مدیره

    // ------------------------------------------------------------------
    // ✅ تازه — قواعد خرج (محدودیت‌های حکمرانی‌شونده توسط مجمع که هیأت‌مدیره باید توش کار کنه)
    // ------------------------------------------------------------------

    /// @notice سقف هر پرداخت تکی تصویب‌شده توسط هیأت‌مدیره. هر پرداختی مساوی یا بیشتر از این،
    ///         مستقیماً رد می‌شه — عمداً **هیچ مسیر جایگزینی** برای پرداخت بزرگ‌تر نیست (به
    ///         کامنت سطح قرارداد بالا مراجعه کن: مسیر فرار قدیمی «رأی کامل مجمع برای هر مبلغی»
    ///         عمداً حذف شد). تنها راه یه پرداخت بزرگ‌تر اینه که اول این سقف رو از طریق
    ///         proposeCapChange() پایین بالا ببری، منتظر گذشت CAP_CHANGE_TIMELOCK_DELAY بمونی،
    ///         و بعد زیر سقف تازه از همون مسیر معمولی خرج کنی — هرگز توی همون تراکنش یا رأی
    ///         خودِ تغییر سقف.
    /// @dev 🔶 FILL_IN (دستور صریح کاربر: این عدد رو حدس نزن — یه تصمیم واقعی قبل از genesis،
    ///      برحسب wei سورن بومی).
    uint256 public perPaymentCap = 0;

    /// @notice سقف روی **مجموع** همه‌ی پرداخت‌های تصویب‌شده‌ی هیأت‌مدیره در تقریباً ۳۰ روز اخیر
    ///         — یه تقریب با دانه‌بندی روزانه (dailySpend پایین را ببین)، نه یه پنجره‌ی
    ///         چرخشیِ دقیقِ ثانیه‌به‌ثانیه. ⚠️ **تصحیح صادقانه (پیداشده در بازبینی مستقل — یه
    ///         نسخه‌ی قبلی این کامنت ادعای دقتی بیش از واقعیت داشت):** چون `_currentDay()` با
    ///         روز تقویمی سطل‌بندی می‌کنه (`block.timestamp / 1 days`، یعنی مرزهای روز UTC)،
    ///         یه پرداخت می‌تونه تا ~۲۴ ساعت زودتر یا دیرتر از یه پنجره‌ی دقیق ۳۰×۲۴ساعته از
    ///         محاسبه بیفته بیرون، بسته به این‌که چه ساعتی از روزِ سطلش پرداخت شده. این
    ///         همچنان به‌طرز معناداری بهتر از یه ریست دوره‌ای ساده‌ست (که یه مرز واحد، ثابت،
    ///         و بارها قابل‌سوءاستفاده هر ۳۰ روز داره) — لغزش سطل‌روزانه کوچیک، محدود، و در یه
    ///         نقطه‌ی ثابت قابل‌سوءاستفاده تکرار نمی‌شه — ولی نباید به‌عنوان یه پنجره‌ی چرخشی
    ///         دقیق توصیف بشه. اگه دقت ثانیه‌ای دقیق لازم بشه، خودِ الگوریتم باید عوض بشه
    ///         (مثلاً یه لاگ timestamp‌دار که به‌ازای هر پرداخت جمع و هرس بشه، با هزینه‌ی گس
    ///         به‌طرز معناداری بیشتر). هر پرداختی، صرف‌نظر از مقصد یا توضیحش، توی همین مجموع
    ///         مشترک حساب می‌شه — خردکردن یه پرداخت بزرگ به چندتای کوچیک‌تر، یا فرستادن به
    ///         گیرنده‌های مختلف، بودجه‌ی جدا نمی‌سازه.
    /// @dev 🔶 FILL_IN (دستور صریح کاربر: این عدد رو حدس نزن — یه تصمیم واقعی قبل از genesis،
    ///      برحسب wei سورن بومی).
    uint256 public periodCap = 0;

    /// @notice یه تغییر تصویب‌شده‌ی مجمع روی perPaymentCap یا periodCap چقدر باید قبل از اجرا
    ///         صبر کنه — عمداً جدا از خودِ رأی، تا افزایش سقف و پرداخت زیر سقف تازه هرگز توی
    ///         همون لحظه اتفاق نیفتن (طبق دستور صریح کاربر: «افزایش سقف و خرج‌کردن در همان
    ///         لحظه ممکن نباشد»). 🔶 FILL_IN: این تأخیر خاص جزو دو عددی نبود که کاربر صریح گفت
    ///         حدس نزن، ولی با توجه به این‌که مستقیم روی این‌که چقدر سریع می‌شه یه افزایش سقف
    ///         رو سوءاستفاده کرد اثر می‌ذاره، همچنان باید تأیید بشه، نه این‌که بی‌صدا بهش
    ///         تکیه بشه — ۷ روز اینجا **فقط به‌عنوان placeholder کاری** استفاده شده (هم‌مقیاس
    ///         با مهلت رأی‌گیری استفاده‌شده در مکانیزم‌های حکمرانی تازه‌تر این پروژه)، نه یه
    ///         مقدار تصمیم‌گیری‌شده.
    uint256 public constant CAP_CHANGE_TIMELOCK_DELAY = 7 days;

    /// @notice تعداد سطل‌های روزانه‌ای که برای چک پنجره‌ی چرخشی جمع می‌شن — دقیقاً ۳۰ تا، تا
    ///         با «۳۰ روز» دقیق مطابقت داشته باشه؛ هر چک دقیقاً همین‌تعداد خوندن storage
    ///         می‌کنه، یه هزینه‌ی گس کوچیک، ثابت، و قابل‌پیش‌بینی (نه نامحدود، نه وابسته به
    ///         این‌که چندتا پرداخت تا الان انجام شده).
    uint256 public constant ROLLING_WINDOW_DAYS = 30;

    /// @notice کل خرج تصویب‌شده‌ی هیأت‌مدیره برای یه شاخص روز مشخص (block.timestamp / 1 days).
    ///         فقط برای محاسبه‌ی مجموع چرخشی ۳۰روزه توی _rollingWindowSpend() پایین استفاده
    ///         می‌شه — هیچ‌جای دیگه‌ای خونده یا نوشته نمی‌شه.
    mapping(uint256 => uint256) public dailySpend;

    enum CapKind { PerPayment, Period }

    /// @dev ✅ اصلاح‌شده (همون کلاس باگ رأی‌مانده‌شده‌ی هر struct پیشنهاد دیگه‌ی این پروژه):
    ///      requiredVotes/expiresAt در لحظه‌ی ایجاد snapshot می‌شن، هرگز زنده دوباره محاسبه
    ///      نمی‌شن.
    struct CapChangeProposal {
        CapKind kind;
        uint256 newValue;
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed; // true می‌شه به‌محض این‌که **رأی مجمع** تصویب بشه — جدا از این‌که آیا
        // timelock گذشته و مقدار تازه واقعاً اجرا شده (pendingCapChange پایین و
        // applyPendingCapChange() را ببین).
    }

    uint256 public constant TREASURY_PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => CapChangeProposal) public capChangeProposals;
    mapping(uint256 => mapping(address => bool)) private capChangeHasVoted;
    uint256 public capChangeProposalCount;

    /// @notice تنها تغییر سقف معلق منتظر timelock، به‌ازای هر نوع سقف — یه پیشنهاد دومِ همون
    ///         نوع که تصویب بشه درحالی‌که یکی از قبل معلقه، فقط جایگزینش می‌کنه (با یه
    ///         timelock تازه‌شروع‌شده)، نه این‌که چند تغییر رو صف‌بندی کنه.
    struct PendingCapChange {
        uint256 newValue;
        uint256 effectiveAt;
        bool exists;
    }

    mapping(uint256 => PendingCapChange) public pendingCapChange; // با کلید uint256(CapKind)

    // ------------------------------------------------------------------
    // رویدادها
    // ------------------------------------------------------------------
    event RewardsReceived(address indexed from, uint256 amount);
    event BoardExpenditureExecuted(address indexed to, uint256 amount, string description);
    event CapChangeProposed(uint256 indexed id, CapKind kind, uint256 newValue, address indexed proposer);
    event CapChangeVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event CapChangeQueued(CapKind kind, uint256 newValue, uint256 effectiveAt);
    event CapChangeApplied(CapKind kind, uint256 oldValue, uint256 newValue);

    // ------------------------------------------------------------------
    // Modifier ها
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsTreasury: caller is not an active validator");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "ValidatorsTreasury: caller is not the board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "ValidatorsTreasury: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // 🔶 GENESIS FILL-IN — این قرارداد constructor ندارد چون مستقیم در genesis `alloc` تزریق
    // می‌شود (constructor‌اش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شد). برای دستورالعمل کامل به
    // "sur-contracts-deploy-notes.md" مراجعه کن.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // دریافت خودکار سورن بومی
    // ------------------------------------------------------------------
    receive() external payable {
        totalDistributedToTreasury += msg.value;
        emit RewardsReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // ✅ تنها مسیر خرج — فقط هیأت‌مدیره، محدود به قواعد تعیین‌شده‌ی مجمع
    // ------------------------------------------------------------------

    function _currentDay() private view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice دقیقاً ROLLING_WINDOW_DAYS سطل روزانه‌ی منتهی به امروز رو جمع می‌زنه — یه تقریب
    ///         با دانه‌بندی روزانه از یه پنجره‌ی ۳۰روزه (به کامنت periodCap بالا برای تذکر
    ///         صادقانه‌ی دقت مراجعه کن)، نه یه پنجره‌ی چرخشیِ دقیقِ ثانیه‌به‌ثانیه. همچنان
    ///         به‌طرز معناداری بهتر از یه ریست دوره‌ای ساده‌ست: هیچ مرز واحد، ثابت، و بارها
    ///         قابل‌سوءاستفاده‌ای هر ۳۰ روز، مثل یه ریست ساده، وجود نداره.
    function _rollingWindowSpend() private view returns (uint256 total) {
        uint256 today = _currentDay();
        for (uint256 i = 0; i < ROLLING_WINDOW_DAYS; i++) {
            total += dailySpend[today - i];
        }
    }

    /// @notice یه view تا هیأت‌مدیره (یا هرکسی) بتونه فضای باقیمانده‌ی پنجره‌ی چرخشی رو قبل از
    ///         پیشنهاد یه پرداخت چک کنه.
    function rollingWindowSpendNow() external view returns (uint256) {
        return _rollingWindowSpend();
    }

    /// @notice فقط توسط ValidatorsBoard صدا زده می‌شه، فقط بعد از این‌که اکثریت داخلی خودِ
    ///         هیأت‌مدیره (حداقل ۳ رأی، سخت و بدون‌قید نسبت به اندازه‌ی فعلی هیأت — به کامنت
    ///         proposeApproveBudget توی ValidatorsBoard.sol مراجعه کن) این درخواست رو تصویب
    ///         کرده باشه. ✅ هیچ مسیر جایگزینی برای پرداخت مساوی یا بیشتر از perPaymentCap
    ///         وجود نداره — به‌سادگی revert می‌شه. این عمدیه: بالابردن سقف (رأی مجمع + timelock)
    ///         تنها راه ممکن‌کردن یه پرداخت بزرگ‌تره، و هرگز توی همون لحظه‌ی خرج زیر همون سقف
    ///         نیست.
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external onlyBoard nonReentrant {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0 && amount < perPaymentCap, "ValidatorsTreasury: amount outside per-payment cap");
        require(amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");
        require(_rollingWindowSpend() + amount <= periodCap, "ValidatorsTreasury: 30-day period cap exceeded");

        dailySpend[_currentDay()] += amount; // صرف‌نظر از `to` یا `description` توی همین مجموع
        // چرخشی مشترک حساب می‌شه — خردکردن به پرداخت‌های کوچیک‌تر یا گیرنده‌های مختلف بودجه‌ی
        // جدا نمی‌سازه (به کامنت periodCap مراجعه کن).
        totalSpent += amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit BoardExpenditureExecuted(to, amount, description);
    }

    // ------------------------------------------------------------------
    // ✅ حکمرانی قواعد — رأی کامل مجمع ولیدیتورهای فعال، فقط تغییر سقف‌ها (هرگز یه پرداخت
    // مشخص). قواعدی که هیأت‌مدیره باید توش خرج کنه رو تعیین می‌کنه؛ خودش خرج نمی‌کنه.
    // ------------------------------------------------------------------

    /// @notice تغییر perPaymentCap یا periodCap رو پیشنهاد بده. تصویب رأی **بلافاصله اجرا
    ///         نمی‌شه** — پشت CAP_CHANGE_TIMELOCK_DELAY صف می‌کشه (applyPendingCapChange()
    ///         پایین را ببین)، پس یه افزایش سقف هرگز نمی‌تونه برای یه پرداخت بزرگ‌تر فوری
    ///         سوءاستفاده بشه.
    function proposeCapChange(CapKind kind, uint256 newValue) external onlyActiveValidator returns (uint256 id) {
        capChangeProposalCount++;
        id = capChangeProposalCount;
        capChangeProposals[id] = CapChangeProposal({
            kind: kind,
            newValue: newValue,
            votes: 0,
            requiredVotes: (REGISTRY.getValidators().length / 2) + 1, // الان منجمد شد
            createdAt: block.timestamp,
            expiresAt: block.timestamp + TREASURY_PROPOSAL_EXPIRY,
            executed: false
        });
        emit CapChangeProposed(id, kind, newValue, msg.sender);
        _voteCapChange(id, msg.sender);
    }

    function voteCapChange(uint256 id) external onlyActiveValidator {
        _voteCapChange(id, msg.sender);
    }

    function _voteCapChange(uint256 id, address voter) private {
        CapChangeProposal storage p = capChangeProposals[id];
        require(p.createdAt != 0, "ValidatorsTreasury: proposal not found");
        require(!p.executed, "ValidatorsTreasury: already executed");
        require(block.timestamp <= p.expiresAt, "ValidatorsTreasury: proposal has expired");
        require(!capChangeHasVoted[id][voter], "ValidatorsTreasury: already voted");

        capChangeHasVoted[id][voter] = true;
        p.votes++;

        emit CapChangeVoted(id, voter, p.votes, p.requiredVotes);

        if (p.votes >= p.requiredVotes) {
            p.executed = true;
            uint256 effectiveAt = block.timestamp + CAP_CHANGE_TIMELOCK_DELAY;
            pendingCapChange[uint256(p.kind)] = PendingCapChange({
                newValue: p.newValue,
                effectiveAt: effectiveAt,
                exists: true
            });
            emit CapChangeQueued(p.kind, p.newValue, effectiveAt);
        }
    }

    /// @notice بدون نیاز به مجوز — یه تغییر سقف صف‌شده رو بعد از گذشت timelockش اجرا می‌کنه.
    ///         عمداً جدا از خودِ رأیه (همون الگوی «تصمیم الان، اثر بعداً» که برای تایمر
    ///         پارامتر اقتصادی ValidatorsRegistry جای دیگه‌ی این پروژه استفاده شده)، پس لحظه‌ای
    ///         که یه سقف بزرگ‌تر قابل‌خرج می‌شه همیشه حداقل CAP_CHANGE_TIMELOCK_DELAY از رأیی
    ///         که تصویبش کرده فاصله داره — هرگز همون تراکنش، هرگز همون بلاک.
    function applyPendingCapChange(CapKind kind) external {
        PendingCapChange storage pending = pendingCapChange[uint256(kind)];
        require(pending.exists, "ValidatorsTreasury: no pending change for this cap");
        require(block.timestamp >= pending.effectiveAt, "ValidatorsTreasury: timelock not elapsed");

        if (kind == CapKind.PerPayment) {
            emit CapChangeApplied(kind, perPaymentCap, pending.newValue);
            perPaymentCap = pending.newValue;
        } else {
            emit CapChangeApplied(kind, periodCap, pending.newValue);
            periodCap = pending.newValue;
        }
        delete pendingCapChange[uint256(kind)];
    }

    // ------------------------------------------------------------------
    // توابع کمکی view
    // ------------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
