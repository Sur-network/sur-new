// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
}

/// @title ValidatorsTreasury
/// @notice Deployed at the fixed genesis address SurAddresses.VALIDATORS_TREASURY (0x5555...5555).
///         Holds native Suren only — Suren is the SUR chain's own base/gas currency (like ETH on
///         Ethereum, credited via genesis `alloc` balances and ordinary value transfers), NOT an
///         ERC20 token, so there is no separate token contract or `transferFrom` involved
///         anywhere in this system.
///
///         Two inflows, both native currency:
///           - Whatever remains of the block reward after Foundation's fixed 15% cut (of TOTAL
///             rewards) and validators' own direct, governable share (validatorDirectShareBps,
///             [40%, 65%] of total) are both removed — see sur-tokenomics.md sections 6.5/6.6.
///             Transaction fees never flow here — 70% of fees go directly to validators by block
///             ratio, and the remaining 30% is permanently burned (section 7) — treasury gets
///             none of either.
///           - The slashed collateral forwarded directly by ValidatorsRegistry on every
///             inactivity-demotion. Membership fees go to BlockRewardDistributor instead.
///
///         ✅ REDESIGNED (explicit user decision — full-validator-assembly spending removed
///         entirely): the assembly (all active validators) no longer has ANY path to propose or
///         approve an individual payment from this treasury. Its role is now limited strictly to
///         setting/changing the SPENDING RULES the board must operate within (the per-payment
///         cap, the rolling 30-day total cap, and how long a rule change is delayed before taking
///         effect) — never a specific payment. Every actual expenditure now goes through
///         ValidatorsBoard exclusively, bounded by those assembly-set rules. Rationale (stated by
///         the user): having two parallel paths to the same kind of decision (assembly vote vs.
///         board vote) invited "venue shopping" — trying whichever path was more likely to
///         approve a given payment. A single path with assembly-controlled limits removes that
///         ambiguity while still keeping the assembly in ultimate control of how much can ever be
///         spent, just not of any one payment's approval.
///
///         GENESIS DEPLOYMENT: ValidatorsBoard's address is a fixed constant (see
///         SurAddresses.sol) rather than mutable state set via a runtime `wire()` step, because
///         all five structural contracts share a common, pre-agreed genesis address map.
contract ValidatorsTreasury {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice The only address allowed to actually spend from this treasury.
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    bool private locked; // reentrancy guard

    uint256 public totalDistributedToTreasury; // lifetime inflow received (reward share + slashed stake)
    uint256 public totalSpent;                 // lifetime amount paid out by the board

    // ------------------------------------------------------------------
    // ✅ NEW — spending rules (assembly-governed limits the board must operate within)
    // ------------------------------------------------------------------

    /// @notice Ceiling for any single board-approved payment. Any payment at or above this is
    ///         rejected outright — there is deliberately NO alternate path for a larger payment
    ///         (see the contract-level doc comment: the old "full validator vote for any amount"
    ///         escape hatch was removed on purpose). The only way to make a larger payment is to
    ///         first raise this cap via proposeCapChange() below, wait out
    ///         CAP_CHANGE_TIMELOCK_DELAY, and then spend under the new cap through the normal
    ///         path — never in the same transaction or vote as the cap change itself.
    /// @dev ✅ FINAL DECISION (P06): initial value 50,000 Suren (native, in wei). Chosen from the 25% ratio to periodCap;
    ///      that ratio is NOT enforced by code (deliberately — no automatic, permanent link between the two caps).
    ///      Because genesis injects runtime code, this initializer does NOT run on the real chain — the genesis tool must
    ///      overlay this slot (see the genesis-builder spec).
    uint256 public perPaymentCap = 50_000 ether;

    /// @notice Ceiling on the SUM of every board-approved payment within roughly the trailing 30
    ///         days — a day-bucketed approximation (see dailySpend below), not an exact
    ///         to-the-second sliding window. ⚠️ HONEST CORRECTION (found in independent review —
    ///         an earlier version of this comment overclaimed precision): because `_currentDay()`
    ///         buckets by calendar day (`block.timestamp / 1 days`, i.e., UTC day boundaries),
    ///         a payment can age out of the 30-bucket sum up to ~24 hours earlier or later than
    ///         an exact 30×24-hour window would, depending on what time of day within its bucket
    ///         it was made. This is still meaningfully better than a naive periodic reset (which
    ///         has a single, predictable, exploitable boundary every 30 days) — the day-bucket
    ///         slop is small, bounded, and does not repeat at a fixed exploitable point — but it
    ///         should not be described as a precise rolling window. If exact-second precision is
    ///         ever required, the algorithm here would need to change (e.g., a timestamped log
    ///         summed and pruned per payment, at meaningfully higher gas cost). Every payment
    ///         counts toward this same shared total regardless of its destination or description
    ///         — splitting one large payment into several smaller ones, or sending to different
    ///         recipients, does not create separate budgets.
    /// @dev ✅ FINAL DECISION (P06): initial value 200,000 Suren (native, in wei) for the ~30-day window. Genesis must
    ///      overlay this slot too (initializers do not run on injection).
    uint256 public periodCap = 200_000 ether;

    /// @notice How long an assembly-approved change to perPaymentCap or periodCap must wait before taking effect —
    ///         deliberately separate from the vote itself, so a cap increase and a payment under the new, larger cap can
    ///         never happen in the same moment. ✅ FINAL DECISION (P06): 7 days. This delay applies ONLY to changes of the
    ///         caps — ordinary payments approved by the board are NOT delayed.
    uint256 public constant CAP_CHANGE_TIMELOCK_DELAY = 7 days;

    /// @notice Number of daily buckets summed for the rolling-window check — fixed at 30 to
    ///         match "30 days" exactly; each check sums exactly this many storage reads, a
    ///         small, constant, predictable gas cost (not unbounded, not dependent on how many
    ///         payments have ever been made).
    uint256 public constant ROLLING_WINDOW_DAYS = 30;

    /// @notice Total board-approved spend recorded for a given day index (block.timestamp / 1
    ///         days). Used only to compute the rolling 30-day sum in
    ///         _rollingWindowSpend() below — never read or written any other way.
    mapping(uint256 => uint256) public dailySpend;

    enum CapKind { PerPayment, Period }

    /// @dev ✅ FIXED (same stale-vote class as every other proposal struct in this project):
    ///      requiredVotes/expiresAt are snapshotted at creation, never recomputed live.
    struct CapChangeProposal {
        CapKind kind;
        uint256 newValue;
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed; // true once the ASSEMBLY VOTE passed — separate from whether the
        // timelock has elapsed and the new value has actually taken effect (see
        // pendingCapChange below and applyPendingCapChange()).
    }

    uint256 public constant TREASURY_PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => CapChangeProposal) public capChangeProposals;
    mapping(uint256 => mapping(address => bool)) private capChangeHasVoted;
    uint256 public capChangeProposalCount;

    /// @notice The single pending cap change awaiting its timelock, per cap kind — a second
    ///         proposal of the SAME kind passing while one is already pending simply replaces
    ///         it (with a freshly-started timelock), rather than queueing multiple changes.
    struct PendingCapChange {
        uint256 newValue;
        uint256 effectiveAt;
        bool exists;
    }

    mapping(uint256 => PendingCapChange) public pendingCapChange; // keyed by uint256(CapKind)

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event RewardsReceived(address indexed from, uint256 amount);
    event BoardExpenditureExecuted(address indexed to, uint256 amount, string description);
    event CapChangeProposed(uint256 indexed id, CapKind kind, uint256 newValue, address indexed proposer);
    event CapChangeVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event CapChangeQueued(CapKind kind, uint256 newValue, uint256 effectiveAt);
    event CapChangeApplied(CapKind kind, uint256 oldValue, uint256 newValue);

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
    // 🔶 GENESIS FILL-IN — this contract has no constructor because it is injected directly
    // into the genesis `alloc` (its constructor would never execute on the real chain). See
    // "sur-contracts-deploy-notes.md" for the full simulate-and-extract recipe.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Automatic receipt of native Suren
    // ------------------------------------------------------------------
    receive() external payable {
        totalDistributedToTreasury += msg.value;
        emit RewardsReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // ✅ THE ONLY spending path — board-only, bounded by assembly-set rules
    // ------------------------------------------------------------------

    function _currentDay() private view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice Sums exactly ROLLING_WINDOW_DAYS daily buckets ending today — a day-granularity
    ///         approximation of a trailing 30-day window (see periodCap's doc comment above for
    ///         the honest precision caveat), not an exact-to-the-second sliding window. Still
    ///         meaningfully better than a naive periodic reset: there is no single, fixed,
    ///         repeatedly-exploitable boundary every 30 days the way a simple reset would have.
    function _rollingWindowSpend() private view returns (uint256 total) {
        uint256 today = _currentDay();
        for (uint256 i = 0; i < ROLLING_WINDOW_DAYS; i++) {
            total += dailySpend[today - i];
        }
    }

    /// @notice View so the board (or anyone) can check remaining rolling-window headroom before
    ///         proposing a payment.
    function rollingWindowSpendNow() external view returns (uint256) {
        return _rollingWindowSpend();
    }

    /// @notice Called only by ValidatorsBoard, only after its own internal board majority
    ///         (minimum 3 votes, hard-floored regardless of current board size — see
    ///         ValidatorsBoard.sol's proposeApproveBudget doc comment) has approved the request.
    ///         ✅ NO alternate path exists for a payment at or above perPaymentCap — it simply
    ///         reverts. This is deliberate: raising the cap (assembly vote + timelock) is the
    ///         only way to make a larger payment possible, and never in the same moment as
    ///         spending under it.
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external onlyBoard nonReentrant {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0 && amount < perPaymentCap, "ValidatorsTreasury: amount outside per-payment cap");
        require(amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");
        require(_rollingWindowSpend() + amount <= periodCap, "ValidatorsTreasury: 30-day period cap exceeded");

        dailySpend[_currentDay()] += amount; // counts toward the shared rolling total regardless
        // of `to` or `description` — splitting into multiple smaller payments or different
        // recipients does not create separate budgets (see periodCap's doc comment).
        totalSpent += amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit BoardExpenditureExecuted(to, amount, description);
    }

    // ------------------------------------------------------------------
    // ✅ Rule governance — full active-validator assembly vote, cap changes ONLY (never an
    // individual payment). Sets the rules the board must spend within; does not itself spend.
    // ------------------------------------------------------------------

    /// @notice Propose changing perPaymentCap or periodCap. Passing the vote does NOT take
    ///         effect immediately — it queues the change behind CAP_CHANGE_TIMELOCK_DELAY (see
    ///         applyPendingCapChange() below), so a cap increase can never be exploited for an
    ///         immediate larger payment.
    function proposeCapChange(CapKind kind, uint256 newValue) external onlyActiveValidator returns (uint256 id) {
        capChangeProposalCount++;
        id = capChangeProposalCount;
        capChangeProposals[id] = CapChangeProposal({
            kind: kind,
            newValue: newValue,
            votes: 0,
            requiredVotes: (REGISTRY.getValidators().length / 2) + 1, // frozen now
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

    /// @notice Permissionless — applies a queued cap change once its timelock has elapsed.
    ///         Separate from the vote itself (same "decision now, effect later" pattern used for
    ///         ValidatorsRegistry's economic-parameter timer elsewhere in this project) so the
    ///         moment a larger cap becomes spendable is always at least CAP_CHANGE_TIMELOCK_DELAY
    ///         away from the vote that approved it — never the same transaction, never the same
    ///         block.
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
    // View helpers
    // ------------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
