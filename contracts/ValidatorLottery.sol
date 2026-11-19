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
/// @notice Lottery of validator seats against validator monopoly (decision 2026-11-19, ✅ commit–reveal).
///         The foundation board is the executor: it starts a lottery with the typed FoundationDAO
///         proposal `StartLottery(ticketPrice, winnersCount, closeTime)` (at least one year after the
///         previous lottery). Winners post no collateral; each winner gets a seat through
///         ValidatorsRegistry.enterAsLotteryWinner (node verification and the agreement signature
///         still happen off-chain/in the registry).
///
///         RANDOMNESS = commit–reveal + blockhash (not prevrandao; QBFT's mixHash is not safe):
///           1. before `closeTime` the CEO commits H(secret) once (`commitSecret`);
///           2. at/after `closeTime` ANYONE calls `closeLottery()`: the participant list is frozen forever
///              and the contract itself fixes `targetBlock = block.number + TARGET_DELAY`, so nobody picks
///              or delays it;
///           3. the CEO reveals the secret only between targetBlock+1 and targetBlock+REVEAL_WINDOW
///              (250 < 256, the EVM blockhash horizon); the contract requires blockhash(targetBlock) != 0;
///              seed = keccak256(secret, blockhash(targetBlock));
///           4. ANYONE calls `drawBatch(n)` repeatedly: partial Fisher–Yates (O(winners)), rand_i =
///              keccak256(seed, i) with rejection sampling (no modulo bias), state kept between batches;
///           5. if the CEO never reveals in the window (or never commits), the lottery is cancelled and
///              every buyer pulls a full refund with `claimRefund()`.
///         Residual risk, kept visible: the CEO can refuse to reveal to cancel an unfavourable outcome
///         (mitigations: cancellation + refund + public event, and neither the CEO nor any principal
///         board member may buy a ticket). REVEAL_WINDOW is a BLOCK count: its length in time depends on
///         the block period of the network.
///
///         MONEY: ticket money stays in this contract until the last `drawBatch`, then goes to the
///         foundation treasury (FoundationDAO) in one transfer; on cancellation buyers refund themselves.
///
///         GENESIS: structural contract, no constructor (initial state is all zero).
contract ValidatorLottery {
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;
    ILotteryIdentity public constant IDENTITY = ILotteryIdentity(SurAddresses.IDENTITY_REGISTRY);
    ILotteryRegistry public constant REGISTRY = ILotteryRegistry(SurAddresses.VALIDATORS_REGISTRY);

    uint256 public constant MIN_INTERVAL = 365 days;
    uint256 public constant TARGET_DELAY = 10; // blocks between closeLottery and the target block
    uint256 public constant REVEAL_WINDOW = 250; // blocks after the target block; must stay < 256

    enum Phase { None, Open, Closed, Revealed, Drawn, Cancelled }

    struct Lottery {
        Phase phase;
        uint256 ticketPrice;
        uint256 winnersCount; // requested; the effective number is min(winnersCount, participants)
        uint256 closeTime;
        bytes32 commitment;
        uint256 targetBlock;
        bytes32 seed;
        uint256 drawn; // winners picked so far
        uint256 pot; // ticket money held
    }

    uint256 public lotteryCount;
    uint256 public lastStartedAt;
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => address[]) private _participants;
    mapping(uint256 => mapping(address => bool)) private _bought;
    mapping(uint256 => mapping(address => bool)) private _refunded;
    mapping(uint256 => address[]) private _winners;
    /// @dev Fisher–Yates swap table: value stored at index (+1; 0 means "still the identity").
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
    // Start — only through the StartLottery proposal of FoundationDAO
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
    // Registration period
    // ------------------------------------------------------------------
    function buyTicket() external payable {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Open && block.timestamp < l.closeTime, "ValidatorLottery: registration is not open");
        require(msg.value == l.ticketPrice, "ValidatorLottery: wrong ticket price");
        require(!_bought[id][msg.sender], "ValidatorLottery: one ticket per address");
        require(IDENTITY.isFullyVerified(msg.sender), "ValidatorLottery: identity not fully verified");
        ILotteryFoundation f = ILotteryFoundation(FOUNDATION);
        require(!f.isBoardMember(msg.sender) && msg.sender != f.ceo(), "ValidatorLottery: board members and the CEO cannot take part");
        _bought[id][msg.sender] = true;
        _participants[id].push(msg.sender);
        l.pot += msg.value;
        emit TicketBought(id, msg.sender);
    }

    /// @notice The CEO commits H(secret) once, during registration. It can never change.
    function commitSecret(bytes32 commitment) external onlyCeo {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Open && block.timestamp < l.closeTime, "ValidatorLottery: registration is not open");
        require(l.commitment == bytes32(0) && commitment != bytes32(0), "ValidatorLottery: commitment already set or empty");
        l.commitment = commitment;
        emit SecretCommitted(id, commitment);
    }

    // ------------------------------------------------------------------
    // Closing — anyone, so the CEO can neither delay it nor choose the target block
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
    // Reveal — only the CEO, only inside the window, never with a zero blockhash
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

    /// @notice Anyone, once the reveal window is over without a reveal: cancels and opens the refunds.
    function cancelLottery() external {
        uint256 id = lotteryCount;
        Lottery storage l = _lotteries[id];
        require(l.phase == Phase.Closed && block.number > l.targetBlock + REVEAL_WINDOW, "ValidatorLottery: cannot cancel now");
        l.phase = Phase.Cancelled;
        emit LotteryCancelled(id, "secret not revealed in the window");
    }

    // ------------------------------------------------------------------
    // Draw — anyone, in batches
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

    /// @dev One partial Fisher–Yates step: pick a uniform index j in [i, total), swap it with position i
    ///      in the sparse swap table, record and return the winner.
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

    /// @dev Uniform integer in [0, range) by rejection sampling over keccak256(seed, position, attempt).
    function _uniform(bytes32 seed, uint256 position, uint256 range) private pure returns (uint256) {
        uint256 limit = type(uint256).max - (type(uint256).max % range) ; // multiples of range below this are unbiased
        for (uint256 attempt = 0; ; attempt++) {
            uint256 r = uint256(keccak256(abi.encode(seed, position, attempt)));
            if (r < limit) return r % range;
        }
    }

    // ------------------------------------------------------------------
    // Refunds after a cancellation (pull)
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
    // Views
    // ------------------------------------------------------------------
    function getLottery(uint256 id) external view returns (Lottery memory) { return _lotteries[id]; }
    function participantsOf(uint256 id) external view returns (address[] memory) { return _participants[id]; }
    function winnersOf(uint256 id) external view returns (address[] memory) { return _winners[id]; }
    function isParticipant(uint256 id, address who) external view returns (bool) { return _bought[id][who]; }
    function participantCount(uint256 id) external view returns (uint256) { return _participants[id].length; }
}
