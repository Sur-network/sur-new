// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
    function setEntryCollateral(uint256 newValue) external;
    function setMembershipFeeBps(uint256 newValue) external;
    function setVerifier(address newVerifier) external;
    function recoveryPeriod() external view returns (uint256);

    // v2.5: حذف در جریان بازیابی شبکه
    function recoveryCaseInfo(address validator) external view returns (uint8 state, uint256 recordedAt, uint256 resolutionDeadline);
    function recoveryReferral(address validator) external view returns (uint256 referralNonce, uint256 eligibleCount);
    function setRecoveryCaseReferred(address validator) external;
    function resolveRecoveryRemoval(address validator, bool upheld) external;
    function wasActiveAt(address who, uint256 nonce) external view returns (bool);

    /// @dev هر بار آدرسی داوطلبانه خارج شود یک واحد زیاد می‌شود؛ کرسی فقط تا وقتی معتبر است که epoch هنوز برابر مقداری باشد
    ///      که هنگام گرفتن کرسی ثبت شد.
    function membershipEpoch(address who) external view returns (uint256);

    /// @dev جایگاه `who` در ترتیبی که آدرس‌ها نخستین‌بار فعال شدند (۱ = قدیمی‌ترین)؛ ۰ برای آدرسی که هرگز فعال نشده.
    ///      برای شکستن تساوی بین نامزدهای هم‌رأی به کار می‌رود: ولیدیتور قدیمی‌تر برنده است.
    function activationSeq(address who) external view returns (uint256);

    /// @dev `status` از رمزگذاری ABI مربوط به ValidatorsRegistry.Status استفاده می‌کند:
    ///      0=None, 1=Probation, 2=Active, 3=Demoted, 4=Exiting, 5=RemovedInRecovery. شش خروجی باید دقیقاً با تابع
    ///      واقعی و به همین ترتیب یکی باشند.
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
    );
}

/// @dev هویت در قرارداد مستقل `IdentityRegistry` (آدرس ثابت `0x6666...6666`) است.
interface IIdentityRegistry {
    function hasIdentity(address who) external view returns (bool);
}

interface IBlockRewardDistributor {
    function setDistributionOracle(address newOracle) external;
}

interface IKmsDirectives {
    function setFrozen(uint8 slot, bool isFrozen) external;
}

interface IValidatorsTreasury {
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external;
}

/// @title ValidatorsBoard
/// @notice هیأت‌مدیرهٔ ولیدیتورها، مستقر در `SurAddresses.VALIDATORS_BOARD` (‏0x4444...4444).
///
///         عضویت هیأت — رأی تأییدی (approval voting)، پنج کرسی، یک هیأت برای هر ماه میلادی:
///           - هر ولیدیتور فعالی که هویت ثبت کرده باشد می‌تواند به حداکثر MAX_VOTES_PER_VOTER (۵) ولیدیتور فعال رأی بدهد
///             (`voteFor`) و هر رأی را هر زمان پس بگیرد (`unvoteFor`). مرحلهٔ نامزدی و پنجرهٔ رأی‌گیری وجود ندارد.
///             رأی‌ها تا وقتی رأی‌دهنده تغییرشان ندهد می‌مانند.
///           - هیأتِ یک ماه میلادی (UTC) با نخستین فراخوان `refreshBoard` در آن ماه کار را شروع می‌کند. هر کسی می‌تواند
///             صدایش بزند. پنج ولیدیتور فعال با بیشترین رأی هیأت می‌شوند؛ در تساوی، ولیدیتوری که زودتر فعال شده
///             برنده است. عضویت قبلی هیچ برتری‌ای نمی‌دهد و هر پنج کرسی می‌توانند هم‌زمان عوض شوند.
///           - تا وقتی در ماه جدید `refreshBoard` صدا زده نشده، هیأت قبلی هیچ اختیاری ندارد. در یک ماه `refreshBoard` یک‌بار
///             موفق می‌شود (هیأت خالی را می‌شود هر زمان پر کرد).
///           - رأی‌ها افزایشی شمرده می‌شوند. هر نامزد یک شمارندهٔ جاری دارد که `voteFor` و `unvoteFor` به‌روزش می‌کنند.
///             فقط رأی ولیدیتورهای فعال در آن می‌آید. وقتی وضعیت ولیدیتوری عوض شود، Registry `syncVoter` را صدا می‌زند که
///             رأی‌های آن ولیدیتور را اضافه یا کم می‌کند؛ هر کسی هم می‌تواند برای ترمیم شمارنده‌ها آن را صدا بزند.
///             صلاحیت خودِ نامزد هنگام انتخاب هیأت زنده بررسی می‌شود.
///           - اگر ولیدیتوری بیش از `recoveryPeriod()` Registry به‌علاوهٔ STALE_VOTE_CLEAR_DELAY (۳۰ روز) Demoted بماند،
///             هر کسی می‌تواند `clearStaleVotes` را صدا بزند تا همهٔ رأی‌هایی که آن ولیدیتور داده و گرفته پاک شود.
///
///         اختیارات هیأت (محدود و صریح):
///           ۱. چرخاندن کلید `distributionOracle` در BlockRewardDistributor.
///           ۲. چرخاندن کلید `verifier` در ValidatorsRegistry.
///           ۳. تأیید پرداخت‌های معمول خزانه تا سقف‌های خزانه.
///           ۴. تعیین سه پارامتر اقتصادی ورود در ValidatorsRegistry
///              (entryThresholdBase، growthFactorPerValidator، membershipFeeBps).
///         هر اقدام هیأت رأی داخلی اعضای فعلی را می‌خواهد. چرخش کلیدها و تأیید بودجه دست‌کم سه رأی می‌خواهند و به‌محض
///         رسیدن به آن تعداد اجرا می‌شوند. هیأت نمی‌تواند پارامترهای امنیتی یا آدرس قراردادهای هسته را عوض کند.
///
///         استقرار در GENESIS: قرارداد constructor ندارد؛ در `alloc` بلاک genesis تزریق می‌شود. پنج عضو اولیه،
///         `boardVersion`، `boardMonthId` و `seatMembershipEpoch` هر عضو را ابزار ساخت genesis می‌نویسد
///         (`genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol` را ببینید). `boardMonthId` باید برابر ماه زمان genesis
///         باشد، وگرنه هیأت مؤسس تا نخستین refresh اختیاری ندارد.
contract ValidatorsBoard {
    address public constant DISTRIBUTOR = SurAddresses.BLOCK_REWARD_DISTRIBUTOR;
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);
    IIdentityRegistry public constant IDENTITY_REGISTRY = IIdentityRegistry(SurAddresses.IDENTITY_REGISTRY);

    /// @notice تعداد کرسی‌های هیأت.
    uint256 public constant BOARD_SIZE = 5;

    /// @notice حداکثر تعداد نامزدهایی که یک ولیدیتور هم‌زمان می‌تواند به آن‌ها رأی بدهد.
    uint256 public constant MAX_VOTES_PER_VOTER = 5;

    /// @notice مدتی پس از پایان دورهٔ بازگشت یک ولیدیتور (بدون بازگشت) که پس از آن هر کسی می‌تواند با clearStaleVotes
    ///         رأی‌هایش را پاک کند.
    uint256 public constant STALE_VOTE_CLEAR_DELAY = 30 days;

    /// @notice حداقل تعداد رأی هیأت برای چرخش کلید یا تأیید بودجه.
    uint256 public constant MIN_VOTES_SENSITIVE_ACTION = 3;

    /// @notice اقدام هیأت که در این مدت به نصاب نرسد منقضی می‌شود.
    uint256 public constant BOARD_ACTION_EXPIRY = 14 days;

    // ------------------------------------------------------------------
    // storage. ترتیب چند متغیر اول باید با کمک‌کنندهٔ seed genesis یکی باشد.
    // ------------------------------------------------------------------
    address[] internal boardMembers;
    mapping(address => bool) public isBoardMember;

    /// @notice نامزدهایی که یک رأی‌دهنده اکنون به آن‌ها رأی داده (تا MAX_VOTES_PER_VOTER).
    mapping(address => address[]) private voterCandidates;

    /// @notice رأی‌دهنده => نامزد => آیا آن رأی اکنون برقرار است.
    mapping(address => mapping(address => bool)) public hasVotedFor;

    /// @notice رأی‌دهندگانی که اکنون به یک نامزد رأی داده‌اند (برای پاک‌کردن رأی‌های دریافتی).
    mapping(address => address[]) private candidateVoters;

    /// @notice جایگاه ۱-پایهٔ `voter` درون `candidateVoters[candidate]` برای حذف O(1).
    mapping(address => mapping(address => uint256)) private voterIndexInCandidateVoters;

    enum ActionType { RotateOracle, ApproveBudget, SetEntryCollateral, SetMembershipFeeBps, RotateVerifier, KmsFreeze }

    /// @dev `requiredVotes` هنگام ساخت اقدام ثابت می‌شود و هرگز بازمحاسبه نمی‌شود. `expiresAt` مدت باز‌ماندن اقدام را
    ///      محدود می‌کند. `boardVersionAtCreation` اقدام را به ترکیب هیأتی می‌بندد که آن را پیشنهاد داد: وقتی ترکیب عوض شود
    ///      دیگر نمی‌شود به آن اقدام رأی داد.
    struct BoardAction {
        ActionType atype;
        address target;  // آدرس تازهٔ oracle / verifier یا گیرندهٔ بودجه
        uint256 amount;  // مبلغ بودجه، یا مقدار جدید برای اقدام پارامتر اقتصادی
        string description;  // فقط برای ApproveBudget
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        uint256 boardVersionAtCreation;
    }

    /// @notice هر بار مجموعهٔ اعضای هیأت واقعاً عوض شود یک واحد زیاد می‌شود.
    uint256 public boardVersion = 1;

    /// @notice شناسهٔ ماه میلادی (UTC، سال * ۱۲ + ماه - ۱) که هیأت فعلی در آن خدمت می‌کند.
    uint256 public boardMonthId;

    /// @notice کرسی‌های آزادشده با خروج که هنوز پر نشده‌اند.
    uint256 public pendingVacancies;

    event BoardMemberAuthorityEnded(address indexed member);
    event BoardSuccession(address indexed newMember);

    /// @notice epoch عضویت آدرس در Registry در لحظه‌ای که کرسی گرفت.
    mapping(address => uint256) public seatMembershipEpoch;

    mapping(uint256 => BoardAction) public actions;
    mapping(uint256 => mapping(address => bool)) private actionHasVoted;
    uint256 public actionCount;

    /// @notice تعداد جاری رأی‌های شمرده‌شده‌ای که هر نامزد دارد.
    mapping(address => uint256) public voteCount;

    /// @dev نامزدهایی که voteCount > 0 دارند.
    address[] private candidateList;

    /// @dev جایگاه ۱-پایهٔ یک نامزد درون candidateList (۰ = نبودن).
    mapping(address => uint256) private candidateListIndex;

    /// @notice آیا رأی‌های یک رأی‌دهنده اکنون در `voteCount` شمرده شده‌اند.
    mapping(address => bool) public votesCounted;

    event VoteCast(address indexed voter, address indexed candidate);
    event VoteWithdrawn(address indexed voter, address indexed candidate);
    event VoterSynced(address indexed voter, bool counted);
    event BoardRefreshed(uint256 indexed monthId, address[] newBoard, uint256[] voteCounts);
    event StaleVotesCleared(address indexed validator, uint256 votesGivenCleared, uint256 votesReceivedCleared);
    event ActionProposed(uint256 indexed id, ActionType atype, address indexed target, uint256 amount, address indexed proposer);
    event ActionVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event OracleRotated(address indexed newOracle);
    event BudgetApproved(address indexed to, uint256 amount, string description);
    event RegistryEconomicParamSet(ActionType indexed atype, uint256 newValue);
    event VerifierRotated(address indexed newVerifier);
    event KmsFreezeApplied(uint8 indexed slot, bool frozen);

    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsBoard: caller is not an active validator");
        _;
    }

    /// @notice فراخواننده فقط وقتی به‌عنوان عضو هیأت عمل می‌کند که (الف) ماهِ هیأت همین ماه باشد، (ب) کرسی داشته باشد و
    ///         درخواست خروج نداده باشد، و (ج) هیچ دارندهٔ کرسی بدون پاک‌شدن کرسی درخواست خروج نداده باشد
    ///         (هر کسی می‌تواند برای آن `syncBoard()` را صدا بزند).
    modifier onlyBoardMember() {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        require(_canAct(msg.sender), "ValidatorsBoard: caller has no board authority");
        require(!_syncNeeded(), "ValidatorsBoard: a seat holder has requested exit - call syncBoard() first");
        _;
    }

    // ------------------------------------------------------------------
    // تقویم
    // ------------------------------------------------------------------

    /// @notice شناسه‌ی ماه (UTC) برای یک timestamp: year * 12 + (month - 1).
    /// @dev seed کردن genesis برای هیأت مؤسس. «فقط» genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol از آن استفاده می‌کند (که
    ///      از این قرارداد ارث می‌برد). `boardMonthId` باید ماه timestamp مربوط به genesis باشد، وگرنه هیأت مؤسس
    ///      تا نخستین refreshBoard() هیچ اختیاری ندارد.
    function _seedBoard(address[] memory members, uint256 genesisTimestamp) internal {
        require(members.length == BOARD_SIZE, "seed: exactly 5 board members");
        for (uint256 i = 0; i < members.length; i++) {
            address m = members[i];
            require(m != address(0) && !isBoardMember[m], "seed: bad or duplicate member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }
        boardMonthId = monthIdOf(genesisTimestamp);
    }

    function monthIdOf(uint256 timestamp) public pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    function currentMonthId() public view returns (uint256) {
        return monthIdOf(block.timestamp);
    }

    /// @notice وقتی `refreshBoard` اکنون می‌تواند موفق شود true است.
    function refreshDue() public view returns (bool) {
        return boardMembers.length == 0 || currentMonthId() > boardMonthId;
    }

    function _boardIsCurrent() private view returns (bool) {
        return boardMonthId == currentMonthId();
    }

    // ------------------------------------------------------------------
    // رأی تأییدی
    // ------------------------------------------------------------------

    /// @notice رأی به `candidate` برای هیأت‌شدن. هر ولیدیتور فعالی که هویت ثبت کرده می‌تواند برای هر ولیدیتور فعال
    ///         رأی بدهد (رأی به خود مجاز است). رأی در `refreshBoard` بعدی شمرده می‌شود.
    function voteFor(address candidate) external onlyActiveValidator {
        require(IDENTITY_REGISTRY.hasIdentity(msg.sender), "ValidatorsBoard: register identity before voting");
        require(REGISTRY.isValidator(candidate), "ValidatorsBoard: candidate is not an active validator");
        require(!hasVotedFor[msg.sender][candidate], "ValidatorsBoard: already voted for this candidate");
        require(voterCandidates[msg.sender].length < MAX_VOTES_PER_VOTER, "ValidatorsBoard: max votes already used");

        _syncVoter(msg.sender);  // فراخواننده فعال است، پس رأی‌های موجودش از اینجا به بعد شمرده می‌شوند

        hasVotedFor[msg.sender][candidate] = true;
        voterCandidates[msg.sender].push(candidate);

        candidateVoters[candidate].push(msg.sender);
        voterIndexInCandidateVoters[candidate][msg.sender] = candidateVoters[candidate].length;

        _increase(candidate);
        emit VoteCast(msg.sender, candidate);
    }

    /// @notice پس‌گرفتن رأی. هر زمان قابل‌فراخوانی است.
    function unvoteFor(address candidate) external {
        require(hasVotedFor[msg.sender][candidate], "ValidatorsBoard: no such active vote");
        _removeVote(msg.sender, candidate);
    }

    /// @notice شمارنده‌های رأی را با وضعیت فعلی یک ولیدیتور هماهنگ می‌کند: رأی‌هایش تا وقتی فعال است شمرده می‌شود و
    ///         وگرنه نه. هر کسی می‌تواند صدایش بزند؛ ایدمپوتنت است. Registry هر بار وضعیت ولیدیتوری عوض شود آن را صدا می‌زند.
    function syncVoter(address voter) external {
        _syncVoter(voter);
    }

    function syncVoters(address[] calldata voters) external {
        for (uint256 i = 0; i < voters.length; i++) {
            _syncVoter(voters[i]);
        }
    }

    function _syncVoter(address voter) private {
        bool active = REGISTRY.isValidator(voter);
        if (active == votesCounted[voter]) return;
        address[] storage cands = voterCandidates[voter];
        uint256 n = cands.length;
        if (active) {
            votesCounted[voter] = true;
            for (uint256 i = 0; i < n; i++) _increase(cands[i]);
        } else {
            votesCounted[voter] = false;
            for (uint256 i = 0; i < n; i++) _decrease(cands[i]);
        }
        emit VoterSynced(voter, active);
    }

    function _increase(address candidate) private {
        if (voteCount[candidate]++ == 0) {
            candidateList.push(candidate);
            candidateListIndex[candidate] = candidateList.length;
        }
    }

    /// @dev هرگز بر اثر ناهماهنگی دفتری revert نمی‌کند، پس شمارندهٔ کهنه هرگز رأی‌دادن را قفل نمی‌کند.
    function _decrease(address candidate) private {
        uint256 current = voteCount[candidate];
        if (current == 0) return;
        voteCount[candidate] = current - 1;
        if (current == 1) {
            uint256 idx = candidateListIndex[candidate];  // ۱-پایه
            uint256 last = candidateList.length;
            if (idx != last) {
                address moved = candidateList[last - 1];
                candidateList[idx - 1] = moved;
                candidateListIndex[moved] = idx;
            }
            candidateList.pop();
            delete candidateListIndex[candidate];
        }
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
        uint256 idx = voterIndexInCandidateVoters[candidate][voter];
        uint256 lastIdx = cv.length;
        if (idx != lastIdx) {
            address lastVoter = cv[lastIdx - 1];
            cv[idx - 1] = lastVoter;
            voterIndexInCandidateVoters[candidate][lastVoter] = idx;
        }
        cv.pop();
        delete voterIndexInCandidateVoters[candidate][voter];

        if (votesCounted[voter]) _decrease(candidate);
        emit VoteWithdrawn(voter, candidate);
    }

    // ------------------------------------------------------------------
    // انتخاب ماهانهٔ هیأت
    // ------------------------------------------------------------------

    /// @notice هیأت ماه میلادی جاری را می‌نشاند: BOARD_SIZE ولیدیتور فعال با بیشترین رأی، در تساوی زودتر فعال‌شده.
    ///         هر کسی می‌تواند صدایش بزند؛ در هر ماه یک‌بار موفق می‌شود (و تا وقتی هیأت خالی است در هر زمان). اگر
    ///         کمتر از BOARD_SIZE نامزد رأی داشته باشد کرسی‌های کمتری پر می‌شود.
    ///
    ///         `votersToSync` فهرست ولیدیتورهایی است که شمارندهٔ رأی‌هایشان پیش از انتخاب هیأت با وضعیت فعلی‌شان هماهنگ
    ///         می‌شود (`syncVoter` را ببینید)، تا ترمیم و refresh در یک تراکنش انجام شود. فهرست معمولاً خالی است: Registry
    ///         در هر تغییر وضعیت خودش `syncVoter` را صدا می‌زند.
    function refreshBoard(address[] calldata votersToSync) external {
        uint256 month = currentMonthId();
        require(boardMembers.length == 0 || month > boardMonthId, "ValidatorsBoard: this month's board is already set");

        for (uint256 i = 0; i < votersToSync.length; i++) {
            _syncVoter(votersToSync[i]);
        }

        uint256 priorCount = boardMembers.length;
        (address[] memory picks, uint256[] memory pickVotes, uint256 n) = _selectTop(BOARD_SIZE, false);

        uint256 kept = 0;
        for (uint256 i = 0; i < n; i++) {
            if (isBoardMember[picks[i]]) kept++;
        }
        bool changed = (kept != n) || (kept != priorCount);

        for (uint256 i = 0; i < priorCount; i++) {
            isBoardMember[boardMembers[i]] = false;
        }
        delete boardMembers;

        address[] memory finalBoard = new address[](n);
        uint256[] memory finalVotes = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            boardMembers.push(picks[i]);
            isBoardMember[picks[i]] = true;
            seatMembershipEpoch[picks[i]] = REGISTRY.membershipEpoch(picks[i]);
            finalBoard[i] = picks[i];
            finalVotes[i] = pickVotes[i];
        }

        if (changed) boardVersion++;
        boardMonthId = month;
        pendingVacancies = 0;

        emit BoardRefreshed(month, finalBoard, finalVotes);
    }

    /// @dev حداکثر `k` نامزد فعال با بیشترین رأی (در تساوی activationSeq کمتر برنده است). نامزدهایی که نمی‌توانند به
    ///      `k` نفر برتر برسند بدون هیچ فراخوان خارجی کنار گذاشته می‌شوند.
    function _selectTop(uint256 k, bool excludeMembers)
        private
        view
        returns (address[] memory picks, uint256[] memory votes, uint256 filled)
    {
        picks = new address[](k);
        votes = new uint256[](k);
        if (k == 0) return (picks, votes, 0);
        uint256[] memory seqs = new uint256[](k);

        uint256 len = candidateList.length;
        for (uint256 i = 0; i < len; i++) {
            address c = candidateList[i];
            if (excludeMembers && isBoardMember[c]) continue;
            uint256 v = voteCount[c];

            uint256 weakest = 0;
            if (filled == k) {
                weakest = _weakestIndex(votes, seqs, k);
                if (v < votes[weakest]) continue;
            }
            if (!REGISTRY.isValidator(c)) continue;
            uint256 s = REGISTRY.activationSeq(c);

            if (filled < k) {
                picks[filled] = c;
                votes[filled] = v;
                seqs[filled] = s;
                filled++;
            } else if (v > votes[weakest] || (v == votes[weakest] && s < seqs[weakest])) {
                picks[weakest] = c;
                votes[weakest] = v;
                seqs[weakest] = s;
            }
        }
    }

    /// @dev اندیس ورودی که اول جابه‌جا می‌شود: کمترین رأی، و میان هم‌رأی‌ها آن که دیرتر فعال شده.
    function _weakestIndex(uint256[] memory votes, uint256[] memory seqs, uint256 k) private pure returns (uint256 w) {
        for (uint256 i = 1; i < k; i++) {
            if (votes[i] < votes[w] || (votes[i] == votes[w] && seqs[i] > seqs[w])) w = i;
        }
    }

    // ------------------------------------------------------------------
    // اختیار و جانشینی ناشی از خروج
    // ------------------------------------------------------------------

    /// @dev کرسی تا وقتی معتبر است که دارنده خروج نداده باشد (epoch عضویت بدون تغییر) و وضعیتش نه None باشد نه Exiting.
    ///      تعلیق (Demoted) به‌تنهایی اختیار را در طول همان ماه قطع نمی‌کند.
    function _hasAuthority(address who) private view returns (bool) {
        if (!isBoardMember[who]) return false;
        if (REGISTRY.membershipEpoch(who) != seatMembershipEpoch[who]) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        // نه None، نه Exiting، و (v2.5) نه حذف‌شده در بازیابی شبکه
        return status != 0 && status != 4 && status != 5;
    }

    /// @notice تا وقتی `who` می‌تواند به‌عنوان عضو هیأت عمل کند true است: ماهِ هیأت همین ماه است و کرسی معتبر است.
    /// @dev عضو جایگاه‌دار فقط وقتی می‌تواند «عمل کند» (پیشنهاد دهد، رأی دهد، در حد نصاب بازیابی شمرده شود) که ولیدیتوری باشد
    ///      که از Probation خارج شده است: بنیان‌گذارانی که روی هیأت ژنسیس با وضعیت Probation کاشته شده‌اند جایگاه خود را دارند
    ///      اما تا فعال‌سازی توسط Verifier نمی‌توانند عمل کنند. اعتبار جایگاه (_hasAuthority) بدون تغییر است، پس هر کس
    ///      syncBoard() را صدا بزند بنیان‌گذاری را که هنوز در Probation است حذف «نمی‌کند». عضو تعلیق‌شده (Demoted یا
    ///      SelfSuspended) مانند قبل تا پایان ماه خود عمل می‌کند (خودِ تعلیق اختیار را پایان نمی‌دهد).
    function _canAct(address who) private view returns (bool) {
        if (!_hasAuthority(who)) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        return status != 1; // 1 = Probation
    }

    function hasBoardAuthority(address who) external view returns (bool) {
        return _boardIsCurrent() && _canAct(who);
    }

    function _syncNeeded() private view returns (bool) {
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (!_hasAuthority(boardMembers[i])) return true;
        }
        return false;
    }

    /// @notice دارندگان کرسی‌ای را که اختیارشان پایان یافته حذف می‌کند و کرسی‌هایشان را از نامزدهای پررأی‌تر پر می‌کند.
    ///         هر کسی می‌تواند در طول ماه هیأت صدایش بزند.
    function syncBoard() external {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
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
        if (changed) boardVersion++;
    }

    /// @notice کرسی‌های آزادشده با خروج را با نامزدهای واجد شرایط (فعال و بدون کرسی) که بیشترین رأی را دارند پر می‌کند.
    ///         هرگز تغییر عادی اضافه نمی‌سازد. با کمتر از سه عضو نشسته، پرداخت خزانه و چرخش کلید تا پرشدن یک کرسی
    ///         متوقف است.
    function fillVacancies() external {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        if (_fillVacancies()) boardVersion++;
    }

    function _fillVacancies() private returns (bool filledAny) {
        uint256 room = BOARD_SIZE - boardMembers.length;
        uint256 want = pendingVacancies < room ? pendingVacancies : room;
        if (want == 0) return false;
        (address[] memory picks, , uint256 n) = _selectTop(want, true);
        for (uint256 i = 0; i < n; i++) {
            boardMembers.push(picks[i]);
            isBoardMember[picks[i]] = true;
            seatMembershipEpoch[picks[i]] = REGISTRY.membershipEpoch(picks[i]);
            emit BoardSuccession(picks[i]);
        }
        if (n > 0) {
            pendingVacancies -= n;
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // پاک‌سازی رأی‌های کهنه
    // ------------------------------------------------------------------

    /// @notice همهٔ رأی‌هایی را که `validator` داده و گرفته پاک می‌کند، وقتی بیش از `recoveryPeriod() + STALE_VOTE_CLEAR_DELAY`
    ///         Demoted مانده باشد. هر کسی می‌تواند صدایش بزند.
    function clearStaleVotes(address validator) external {
        (uint8 status, , uint256 periodStartedAt, uint256 demotedAt, , ) = REGISTRY.getValidatorInfo(validator);
        // Demoted (3): دورهٔ بازیابی به‌علاوهٔ تأخیر پس از تعلیق. SelfSuspended (6): برای تعلیق داوطلبانه دورهٔ بازیابی وجود
        // ندارد، پس تأخیر از لحظهٔ شروع آن شمرده می‌شود (Registry این لحظه را در periodStartedAt نگه می‌دارد).
        require(status == 3 || status == 6, "ValidatorsBoard: validator is not currently suspended");
        uint256 threshold = status == 3
            ? demotedAt + REGISTRY.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY
            : periodStartedAt + STALE_VOTE_CLEAR_DELAY;
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
    // اقدام‌های هیأت
    // ------------------------------------------------------------------

    /// @notice چرخاندن کلید distributionOracle. دست‌کم MIN_VOTES_SENSITIVE_ACTION رأی می‌خواهد و به‌محض رسیدن به
    ///         نصاب اجرا می‌شود.
    function proposeRotateOracle(address newOracle) external onlyBoardMember returns (uint256 id) {
        require(newOracle != address(0), "ValidatorsBoard: zero oracle address");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key rotation halted");
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice تأیید یک پرداخت معمول خزانه زیر سقف‌های خزانه. دست‌کم MIN_VOTES_SENSITIVE_ACTION رأی می‌خواهد؛ تا وقتی
    ///         کمتر از سه عضو نشسته‌اند متوقف است.
    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - spending halted");
        id = _createAction(ActionType.ApproveBudget, to, amount, description, MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice پارامترهای اقتصادی ورود: اکثریت هیأت.
    function proposeSetEntryCollateral(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryCollateral, address(0), newValue, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice چرخاندن کلید `verifier` در ValidatorsRegistry. دست‌کم MIN_VOTES_SENSITIVE_ACTION رأی می‌خواهد و
    ///         به‌محض رسیدن به نصاب اجرا می‌شود.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key rotation halted");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice قطع یا وصل‌کردن کلید verifier (slot 0) یا distributionOracle (slot 1) در KmsDirectives. identityOracle (slot 2) با FoundationDAO است، نه اینجا. همان _createAction: حداقل ۳ رأی و اکثریت، BOARD_ACTION_EXPIRY، باطل با تغییر boardVersion.
    ///         slot و پرچم در amount بسته‌بندی می‌شوند: بیت‌های ۰..۷ = slot، بیت ۸ = frozen.
    function proposeKmsFreeze(uint8 slot, bool isFrozen) external onlyBoardMember returns (uint256 id) {
        require(slot <= 1, "ValidatorsBoard: the board freezes only the verifier and distributionOracle keys");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key control halted");
        id = _createAction(ActionType.KmsFreeze, address(0), uint256(slot) | (isFrozen ? 0x100 : 0), "", MIN_VOTES_SENSITIVE_ACTION);
    }

    function voteAction(uint256 id) external onlyBoardMember {
        _voteAction(id, msg.sender);
    }

    /// @dev تعداد رأی لازم برابر اکثریت هیأت در لحظهٔ ساخت است که برای اقدام‌های حساس تا `minRequiredVotes` بالا می‌رود
    ///      و سپس در تمام عمر اقدام ثابت می‌ماند.
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
            requiredVotes: majority > minRequiredVotes ? majority : minRequiredVotes,
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
                require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - spending halted");
                IValidatorsTreasury(TREASURY).boardApproveExpenditure(a.target, a.amount, a.description);
                emit BudgetApproved(a.target, a.amount, a.description);
            } else if (a.atype == ActionType.SetEntryCollateral) {
                REGISTRY.setEntryCollateral(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetMembershipFeeBps) {
                REGISTRY.setMembershipFeeBps(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.RotateVerifier) {
                REGISTRY.setVerifier(a.target);
                emit VerifierRotated(a.target);
            } else if (a.atype == ActionType.KmsFreeze) {
                require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key control halted");
                IKmsDirectives(SurAddresses.KMS_DIRECTIVES).setFrozen(uint8(a.amount & 0xff), (a.amount & 0x100) != 0);
                emit KmsFreezeApplied(uint8(a.amount & 0xff), (a.amount & 0x100) != 0);
            }
        }
    }

    // ------------------------------------------------------------------
    // نمایش
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

    /// @notice نامزدهایی که اکنون دست‌کم یک رأی شمرده‌شده دارند.
    function getCandidateList() external view returns (address[] memory) {
        return candidateList;
    }

    // ------------------------------------------------------------------
    // v2.5: اعتراض به حذف در جریان بازیابی شبکه (تصمیم ۲۰۲۶-۱۱-۱۹)
    //
    // ولیدیتورِ حذف‌شده ظرف ۷۲ ساعت در Registry اعتراض می‌کند. سپس هیأت ظرف ۷ روز تصمیم می‌گیرد: ۳ رأی برای تأیید
    // یا ۳ رأی برای لغو؛ خودِ موضوع هرگز رأی نمی‌دهد (چون به‌هرحال صندلی‌ای ندارد). اگر کمتر از ۳ عضو بی‌طرف هیأت
    // اختیار داشته باشند، «هر کسی» می‌تواند پرونده را به ولیدیتورها ارجاع دهد: هر ولیدیتوری که در لحظه‌ی ارجاع Active بوده
    // می‌تواند رأی بدهد و دو‌سوم آن رأی‌دهندگان تصمیم می‌گیرند. نبودِ تصمیم در موعد = لغو حذف (Registry.expire...).
    // حالت‌های پرونده در Registry: ۲ = Objected (هیأت)، ۳ = ReferredToAssembly (ولیدیتورها).
    // ------------------------------------------------------------------
    struct RecoveryTally {
        uint256 uphold;
        uint256 cancel;
    }

    /// @dev با کلید (validator, recordedAt) تعریف می‌شود تا پرونده‌ی بعدیِ همان آدرس از صفر شروع کند.
    mapping(address => mapping(uint256 => RecoveryTally)) public boardRecoveryTallies;
    mapping(address => mapping(uint256 => RecoveryTally)) public assemblyRecoveryTallies;
    mapping(address => mapping(uint256 => mapping(address => bool))) private recoveryVoted;
    mapping(address => mapping(uint256 => mapping(address => bool))) private recoveryAssemblyVoted;

    event RecoveryRemovalVote(address indexed validator, address indexed voter, bool uphold, uint256 upholdVotes, uint256 cancelVotes);
    event RecoveryAssemblyVote(address indexed validator, address indexed voter, bool uphold, uint256 upholdVotes, uint256 cancelVotes);
    event RecoveryCaseDecided(address indexed validator, bool upheld, bool byAssembly);

    function voteRecoveryRemoval(address validator, bool uphold) external onlyBoardMember {
        (uint8 state, uint256 recordedAt, uint256 deadline) = REGISTRY.recoveryCaseInfo(validator);
        require(state == 2, "ValidatorsBoard: no open board case");
        require(block.timestamp <= deadline, "ValidatorsBoard: decision window over");
        require(msg.sender != validator, "ValidatorsBoard: the subject of a case cannot vote");
        require(!recoveryVoted[validator][recordedAt][msg.sender], "ValidatorsBoard: already voted");
        recoveryVoted[validator][recordedAt][msg.sender] = true;
        RecoveryTally storage t = boardRecoveryTallies[validator][recordedAt];
        if (uphold) t.uphold++; else t.cancel++;
        emit RecoveryRemovalVote(validator, msg.sender, uphold, t.uphold, t.cancel);
        if (t.uphold >= MIN_VOTES_SENSITIVE_ACTION) {
            REGISTRY.resolveRecoveryRemoval(validator, true);
            emit RecoveryCaseDecided(validator, true, false);
        } else if (t.cancel >= MIN_VOTES_SENSITIVE_ACTION) {
            REGISTRY.resolveRecoveryRemoval(validator, false);
            emit RecoveryCaseDecided(validator, false, false);
        }
    }

    /// @notice هر کسی، وقتی کمتر از ۳ عضو هیأت غیر از موضوع اختیار دارند: ولیدیتورها تصمیم می‌گیرند.
    function referRecoveryRemovalToAssembly(address validator) external {
        require(_impartialAuthorityCount(validator) < MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: enough impartial board members");
        REGISTRY.setRecoveryCaseReferred(validator); // بررسی می‌کند پرونده Objected و هنوز باز باشد
    }

    function _impartialAuthorityCount(address subject) private view returns (uint256 n) {
        if (!_boardIsCurrent()) return 0;
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (boardMembers[i] != subject && _canAct(boardMembers[i])) n++;
        }
    }

    /// @notice ولیدیتوری که هنگام ارجاع پرونده Active بوده رأی می‌دهد؛ دو‌سوم آن رأی‌دهندگان تصمیم می‌گیرند.
    function voteRecoveryAssembly(address validator, bool uphold) external {
        (uint8 state, uint256 recordedAt, uint256 deadline) = REGISTRY.recoveryCaseInfo(validator);
        require(state == 3, "ValidatorsBoard: no open assembly case");
        require(block.timestamp <= deadline, "ValidatorsBoard: decision window over");
        require(msg.sender != validator, "ValidatorsBoard: the subject of a case cannot vote");
        (uint256 referralNonce, uint256 eligible) = REGISTRY.recoveryReferral(validator);
        require(REGISTRY.isValidator(msg.sender) && REGISTRY.wasActiveAt(msg.sender, referralNonce), "ValidatorsBoard: not an eligible validator");
        require(!recoveryAssemblyVoted[validator][recordedAt][msg.sender], "ValidatorsBoard: already voted");
        recoveryAssemblyVoted[validator][recordedAt][msg.sender] = true;
        RecoveryTally storage t = assemblyRecoveryTallies[validator][recordedAt];
        if (uphold) t.uphold++; else t.cancel++;
        emit RecoveryAssemblyVote(validator, msg.sender, uphold, t.uphold, t.cancel);
        uint256 need = (2 * eligible + 2) / 3; // ceil(2n/3)
        if (t.uphold >= need) {
            REGISTRY.resolveRecoveryRemoval(validator, true);
            emit RecoveryCaseDecided(validator, true, true);
        } else if (t.cancel > eligible - need) {
            REGISTRY.resolveRecoveryRemoval(validator, false); // دو‌سومِ لازم برای تأیید دیگر قابل‌دستیابی نیست
            emit RecoveryCaseDecided(validator, false, true);
        }
    }
}
