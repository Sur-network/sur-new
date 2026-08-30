// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
}

/// @title ValidatorsTreasury
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.VALIDATORS_TREASURY (0x5555...5555).
///         فقط سورن بومی نگه می‌دارد — سورن ارز پایه/گس خودِ زنجیره‌ی سور است (مثل ETH روی
///         اتریوم، از طریق موجودی `alloc` genesis و انتقال‌های معمولی اعتبار می‌گیرد)، **نه**
///         یک توکن ERC20، پس هیچ قرارداد توکن جدا یا `transferFrom` ای در هیچ‌جای این سیستم
///         درگیر نیست.
///
///         دو منبع ورودی، هر دو ارز بومی:
///           - ۵۰٪ از سهم ریوارد هر بلاک از BlockRewardDistributor (بخش ۳ سند طراحی: «۵۰٪
///             بلاک‌ریوارد به خزانه‌ی ولیدیتورها می‌رود»). فی تراکنش هرگز اینجا وارد نمی‌شود —
///             ۱۰۰٪ فی مستقیم و به نسبت بلاک بین ولیدیتورها می‌رود.
///           - کارمزد عضویت (+ استیک اسلش‌شده) که مستقیم توسط ValidatorsRegistry در هر عضویت
///             تازه/هر دموت به‌خاطر غیرفعالی فوروارد می‌شود (به کامنت مستندات «کارمزد عضویت»
///             در ValidatorsRegistry برای مدل ترکیبی استیک مراجعه کن).
///
///         دو مسیر خرج، متناظر با ساختار حکمرانی سند طراحی:
///
///           ۱. رأی کامل ولیدیتورها (این قرارداد): هر خرجی، پیشنهادشده توسط یک ولیدیتور فعال،
///              تصویب‌شده با اکثریت ولیدیتورهای فعال الان.
///              ⚠️ بنیاد سور اصلاً هیچ دسترسی‌ای به این قرارداد ندارد (یک مسیر قدیمی
///              «درخواست بودجه» که بنیاد آغازش می‌کرد، چون غیرضروری بود حذف شد — به
///              FoundationDAO.sol مراجعه کن). اگر بنیاد به وجه نیاز داشته باشد، باید یک
///              ولیدیتور فعال یا عضو ValidatorsBoard خودش پیشنهادش کند.
///           ۲. تفویضی به هیأت (فقط ValidatorsBoard، یک آدرس ثابت genesis): خرج‌های روتین و
///              کوچک زیر SMALL_BUDGET_CAP، فقط بعد از تصویب اکثریت داخلی خودِ ValidatorsBoard
///              قابل‌فراخوانی است. خودِ سقف، مثل هر پارامتر امنیتی دیگر اینجا، فقط با رأی کامل
///              ولیدیتورها قابل‌تغییر است — هیأت نمی‌تواند سقف خرج خودش را بالا ببرد.
///
///         دیپلوی genesis: آدرس ValidatorsBoard یک ثابت genesis است (به SurAddresses.sol
///         مراجعه کن)، نه یک state قابل‌تغییر که با یک مرحله‌ی اجرایی `wire()` تنظیم شود، چون
///         هر پنج قرارداد ساختاری یک نقشه‌ی آدرس مشترک و از‌پیش‌توافق‌شده در genesis دارند.
contract ValidatorsTreasury {
    // ------------------------------------------------------------------
    // آدرس‌های ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------

    /// @notice تنها آدرسی که مجاز به فراخوانی boardApproveExpenditure (مسیر ۲ پایین) است.
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice سقف خرج‌های تصویب‌شده توسط هیأت. هرچیزی مساوی یا بیشتر از این باید از مسیر رأی
    ///         کامل ولیدیتورها بگذرد. فقط با رأی کامل ولیدیتورها قابل‌تغییر است (به
    ///         proposeSmallBudgetCap پایین مراجعه کن) — هیأت نمی‌تواند سقف خودش را بالا ببرد.
    /// @dev 🔶 FILL_IN: سقف بودجه‌ی کوچک اولیه (به wei سورن بومی).
    uint256 public smallBudgetCap = 0;

    bool private locked; // نگهبان reentrancy

    // ------------------------------------------------------------------
    // پیشنهادهای خرج با رأی کامل
    // ------------------------------------------------------------------
    struct Expenditure {
        address to;
        uint256 amount;
        string description;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => Expenditure) public expenditures;
    mapping(uint256 => mapping(address => bool)) private expenditureHasVoted;
    uint256 public expenditureCount;

    uint256 public totalDistributedToTreasury; // مجموع ورودی تاریخی دریافت‌شده (سهم ریوارد + کارمزد عضویت/استیک اسلش‌شده)
    uint256 public totalSpent;                 // مجموع تاریخی پرداخت‌شده (هر دو مسیر خرج باهم)

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event RewardsReceived(address indexed from, uint256 amount);
    event ExpenditureProposed(uint256 indexed id, address indexed to, uint256 amount, string description, address indexed proposer);
    event ExpenditureVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event ExpenditureExecuted(uint256 indexed id, address indexed to, uint256 amount);
    event BoardExpenditureExecuted(address indexed to, uint256 amount, string description);
    event SmallBudgetCapUpdated(uint256 oldCap, uint256 newCap);

    // ------------------------------------------------------------------
    // Modifiers
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
    // 🔶 پرکردنِ genesis — این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis
    // تزریق می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). برای دستورالعمل کامل
    // شبیه‌سازی+استخراج به "sur-contracts-deploy-notes.md" مراجعه کن.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // دریافت خودکار سورن بومی — از سهم ۵۰٪ ریوارد BlockRewardDistributor، و از کارمزد
    // عضویت/استیک اسلش‌شده‌ی ValidatorsRegistry.
    // ------------------------------------------------------------------
    receive() external payable {
        totalDistributedToTreasury += msg.value;
        emit RewardsReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // مسیر ۱: رأی کامل ولیدیتورها
    // ------------------------------------------------------------------

    /// @notice پیشنهاد یک خرج. فقط توسط یک ولیدیتور فعال قابل‌فراخوانی است — بنیاد سور هیچ
    ///         اتصالی به این قرارداد ندارد (یک مسیر قدیمی `proposeRequestTreasuryBudget` روی
    ///         FoundationDAO چون غیرضروری بود حذف شد؛ اگر بنیاد روزی به وجه سورن نیاز داشت،
    ///         یک ولیدیتور فعال یا عضو ValidatorsBoard باید خودش اینجا یا از طریق
    ///         boardApproveExpenditure پیشنهادش کند).
    function proposeExpenditure(address to, uint256 amount, string calldata description) external onlyActiveValidator returns (uint256 id) {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0, "ValidatorsTreasury: zero amount");

        expenditureCount++;
        id = expenditureCount;
        expenditures[id] = Expenditure({
            to: to,
            amount: amount,
            description: description,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        emit ExpenditureProposed(id, to, amount, description, msg.sender);

        _voteExpenditure(id, msg.sender);
    }

    function voteExpenditure(uint256 id) external onlyActiveValidator {
        _voteExpenditure(id, msg.sender);
    }

    function _voteExpenditure(uint256 id, address voter) private {
        Expenditure storage e = expenditures[id];
        require(e.createdAt != 0, "ValidatorsTreasury: expenditure not found");
        require(!e.executed, "ValidatorsTreasury: already executed");
        require(!expenditureHasVoted[id][voter], "ValidatorsTreasury: already voted");

        expenditureHasVoted[id][voter] = true;
        e.votes++;

        uint256 activeCount = REGISTRY.getValidators().length;
        uint256 required = (activeCount / 2) + 1;
        emit ExpenditureVoted(id, voter, e.votes, required);

        if (e.votes >= required) {
            _executeExpenditure(id);
        }
    }

    function _executeExpenditure(uint256 id) private nonReentrant {
        Expenditure storage e = expenditures[id];
        require(!e.executed, "ValidatorsTreasury: already executed");
        require(e.amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");
        e.executed = true;

        totalSpent += e.amount;
        (bool success, ) = e.to.call{value: e.amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit ExpenditureExecuted(id, e.to, e.amount);
    }

    // ------------------------------------------------------------------
    // مسیر ۲: بودجه‌ی کوچک تفویضی به هیأت
    // ------------------------------------------------------------------

    /// @notice فقط توسط ValidatorsBoard فراخوانی می‌شود، فقط بعد از تصویب اکثریت داخلی خودِ
    ///         هیأت. صرف‌نظر از این‌که هیأت به چه مبلغی رأی داده، سقفش smallBudgetCap است.
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external onlyBoard nonReentrant {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0 && amount < smallBudgetCap, "ValidatorsTreasury: amount outside board cap");
        require(amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");

        totalSpent += amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit BoardExpenditureExecuted(to, amount, description);
    }

    // ------------------------------------------------------------------
    // حکمرانی پارامتر — رأی اکثریت کامل ولیدیتورهای فعال. سقف هیأت تنها پارامتر
    // اختصاصی باقی‌مانده‌ی خزانه است؛ BOARD یک آدرس ثابت genesis است (SurAddresses.sol) و
    // بدون دیپلوی کامل مجدد قرارداد قابل‌تغییر نیست.
    // ------------------------------------------------------------------

    struct ParamProposal {
        uint256 newCap;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    function proposeSmallBudgetCap(uint256 newCap) external onlyActiveValidator returns (uint256 id) {
        paramProposalCount++;
        id = paramProposalCount;
        paramProposals[id] = ParamProposal({
            newCap: newCap,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        _voteParam(id, msg.sender);
    }

    function voteParameterChange(uint256 id) external onlyActiveValidator {
        _voteParam(id, msg.sender);
    }

    function _voteParam(uint256 id, address voter) private {
        ParamProposal storage p = paramProposals[id];
        require(p.createdAt != 0, "ValidatorsTreasury: proposal not found");
        require(!p.executed, "ValidatorsTreasury: already executed");
        require(!paramHasVoted[id][voter], "ValidatorsTreasury: already voted");

        paramHasVoted[id][voter] = true;
        p.votes++;

        uint256 activeCount = REGISTRY.getValidators().length;
        uint256 required = (activeCount / 2) + 1;

        if (p.votes >= required) {
            p.executed = true;
            emit SmallBudgetCapUpdated(smallBudgetCap, p.newCap);
            smallBudgetCap = p.newCap;
        }
    }

    // ------------------------------------------------------------------
    // توابع کمکی view
    // ------------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
