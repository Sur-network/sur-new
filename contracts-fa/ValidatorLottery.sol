// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface ILotteryIdentity {
    function isFullyVerified(address who) external view returns (bool);
}

interface ILotteryFoundation {
    function ceo() external view returns (address);
    function isBoardMember(address who) external view returns (bool);
}

interface ILotteryRegistry {
    function enterAsLotteryWinner(address winner) external;
}

/// @title ValidatorLottery
/// @notice قرعه‌کشی جایگاه‌های ولیدیتور برای مقابله با انحصار ولیدیتورها (تصمیم ۲۰۲۶-۱۱-۱۹، ✅ commit–reveal).
///         مجری، هیأت بنیاد است: قرعه‌کشی را با پیشنهاد تایپ‌شده‌ی FoundationDAO به نام
///         `StartLottery(ticketPrice, winnersCount, closeTime)` شروع می‌کند (دست‌کم یک سال پس از
///         قرعه‌کشی قبلی). برندگان وثیقه نمی‌گذارند؛ هر برنده از طریق
///         ValidatorsRegistry.enterAsLotteryWinner جایگاه می‌گیرد (راستی‌آزمایی گره و امضای برگ قبولی
///         همچنان خارج از زنجیره/در Registry انجام می‌شود).
///
///         تصادفی‌بودن = commit–reveal + blockhash (نه prevrandao؛ mixHash در QBFT امن نیست):
///           ۱. پیش از `closeTime` مدیرعامل یک بار H(secret) را commit می‌کند (`commitSecret`)؛
///           ۲. در/پس از `closeTime` «هر کسی» می‌تواند `closeLottery()` را صدا بزند: فهرست شرکت‌کنندگان
///              برای همیشه قفل می‌شود و خود قرارداد `targetBlock = block.number + TARGET_DELAY` را
///              تعیین می‌کند، پس هیچ‌کس آن را انتخاب یا به تأخیر نمی‌اندازد؛
///           ۳. مدیرعامل راز را فقط بین targetBlock+1 و targetBlock+REVEAL_WINDOW فاش می‌کند
///              (۲۵۰ < ۲۵۶، افق blockhash در EVM)؛ قرارداد الزام می‌کند blockhash(targetBlock) != 0 باشد؛
///              seed = keccak256(secret, blockhash(targetBlock))؛
///           ۴. «هر کسی» می‌تواند `drawBatch(n)` را به‌تکرار صدا بزند: Fisher–Yates جزئی (O(winners))،
///              rand_i = keccak256(seed, i) با نمونه‌برداری ردکننده (بدون اریب باقی‌مانده)، و state
///              بین دسته‌ها نگه داشته می‌شود؛
///           ۵. اگر مدیرعامل در بازه فاش نکند (یا اصلاً commit نکند)، قرعه‌کشی لغو می‌شود و هر
///              خریدار با `claimRefund()` بازپرداخت کامل را خودش برمی‌دارد.
///         ریسک باقی‌مانده، که عمداً دیده می‌ماند: مدیرعامل می‌تواند برای لغو یک نتیجه‌ی نامطلوب از
///         فاش‌کردن خودداری کند (تعدیل‌ها: لغو + بازپرداخت + رویداد عمومی؛ مدیرعامل و هیچ‌یک از
///         اعضای اصلی هیأت اجازه‌ی خرید بلیت ندارند). REVEAL_WINDOW یک «تعداد بلاک» است: طولش بر حسب
///         زمان به دوره‌ی بلاک شبکه بستگی دارد.
///
///         پول: پول بلیت‌ها تا آخرین `drawBatch` در همین قرارداد می‌ماند، سپس با یک انتقال به خزانه‌ی
///         بنیاد (FoundationDAO) می‌رود؛ در صورت لغو، خریداران خودشان بازپرداخت می‌گیرند.
///
///         GENESIS: قرارداد ساختاری، بدون constructor (وضعیت اولیه همه صفر است).
contract ValidatorLottery {
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;
    ILotteryIdentity public constant IDENTITY = ILotteryIdentity(SurAddresses.IDENTITY_REGISTRY);
    ILotteryRegistry public constant REGISTRY = ILotteryRegistry(SurAddresses.VALIDATORS_REGISTRY);

    uint256 public constant MIN_INTERVAL = 365 days;
    uint256 public constant TARGET_DELAY = 10; // تعداد بلاک بین closeLottery و بلاک هدف
    uint256 public constant REVEAL_WINDOW = 250; // تعداد بلاک پس از بلاک هدف؛ باید زیر ۲۵۶ بماند

    enum Phase { None, Open, Closed, Revealed, Drawn, Cancelled }

    struct Lottery {
        Phase phase;
        uint256 ticketPrice;
        uint256 winnersCount; // درخواست‌شده؛ تعداد مؤثر min(winnersCount, participants) است
        uint256 closeTime;
        bytes32 commitment;
        uint256 targetBlock;
        bytes32 seed;
        uint256 drawn; // تعداد برندگانی که تا الان انتخاب شده‌اند
        uint256 pot; // پول بلیت‌های نگه‌داشته‌شده
    }

    uint256 public lotteryCount;
    uint256 public lastStartedAt;
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => address[]) private _participants;
    mapping(uint256 => mapping(address => bool)) private _bought;
    mapping(uint256 => mapping(address => bool)) private _refunded;
    mapping(uint256 => address[]) private _winners;
    /// @dev جدول swap در Fisher–Yates: مقدار ذخیره‌شده در اندیس (+۱؛ صفر یعنی «هنوز همانی»).
    mapping(uint256 => mapping(uint256 => uint256)) private _swapped;
    mapping(uint256 => mapping(address => bool)) public entryFailed;

    event LotteryStarted(uint256 indexed id, uint256 ticketPrice, uint256 winnersCount, uint256 closeTime);
    event TicketBought(uint256 indexed id, address indexed buyer);
    event SecretCommitted(uint256 indexed id, bytes32 commitment);
    event LotteryClosed(uint256 indexed id, uint256 participants, uint256 targetBlock);
    event SecretRevealed(uint256 indexed id, bytes32 seed);
    event WinnerDrawn(uint256 indexed id, uint256 indexed position, address winner);
    event WinnerEntryFailed(uint256 indexed id, address winner);
    event LotteryDrawn(uint256 indexed id, uint256 winners, uint256 pot);
    event LotteryCancelled(uint256 indexed id, string reason);
    event RefundClaimed(uint256 indexed id, address indexed buyer, uint256 amount);

    modifier onlyFoundation() {
        require(msg.sender == FOUNDATION, "ValidatorLottery: only FoundationDAO");
        _;
    }

    modifier onlyCeo() {
        address c = ILotteryFoundation(FOUNDATION).ceo();
        require(c != address(0) && msg.sender == c, "ValidatorLottery: only the CEO");
        _;
    }

    // ------------------------------------------------------------------
    // شروع — فقط از طریق پیشنهاد StartLottery در FoundationDAO
    // ------------------------------------------------------------------
    function startLottery(uint256 ticketPrice, uint256 winnersCount, uint256 closeTime) external onlyFoundation {
        require(ticketPrice > 0 && winnersCount > 0, "ValidatorLottery: bad parameters");
        require(closeTime > block.timestamp, "ValidatorLottery: closeTime in the past");
        require(lastStartedAt == 0 || block.timestamp >= lastStartedAt + MIN_INTERVAL, "ValidatorLottery: less than a year since the last lottery");
        if (lotteryCount > 0) {
            Phase p = _lotteries[lotteryCount].phase;
            require(p == Phase.Drawn || p == Phase.Cancelled, "ValidatorLottery: previous lottery unfinished");
        }
        lotteryCount++;
        lastStartedAt = block.timestamp;
        Lottery storage l = _lotteries[lotteryCount];
        l.phase = Phase.Open;
        l.ticketPrice = ticketPrice;
        l.winnersCount = winnersCount;
        l.closeTime = closeTime;
        emit LotteryStarted(lotteryCount, ticketPrice, winnersCount, closeTime);
    }

    // ------------------------------------------------------------------
    // دوره‌ی ثبت‌نام
    // ------------------------------------------------------------------
    function buyTicket() external payable {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Open && block.timestamp < l.closeTime, "ValidatorLottery: registration is not open");
        require(msg.value == l.ticketPrice, "ValidatorLottery: wrong ticket price");
        require(msg.sender.code.length == 0 && msg.sender == tx.origin, "ValidatorLottery: a seat owner must be a plain wallet (EOA)"); // RD-12
        require(!_bought[id][msg.sender], "ValidatorLottery: one ticket per address");
        require(IDENTITY.isFullyVerified(msg.sender), "ValidatorLottery: identity not fully verified");
        ILotteryFoundation f = ILotteryFoundation(FOUNDATION);
        require(!f.isBoardMember(msg.sender) && msg.sender != f.ceo(), "ValidatorLottery: board members and the CEO cannot take part");
        _bought[id][msg.sender] = true;
        _participants[id].push(msg.sender);
        l.pot += msg.value;
        emit TicketBought(id, msg.sender);
    }

    /// @notice مدیرعامل یک بار H(secret) را در دوره‌ی ثبت‌نام commit می‌کند. هرگز قابل تغییر نیست.
    function commitSecret(bytes32 commitment) external onlyCeo {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Open && block.timestamp < l.closeTime, "ValidatorLottery: registration is not open");
        require(l.commitment == bytes32(0) && commitment != bytes32(0), "ValidatorLottery: commitment already set or empty");
        l.commitment = commitment;
        emit SecretCommitted(id, commitment);
    }

    // ------------------------------------------------------------------
    // بستن — هر کسی؛ تا مدیرعامل نه بتواند آن را به تأخیر بیندازد نه بلاک هدف را انتخاب کند
    // ------------------------------------------------------------------
    function closeLottery() external {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Open && block.timestamp >= l.closeTime, "ValidatorLottery: cannot close now");
        if (l.commitment == bytes32(0)) {
            l.phase = Phase.Cancelled;
            emit LotteryCancelled(id, "no commitment before closeTime");
            return;
        }
        uint256 n = _participants[id].length;
        if (n == 0) {
            l.phase = Phase.Drawn;
            emit LotteryDrawn(id, 0, 0);
            return;
        }
        l.phase = Phase.Closed;
        l.targetBlock = block.number + TARGET_DELAY;
        emit LotteryClosed(id, n, l.targetBlock);
    }

    // ------------------------------------------------------------------
    // افشا (reveal) — فقط مدیرعامل، فقط داخل بازه، و هرگز با blockhash صفر
    // ------------------------------------------------------------------
    function reveal(bytes32 secret) external onlyCeo {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Closed, "ValidatorLottery: not waiting for the reveal");
        require(block.number > l.targetBlock, "ValidatorLottery: target block not mined yet");
        require(block.number <= l.targetBlock + REVEAL_WINDOW, "ValidatorLottery: reveal window over");
        require(keccak256(abi.encodePacked(secret)) == l.commitment, "ValidatorLottery: secret does not match the commitment");
        bytes32 bHash = blockhash(l.targetBlock);
        require(bHash != bytes32(0), "ValidatorLottery: target blockhash expired");
        l.seed = keccak256(abi.encode(secret, bHash));
        l.phase = Phase.Revealed;
        emit SecretRevealed(id, l.seed);
    }

    /// @notice هر کسی، وقتی بازه‌ی افشا بدون افشا تمام شد: قرعه‌کشی را لغو می‌کند و بازپرداخت‌ها را باز می‌کند.
    function cancelLottery() external {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Closed && block.number > l.targetBlock + REVEAL_WINDOW, "ValidatorLottery: cannot cancel now");
        l.phase = Phase.Cancelled;
        emit LotteryCancelled(id, "secret not revealed in the window");
    }

    // ------------------------------------------------------------------
    // قرعه‌کشی — هر کسی، در دسته‌ها
    // ------------------------------------------------------------------
    function drawBatch(uint256 n) external {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Revealed, "ValidatorLottery: not ready to draw");
        require(n > 0, "ValidatorLottery: empty batch");
        address[] storage parts = _participants[id];
        uint256 total = parts.length;
        uint256 k = l.winnersCount < total ? l.winnersCount : total;

        uint256 i = l.drawn;
        uint256 end = i + n > k ? k : i + n;
        for (; i < end; i++) {
            address winner = _drawOne(id, l.seed, i, total);
            emit WinnerDrawn(id, i, winner);
            try REGISTRY.enterAsLotteryWinner(winner) {} catch {
                entryFailed[id][winner] = true;
                emit WinnerEntryFailed(id, winner);
            }
        }
        l.drawn = i;
        if (i == k) {
            l.phase = Phase.Drawn;
            uint256 pot = l.pot;
            l.pot = 0;
            emit LotteryDrawn(id, k, pot);
            (bool ok, ) = FOUNDATION.call{value: pot}("");
            require(ok, "ValidatorLottery: transfer to the foundation treasury failed");
        }
    }

    /// @dev یک گام Fisher–Yates جزئی: یک اندیس یکنواخت j در [i, total) انتخاب می‌کند، آن را با
    ///      موقعیت i در جدول swap پراکنده عوض می‌کند، برنده را ثبت و برمی‌گرداند.
    function _drawOne(uint256 id, bytes32 seed, uint256 i, uint256 total) private returns (address winner) {
        uint256 j = i + _uniform(seed, i, total - i);
        uint256 atJ = _swapped[id][j];
        uint256 valueJ = atJ == 0 ? j : atJ - 1;
        uint256 atI = _swapped[id][i];
        uint256 valueI = atI == 0 ? i : atI - 1;
        _swapped[id][j] = valueI + 1;
        _swapped[id][i] = valueJ + 1;
        winner = _participants[id][valueJ];
        _winners[id].push(winner);
    }

    /// @dev عدد صحیح یکنواخت در [0, range) با نمونه‌برداری ردکننده روی keccak256(seed, position, attempt).
    function _uniform(bytes32 seed, uint256 position, uint256 range) private pure returns (uint256) {
        uint256 limit = type(uint256).max - (type(uint256).max % range) ; // مضرب‌های range زیر این حد بدون اریب‌اند
        for (uint256 attempt = 0; ; attempt++) {
            uint256 r = uint256(keccak256(abi.encode(seed, position, attempt)));
            if (r < limit) return r % range;
        }
    }

    // ------------------------------------------------------------------
    // بازپرداخت پس از لغو (pull)
    // ------------------------------------------------------------------
    function claimRefund(uint256 id) external {
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Cancelled, "ValidatorLottery: not cancelled");
        require(_bought[id][msg.sender] && !_refunded[id][msg.sender], "ValidatorLottery: nothing to refund");
        _refunded[id][msg.sender] = true;
        l.pot -= l.ticketPrice;
        emit RefundClaimed(id, msg.sender, l.ticketPrice);
        (bool ok, ) = msg.sender.call{value: l.ticketPrice}("");
        require(ok, "ValidatorLottery: refund failed");
    }

    // ------------------------------------------------------------------
    // نمایش
    // ------------------------------------------------------------------
    function getLottery(uint256 id) external view returns (Lottery memory) { return _lotteries[id]; }
    function participantsOf(uint256 id) external view returns (address[] memory) { return _participants[id]; }
    function winnersOf(uint256 id) external view returns (address[] memory) { return _winners[id]; }
    function isParticipant(uint256 id, address who) external view returns (bool) { return _bought[id][who]; }
    function participantCount(uint256 id) external view returns (uint256) { return _participants[id].length; }
}
