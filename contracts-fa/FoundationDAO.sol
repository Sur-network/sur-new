// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice اینترفیس حداقلی ERC20 برای انتقال توکن
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title FoundationDAO
/// @notice دیپلوی‌شده در آدرس ثابت genesis، یعنی SurAddresses.FOUNDATION_DAO (0x1111...1111).
///         قرارداد حکمرانی بنیاد سور (تغییرنام از MemberDAO). اعضا و وجوه خودِ بنیاد را
///         مدیریت می‌کند.
///
///         نصاب‌های حکمرانی (تصمیم نهایی، بعد از یک اصلاح صریح کاربر):
///           - AddMember، RemoveMember: نصاب دوسوم، ceil(2n/3) از اعضای فعلی — یک آستانه‌ی
///             عمداً بالاتر مخصوص تغییرات عضویت.
///           - SendETH، SendERC20، Execute: همه‌ی این‌ها (یعنی هر نوع خرج/پرداخت بنیاد،
///             چه ارز بومی چه ERC20، چه فراخوان دلخواه بدون انتقال دارایی) اکثریت ساده،
///             floor(n/2) + 1. ✅ **تصحیح‌شده:** SendETH قبلاً اشتباهاً همراه با تغییرات
///             عضویت زیر نصاب دوسوم دسته‌بندی شده بود — طبق تصمیم صریح کاربر، هر نوع
///             پرداخت باید اکثریت ساده باشه، نه دوسوم. شامل موجودی ۲۰,۰۰۰,۰۰۰ سورنی که این
///             قرارداد از genesis گرفته (بخش ۶ سند طراحی / ماده ۳-۶ اساسنامه‌ی بنیاد) هم می‌شه.
///
///         ⚠️ حذف‌شده (تصمیم به‌روزشده): `proposeRequestTreasuryBudget` / `RequestTreasuryBudget`
///         — غیرمفید تشخیص داده شد و کاملاً حذف شد. این قرارداد الان هیچ اتصالی به
///         ValidatorsTreasury ندارد؛ نمی‌تواند هیچ خرجی را آنجا درخواست، پیشنهاد، یا فعال کند.
///         تنها راهی که الان وجوه سورن از ValidatorsTreasury به بنیاد می‌رسد این است که یک
///         ولیدیتور فعال یا عضو ValidatorsBoard خودش آن پیشنهاد را آغاز کند (به
///         ValidatorsTreasury.sol / ValidatorsBoard.sol مراجعه کن) — بنیاد دیگر هیچ مسیر
///         درخواست خودکاری ندارد.
///
///         عضویت در بنیاد هیچ حق مدنی دیگری را محدود نمی‌کند — یک عضو بنیاد می‌تواند هم‌زمان
///         ولیدیتور شبکه و/یا عضو ValidatorsBoard هم باشد؛ هیچ‌چیز در این قرارداد یا در
///         ValidatorsRegistry/ValidatorsBoard این هم‌پوشانی را چک یا محدود نمی‌کند.
///
///         مهم — مرز حکمرانی (بخش ۴ سند طراحی): بنیاد هیچ کنترلی روی شبکه، ولیدیتورها، یا
///         اوراکل‌های مرتبط با اجماع/وضعیت ولیدیتور ندارد. ✅ **تصحیح‌شده (نادرست بود — ادعای
///         مطلق «هیچ اوراکلی» پایین یک استثنای واقعی رو نادیده می‌گرفت):** این قرارداد
///         همچنان کنترل دو اوراکل مرتبط با عملیات خودش را دارد — `identityOracle` (در
///         IdentityRegistry، از طریق proposeExecute قابل‌چرخش) و `paymentOracle` (در
///         SurenSale) — که هیچ‌کدام روی اجماع یا صلاحیت ولیدیتور اثری ندارند. طراحی قبلی که
///         این قرارداد (به‌عنوان `MemberDAO`) اختیار
///         `setDistributionOracle` / `setValidatorSyncOracle` روی BlockRewardDistributor داشت،
///         کاملاً کنار گذاشته شده است — آن توابع، ثابت قدیمی BLOCK_REWARD_DISTRIBUTOR، و انواع
///         پیشنهاد متناظرشان کاملاً حذف شده‌اند، نه فقط منسوخ. کنترل اوراکل‌های مرتبط با
///         اجماع/ولیدیتور الان منحصراً به
///         ValidatorsBoard (چرخش روتین) و رأی کامل ولیدیتورها (تغییرات ساختاری) تعلق دارد —
///         به ValidatorsBoard.sol و BlockRewardDistributor.sol مراجعه کن.
///
///         دیپلوی genesis: این قرارداد constructor ندارد — مستقیم در alloc genesis تزریق
///         می‌شود، پس constructor هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود. ۱۵ عضو اولیه‌ی بنیاد
///         به‌جایش با ابزار genesis آف‌چین seed می‌شوند (شبیه‌سازی+استخراج، یا محاسبه‌ی مستقیم
///         storage — یادداشت 🔶 پرکردنِ genesis پایین را ببین)، به‌جای bootstrap قدیمیِ
///         تک‌فراخوان `register()`. جدا از این، alloc بلاک genesis آدرس خودِ این قرارداد را
///         با ۲۰,۰۰۰,۰۰۰ سورن (ارز بومی، نه یک انتقال توکن) اعتبار می‌دهد — توزیع اولیه‌ی
///         توکن‌های پایه‌ی شبکه که طبق ماده ۳-۶ اساسنامه مسئولیت بنیاد است؛ بعداً از طریق
///         پیشنهادهای proposeSendETH و با همان اکثریت ساده‌ی هر نوع پرداخت توزیع می‌شود.
contract FoundationDAO {
    // ------------------------------------------------------------------
    // ساختارهای داده
    // ------------------------------------------------------------------
    struct Member {
        string name;
        address account;
    }

    enum ProposalType { AddMember, RemoveMember, SendETH, SendERC20, Execute }
    enum ProposalStatus { Pending, Executed }

    /// @dev ✅ اصلاح‌شده (باگ بحرانی رأی مانده‌شده‌ی پیداشده در بازبینی — همون کلاس مشکل هر
    ///      مکانیزم پیشنهاد/رأی دیگر این پروژه، ولی این یکی توی دور قبلی جا مونده بود):
    ///      `requiredVotes`/`expiresAt` حالا در لحظه‌ی ثبت پیشنهاد snapshot/ثابت می‌شن — دقیقاً
    ///      مثل ShareProposal در BlockRewardDistributor، ParamProposal در ValidatorsRegistry، و
    ///      Expenditure/ParamProposal در ValidatorsTreasury. قبلاً `_requiredVotes()` هر بار
    ///      زنده از memberList.length *فعلی* محاسبه می‌شد، درحالی‌که `votes` فقط زیاد می‌شد —
    ///      یعنی یه پیشنهاد (شامل خرج موجودی ۲۰,۰۰۰,۰۰۰ سورن genesis بنیاد، افزودن/حذف عضو، یا
    ///      یه فراخوانی دلخواه از طریق proposeExecute) که در ۱۵ عضو به نصاب نرسیده بود، می‌تونست
    ///      بعداً، بدون هیچ رأی تازه‌ای، فقط به‌خاطر کوچیک‌شدن ترکیب اعضا، خودبه‌خود
    ///      قابل‌اجرا بشه.
    struct Proposal {
        uint256 id;
        ProposalType pType;
        string description;
        address proposer;
        string newMemberName;   // فقط برای AddMember
        address targetAccount;  // عضو هدف، مقصد انتقال/فراخوانی، یا گیرنده‌ی بودجه‌ی خزانه
        uint256 amount;         // مبلغ ETH یا توکن، یا value برای Execute
        address tokenAddress;   // فقط برای SendERC20
        bytes data;             // فقط برای Execute
        uint256 votes;
        uint256 requiredVotes; // ✅ تازه — در لحظه‌ی ثبت snapshot می‌شه، هرگز دوباره حساب نمی‌شه
        uint256 createdAt;
        uint256 expiresAt; // ✅ تازه — بعد از این دیگه قابل‌رأی/اجرا نیست
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    /// @notice ✅ تازه: مدت زمانی که یه پیشنهاد بنیاد بعد از ثبت هنوز قابل‌رأی/اجراست.
    uint256 public constant PROPOSAL_EXPIRY = 30 days;

    // ------------------------------------------------------------------
    // متغیرهای state
    //
    // 🔶 پرکردنِ genesis: ۱۵ عضو مؤسس بنیاد. `memberList` یک آرایه‌ی پویاست و
    // `memberIndex`/`isMember` هر دو mapping‌اند — Solidity هیچ syntax ای برای پرکردن هیچ‌کدام
    // با یک حلقه خارج از تابع ندارد، پس این state اولیه اینجا نمی‌تواند به‌صورت یک مقداردهی
    // ساده‌ی متغیر state بیان شود. ابزار genesis آف‌چین باید یا (الف) دیپلوی این قرارداد را با
    // منطق seed کردن واقعی پایین، روی یک زنجیره‌ی محلی موقت شبیه‌سازی کند و storage نتیجه را
    // در فایل نهایی genesis کپی کند، یا (ب) مستقیم storage slot های متناظر را در alloc genesis
    // محاسبه و بنویسد. برای دستورالعمل کامل به "sur-contracts-deploy-notes.md" مراجعه کن.
    //
    // منطق مرجع (کد زنده نیست — برای این‌که ابزار genesis آن را، چه با شبیه‌سازی چه با
    // محاسبه‌ی مستقیم storage، بازتولید کند) — برای هرکدام از ۱۵ جفت (نام، آدرس) مؤسس:
    //   memberList.push(Member({name: name, account: account}));
    //   memberIndex[account] = memberList.length; // یک‌مبنایی
    //   isMember[account] = true;
    // ------------------------------------------------------------------
    Member[] public memberList;
    mapping(address => uint256) private memberIndex; // اندیس یک‌مبنایی در memberList، صفر یعنی عضو نیست
    mapping(address => bool) public isMember;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private proposals;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ProposalCreated(uint256 indexed id, ProposalType pType, address indexed proposer);
    event Voted(uint256 indexed id, address indexed voter, uint256 totalVotes, uint256 requiredVotes);
    event ProposalExecuted(uint256 indexed id, ProposalType pType);
    event MemberAdded(address indexed account, string name);
    event MemberRemoved(address indexed account);

    modifier onlyMember() {
        require(isMember[msg.sender], "FoundationDAO: caller is not a member");
        _;
    }

    receive() external payable {}

    // ------------------------------------------------------------------
    // 🔶 پرکردنِ genesis — این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis
    // تزریق می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). برای دستورالعمل کامل
    // شبیه‌سازی+استخراج به "sur-contracts-deploy-notes.md" مراجعه کن. جدا از این، alloc
    // genesis باید آدرس خودِ این قرارداد را هم با ۲۰,۰۰۰,۰۰۰ سورن اعتبار بدهد (ارز بومی — به
    // مستندات سطح قرارداد بالا و sur-tokenomics.md برای توزیع کامل و سه‌ردیفی genesis
    // مراجعه کن).
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // ساخت پیشنهاد — فقط اعضا
    // ------------------------------------------------------------------
    function proposeAddMember(string calldata description, string calldata name, address account) external onlyMember returns (uint256) {
        require(account != address(0), "FoundationDAO: zero address");
        require(!isMember[account], "FoundationDAO: already a member");
        require(bytes(name).length > 0, "FoundationDAO: empty name");
        return _createProposal(description, ProposalType.AddMember, name, account, 0, address(0), "");
    }

    function proposeRemoveMember(string calldata description, address account) external onlyMember returns (uint256) {
        require(isMember[account], "FoundationDAO: not a member");
        return _createProposal(description, ProposalType.RemoveMember, "", account, 0, address(0), "");
    }

    function proposeSendETH(string calldata description, address to, uint256 amount) external onlyMember returns (uint256) {
        // توجه: این همچنین مکانیزم ماده ۳-۶ اساسنامه‌ی بنیاد است (توزیع اولیه‌ی سورنِ
        // mint‌شده در genesis، ارز بومی زنجیره، توسط بنیاد به شرکت‌کنندگان شبکه) — نیازی به
        // قرارداد توزیع جدا نیست. سورنی که به موجودی alloc genesis خودِ این قرارداد اعتبار
        // داده شده، می‌تواند به‌سادگی با پیشنهاد عضو‌به‌عضو از همین تابع بیرون فرستاده شود،
        // چون سورن ارز بومی است، نه یک توکن.
        require(to != address(0), "FoundationDAO: zero address");
        return _createProposal(description, ProposalType.SendETH, "", to, amount, address(0), "");
    }

    function proposeSendERC20(string calldata description, address token, address to, uint256 amount) external onlyMember returns (uint256) {
        require(token != address(0) && to != address(0), "FoundationDAO: zero address");
        return _createProposal(description, ProposalType.SendERC20, "", to, amount, token, "");
    }

    /// @notice اجرای کد دلخواه (data) روی یک آدرس هدف، منوط به اجماع اکثریت اعضا
    /// @notice ✅ اصلاح‌شده (باگ دورزدن حکمرانی پیداشده در بازبینی، حتی بعد از تصمیم بعدیِ
    ///         نصاب که خودش این باگ رو کم‌خطرتر کرد، همچنان نگه داشته شد): `Execute` قبلاً هر
    ///         `value`ای رو قبول می‌کرد، و _execute() پایین اون رو عیناً از طریق
    ///         `target.call{value: amount}(data)` فوروارد می‌کرد — یعنی یه عضو می‌تونست هر
    ///         مقداری از سورن بنیاد رو با صدازدن proposeExecute() با `data`ی خالی و `value`ی
    ///         غیرصفر منتقل کنه، با نصاب همین تابع به‌جای نصاب proposeSendETH(). ✅ **تصمیم
    ///         بعدی (اصلاح صریح):** الان هر دو تابع دقیقاً همون نصاب اکثریت ساده رو دارن (به
    ///         _requiredVotes() پایین مراجعه کن — هر نوع پرداخت بنیاد همینه)، پس این دورزدن
    ///         خاص دیگه هیچ تفاوتی توی تعداد رأی لازم نمی‌سازه. الزام `value == 0` همچنان نگه
    ///         داشته شد، به‌عنوان یه تفکیک مسئولیت درست: انتقال سورن یه مسیر اختصاصی و
    ///         قابل‌ردیابی داره (proposeSendETH())، و Execute مخصوص فراخوان‌هایی می‌مونه که
    ///         اصلاً موجودی بومی بنیاد رو جابه‌جا نمی‌کنن.
    function proposeExecute(string calldata description, address target, uint256 value, bytes calldata data) external onlyMember returns (uint256) {
        require(target != address(0), "FoundationDAO: zero address");
        require(value == 0, "FoundationDAO: Execute cannot move Suren - use proposeSendETH for that");
        return _createProposal(description, ProposalType.Execute, "", target, value, address(0), data);
    }

    function _createProposal(
        string memory description,
        ProposalType pType,
        string memory name,
        address target,
        uint256 amount,
        address token,
        bytes memory data
    ) private returns (uint256) {
        proposalCount++;
        uint256 id = proposalCount;

        Proposal storage p = proposals[id];
        p.id = id;
        p.description = description;
        p.pType = pType;
        p.proposer = msg.sender;
        p.newMemberName = name;
        p.targetAccount = target;
        p.amount = amount;
        p.tokenAddress = token;
        p.data = data;
        p.requiredVotes = _requiredVotes(pType); // ✅ همین لحظه ثابت‌شده
        p.createdAt = block.timestamp;
        p.expiresAt = block.timestamp + PROPOSAL_EXPIRY; // ✅ تازه
        p.status = ProposalStatus.Pending;

        emit ProposalCreated(id, pType, msg.sender);

        // پیشنهاددهنده خودکار به‌عنوان یک رأی «موافق» شمرده می‌شود
        _vote(id, msg.sender);

        return id;
    }

    // ------------------------------------------------------------------
    // رأی‌گیری — به‌محض رسیدن به آستانه‌ی اکثریت، پیشنهاد بلافاصله اجرا می‌شود
    // ------------------------------------------------------------------
    function vote(uint256 proposalId) external onlyMember {
        _vote(proposalId, msg.sender);
    }

    function _vote(uint256 proposalId, address voter) private {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "FoundationDAO: proposal not found");
        require(p.status == ProposalStatus.Pending, "FoundationDAO: proposal not pending");
        require(block.timestamp <= p.expiresAt, "FoundationDAO: proposal has expired");
        require(!p.hasVoted[voter], "FoundationDAO: already voted");

        p.hasVoted[voter] = true;
        p.votes++;

        emit Voted(proposalId, voter, p.votes, p.requiredVotes);

        if (p.votes >= p.requiredVotes) {
            _execute(p);
        }
    }

    /// @dev آستانه‌ی رأی‌گیری بسته به نوع پیشنهاد فرق می‌کند:
    ///      - AddMember، RemoveMember: نصاب دوسوم، ceil(2n/3) — یک آستانه‌ی عمداً بالاتر
    ///        مخصوص تغییرات عضویت.
    ///      - بقیه، شامل SendETH (یعنی خرج موجودی ۲۰,۰۰۰,۰۰۰ سورنی که این قرارداد از genesis
    ///        گرفته — سورن ارز بومی است، بخش ۳-۶ سند طراحی / ماده ۳-۶ اساسنامه‌ی بنیاد را
    ///        ببین)، SendERC20، و Execute: اکثریت ساده، floor(n/2) + 1. ✅ **تصمیم قطعی
    ///        (اصلاح صریح): SendETH قبلاً اشتباهاً همراه با تغییرات عضویت زیر نصاب دوسوم
    ///        بود؛ هر نوع پرداخت بنیاد حالا همون آستانه‌ی اکثریت ساده رو داره.**
    ///      مثلاً با ۱۵ عضو: اکثریت ساده -> ۸، نصاب دوسوم -> ۱۰.
    /// @notice ✅ تصمیم قطعی (اصلاح صریح کاربر — نهایی): SendETH قبلاً همراه با
    ///         AddMember/RemoveMember زیر نصاب دوسوم دسته‌بندی شده بود. این اشتباه بود — هر
    ///         نوع پرداخت بنیاد (خرج سورن) از اکثریت ساده استفاده می‌کند، دقیقاً مثل
    ///         SendERC20 و Execute، که هیچ‌وقت بیشتر از این نیاز نداشتند. فقط تغییرات عضویت
    ///         (AddMember، RemoveMember) نصاب دوسوم رو نگه می‌دارن.
    function _requiredVotes(ProposalType pType) private view returns (uint256) {
        uint256 n = memberList.length;
        if (pType == ProposalType.AddMember || pType == ProposalType.RemoveMember) {
            return (2 * n + 2) / 3; // ceil(2n/3)
        }
        return (n / 2) + 1;
    }

    // ------------------------------------------------------------------
    // اجرای پیشنهاد بعد از رسیدن به اجماع
    // ------------------------------------------------------------------
    function _execute(Proposal storage p) private {
        p.status = ProposalStatus.Executed;

        if (p.pType == ProposalType.AddMember) {
            _addMember(p.targetAccount, p.newMemberName);
            emit MemberAdded(p.targetAccount, p.newMemberName);

        } else if (p.pType == ProposalType.RemoveMember) {
            _removeMember(p.targetAccount);
            emit MemberRemoved(p.targetAccount);

        } else if (p.pType == ProposalType.SendETH) {
            (bool success, ) = p.targetAccount.call{value: p.amount}("");
            require(success, "FoundationDAO: ETH transfer failed");

        } else if (p.pType == ProposalType.SendERC20) {
            bool success = IERC20(p.tokenAddress).transfer(p.targetAccount, p.amount);
            require(success, "FoundationDAO: ERC20 transfer failed");

        } else if (p.pType == ProposalType.Execute) {
            (bool success, ) = p.targetAccount.call{value: p.amount}(p.data);
            require(success, "FoundationDAO: execution failed");
        }

        emit ProposalExecuted(p.id, p.pType);
    }

    // ------------------------------------------------------------------
    // توابع داخلی مدیریت عضویت
    // ------------------------------------------------------------------
    function _addMember(address account, string memory name) private {
        require(account != address(0), "FoundationDAO: zero address");
        require(!isMember[account], "FoundationDAO: already a member");
        memberList.push(Member({name: name, account: account}));
        memberIndex[account] = memberList.length; // اندیس یک‌مبنایی
        isMember[account] = true;
    }

    function _removeMember(address account) private {
        require(isMember[account], "FoundationDAO: not a member");
        uint256 idx = memberIndex[account] - 1;
        uint256 lastIdx = memberList.length - 1;

        if (idx != lastIdx) {
            memberList[idx] = memberList[lastIdx];
            memberIndex[memberList[idx].account] = idx + 1;
        }
        memberList.pop();

        delete memberIndex[account];
        isMember[account] = false;
    }

    // ------------------------------------------------------------------
    // توابع کمکی view
    // ------------------------------------------------------------------
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }

    function getAllMembers() external view returns (Member[] memory) {
        return memberList;
    }

    /// @notice آستانه‌ی رأی موردنیاز همین الان برای یک نوع پیشنهاد مشخص — نصاب دوسوم برای
    ///         AddMember/RemoveMember، اکثریت ساده در بقیه‌ی موارد (شامل SendETH — هر نوع
    ///         پرداخت بنیاد).
    function requiredVotesNow(ProposalType pType) external view returns (uint256) {
        return _requiredVotes(pType);
    }

    function getProposal(uint256 id) external view returns (
        ProposalType pType,
        address proposer,
        string memory newMemberName,
        address targetAccount,
        uint256 amount,
        address tokenAddress,
        bytes memory data,
        uint256 votes,
        ProposalStatus status
    ) {
        Proposal storage p = proposals[id];
        return (
            p.pType,
            p.proposer,
            p.newMemberName,
            p.targetAccount,
            p.amount,
            p.tokenAddress,
            p.data,
            p.votes,
            p.status
        );
    }

    /// @notice D05 (ممیزی ۲۰۲۶-۰۹-۳۰): مکمل فقط‌خواندنی getProposal()، که برای فراخوان‌های موجود بدون تغییر حفظ شده است.
    ///         `proposals` خصوصی است و getProposal() این چهار فیلد را برنمی‌گرداند؛ پس بدون این getter رابط کاربری نمی‌توانست
    ///         توضیح پیشنهاد، نصاب ثبت‌شده «هنگام ساخت» آن (requiredVotesNow() فقط نصاب یک پیشنهاد تازه است و با تغییر اعضا فرق
    ///         می‌کند)، یا زمان انقضا را نشان دهد. برای شناسه‌ای که هرگز ساخته نشده، همهٔ فیلدها خالی/صفرند (همانند getProposal()).
    function getProposalMeta(uint256 id) external view returns (
        string memory description,
        uint256 requiredVotes,
        uint256 createdAt,
        uint256 expiresAt
    ) {
        Proposal storage p = proposals[id];
        return (p.description, p.requiredVotes, p.createdAt, p.expiresAt);
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getErc20Balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasVoted[voter];
    }
}
