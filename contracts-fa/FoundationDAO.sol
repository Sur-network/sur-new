// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IFoundationMembers {
    enum PersonType { Individual, Legal }

    struct MemberView {
        address account;
        string name;
        PersonType personType;
        address representative;
        uint256 shares;
    }

    function isMember(address account) external view returns (bool);
    function shareOf(address account) external view returns (uint256);
    function totalShares() external view returns (uint256);
    function getMemberCount() external view returns (uint256);
    function isMemberOrRepresentative(address who) external view returns (bool);
    function memberOfVoter(address who) external view returns (address);
    function getAllMembers() external view returns (MemberView[] memory);
    function addMember(address account, string calldata name, PersonType personType, address representative, uint256 shares) external;
    function removeMember(address account) external;
    function transferShares(address from, address to, uint256 amount) external;
    function setRepresentative(address account, address representative) external;
}

interface ISurenSale {
    function registerExchange(address account, string calldata name, uint256 quota) external;
    function setExchangeQuota(address account, uint256 newQuota) external;
    function changeExchangeKey(address oldAccount, address newAccount) external;
    function resumeExchange(address account) external;
    function removeExchange(address account) external;
    function setTotalCap(uint256 cap) external;
    function sweepUnsold(address to) external;
    function endSale() external;
    function pauseExchange(address account) external;
}

interface IIdentityRegistryOracle {
    function setIdentityOracle(address newOracle) external;
}

interface IValidatorLottery {
    function startLottery(uint256 ticketPrice, uint256 winnersCount, uint256 closeTime) external;
}

/// @title FoundationDAO
/// @notice حکمرانی روی‌زنجیره‌ی بنیاد سور، مطابق اساسنامه‌ی امضاشده (خودِ اساسنامه با این کد تغییر
///         نمی‌کند): مجمع عمومی (اعضا با وزن سهم‌الشرکه)، هیأت (۵ عضو اصلی + ۲ عضو علی‌البدل)،
///         بازرس، و خزانه‌ی بنیاد. در SurAddresses.FOUNDATION_DAO (0x1111...1111) مستقر می‌شود.
///
///         طراحی v2.5 (تصمیم‌های ۲۰۲۶-۱۱-۱۹):
///           * تصمیم‌های هیأت پیشنهادهای «تایپ‌شده» هستند: هر پیشنهاد پارامترهای دقیق خودش را ذخیره
///             می‌کند، `getProposal(id)` همه‌ی آن‌ها را برمی‌گرداند، و `vote(id, paramsHash)` فقط برای
///             همان id و فقط وقتی شمرده می‌شود که رأی‌دهنده هش پارامترِ منطبق را بدهد (یعنی رأی‌دهنده
///             ثابت می‌کند پارامترها را دیده است). حدنصاب اکثریت عددی ۵ عضو اصلی است (۳ از ۵)؛ رأی
///             پیشنهاددهنده خودکار شمرده می‌شود؛ هر پیشنهاد پس از ۳۰ روز منقضی می‌شود؛ تغییر ترکیب
///             هیأت همه‌ی پیشنهادهای باز را باطل می‌کند.
///           * فهرست انواع پیشنهاد در genesis ثابت می‌شود (نوع جدید یعنی نسخه‌ی جدید قرارداد و
///             مهاجرت). نوع `Execute` تنها نوع آزاد است: target، value و `data` را آشکارا در پیشنهاد
///             ذخیره می‌کند و نمی‌تواند این قرارداد یا FoundationMembers را صدا بزند (عضویت و سهم‌ها فقط
///             با مصوبه‌ی مجمع فوق‌العاده تغییر می‌کنند، هرگز با رأی هیأت).
///           * هیچ اختیاری بر اجماع، ولیدیتورها، خزانه‌ی ولیدیتورها یا هر oracle مرتبط با اجماع ندارد.
///             استثناها (تصمیم‌گرفته‌شده): کلید `identityOracle` (مسئولیت بنیاد)، سهمیه‌ی صرافی‌ها در
///             SurenSale، و شروع قرعه‌کشی.
///
///         GENESIS: constructor ندارد — همراه با ۲۰٬۰۰۰٬۰۰۰ سورن در `alloc` بلاک genesis تزریق می‌شود.
///         هیأت/افسران اولیه توسط genesis-seed-helpers/FoundationDAO_GenesisSeed.sol seed می‌شوند که
///         از این قرارداد «ارث می‌برد» (چیدمان storage یکسان).
///
///         🔶 نکته‌های باز که در کد دیده می‌مانند: طول دوره‌ی رأی‌گیری، برخورد با شرط «سند رسمی» اساسنامه
///         برای انتقال سهم، جایگزینی علی‌البدل به‌جای صندلی خالی‌شده‌ی عضو اصلی، قرائت سخت‌گیرانه‌ی
///         حدنصاب فوق‌العاده (به EXTRAORDINARY_* پایین مراجعه کن).
contract FoundationDAO {
    // ------------------------------------------------------------------
    // ثابت‌ها
    // ------------------------------------------------------------------
    IFoundationMembers public constant MEMBERS = IFoundationMembers(SurAddresses.FOUNDATION_MEMBERS);

    uint256 public constant BOARD_SIZE = 5;
    uint256 public constant ALTERNATES_SIZE = 2;
    uint256 public constant BOARD_TERM = 730 days;
    uint256 public constant PROPOSAL_EXPIRY = 30 days;
    uint256 public constant MIN_NOTICE = 10 days;
    uint256 public constant MAX_NOTICE = 40 days;
    /// @dev 🔶 در اساسنامه نیامده: رأی‌گیری یک مجمع تا چه مدت پس از meetingTime باز می‌ماند.
    uint256 public constant VOTING_PERIOD = 3 days;

    // ------------------------------------------------------------------
    // انواع
    // ------------------------------------------------------------------
    enum ProposalType {
        Spend, ElectOfficers, RegisterExchange, SetExchangeQuota, ChangeExchangeKey, ResumeExchange,
        RemoveExchange, SetSaleTotalCap, SweepUnsold, RotateIdentityOracle, StartLottery, SetSaleContract, Execute, EndSale
    }
    enum ProposalStatus { Pending, Executed }
    enum AssemblyKind { Ordinary, Extraordinary }
    enum MembersAction { AddMember, RemoveMember, TransferShares, SetRepresentative }

    /// @dev اسلات‌های پارامتر به تفکیک نوع (همه از طریق getProposal / ProposalParams دیده می‌شوند):
    ///   Spend:               addrA=token (0=Suren), addrB=to, numA=amount, text=description
    ///   ElectOfficers:       addrA=chair, addrB=treasurer, addrC=ceo
    ///   RegisterExchange:    addrA=account, numA=quota, text=name
    ///   SetExchangeQuota:    addrA=account, numA=newQuota
    ///   ChangeExchangeKey:   addrA=oldAccount, addrB=newAccount
    ///   ResumeExchange / RemoveExchange: addrA=account
    ///   SetSaleTotalCap:     numA=cap
    ///   SweepUnsold:         addrA=to
    ///   RotateIdentityOracle: addrA=newOracle
    ///   StartLottery:        numA=ticketPrice, numB=winnersCount, numC=closeTime
    ///   SetSaleContract:     addrA=SurenSale address
    ///   Execute:             addrA=target, numA=value, text=description, data=calldata
    ///   EndSale:             (no parameters) — stops SurenSale for good
    struct Params {
        ProposalType pType;
        address addrA;
        address addrB;
        address addrC;
        uint256 numA;
        uint256 numB;
        uint256 numC;
        string text;
        bytes data;
    }

    struct Proposal {
        Params p;
        address proposer;
        bytes32 paramsHash;
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 boardVersionAtCreation;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    struct ProposalView {
        ProposalType pType;
        address proposer;
        address addrA;
        address addrB;
        address addrC;
        uint256 numA;
        uint256 numB;
        uint256 numC;
        string text;
        bytes data;
        bytes32 paramsHash;
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 boardVersionAtCreation;
        ProposalStatus status;
    }

    struct Assembly {
        AssemblyKind kind;
        bool secondSession;
        bool done; // یک انتخابات نهایی شد / یک مصوبه در این مجمع اجرا شد
        address caller;
        uint256 calledAt;
        uint256 meetingTime;
        uint256 votingEnd;
        uint256 totalShares;
        uint256 memberCount;
        string agendaURI;
    }

    struct Resolution {
        uint256 assemblyId;
        MembersAction action;
        address account;
        address other;
        string name;
        IFoundationMembers.PersonType personType;
        uint256 amount;
        address proposer;
        uint256 yesWeight;
        uint256 noWeight;
        uint256 yesCount;
        uint256 attendedCount;
        bool executed;
    }

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    address[] private _board;      // اعضای اصلی (۵)
    address[] private _alternates; // علی‌البدل‌ها (حداکثر ۲)
    mapping(address => bool) private _isBoard;
    address public inspector;
    address public chair;
    address public treasurer;
    address public ceo;
    uint256 public boardTermEnd;
    /// @notice با هر تغییر در ترکیب هیأت یکی اضافه می‌شود؛ پیشنهادهای بازِ نسخه‌ی قدیمی‌تر باطل‌اند.
    uint256 public boardVersion;

    /// @notice قرارداد SurenSale (قرارداد genesis نیست — با پیشنهاد SetSaleContract یک بار تنظیم یا جایگزین می‌شود).
    address public saleContract;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private _proposals;

    uint256 public assemblyCount;
    mapping(uint256 => Assembly) private _assemblies;
    mapping(uint256 => mapping(address => uint256)) private _assemblyWeight; // عکس لحظه‌ای در زمان فراخوان، به تفکیک حساب عضو

    /// @notice وقتی برای این مجمع (ناموفق) جلسه‌ی دوم فراخوانده شد true می‌شود
    mapping(uint256 => bool) public secondSessionCalled;

    // انتخابات با شناسه‌ی مجمع کلیدگذاری می‌شوند (هر مجمع عادی یک انتخابات)
    mapping(uint256 => bool) public electionOpened;
    mapping(uint256 => bool) public electionFinalized;
    mapping(uint256 => uint256) public attendedWeight;
    mapping(uint256 => mapping(address => bool)) private _attended;
    mapping(uint256 => mapping(address => bool)) private _boardVoted;
    mapping(uint256 => mapping(address => bool)) private _inspectorVoted;
    mapping(uint256 => address[]) private _boardCands;
    mapping(uint256 => address[]) private _inspectorCands;
    mapping(uint256 => mapping(address => uint256)) public boardTally;
    mapping(uint256 => mapping(address => uint256)) public inspectorTally;

    uint256 public resolutionCount;
    mapping(uint256 => Resolution) private _resolutions;
    mapping(uint256 => mapping(address => bool)) private _resolutionVoted; // به تفکیک حساب عضو

    bool private _locked;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ProposalCreated(uint256 indexed id, ProposalType indexed pType, address indexed proposer, bytes32 paramsHash);
    event ProposalParams(uint256 indexed id, address addrA, address addrB, address addrC, uint256 numA, uint256 numB, uint256 numC, string text, bytes data);
    event Voted(uint256 indexed id, address indexed voter, uint256 votes, uint256 requiredVotes);
    event ProposalExecuted(uint256 indexed id, ProposalType indexed pType);
    event OfficersElected(address chair, address treasurer, address ceo);
    event SaleContractSet(address saleContract);
    event ExchangePaused(address indexed account, address indexed by);
    event AssemblyCalled(uint256 indexed id, AssemblyKind kind, bool secondSession, uint256 meetingTime, string agendaURI);
    event ElectionOpened(uint256 indexed id);
    event BoardVoted(uint256 indexed id, address indexed voterMember, uint256 weight);
    event InspectorVoted(uint256 indexed id, address indexed voterMember, address pick, uint256 weight);
    event ElectionFinalized(uint256 indexed id, address[] board, address[] alternates, address inspector, uint256 termEnd);
    event ResolutionProposed(uint256 indexed id, uint256 indexed assemblyId, MembersAction action, address account, address other, string name, uint256 amount);
    event ResolutionVoted(uint256 indexed id, address indexed voterMember, bool approve, uint256 weight);
    event ResolutionExecuted(uint256 indexed id);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyBoard() {
        require(_isBoard[msg.sender], "FoundationDAO: not a principal board member");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "FoundationDAO: reentrancy");
        _locked = true;
        _;
        _locked = false;
    }

    receive() external payable {}

    // ------------------------------------------------------------------
    // نماها — هیأت فعلی
    // ------------------------------------------------------------------
    function getBoard() external view returns (address[] memory) { return _board; }
    function getAlternates() external view returns (address[] memory) { return _alternates; }
    function getInspector() external view returns (address) { return inspector; }
    function isBoardMember(address who) external view returns (bool) { return _isBoard[who]; }

    function getMemberCount() external view returns (uint256) { return MEMBERS.getMemberCount(); }
    function getAllMembers() external view returns (IFoundationMembers.MemberView[] memory) { return MEMBERS.getAllMembers(); }

    function getEthBalance() external view returns (uint256) { return address(this).balance; }

    function getErc20Balance(address token) external view returns (uint256) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        require(ok && ret.length >= 32, "FoundationDAO: balanceOf failed");
        return abi.decode(ret, (uint256));
    }

    // ==================================================================
    //  الف. پیشنهادهای هیأت (تایپ‌شده)
    // ==================================================================
    function proposeSpend(address token, address to, uint256 amount, string calldata description) external onlyBoard returns (uint256) {
        require(to != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.Spend, token, to, address(0), amount, 0, 0, description, ""));
    }

    function proposeElectOfficers(address chair_, address treasurer_, address ceo_) external onlyBoard returns (uint256) {
        require(_isBoard[chair_] && _isBoard[treasurer_], "FoundationDAO: chair and treasurer must be principal board members");
        require(ceo_ != address(0) && ceo_ != inspector, "FoundationDAO: bad ceo");
        return _create(Params(ProposalType.ElectOfficers, chair_, treasurer_, ceo_, 0, 0, 0, "", ""));
    }

    function proposeRegisterExchange(address account, string calldata name, uint256 quota) external onlyBoard returns (uint256) {
        require(account != address(0) && bytes(name).length > 0, "FoundationDAO: bad exchange");
        return _create(Params(ProposalType.RegisterExchange, account, address(0), address(0), quota, 0, 0, name, ""));
    }

    function proposeSetExchangeQuota(address account, uint256 newQuota) external onlyBoard returns (uint256) {
        require(account != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.SetExchangeQuota, account, address(0), address(0), newQuota, 0, 0, "", ""));
    }

    function proposeChangeExchangeKey(address oldAccount, address newAccount) external onlyBoard returns (uint256) {
        require(oldAccount != address(0) && newAccount != address(0) && oldAccount != newAccount, "FoundationDAO: bad accounts");
        return _create(Params(ProposalType.ChangeExchangeKey, oldAccount, newAccount, address(0), 0, 0, 0, "", ""));
    }

    function proposeResumeExchange(address account) external onlyBoard returns (uint256) {
        require(account != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.ResumeExchange, account, address(0), address(0), 0, 0, 0, "", ""));
    }

    function proposeRemoveExchange(address account) external onlyBoard returns (uint256) {
        require(account != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.RemoveExchange, account, address(0), address(0), 0, 0, 0, "", ""));
    }

    function proposeSetSaleTotalCap(uint256 cap) external onlyBoard returns (uint256) {
        return _create(Params(ProposalType.SetSaleTotalCap, address(0), address(0), address(0), cap, 0, 0, "", ""));
    }

    function proposeSweepUnsold(address to) external onlyBoard returns (uint256) {
        require(to != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.SweepUnsold, to, address(0), address(0), 0, 0, 0, "", ""));
    }

    function proposeRotateIdentityOracle(address newOracle) external onlyBoard returns (uint256) {
        require(newOracle != address(0), "FoundationDAO: zero address");
        return _create(Params(ProposalType.RotateIdentityOracle, newOracle, address(0), address(0), 0, 0, 0, "", ""));
    }

    function proposeStartLottery(uint256 ticketPrice, uint256 winnersCount, uint256 closeTime) external onlyBoard returns (uint256) {
        require(ticketPrice > 0 && winnersCount > 0, "FoundationDAO: bad lottery parameters");
        require(closeTime > block.timestamp, "FoundationDAO: closeTime in the past");
        return _create(Params(ProposalType.StartLottery, address(0), address(0), address(0), ticketPrice, winnersCount, closeTime, "", ""));
    }

    function proposeSetSaleContract(address sale) external onlyBoard returns (uint256) {
        require(sale != address(0) && sale.code.length > 0, "FoundationDAO: not a contract");
        return _create(Params(ProposalType.SetSaleContract, sale, address(0), address(0), 0, 0, 0, "", ""));
    }

    function proposeEndSale() external onlyBoard returns (uint256) {
        return _create(Params(ProposalType.EndSale, address(0), address(0), address(0), 0, 0, 0, "", ""));
    }

    /// @notice تنها نوع آزاد. آشکارا ذخیره می‌شود (target، value، data، description) و با همان قاعده‌ی
    ///         paramsHash مثل هر نوع دیگر رأی‌گیری می‌شود. target نمی‌تواند این قرارداد یا FoundationMembers باشد.
    function proposeExecute(address target, uint256 value, bytes calldata data, string calldata description) external onlyBoard returns (uint256) {
        require(target != address(0), "FoundationDAO: zero address");
        require(target != address(this) && target != address(MEMBERS), "FoundationDAO: forbidden target");
        return _create(Params(ProposalType.Execute, target, address(0), address(0), value, 0, 0, description, data));
    }

    // ------------------------------------------------------------------
    // خواندن پیشنهادها
    // ------------------------------------------------------------------
    function getProposal(uint256 id) external view returns (ProposalView memory v) {
        Proposal storage q = _proposals[id];
        require(q.createdAt != 0, "FoundationDAO: proposal not found");
        Params storage p = q.p;
        v = ProposalView(
            p.pType, q.proposer, p.addrA, p.addrB, p.addrC, p.numA, p.numB, p.numC, p.text, p.data,
            q.paramsHash, q.votes, q.requiredVotes, q.createdAt, q.expiresAt, q.boardVersionAtCreation, q.status
        );
    }

    function hasVoted(uint256 id, address voter) external view returns (bool) {
        return _proposals[id].hasVoted[voter];
    }

    /// @notice هشی که رأی‌دهنده باید به `vote` بدهد. تابع کمکی pure تا UI/ممیز بتواند دوباره محاسبه‌اش کند.
    function computeParamsHash(
        ProposalType pType, address a, address b, address c, uint256 x, uint256 y, uint256 z, string calldata text, bytes calldata data
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(pType, a, b, c, x, y, z, text, keccak256(data)));
    }

    // ------------------------------------------------------------------
    // رأی‌گیری
    // ------------------------------------------------------------------
    function vote(uint256 id, bytes32 paramsHash) external onlyBoard nonReentrant {
        _vote(id, paramsHash, msg.sender);
    }

    function _create(Params memory q) private returns (uint256 id) {
        proposalCount++;
        id = proposalCount;
        Proposal storage s = _proposals[id];
        s.p = q;
        s.proposer = msg.sender;
        s.paramsHash = keccak256(abi.encode(q.pType, q.addrA, q.addrB, q.addrC, q.numA, q.numB, q.numC, q.text, keccak256(q.data)));
        s.requiredVotes = _board.length / 2 + 1;
        s.createdAt = block.timestamp;
        s.expiresAt = block.timestamp + PROPOSAL_EXPIRY;
        s.boardVersionAtCreation = boardVersion;
        emit ProposalCreated(id, q.pType, msg.sender, s.paramsHash);
        emit ProposalParams(id, q.addrA, q.addrB, q.addrC, q.numA, q.numB, q.numC, q.text, q.data);
        // رأی پیشنهاددهنده خودکار شمرده می‌شود (تصمیم ۲۰۲۶-۱۱-۱۹)
        _vote(id, s.paramsHash, msg.sender);
    }

    function _vote(uint256 id, bytes32 paramsHash, address voter) private {
        Proposal storage s = _proposals[id];
        require(s.createdAt != 0, "FoundationDAO: proposal not found");
        require(s.status == ProposalStatus.Pending, "FoundationDAO: not pending");
        require(block.timestamp <= s.expiresAt, "FoundationDAO: expired");
        require(s.boardVersionAtCreation == boardVersion, "FoundationDAO: void - board composition changed");
        require(paramsHash == s.paramsHash, "FoundationDAO: parameters hash mismatch");
        require(!s.hasVoted[voter], "FoundationDAO: already voted");
        s.hasVoted[voter] = true;
        s.votes++;
        emit Voted(id, voter, s.votes, s.requiredVotes);
        if (s.votes >= s.requiredVotes) {
            s.status = ProposalStatus.Executed; // effects پیش از interactions
            _execute(s.p);
            emit ProposalExecuted(id, s.p.pType);
        }
    }

    // ------------------------------------------------------------------
    // اجرای پیشنهادهای تایپ‌شده
    // ------------------------------------------------------------------
    function _execute(Params storage p) private {
        ProposalType t = p.pType;
        if (t == ProposalType.Spend) {
            _spend(p.addrA, p.addrB, p.numA);
        } else if (t == ProposalType.ElectOfficers) {
            chair = p.addrA;
            treasurer = p.addrB;
            ceo = p.addrC;
            emit OfficersElected(chair, treasurer, ceo);
        } else if (t == ProposalType.SetSaleContract) {
            saleContract = p.addrA;
            emit SaleContractSet(p.addrA);
        } else if (t == ProposalType.RotateIdentityOracle) {
            IIdentityRegistryOracle(SurAddresses.IDENTITY_REGISTRY).setIdentityOracle(p.addrA);
        } else if (t == ProposalType.StartLottery) {
            IValidatorLottery(SurAddresses.VALIDATOR_LOTTERY).startLottery(p.numA, p.numB, p.numC);
        } else if (t == ProposalType.Execute) {
            _rawCall(p.addrA, p.numA, p.data);
        } else {
            _executeSale(p);
        }
    }

    function _executeSale(Params storage p) private {
        address sale = saleContract;
        require(sale != address(0), "FoundationDAO: SurenSale not set");
        ProposalType t = p.pType;
        if (t == ProposalType.RegisterExchange) {
            ISurenSale(sale).registerExchange(p.addrA, p.text, p.numA);
        } else if (t == ProposalType.SetExchangeQuota) {
            ISurenSale(sale).setExchangeQuota(p.addrA, p.numA);
        } else if (t == ProposalType.ChangeExchangeKey) {
            ISurenSale(sale).changeExchangeKey(p.addrA, p.addrB);
        } else if (t == ProposalType.ResumeExchange) {
            ISurenSale(sale).resumeExchange(p.addrA);
        } else if (t == ProposalType.RemoveExchange) {
            ISurenSale(sale).removeExchange(p.addrA);
        } else if (t == ProposalType.SetSaleTotalCap) {
            ISurenSale(sale).setTotalCap(p.numA);
        } else if (t == ProposalType.SweepUnsold) {
            ISurenSale(sale).sweepUnsold(p.addrA);
        } else if (t == ProposalType.EndSale) {
            ISurenSale(sale).endSale();
        } else {
            revert("FoundationDAO: unknown type");
        }
    }

    function _spend(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "FoundationDAO: Suren transfer failed");
        } else {
            (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "FoundationDAO: token transfer failed");
        }
    }

    function _rawCall(address target, uint256 value, bytes memory data) private {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            if (ret.length > 0) {
                assembly { revert(add(ret, 32), mload(ret)) }
            }
            revert("FoundationDAO: call failed");
        }
    }

    // ==================================================================
    //  ب. توقف فوری (مدیرعامل یا هر عضو اصلی هیأت، به‌تنهایی)
    // ==================================================================
    /// @notice فروش یک صرافی را فوراً متوقف می‌کند (فقط توقف: از سرگیری، تغییر کلید و حذف
    ///         پیشنهادهای تایپ‌شده با ۳ از ۵ هستند).
    function pauseExchange(address exchange) external {
        require(msg.sender == ceo || _isBoard[msg.sender], "FoundationDAO: only CEO or board member");
        require(saleContract != address(0), "FoundationDAO: SurenSale not set");
        ISurenSale(saleContract).pauseExchange(exchange);
        emit ExchangePaused(exchange, msg.sender);
    }

    // ==================================================================
    //  ج. مجمع عمومی
    // ==================================================================
    function callAssembly(AssemblyKind kind, uint256 meetingTime, string calldata agendaURI) external returns (uint256) {
        return _callAssembly(kind, false, meetingTime, agendaURI);
    }

    /// @notice جلسه‌ی دوم، وقتی جلسه‌ی اول همان نوع به حدنصابش نرسید: حدنصاب پایین‌تر (اساسنامه). فقط
    ///         پس از پایان رأی‌گیری مجمع قبلی بدون نتیجه مجاز است.
    function callSecondSession(uint256 previousAssemblyId, uint256 meetingTime, string calldata agendaURI) external returns (uint256) {
        Assembly storage prev = _assemblies[previousAssemblyId];
        require(prev.calledAt != 0, "FoundationDAO: assembly not found");
        require(!prev.secondSession, "FoundationDAO: already a second session");
        require(block.timestamp > prev.votingEnd && !prev.done, "FoundationDAO: previous assembly not failed");
        require(!secondSessionCalled[previousAssemblyId], "FoundationDAO: second session already called");
        secondSessionCalled[previousAssemblyId] = true;
        return _callAssembly(prev.kind, true, meetingTime, agendaURI);
    }

    function _callAssembly(AssemblyKind kind, bool second, uint256 meetingTime, string calldata agendaURI) private returns (uint256 id) {
        require(msg.sender == chair || msg.sender == inspector, "FoundationDAO: only chair or inspector");
        require(meetingTime >= block.timestamp + MIN_NOTICE && meetingTime <= block.timestamp + MAX_NOTICE, "FoundationDAO: notice must be 10-40 days");
        assemblyCount++;
        id = assemblyCount;
        Assembly storage a = _assemblies[id];
        a.kind = kind;
        a.secondSession = second;
        a.caller = msg.sender;
        a.calledAt = block.timestamp;
        a.meetingTime = meetingTime;
        a.votingEnd = meetingTime + VOTING_PERIOD;
        a.agendaURI = agendaURI;
        IFoundationMembers.MemberView[] memory ms = MEMBERS.getAllMembers();
        uint256 total;
        for (uint256 i = 0; i < ms.length; i++) {
            _assemblyWeight[id][ms[i].account] = ms[i].shares;
            total += ms[i].shares;
        }
        a.totalShares = total;
        a.memberCount = ms.length;
        emit AssemblyCalled(id, kind, second, meetingTime, agendaURI);
    }

    function getAssembly(uint256 id) external view returns (Assembly memory) {
        require(_assemblies[id].calledAt != 0, "FoundationDAO: assembly not found");
        return _assemblies[id];
    }

    function assemblyWeightOf(uint256 id, address member) external view returns (uint256) {
        return _assemblyWeight[id][member];
    }

    function _quorumReached(Assembly storage a, uint256 attended) private view returns (bool) {
        // جلسه‌ی اول: بیش از نیمی از سهم‌ها؛ جلسه‌های بعدی: بیش از یک‌سوم
        return a.secondSession ? attended * 3 > a.totalShares : attended * 2 > a.totalShares;
    }

    function _voterWeight(uint256 assemblyId) private view returns (address member, uint256 weight) {
        Assembly storage a = _assemblies[assemblyId];
        require(a.calledAt != 0, "FoundationDAO: assembly not found");
        require(block.timestamp >= a.meetingTime && block.timestamp <= a.votingEnd, "FoundationDAO: voting is not open");
        member = MEMBERS.memberOfVoter(msg.sender);
        require(member != address(0), "FoundationDAO: not a member or representative");
        weight = _assemblyWeight[assemblyId][member];
        require(weight > 0, "FoundationDAO: no voting weight in this assembly");
    }

    // ------------------------------------------------------------------
    // انتخابات هیأت و بازرس (مجمع عادی)
    // ------------------------------------------------------------------
    /// @notice انتخابات هیأت و بازرس را برای یک مجمع عادی باز می‌کند. شناسه‌ی انتخابات همان شناسه‌ی مجمع است.
    function proposeBoardElection(uint256 assemblyId) external returns (uint256) {
        Assembly storage a = _assemblies[assemblyId];
        require(a.calledAt != 0, "FoundationDAO: assembly not found");
        require(a.kind == AssemblyKind.Ordinary, "FoundationDAO: elections need an ordinary assembly");
        require(block.timestamp <= a.votingEnd, "FoundationDAO: assembly over");
        require(!electionOpened[assemblyId], "FoundationDAO: election already opened");
        require(
            msg.sender == chair || msg.sender == inspector || MEMBERS.memberOfVoter(msg.sender) != address(0),
            "FoundationDAO: not allowed to open an election"
        );
        electionOpened[assemblyId] = true;
        emit ElectionOpened(assemblyId);
        return assemblyId;
    }

    function voteBoard(uint256 id, address[5] calldata picks) external {
        require(electionOpened[id] && !electionFinalized[id], "FoundationDAO: election not open");
        (address member, uint256 w) = _voterWeight(id);
        require(!_boardVoted[id][member], "FoundationDAO: already voted for the board");
        _boardVoted[id][member] = true;
        for (uint256 i = 0; i < 5; i++) {
            address c = picks[i];
            require(MEMBERS.isMemberOrRepresentative(c), "FoundationDAO: candidate must be a member or representative");
            for (uint256 j = 0; j < i; j++) require(picks[j] != c, "FoundationDAO: duplicate pick");
            if (boardTally[id][c] == 0) _boardCands[id].push(c);
            boardTally[id][c] += w;
        }
        _markAttended(id, member, w);
        emit BoardVoted(id, member, w);
    }

    function voteInspector(uint256 id, address pick) external {
        require(electionOpened[id] && !electionFinalized[id], "FoundationDAO: election not open");
        require(pick != address(0), "FoundationDAO: zero address");
        (address member, uint256 w) = _voterWeight(id);
        require(!_inspectorVoted[id][member], "FoundationDAO: already voted for the inspector");
        _inspectorVoted[id][member] = true;
        if (inspectorTally[id][pick] == 0) _inspectorCands[id].push(pick);
        inspectorTally[id][pick] += w;
        _markAttended(id, member, w);
        emit InspectorVoted(id, member, pick, w);
    }

    function _markAttended(uint256 id, address member, uint256 w) private {
        if (!_attended[id][member]) {
            _attended[id][member] = true;
            attendedWeight[id] += w;
        }
    }

    function boardCandidates(uint256 id) external view returns (address[] memory) { return _boardCands[id]; }
    function inspectorCandidates(uint256 id) external view returns (address[] memory) { return _inspectorCands[id]; }

    /// @notice هر کسی، پس از پایان رأی‌گیری و رسیدن به حدنصاب: ۵ نفر پررأی‌ترین عضو اصلی می‌شوند، ۲ نفر بعدی
    ///         علی‌البدل، و پررأی‌ترین نامزدِ باقی‌مانده (نه عضو جدید هیأت و نه مدیرعامل — ماده‌ی ۲۸ اساسنامه)
    ///         بازرس؛ یک دوره‌ی ۲ ساله‌ی جدید آغاز می‌شود.
    function finalizeElection(uint256 id) external {
        Assembly storage a = _assemblies[id];
        require(electionOpened[id] && !electionFinalized[id], "FoundationDAO: election not open");
        require(block.timestamp > a.votingEnd, "FoundationDAO: voting not over");
        require(_quorumReached(a, attendedWeight[id]), "FoundationDAO: quorum not reached");

        address[] memory top = _topCandidates(_boardCands[id], id, BOARD_SIZE + ALTERNATES_SIZE);
        require(top.length >= BOARD_SIZE, "FoundationDAO: fewer than 5 candidates");
        address insp = _pickInspector(id, top);
        require(insp != address(0), "FoundationDAO: no valid inspector candidate");

        electionFinalized[id] = true;
        a.done = true;
        _setBoard(top, insp, block.timestamp + BOARD_TERM);
        emit ElectionFinalized(id, _board, _alternates, insp, boardTermEnd);
    }

    /// @dev انتخاب k بیشترین رأی؛ در تساوی، نامزدی که زودتر رأی گرفته برنده است.
    function _topCandidates(address[] storage cands, uint256 id, uint256 k) private view returns (address[] memory out) {
        uint256 n = cands.length;
        uint256[] memory w = new uint256[](n);
        for (uint256 i = 0; i < n; i++) w[i] = boardTally[id][cands[i]];
        address[] memory tmp = new address[](k);
        uint256 found;
        for (uint256 r = 0; r < k; r++) {
            uint256 best = type(uint256).max;
            uint256 bestW;
            for (uint256 i = 0; i < n; i++) {
                if (w[i] > bestW) { bestW = w[i]; best = i; }
            }
            if (best == type(uint256).max) break;
            tmp[found++] = cands[best];
            w[best] = 0;
        }
        out = new address[](found);
        for (uint256 i = 0; i < found; i++) out[i] = tmp[i];
    }

    function _pickInspector(uint256 id, address[] memory top) private view returns (address) {
        address[] storage cands = _inspectorCands[id];
        uint256 n = cands.length;
        uint256[] memory w = new uint256[](n);
        for (uint256 i = 0; i < n; i++) w[i] = inspectorTally[id][cands[i]];
        while (true) {
            uint256 best = type(uint256).max;
            uint256 bestW;
            for (uint256 i = 0; i < n; i++) {
                if (w[i] > bestW) { bestW = w[i]; best = i; }
            }
            if (best == type(uint256).max) return address(0);
            address c = cands[best];
            w[best] = 0;
            bool excluded = (c == ceo);
            // top[0..4] عضو اصلی می‌شوند، top[5..6] علی‌البدل؛ بازرس نمی‌تواند هیچ‌کدام باشد (ماده‌ی ۲۸)
            for (uint256 i = 0; i < top.length && !excluded; i++) if (top[i] == c) excluded = true;
            if (!excluded) return c;
        }
        return address(0); // غیرقابل‌دسترس
    }

    function _setBoard(address[] memory top, address insp, uint256 termEnd) internal {
        for (uint256 i = 0; i < _board.length; i++) _isBoard[_board[i]] = false;
        delete _board;
        delete _alternates;
        for (uint256 i = 0; i < top.length; i++) {
            if (i < BOARD_SIZE) {
                _board.push(top[i]);
                _isBoard[top[i]] = true;
            } else {
                _alternates.push(top[i]);
            }
        }
        inspector = insp;
        boardTermEnd = termEnd;
        boardVersion++; // همه‌ی پیشنهادهای بازِ هیأت قبلی را باطل می‌کند
        if (!_isBoard[chair]) chair = address(0);
        if (!_isBoard[treasurer]) treasurer = address(0);
        if (ceo == insp) ceo = address(0);
    }

    // ------------------------------------------------------------------
    // مصوبه‌های مجمع فوق‌العاده درباره‌ی دفتر اعضا
    // ------------------------------------------------------------------
    /// @notice تغییر دفتر اعضا را در دستور کار یک مجمع فوق‌العاده می‌گذارد. باید پیش از جلسه پیشنهاد شود تا همه
    ///         ببینند. پارامترها به تفکیک عمل:
    ///           AddMember: account, name, personType, other = representative (Legal), amount = shares
    ///           RemoveMember: account
    ///           TransferShares: account = from, other = to, amount
    ///           SetRepresentative: account = member, other = new representative
    function proposeMembersResolution(
        uint256 assemblyId,
        MembersAction action,
        address account,
        address other,
        string calldata name,
        IFoundationMembers.PersonType personType,
        uint256 amount
    ) external returns (uint256 id) {
        Assembly storage a = _assemblies[assemblyId];
        require(a.calledAt != 0, "FoundationDAO: assembly not found");
        require(a.kind == AssemblyKind.Extraordinary, "FoundationDAO: needs an extraordinary assembly");
        require(block.timestamp < a.meetingTime, "FoundationDAO: agenda is closed");
        require(MEMBERS.memberOfVoter(msg.sender) != address(0), "FoundationDAO: only members");
        require(account != address(0), "FoundationDAO: zero address");
        resolutionCount++;
        id = resolutionCount;
        Resolution storage r = _resolutions[id];
        r.assemblyId = assemblyId;
        r.action = action;
        r.account = account;
        r.other = other;
        r.name = name;
        r.personType = personType;
        r.amount = amount;
        r.proposer = msg.sender;
        emit ResolutionProposed(id, assemblyId, action, account, other, name, amount);
    }

    function getResolution(uint256 id) external view returns (Resolution memory) {
        require(_resolutions[id].assemblyId != 0, "FoundationDAO: resolution not found");
        return _resolutions[id];
    }

    function voteResolution(uint256 id, bool approve) external {
        Resolution storage r = _resolutions[id];
        require(r.assemblyId != 0 && !r.executed, "FoundationDAO: resolution not open");
        (address member, uint256 w) = _voterWeight(r.assemblyId);
        require(!_resolutionVoted[id][member], "FoundationDAO: already voted");
        _resolutionVoted[id][member] = true;
        r.attendedCount++;
        if (approve) {
            r.yesWeight += w;
            r.yesCount++;
        } else {
            r.noWeight += w;
        }
        emit ResolutionVoted(id, member, approve, w);
    }

    /// @notice هر کسی، پس از پایان رأی‌گیری. حدنصاب مثل هر جلسه‌ی مجمع (بیش از ۱/۲ سهم‌ها، در جلسه‌ی دوم بیش از ۱/۳)؛
    ///         تصمیم: دارندگان سه‌چهارم سرمایه که هم‌زمان اکثریت عددی هم هستند (ماده‌ی ۱۸ اساسنامه). 🔶 قرائت سخت‌گیرانه:
    ///         با «همه‌ی» سهم‌ها و «همه‌ی» اعضا سنجیده می‌شود، نه فقط حاضران.
    function executeResolution(uint256 id) external nonReentrant {
        Resolution storage r = _resolutions[id];
        require(r.assemblyId != 0 && !r.executed, "FoundationDAO: resolution not open");
        Assembly storage a = _assemblies[r.assemblyId];
        require(block.timestamp > a.votingEnd, "FoundationDAO: voting not over");
        require(_quorumReached(a, r.yesWeight + r.noWeight), "FoundationDAO: quorum not reached");
        require(r.yesWeight * 4 >= a.totalShares * 3, "FoundationDAO: three-quarters of the capital not reached");
        require(r.yesCount * 2 > a.memberCount, "FoundationDAO: numeric majority not reached");
        r.executed = true;
        a.done = true;
        if (r.action == MembersAction.AddMember) {
            MEMBERS.addMember(r.account, r.name, r.personType, r.other, r.amount);
        } else if (r.action == MembersAction.RemoveMember) {
            MEMBERS.removeMember(r.account);
        } else if (r.action == MembersAction.TransferShares) {
            MEMBERS.transferShares(r.account, r.other, r.amount);
        } else {
            MEMBERS.setRepresentative(r.account, r.other);
        }
        emit ResolutionExecuted(id);
    }

    // ------------------------------------------------------------------
    // seed کردن در genesis (فقط FoundationDAO_GenesisSeed از آن استفاده می‌کند)
    // ------------------------------------------------------------------
    function _seedBoard(
        address[] memory principalsAndAlternates,
        address inspector_,
        address chair_,
        address treasurer_,
        address ceo_,
        uint256 termEnd
    ) internal {
        _setBoard(principalsAndAlternates, inspector_, termEnd);
        boardVersion = 0; // هیأت seed‌شده نسخه‌ی ۰ است
        chair = chair_;
        treasurer = treasurer_;
        ceo = ceo_;
    }
}
