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
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 lastLivenessConfirmation,
        uint256 livenessConfirmationsInPeriod,
        uint256 demotedAt
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

    struct BoardAction {
        ActionType atype;
        address target;      // آدرس اوراکل جدید، یا گیرنده‌ی بودجه (برای اقدامات پارامتر اقتصادی استفاده نمی‌شود)
        uint256 amount;       // مبلغ بودجه برای ApproveBudget، یا مقدار جدید برای اقدامات پارامتر اقتصادی
        string description;   // فقط برای ApproveBudget استفاده می‌شود
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

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

    modifier onlyBoardMember() {
        require(isBoardMember[msg.sender], "ValidatorsBoard: caller is not a board member");
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

    /// @notice بازمحاسبه‌ی هیأت به‌عنوان BOARD_SIZE ولیدیتوری که بیشترین رأی جاری را دارند.
    ///         بدون نیاز به مجوز — توسط هرکسی، هر زمان قابل‌فراخوانی. فقط رأی‌هایی که توسط یک
    ///         ولیدیتور فعلاً فعال، به یک ولیدیتور فعلاً فعال داده شده‌اند شمرده می‌شوند؛ هر دو
    ///         طرف در هر فراخوانی مستقیم و زنده در برابر ValidatorsRegistry دوباره چک می‌شوند.
    function refreshBoard() external {
        address[] memory active = REGISTRY.getValidators();

        // شمارش گذرای مخصوص همین فراخوانی: کاندید -> تعداد رأی (قبل از بازگشت به صفر ریست می‌شود)
        address[] memory seenCandidates = new address[](active.length * MAX_VOTES_PER_VOTER);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < active.length; i++) {
            address voter = active[i];
            address[] storage cands = voterCandidates[voter];
            uint256 n = cands.length;
            for (uint256 j = 0; j < n; j++) {
                address c = cands[j];
                if (!REGISTRY.isValidator(c)) continue; // کاندید هم باید الان فعال باشد
                if (_voteTally[c] == 0) {
                    seenCandidates[seenCount] = c;
                    seenCount++;
                }
                _voteTally[c]++;
            }
        }

        // انتخاب BOARD_SIZE کاندیدای برتر بر اساس شمارش؛ در تساوی، هرکدام زودتر ثبت شده می‌ماند
        address[] memory newBoard = new address[](BOARD_SIZE);
        uint256[] memory newBoardVotes = new uint256[](BOARD_SIZE);
        uint256 filled = 0;

        for (uint256 i = 0; i < seenCount; i++) {
            address c = seenCandidates[i];
            uint256 v = _voteTally[c];

            if (filled < BOARD_SIZE) {
                newBoard[filled] = c;
                newBoardVotes[filled] = v;
                filled++;
            } else {
                uint256 minIdx = 0;
                for (uint256 k = 1; k < BOARD_SIZE; k++) {
                    if (newBoardVotes[k] < newBoardVotes[minIdx]) minIdx = k;
                }
                if (v > newBoardVotes[minIdx]) {
                    newBoard[minIdx] = c;
                    newBoardVotes[minIdx] = v;
                }
                // v == newBoardVotes[minIdx]: کاندید موجود (که زودتر ثبت شده) نگه داشته می‌شود
            }
        }

        // ریست شمارش گذرا تا storage عدد کهنه به فراخوانی بعدی درز نکند
        for (uint256 i = 0; i < seenCount; i++) {
            _voteTally[seenCandidates[i]] = 0;
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

        emit BoardRefreshed(finalBoard, finalVotes);
    }

    /// @dev storage شمارش گذرای مخصوص هر فراخوانی refreshBoard(). همیشه بین فراخوانی‌ها صفر
    ///      است — حلقه‌ی ریست refreshBoard() را ببین. به‌عنوان storage قرارداد (نه `memory`)
    ///      اعلان شده، فقط چون Solidity هیچ نوع mapping در memory ندارد.
    mapping(address => uint256) private _voteTally;

    /// @notice پاک‌کردن هر رأیی که یک ولیدیتور طولانی‌مدت‌غیرفعال داده (به‌عنوان رأی‌دهنده) و
    ///         هر رأیی که گرفته (به‌عنوان کاندید)، تا جای رأی بقیه‌ی ولیدیتورها آزاد شود. بدون
    ///         نیاز به مجوز. نیاز دارد ولیدیتور حداقل به مدت
    ///         `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (۳۰ روز) پیوسته
    ///         در وضعیت Demoted مانده باشد. قبل از این نقطه، رأی‌های او از قبل در
    ///         refreshBoard() شمرده نمی‌شوند (بالا را ببین) — این تابع فقط storage/جای رأی را
    ///         آزاد می‌کند، خودش تغییری در ترکیب فعلی هیأت نمی‌دهد.
    function clearStaleVotes(address validator) external {
        (uint8 status, , , , , uint256 demotedAt) = REGISTRY.getValidatorInfo(validator);
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
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "");
    }

    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        id = _createAction(ActionType.ApproveBudget, to, amount, description);
    }

    /// @notice پیشنهاد یک entryThresholdBase تازه روی ValidatorsRegistry (پارامتر اقتصادی
    ///         ورود — تحت حکمرانی هیأت؛ کامنت مستندات سطح قرارداد را ببین).
    function proposeSetEntryThresholdBase(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryThresholdBase, address(0), newValue, "");
    }

    /// @notice پیشنهاد یک growthFactorPerValidator تازه روی ValidatorsRegistry (fixed-point، ۱۸
    ///         رقم اعشار؛ باید > ۱.۰ باشد، یعنی > 1_000000000000000000).
    function proposeSetGrowthFactorPerValidator(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue > 1_000000000000000000, "ValidatorsBoard: growth factor must be > 1.0");
        id = _createAction(ActionType.SetGrowthFactorPerValidator, address(0), newValue, "");
    }

    /// @notice پیشنهاد یک membershipFeeBps تازه روی ValidatorsRegistry.
    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "");
    }

    /// @notice پیشنهاد چرخش کلید احراز هویت (`verifier`) روی ValidatorsRegistry — یک چرخش
    ///         روتین کلید عملیاتی، دقیقاً همان الگوی proposeRotateOracle.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "");
    }

    function voteAction(uint256 id) external onlyBoardMember {
        _voteAction(id, msg.sender);
    }

    function _createAction(ActionType atype, address target, uint256 amount, string memory description) private returns (uint256 id) {
        actionCount++;
        id = actionCount;
        actions[id] = BoardAction({
            atype: atype,
            target: target,
            amount: amount,
            description: description,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        emit ActionProposed(id, atype, target, amount, msg.sender);
        _voteAction(id, msg.sender);
    }

    function _voteAction(uint256 id, address voter) private {
        BoardAction storage a = actions[id];
        require(a.createdAt != 0, "ValidatorsBoard: action not found");
        require(!a.executed, "ValidatorsBoard: already executed");
        require(!actionHasVoted[id][voter], "ValidatorsBoard: already voted");

        actionHasVoted[id][voter] = true;
        a.votes++;

        uint256 required = (boardMembers.length / 2) + 1;
        emit ActionVoted(id, voter, a.votes, required);

        if (a.votes >= required) {
            a.executed = true;
            if (a.atype == ActionType.RotateOracle) {
                IBlockRewardDistributor(DISTRIBUTOR).setDistributionOracle(a.target);
                emit OracleRotated(a.target);
            } else if (a.atype == ActionType.ApproveBudget) {
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
