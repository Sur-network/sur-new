// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
    function statusNonce() external view returns (uint256); // L04
    function wasActiveAt(address who, uint256 nonce) external view returns (bool); // L04
    function everActivated(address who) external view returns (bool); // ✅ FINAL DECISION — see ValidatorsRegistry.sol doc comment
    function getActiveValidatorCount() external view returns (uint256); // ✅ NEW: needed for the 2/3-of-assembly threshold in the bicameral share-change vote below.
}

/// @notice ✅ NEW: minimal interface onto ValidatorsBoard, needed only to check board
///         membership for the bicameral share-change vote below (see proposeShareChange).
interface IValidatorsBoard {
    function isBoardMember(address who) external view returns (bool);
    /// @dev L02 (audit 2026-09-30): LIVE authority — false immediately after requestExit(), even while the raw seat flag
    ///      isBoardMember is still true until syncBoard(). A suspended (Demoted) member keeps authority until the monthly
    ///      point (P02). The Distributor relies on this exact definition instead of re-implementing it.
    function hasBoardAuthority(address who) external view returns (bool);
    /// @dev L02: incremented by ValidatorsBoard ONLY on a real composition change (refresh/sync/succession), never by a
    ///      refresh that leaves the composition unchanged.
    function boardVersion() external view returns (uint256);
}

/// @title BlockRewardDistributor
/// @notice Deployed at the fixed genesis address SurAddresses.BLOCK_REWARD_DISTRIBUTOR
///         (0x2222...2222) — this is the address that must be set as `qbft.miningbeneficiary`
///         in genesis.json. Automatically receives block rewards and transaction fees from the
///         network at the protocol level (verified experimentally to be a plain state-trie
///         balance credit with no EVM call, no event; see "Besu QBFT experiment findings",
///         Experiment 1) and periodically distributes them, based on data reported by an
///         authorized oracle, between validators and ValidatorsTreasury.
///
///         Distribution rules (✅ updated again — see sur-tokenomics.md section 6.5/6/11 for
///         the full economic and governance reasoning behind each piece below):
///           - From total REWARDS: FoundationDAO's 15% (FOUNDATION_SHARE_BPS) is now taken
///             DIRECTLY off the top of total rewards — fixed forever, automatic, no vote, and
///             deliberately NOT computed as a percentage of anything else (earlier drafts of
///             this contract computed it as 15% of a 50% "treasury cut," which meant Foundation
///             income would have silently moved whenever the treasury/validator split below was
///             later made governable — exactly the entanglement the fixed-15%-of-total design
///             avoids).
///           - Of the REMAINING 85%, the split between validators (direct, block-share-based)
///             and ValidatorsTreasury is governed by `validatorDirectShareBps` — ✅ NEW:
///             changeable via a bicameral vote (see proposeShareChange/boardVoteShareChange/
///             validatorVoteShareChange below), bounded to [40%, 65%] of TOTAL rewards, with a
///             mandatory 6-month cooldown between successful changes. Both chambers — a simple
///             majority of ValidatorsBoard AND a two-thirds majority of the full active
///             validator assembly — must independently approve the same proposal before it
///             takes effect. This deliberately uses the two chambers' opposing incentives (rank-
///             and-file validators are pulled toward a bigger direct share; the board is pulled
///             toward a bigger treasury, since a bigger treasury means more discretionary
///             spending under its own small-expenditure approval power) as a built-in check
///             against either chamber unilaterally draining the other's share over time.
///           - From total ORDINARY FEES (not membership fees — see below): ✅ NEW — a fixed
///             30% (FEE_BURN_BPS) is now permanently burned (sent to BURN_ADDRESS =
///             address(0)) every epoch; the remaining 70% is split among validators
///             proportionally to blocks mined exactly as before (still no treasury or
///             foundation cut on the distributed portion). See FEE_BURN_BPS's own doc comment
///             and sur-tokenomics.md section 7 for why fees (not rewards) were chosen as the
///             burn target, and why 30% specifically.
///           - PENDING MEMBERSHIP FEES: ValidatorsRegistry.requestMembership() no longer sends
///             the membership fee to ValidatorsTreasury. Instead it forwards it here via
///             receiveMembershipFee(), where it accumulates in `pendingMembershipFees` and is
///             folded into the *next* epoch's fee pool — ✅ UPDATED: fully exempt from the 30%
///             burn above (100% of it reaches validators, unlike ordinary fees), but otherwise
///             the same 100%-pro-rata-by-blocks treatment as ordinary transaction fees — see
///             sur-tokenomics.md section 6 for why: this gives existing validators a direct,
///             traceable cash incentive tied to every new validator that joins). This means a
///             new member's fee is not paid out in the same
///             block as their registration — it is paid out at the next distributionOracle
///             epoch (~23 hours later), exactly like ordinary fees already are.
///           - Each validator receives exactly one payment per call (a single combined
///             transfer of reward share + fee share, where "fee share" now includes any
///             pending membership fees folded in for that epoch).
///
///         Validator eligibility is checked directly, on-chain, against ValidatorsRegistry —
///         there is no internal whitelist and no second "validatorSyncOracle" (that design was
///         retired once contract-mode validator selection made ValidatorsRegistry itself the
///         single source of truth for both consensus and payment; see design doc section 5).
///
///         GENESIS DEPLOYMENT: this contract has no constructor — it is injected directly into
///         the genesis `alloc`, so a constructor would never execute on the real chain.
///         ValidatorsRegistry, ValidatorsTreasury, and ValidatorsBoard addresses are fixed
///         constants (see SurAddresses.sol), because all six structural contracts share a
///         common, pre-agreed genesis address map. The initial distributionOracle key (a
///         genuinely rotatable operational credential, not a structural contract) and the real
///         genesis timestamp are instead seeded via the off-chain genesis-building tool (see the
///         🔶 GENESIS FILL-IN notes below, and "sur-contracts-deploy-notes.md" for why the real
///         genesis timestamp can't just be read as `block.timestamp` from a simulated
///         environment).
contract BlockRewardDistributor {
    // ------------------------------------------------------------------
    // Constants and configuration
    // ------------------------------------------------------------------

    /// @notice Foundation's share of TOTAL rewards (not of any sub-cut) — basis points out of
    ///         10000 = 100%. ✅ CHANGED: fixed forever, applied directly to totalRewards, and
    ///         deliberately independent of validatorDirectShareBps below — see sur-tokenomics.md
    ///         section 6.5 and the contract-level doc comment above for why this must stay
    ///         decoupled from the governable treasury/validator split.
    uint256 public constant FOUNDATION_SHARE_BPS = 1500; // 15% of total rewards, always

    /// @notice ✅ NEW (replaces the old constant TREASURY_SHARE_BPS): validators' direct,
    ///         block-share-based cut of TOTAL rewards — basis points out of 10000. Starts at the
    ///         same 50% the old fixed constant used, but is now a governable STATE variable,
    ///         changeable only via the bicameral vote below (proposeShareChange /
    ///         boardVoteShareChange / validatorVoteShareChange), bounded to
    ///         [VALIDATOR_SHARE_MIN_BPS, VALIDATOR_SHARE_MAX_BPS]. ValidatorsTreasury receives
    ///         whatever remains after Foundation's fixed 15% and this share are both taken out:
    ///         treasuryShare = 10000 - FOUNDATION_SHARE_BPS - validatorDirectShareBps.
    uint256 public validatorDirectShareBps = 5000; // 50% initially — same starting point as before

    uint256 public constant VALIDATOR_SHARE_MIN_BPS = 4000; // 40% floor
    uint256 public constant VALIDATOR_SHARE_MAX_BPS = 6500; // 65% ceiling
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice ✅ NEW: fixed fraction of ordinary transaction fees (NOT membership fees — see
    /// distributeRewards()'s comment for why they are deliberately exempt) that is permanently
    /// burned every epoch, before the remaining 70% is distributed 100%-pro-rata-by-blocks to
    /// validators exactly as before. See sur-tokenomics.md section 7 for the full reasoning:
    /// rewards (not fees) are the dominant source of Suren inflation, so burning fees alone
    /// cannot offset it, but it creates a usage-linked scarcity mechanism that grows in effect
    /// as real network activity grows — the closest analogue this project's fixed-gasPrice
    /// design allows to Ethereum's EIP-1559 base-fee burn, without adopting a dynamic gas price
    /// (which would break the "predictable Suren-denominated cost" design goal).
    uint256 public constant FEE_BURN_BPS = 3000; // 30%

    /// @notice Burning native Suren means sending it to the zero address — no private key
    ///         exists for it, so any value sent here is permanently and verifiably
    ///         irrecoverable. A plain value transfer to address(0) succeeds on Besu/EVM exactly
    ///         like a transfer to any other externally-owned account.
    address public constant BURN_ADDRESS = address(0);

    /// @notice Cumulative Suren burned from fees since deployment — for off-chain dashboards
    ///         and audits (mirrors totalDistributedToValidators/Treasury/Foundation below).
    uint256 public totalFeesBurned;

    /// @notice Minimum allowed interval between two consecutive distribution calls.
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 23 hours;

    // L03 (audit 2026-09-30): MIN_BLOCK_PERIOD_SECONDS and the time-based "physical maximum" check were REMOVED — see
    // the design note above _settleRange. The block count is bounded by the P05 range control, not by elapsed time.

    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — receives whatever remains of the reward pool after
    ///         Foundation's fixed 15% and validators' governable direct share are both
    ///         removed (no longer a fixed "50% reward cut" — see validatorDirectShareBps).
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice FoundationDAO — receives the automatic 15% share of TOTAL rewards every epoch
    ///         (FOUNDATION_SHARE_BPS, taken directly off the top — see the header comment above
    ///         for why this is deliberately not computed as a percentage of the treasury cut).
    ///         This is the only inbound connection FoundationDAO has to the reward flow; it
    ///         never needs to call anything to receive it (see FoundationDAO.sol comments).
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @notice ValidatorsRegistry is also the only address allowed to forward pending
    ///         membership fees via receiveMembershipFee() below.
    address public constant REGISTRY_ADDRESS = SurAddresses.VALIDATORS_REGISTRY;

    /// @notice ValidatorsBoard — the only address allowed to rotate distributionOracle (a
    ///         delegated power explicitly granted to the board; see design doc section 4).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    /// @notice ValidatorsRegistry — single source of truth for validator eligibility, checked
    ///         directly on every payout, no intermediary oracle.
    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice ✅ NEW: read-only view onto ValidatorsBoard, used only to check board membership
    ///         for the bicameral share-change vote below.
    IValidatorsBoard public constant BOARD_CONTRACT = IValidatorsBoard(SurAddresses.VALIDATORS_BOARD);

    /// @notice Mirrors ValidatorsBoard.BOARD_SIZE — the board is always exactly this many
    ///         members, so a simple majority is BOARD_SIZE/2 + 1 (i.e. 3 of 5).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice ✅ NEW: minimum time between two successful validatorDirectShareBps changes —
    ///         deliberately slow (~6 months) so this parameter cannot be nudged repeatedly in
    ///         quick succession by either chamber. See sur-tokenomics.md section 11 for why.
    uint256 public constant SHARE_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastShareChangeTime;

    /// @notice Address of the oracle authorized to call the periodic distribution function.
    ///         Its only job is to report block counts and reward/fee totals; it cannot pay out
    ///         to any address that ValidatorsRegistry does not currently recognize as active.
    /// @dev ✅ FILLED: initial distributionOracle address, read from SurAddresses.sol (single
    ///      source of truth for all four oracle addresses — see that file for rationale).
    address public distributionOracle = SurAddresses.DISTRIBUTION_ORACLE;

    // L03 (audit 2026-09-30): the immutable `deployTime` was REMOVED together with the time-based cap — no code read it
    // except that cap. This contract therefore has no immutable left for the genesis builder to patch.
    uint256 public lastDistributionTime;
    uint256 public epochCount;

    // ------------------------------------------------------------------
    // P05 (final decision): every distribution declares the REAL block range it settles; the contract keeps the last settled
    // block and accepts only a range that starts exactly after it. An increasing epoch counter alone is not enough — the
    // control is tied to the actual block numbers, so duplicate, overlapping and unexplained-gap ranges are rejected.
    // ------------------------------------------------------------------
    struct BlockRange {
        uint256 fromBlock;
        uint256 toBlock;
    }
    /// @notice Highest block number already settled by a distribution (0 = only genesis; the first range must start at block 1).
    uint256 public lastSettledBlock;
    /// @notice The block range each epoch settled.
    mapping(uint256 => BlockRange) public epochBlockRanges;
    event EpochRangeSettled(uint256 indexed epochId, uint256 fromBlock, uint256 toBlock);

    bool private locked; // simple reentrancy guard

    // ------------------------------------------------------------------
    // 🔶 GENESIS FILL-IN — this contract has no constructor because it is injected directly
    // into the genesis `alloc` (its constructor would never execute on the real chain). The
    // off-chain genesis-building tool must simulate this contract's deployment (with the two
    // real values above filled in, on a temporary local chain) and copy the resulting
    // code + storage into the final genesis file. See "sur-contracts-deploy-notes.md" for the
    // full recipe.
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Epoch reporting structure
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

    /// @notice Membership fees forwarded by ValidatorsRegistry since the last distribution
    ///         epoch, waiting to be folded into that epoch's 100%-pro-rata-by-blocks fee pool.
    ///         Reset to zero at the end of every distributeRewards() call.
    uint256 public pendingMembershipFees;

    /// @notice ✅ NEW: a bicameral proposal to change validatorDirectShareBps. Requires
    ///         independent approval from BOTH a simple majority of ValidatorsBoard AND a
    ///         two-thirds majority of the full active validator assembly before it applies —
    ///         see proposeShareChange/boardVoteShareChange/validatorVoteShareChange below.
    /// @dev ✅ FIXED (critical stale-vote bug found in review): `requiredValidatorApprovals` is
    ///      now snapshotted ONCE at proposal creation (from the active-validator count at that
    ///      moment), not recomputed live on every vote. Previously, `validatorApprovals` was a
    ///      simple counter that only ever increased (never decremented when a voting validator
    ///      later exited), while `required` was recalculated from the CURRENT active count on
    ///      every call. This meant a proposal that failed to reach quorum at a large validator
    ///      count could later become executable with ZERO new votes, purely because the
    ///      network's active count shrank enough that the live-recomputed threshold fell below
    ///      the old, frozen vote tally — a classic stale/replay governance bug. Snapshotting the
    ///      requirement at creation time closes this: the bar a given proposal must clear is
    ///      fixed the moment it's proposed, exactly like a share price is fixed the moment an
    ///      order is placed. Combined with `expiresAt` below (also new), a proposal that doesn't
    ///      reach ITS OWN frozen bar within a bounded window simply dies, rather than being able
    ///      to sit indefinitely waiting for the electorate to shrink.
    struct ShareProposal {
        uint256 newValidatorShareBps;
        uint256 createdAt;
        uint256 expiresAt; // ✅ NEW — proposal can no longer be voted on or executed after this
        uint256 requiredValidatorApprovals; // ✅ NEW — snapshotted at creation, never recomputed
        uint256 boardApprovals;
        uint256 validatorApprovals;
        bool boardPassed;
        bool validatorPassed;
        bool executed;
        /// @dev L02 (audit 2026-09-30): ValidatorsBoard.boardVersion() when the proposal was created. Board votes and the
        ///      final execution are accepted only while the board composition is still this one — the same rule
        ///      ValidatorsBoard applies to its own actions (boardVersionAtCreation). A real composition change voids the
        ///      proposal; it must be proposed again. Appended as the LAST field: mapping-value layout, fresh genesis state.
        uint256 boardVersionAtCreation;
        // L04 (owner decision): ValidatorsRegistry.statusNonce at creation; voters must have been Active at exactly that point.
        uint256 validatorNonceAtCreation;
    }

    /// @notice ✅ NEW: how long a proposal remains votable/executable after creation. Chosen to
    ///         be comfortably shorter than SHARE_CHANGE_MIN_INTERVAL (180 days) — a proposal
    ///         that can't gather the required votes within 30 days should be re-proposed fresh
    ///         (with a fresh electorate snapshot) rather than left open indefinitely.
    uint256 public constant PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ShareProposal) public shareProposals;
    mapping(uint256 => mapping(address => bool)) private shareBoardVoted;
    mapping(uint256 => mapping(address => bool)) private shareValidatorVoted;
    uint256 public shareProposalCount;

    // L05 (owner decision, audit 2026-09-30): approved block-reward rate history, used to cap totalRewards per settled range.
    // Initial rate INITIAL_REWARD_PER_BLOCK applies from block 1 until the first entry. Entries are append-only, with strictly
    // ascending startBlock, and take effect only from a FUTURE height; past effective history is never rewritten.
    // TRUST BOUNDARY: this contract does not read Besu's actual block reward. The approved rates must be kept in line with the
    // network's genesis transitions operationally; the cap does not prove fee correctness, block attribution, or that the
    // recorded rate equals Besu's. It only bounds the gross reward the oracle can report for a range.
    // Governance (implemented below): proposals need 3 of the 5 board members (live authority + board-composition guard, as in L02)
    // AND two thirds of the validators eligible when the proposal was created (L04 policy). The 30-day voting expiry applies to the
    // voting phase only; once both chambers have completed, a 7-day delay starts, and execution re-checks everything (see
    // executeRateChange). The distribution oracle has no power over this history.
    uint256 public constant INITIAL_REWARD_PER_BLOCK = 2 ether;
    struct RewardRateChange {
        uint128 startBlock; // first block at which ratePerBlock applies
        uint128 ratePerBlock; // wei per block
    }
    RewardRateChange[] private rewardRateChanges;

    // ------------------------------------------------------------------
    // L05 governance — approved reward-rate changes (owner decision, audit 2026-09-30)
    // ------------------------------------------------------------------
    /// @notice Board approvals needed: 3 of the 5-member board (== BOARD_SIZE / 2 + 1).
    uint256 public constant RATE_CHANGE_BOARD_APPROVALS = 3;
    /// @notice Voting phase only. An approved proposal waiting for its delay/execution is NOT removed by this expiry.
    uint256 public constant RATE_VOTING_EXPIRY = 30 days;
    /// @notice Starts when BOTH chambers have completed.
    uint256 public constant RATE_CHANGE_DELAY = 7 days;
    /// @notice Minimum distance, in BLOCKS, between the block that executes the change and its startBlock. Roughly 7 days only at the
    ///         nominal 3 s cadence; it is a block count, not a time, and is independent of RATE_CHANGE_DELAY.
    uint256 public constant MIN_RATE_CHANGE_LEAD_BLOCKS = 201_600;

    struct RateProposal {
        uint128 startBlock;
        uint128 ratePerBlock;
        uint256 createdAt;
        uint256 votingExpiresAt;
        uint256 requiredValidatorApprovals; // ceil(2/3) of the validators active at creation, frozen
        uint256 boardApprovals;
        uint256 validatorApprovals;
        uint256 approvedAt; // 0 until both chambers have completed
        bool executed;
        uint256 boardVersionAtCreation; // L02 guard: a real change of board composition voids the proposal
        uint256 validatorNonceAtCreation; // L04 snapshot of the validator electorate
    }
    mapping(uint256 => RateProposal) public rateProposals;
    mapping(uint256 => mapping(address => bool)) private rateBoardVoted;
    mapping(uint256 => mapping(address => bool)) private rateValidatorVoted;
    uint256 public rateProposalCount;

    event RateChangeProposed(uint256 indexed id, uint256 startBlock, uint256 ratePerBlock, address indexed proposer);
    event RateChangeBoardVoted(uint256 indexed id, address indexed boardMember, uint256 approvals, uint256 required);
    event RateChangeValidatorVoted(uint256 indexed id, address indexed validator, uint256 approvals, uint256 required);
    event RateChangeApproved(uint256 indexed id, uint256 approvedAt, uint256 executableAt);
    event RateChangeExecuted(uint256 indexed id, uint256 startBlock, uint256 ratePerBlock);

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
    // Oracle key rotation — board only (delegated power, see ValidatorsBoard)
    // ------------------------------------------------------------------
    function setDistributionOracle(address newOracle) external onlyBoard {
        require(newOracle != address(0), "BlockRewardDistributor: zero distribution oracle address");
        emit DistributionOracleUpdated(distributionOracle, newOracle);
        distributionOracle = newOracle;
    }

    // ------------------------------------------------------------------
    // Automatic receipt of block rewards and fees
    // ------------------------------------------------------------------
    /// @notice Any plain ETH transfer to this contract (protocol-level block reward/fee) is
    ///         received here. Note: as confirmed experimentally, the protocol-level
    ///         miningbeneficiary credit does NOT actually invoke this function — it is a direct
    ///         state-trie balance write. This receive() only fires for ordinary transfers, e.g.
    ///         manual top-ups or testing.
    receive() external payable {
        emit RewardsReceived(msg.sender, msg.value);
    }

    /// @notice Called by ValidatorsRegistry.requestMembership() to forward a new validator's
    ///         membership fee here instead of straight to ValidatorsTreasury (the old
    ///         behavior). The amount simply accumulates until the next distributeRewards()
    ///         call, at which point it is folded into that epoch's fee pool and paid out
    ///         100%-pro-rata-by-blocks, exactly like ordinary transaction fees — see
    ///         sur-tokenomics.md section 6 for why this design (a direct, traceable, per-join
    ///         cash incentive for existing validators) was chosen over an immediate on-the-spot
    ///         payout, which would have required an unbounded loop over all active validators
    ///         inside requestMembership() itself — a real gas-limit / DoS risk as the validator
    ///         set grows, and duplicate logic already implemented correctly here.
    function receiveMembershipFee() external payable {
        require(msg.sender == REGISTRY_ADDRESS, "BlockRewardDistributor: only ValidatorsRegistry may forward membership fees");
        pendingMembershipFees += msg.value;
        emit MembershipFeeReceived(msg.value, pendingMembershipFees);
    }

    // ------------------------------------------------------------------
    // ✅ NEW: bicameral governance for validatorDirectShareBps (the validator-vs-treasury
    // split — see the contract-level doc comment and sur-tokenomics.md section 11 for the full
    // reasoning). Any active validator may propose; a simple majority of ValidatorsBoard AND a
    // two-thirds majority of the full active validator assembly must BOTH independently approve
    // the exact same proposal before it takes effect — whichever chamber's threshold is reached
    // second is what actually triggers execution, via _tryExecuteShareChange.
    // ------------------------------------------------------------------

    /// @notice Starts a new proposal. Any active validator may call this — deliberately not
    ///         restricted to board members, since rank-and-file validators are one of the two
    ///         chambers whose approval is required.
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
            requiredValidatorApprovals: (activeCountAtProposal * 2 + 2) / 3, // ceil(2/3), frozen now
            boardApprovals: 0,
            validatorApprovals: 0,
            boardPassed: false,
            validatorPassed: false,
            executed: false,
            boardVersionAtCreation: BOARD_CONTRACT.boardVersion(),
            validatorNonceAtCreation: REGISTRY.statusNonce()
        });
        emit ShareChangeProposed(id, newValidatorShareBps, msg.sender);
    }

    /// @notice One of the two required votes — the ValidatorsBoard chamber. Simple majority of
    ///         the fixed BOARD_SIZE (5), i.e. 3 votes.
    function boardVoteShareChange(uint256 id) external {
        // L02 (audit 2026-09-30): live authority, not the raw seat flag — a member who requested exit loses the right to
        // vote immediately (P02), even before syncBoard() clears the seat.
        require(BOARD_CONTRACT.hasBoardAuthority(msg.sender), "BlockRewardDistributor: caller has no live board authority");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareBoardVoted[id][msg.sender], "BlockRewardDistributor: board member already voted");

        shareBoardVoted[id][msg.sender] = true;
        p.boardApprovals++;
        uint256 required = (BOARD_SIZE / 2) + 1; // 3 of 5 — BOARD_SIZE is a fixed constant, so
        // unlike the validator-side threshold, this needs no snapshotting: it can never drift.
        emit ShareChangeBoardVoted(id, msg.sender, p.boardApprovals, required);

        if (p.boardApprovals >= required) {
            p.boardPassed = true;
        }
        _tryExecuteShareChange(id);
    }

    /// @notice The other required vote — the full validator assembly chamber. ✅ FIXED: now
    ///         checked against `requiredValidatorApprovals`, snapshotted once at proposal
    ///         creation — see the ShareProposal struct's doc comment for why recomputing this
    ///         live (the previous behavior) was a stale-vote vulnerability.
    function validatorVoteShareChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");
        // L04: the voter must have been Active when the proposal was created (electorate snapshot) AND be Active now (onlyActiveValidator).
        // A temporary suspension does not remove the voter from the original electorate; it only blocks voting while suspended.
        require(REGISTRY.wasActiveAt(msg.sender, p.validatorNonceAtCreation), "BlockRewardDistributor: not eligible - not Active when this proposal was created");

        shareValidatorVoted[id][msg.sender] = true;
        p.validatorApprovals++;
        emit ShareChangeValidatorVoted(id, msg.sender, p.validatorApprovals, p.requiredValidatorApprovals);

        if (p.validatorApprovals >= p.requiredValidatorApprovals) {
            p.validatorPassed = true;
        }
        _tryExecuteShareChange(id);
    }

    /// @dev Applies the change only once BOTH chambers have independently passed the same
    ///      proposal. Called from both vote functions after each new vote, so whichever chamber
    ///      crosses its threshold second is what actually triggers this.
    function _tryExecuteShareChange(uint256 id) private {
        ShareProposal storage p = shareProposals[id];
        if (p.boardPassed && p.validatorPassed && !p.executed) {
            // L02: a board chamber that passed under an older composition cannot be completed later by the validator
            // chamber — the composition is checked again at execution, not only at the board vote.
            require(
                p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
                "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
            );
            // L01 (audit 2026-09-30): the minimum interval between SUCCESSFUL changes is enforced here, where the change is
            // applied. Checking it only in proposeShareChange let two proposals built in the same open window both
            // execute seconds apart. The vote that would complete a too-early proposal reverts; since PROPOSAL_EXPIRY
            // (30 days) < SHARE_CHANGE_MIN_INTERVAL (180 days), such a proposal can never execute and simply expires.
            require(
                block.timestamp >= lastShareChangeTime + SHARE_CHANGE_MIN_INTERVAL,
                "BlockRewardDistributor: too soon since the last successful share change"
            );
            p.executed = true;
            validatorDirectShareBps = p.newValidatorShareBps;
            lastShareChangeTime = block.timestamp;
            emit ShareChangeApplied(id, p.newValidatorShareBps);
        }
    }

    // ------------------------------------------------------------------
    // Main periodic distribution function — callable only by the distribution oracle
    //
    // ✅ Refactored (no longer needs viaIR to compile): the original single large function had
    // too many simultaneously-live local variables for the EVM's 16-slot stack-manipulation
    // window under the legacy (non-IR) codegen pipeline — a real "Stack too deep" compiler
    // error, confirmed identical in both the English and Persian versions of this file. Rather
    // than requiring viaIR (which many verification services, including Blockscout, cannot
    // verify against — see sur-contracts-deploy-notes.md), the logic is split into three
    // functions, each with its own independent stack frame and therefore far fewer
    // simultaneously-live locals. Behavior, event order, and every require() condition are
    // unchanged from the original single-function version.
    // ------------------------------------------------------------------
    /// @param validators list of validator addresses (no duplicates)
    /// @param blocksMined number of blocks each validator mined since the last call (same order as validators)
    /// @param totalRewards total reward amount (in wei) for this epoch — computed off-chain by the oracle, from trace_block "reward" entries
    /// @param totalFees total transaction fee amount (in wei) for this epoch — computed off-chain by the oracle, from eth_getTransactionReceipt.gasUsed * effectiveGasPrice per tx (never from trace_* output, which reports gasUsed=0 for simple transfers)
    /// @notice P05: `range` is the inclusive block range this distribution settles. It must start exactly at
    ///         lastSettledBlock + 1 (no duplicate, no overlap, no gap — an outage is covered by the NEXT, larger range, never
    ///         skipped), must end before the current block, and the reported per-validator block counts (after the daemon's
    ///         filtering of blocks whose producer is no longer valid) cannot exceed its size.
    function distributeRewards(
        BlockRange calldata range,
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

        // ✅ FIXED (real bug found during live Besu/QBFT execution testing — this contradicted an
        // earlier, incorrect claim that this file already compiled clean without viaIR): the
        // pre-computation block that used to sit directly here (membership-fee folding, fee-burn
        // math, block-count sum check; the time-based physical-maximum check was removed by L03) hit a genuine "Stack too deep" compiler
        // error at the _payValidators call further down, under the optimizer — too many
        // simultaneously-live local variables in this function's own stack frame. Extracted into
        // _prepareEpoch() below, which bundles the 4 result values into ONE memory struct
        // (`prep`) instead of 4 separate live locals — this is what actually fixes the stack
        // depth, not merely reformatting. Not a viaIR workaround (this project deliberately
        // avoids viaIR) — same require()s, same order, same math, just computed inside a helper
        // instead of inline.
        EpochPrep memory prep = _prepareEpoch(blocksMined, totalRewards, totalFees);
        _settleRange(range, prep.totalBlocks); // P05
        // L05: totalRewards may not exceed the approved reward of the blocks in this (already validated, contiguous) range.
        // Fees and membership fees are outside this cap; split and burn rules are unchanged.
        require(totalRewards <= maxRewardsForRange(range.fromBlock, range.toBlock), "BlockRewardDistributor: totalRewards exceed approved reward for range");

        epochCount++;
        uint256 epochId = epochCount;
        epochBlockRanges[epochId] = range;
        emit EpochRangeSettled(epochId, range.fromBlock, range.toBlock);

        // ✅ FIXED (same stack-too-deep fix as above): foundationAmount/treasuryAmount are
        // computed AFTER the _payValidators call now, not before — they don't feed into that
        // call and _payValidators doesn't depend on them, so this reordering is fully
        // behavior-preserving. It exists purely to reduce how many locals are simultaneously
        // live at the _payValidators call site, not to change what gets computed or when its
        // effects become visible (both still happen within the same transaction, before
        // _finalizeEpoch below).
        // validatorDirectShareBps is governable (bicameral vote, [40%, 65%]) — see the
        // contract-level doc comment. ValidatorsTreasury receives whatever remains of the
        // reward pool after Foundation's fixed share and this governable share are both
        // removed.
        uint256 validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS_DENOMINATOR;

        (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) =
            _payValidators(
                validators,
                blocksMined,
                EpochContext({
                    epochId: epochId,
                    remainingRewards: validatorDirectAmount,
                    totalFees: prep.feesToDistribute,
                    totalBlocks: prep.totalBlocks
                })
            );

        // ✅ CHANGED: Foundation's cut is a fixed 15% of TOTAL rewards, taken independently off
        // the top — never affected by validatorDirectShareBps above. Only REWARDS are split this
        // way; FEES are never touched by any of these three shares.
        uint256 foundationAmount = (totalRewards * FOUNDATION_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 treasuryAmount = totalRewards - foundationAmount - validatorDirectAmount;

        _finalizeEpoch(
            epochId,
            totalRewards,
            prep.effectiveTotalFees,
            prep.feeBurnAmount,
            treasuryAmount,
            foundationAmount,
            prep.totalBlocks,
            validatorCount,
            distributedRewards,
            distributedFees
        );
    }

    /// @dev ✅ NEW (added purely to fix the "Stack too deep" error above distributeRewards —
    ///      bundles the pre-computation phase's 4 result scalars into one memory struct pointer
    ///      instead of 4 separate live stack locals).

    /// @notice Propose an approved-rate change effective from `startBlock`. Only an active validator may propose.
    ///         Early rejection only: every start-block condition is checked again at execution. Proposals are independent; several
    ///         may be open at once, and whichever is executed first can make another one unexecutable (it is then left as it is).
    function proposeRateChange(uint256 startBlock, uint256 ratePerBlock) external returns (uint256 id) {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: only an active validator may propose a rate change");
        require(startBlock <= type(uint128).max && ratePerBlock <= type(uint128).max, "BlockRewardDistributor: value does not fit uint128");
        _requireRateStartOk(startBlock);
        id = ++rateProposalCount;
        RateProposal storage p = rateProposals[id];
        p.startBlock = uint128(startBlock);
        p.ratePerBlock = uint128(ratePerBlock);
        p.createdAt = block.timestamp;
        p.votingExpiresAt = block.timestamp + RATE_VOTING_EXPIRY;
        p.requiredValidatorApprovals = (REGISTRY.getActiveValidatorCount() * 2 + 2) / 3; // ceil(2/3), frozen now
        p.boardVersionAtCreation = BOARD_CONTRACT.boardVersion();
        p.validatorNonceAtCreation = REGISTRY.statusNonce();
        emit RateChangeProposed(id, startBlock, ratePerBlock, msg.sender);
    }

    /// @notice Board chamber: needs live board authority; the proposal must still belong to the current board composition.
    function boardVoteRateChange(uint256 id) external {
        require(BOARD_CONTRACT.hasBoardAuthority(msg.sender), "BlockRewardDistributor: caller has no live board authority");
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        _requireRateVotable(p);
        require(!rateBoardVoted[id][msg.sender], "BlockRewardDistributor: board member already voted");
        rateBoardVoted[id][msg.sender] = true;
        p.boardApprovals++;
        emit RateChangeBoardVoted(id, msg.sender, p.boardApprovals, RATE_CHANGE_BOARD_APPROVALS);
        _markRateApprovedIfComplete(id, p);
    }

    /// @notice Validator chamber: eligible = Active when the proposal was created (L04) and Active now.
    function validatorVoteRateChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        _requireRateVotable(p);
        require(!rateValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");
        require(REGISTRY.wasActiveAt(msg.sender, p.validatorNonceAtCreation), "BlockRewardDistributor: not eligible - not Active when this proposal was created");
        rateValidatorVoted[id][msg.sender] = true;
        p.validatorApprovals++;
        emit RateChangeValidatorVoted(id, msg.sender, p.validatorApprovals, p.requiredValidatorApprovals);
        _markRateApprovedIfComplete(id, p);
    }

    /// @notice Anyone may execute once both chambers have completed and RATE_CHANGE_DELAY has passed since that moment.
    ///         Re-checks: board composition, start block still in the future, MIN_RATE_CHANGE_LEAD_BLOCKS, and strictly ascending
    ///         history. If any check fails the proposal stays exactly as it is: no time or height is ever moved automatically.
    function executeRateChange(uint256 id) external {
        RateProposal storage p = rateProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: rate proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(p.approvedAt != 0, "BlockRewardDistributor: not approved by both chambers");
        require(block.timestamp >= p.approvedAt + RATE_CHANGE_DELAY, "BlockRewardDistributor: execution delay has not elapsed");
        require(
            p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
            "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
        );
        _requireRateStartOk(p.startBlock);
        p.executed = true;
        rewardRateChanges.push(RewardRateChange({startBlock: p.startBlock, ratePerBlock: p.ratePerBlock}));
        emit RateChangeExecuted(id, p.startBlock, p.ratePerBlock);
    }

    /// @notice Status as of the latest block. status: 0 not found, 1 voting, 2 voting expired (never approved), 3 executed,
    ///         4 approved and waiting for the delay, 5 executable now, 6 approved but currently unexecutable.
    ///         problem (status 6): 1 board composition changed, 2 start block not in the future, 3 closer than
    ///         MIN_RATE_CHANGE_LEAD_BLOCKS, 4 not after the last approved change. Execution happens in a later block, so this is advisory.
    function rateChangeStatus(uint256 id) external view returns (uint8 status, uint8 problem) {
        RateProposal storage p = rateProposals[id];
        if (p.createdAt == 0) return (0, 0);
        if (p.executed) return (3, 0);
        if (p.approvedAt == 0) return (block.timestamp > p.votingExpiresAt ? 2 : 1, 0);
        problem = BOARD_CONTRACT.boardVersion() != p.boardVersionAtCreation ? 1 : _rateStartProblem(p.startBlock);
        if (problem != 0) return (6, problem);
        return (block.timestamp >= p.approvedAt + RATE_CHANGE_DELAY ? 5 : 4, 0);
    }

    function _requireRateVotable(RateProposal storage p) private view {
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(p.approvedAt == 0, "BlockRewardDistributor: voting closed - already approved by both chambers");
        require(block.timestamp <= p.votingExpiresAt, "BlockRewardDistributor: voting period has expired");
    }

    function _markRateApprovedIfComplete(uint256 id, RateProposal storage p) private {
        if (p.boardApprovals >= RATE_CHANGE_BOARD_APPROVALS && p.validatorApprovals >= p.requiredValidatorApprovals) {
            p.approvedAt = block.timestamp;
            emit RateChangeApproved(id, block.timestamp, block.timestamp + RATE_CHANGE_DELAY);
        }
    }

    function _rateStartProblem(uint256 startBlock) private view returns (uint8) {
        if (startBlock <= block.number) return 2;
        if (startBlock < block.number + MIN_RATE_CHANGE_LEAD_BLOCKS) return 3;
        uint256 n = rewardRateChanges.length;
        if (n > 0 && startBlock <= rewardRateChanges[n - 1].startBlock) return 4;
        return 0;
    }

    function _requireRateStartOk(uint256 startBlock) private view {
        uint8 r = _rateStartProblem(startBlock);
        require(r != 2, "BlockRewardDistributor: start block is not in the future");
        require(r != 3, "BlockRewardDistributor: start block is closer than MIN_RATE_CHANGE_LEAD_BLOCKS");
        require(r != 4, "BlockRewardDistributor: start block must be after the last approved rate change");
    }

    /// @dev Binary search: number of history entries whose startBlock <= blockNumber (history is strictly ascending).
    function _rateEntriesUpTo(uint256 blockNumber) private view returns (uint256 lo) {
        uint256 hi = rewardRateChanges.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (rewardRateChanges[mid].startBlock <= blockNumber) lo = mid + 1;
            else hi = mid;
        }
    }

    /// @notice L05: approved gross block reward for blocks [fromBlock, toBlock], summed segment by segment over the rate history.
    ///         Cost = O(log n) to find the rate at fromBlock + one step per rate change INSIDE the range; it depends neither on the
    ///         number of blocks nor on how many older changes the history holds.
    function maxRewardsForRange(uint256 fromBlock, uint256 toBlock) public view returns (uint256 total) {
        require(fromBlock <= toBlock, "BlockRewardDistributor: invalid range");
        uint256 n = rewardRateChanges.length;
        uint256 i = _rateEntriesUpTo(fromBlock);
        uint256 rate = i == 0 ? INITIAL_REWARD_PER_BLOCK : rewardRateChanges[i - 1].ratePerBlock;
        uint256 cursor = fromBlock;
        for (; i < n; i++) {
            RewardRateChange memory c = rewardRateChanges[i];
            if (c.startBlock > toBlock) break;
            total += (c.startBlock - cursor) * rate; // blocks cursor .. startBlock-1
            cursor = c.startBlock;
            rate = c.ratePerBlock;
        }
        total += (toBlock - cursor + 1) * rate;
    }

    /// @notice L05: approved reward per block at `blockNumber`.
    function rewardRateAt(uint256 blockNumber) external view returns (uint256) {
        uint256 i = _rateEntriesUpTo(blockNumber);
        return i == 0 ? INITIAL_REWARD_PER_BLOCK : rewardRateChanges[i - 1].ratePerBlock;
    }

    /// @notice L05: number of approved rate changes and one entry, for dashboards and audits.
    function rewardRateChangeCount() external view returns (uint256) {
        return rewardRateChanges.length;
    }

    function rewardRateChange(uint256 index) external view returns (uint256 startBlock, uint256 ratePerBlock) {
        RewardRateChange memory c = rewardRateChanges[index];
        return (c.startBlock, c.ratePerBlock);
    }

    /// @dev P05 range control (see the BlockRange comment). Kept in its own stack frame.
    ///
    ///      L03 DESIGN NOTE (audit 2026-09-30) — why there is no time-based cap any more.
    ///      The removed check required totalBlocks <= (block.timestamp - lastDistributionTime) / 3. Its two sides measure
    ///      different things: the block count belongs to the range after lastSettledBlock, while lastDistributionTime is
    ///      when the previous distribution TRANSACTION ran, which may have settled only up to an earlier block. Any
    ///      settlement behind head (normal oracle lag) or any block cadence faster than 3 s made correct payments revert,
    ///      and once one cycle reverted every later, longer range reverted too (reproduced: test_L03_settlement_backlog.js).
    ///      What bounds the count instead, entirely on-chain and exactly:
    ///        (1) continuity   fromBlock == lastSettledBlock + 1           -> no gap, no overlap, no duplicate range;
    ///        (2) past only    toBlock < block.number                      -> never settles the current or a future block;
    ///        (3) size         sum(blocksMined) <= toBlock - fromBlock + 1 -> never more blocks than really exist in it.
    ///      (3) is an upper bound, not an equality. Per the current decision (sur-reward-router-spec.md section 3), the sum
    ///      should NORMALLY equal the range length; a producer's later exit/suspension is never a reason to omit its blocks
    ///      (everActivated policy). NOTE: payouts divide by sum(blocksMined), not by the range length, so whether the
    ///      reward/fee of an omitted block stays in this contract or is redistributed to the listed producers depends only
    ///      on the totalRewards/totalFees the oracle reports — the contract enforces neither. Once lastSettledBlock moves
    ///      past an omitted block, there is no on-chain path to pay that block to its producer (open finding L08).
    ///      TRUST BOUNDARY — these checks do NOT prove attribution. The contract cannot read historical block headers or
    ///      historical Registry state, so the distribution oracle alone is trusted for: which address mined each block;
    ///      that the miner was Active at height N-1; the per-validator split; the totalRewards/totalFees split (bounded
    ///      here only by this contract's balance); and not listing an address twice. On-chain backstops are limited to:
    ///      the oracle key, the 23 h interval, the three range rules above, everActivated for every paid address, and
    ///      balance sufficiency. Misattribution among ever-activated addresses is detectable only off-chain, by replaying
    ///      the settled range from chain data (EpochRangeSettled gives the exact range to replay).
    function _settleRange(BlockRange calldata range, uint256 totalBlocks) private {
        require(range.fromBlock == lastSettledBlock + 1, "BlockRewardDistributor: range must start right after the last settled block");
        require(range.toBlock >= range.fromBlock, "BlockRewardDistributor: empty or inverted block range");
        require(range.toBlock < block.number, "BlockRewardDistributor: range includes blocks that are not yet produced");
        require(totalBlocks <= range.toBlock - range.fromBlock + 1, "BlockRewardDistributor: reported blocks exceed the range size");
        lastSettledBlock = range.toBlock;
    }

    struct EpochPrep {
        uint256 effectiveTotalFees;
        uint256 feeBurnAmount;
        uint256 feesToDistribute;
        uint256 totalBlocks;
    }

    /// @dev ✅ NEW helper extracted from distributeRewards()'s original inline body — same
    ///      require()s, same order, same math, just isolated into its own stack frame so that
    ///      distributeRewards() itself has fewer simultaneously-live locals at the
    ///      _payValidators call site. See the fix note on distributeRewards() above.
    function _prepareEpoch(uint256[] calldata blocksMined, uint256 totalRewards, uint256 totalFees)
        private
        returns (EpochPrep memory prep)
    {
        // Fold any membership fees forwarded by ValidatorsRegistry since the last epoch into
        // this epoch's fee pool — they are already sitting in this contract's balance (received
        // via receiveMembershipFee()), so they simply join ordinary fees and get the exact same
        // 100%-pro-rata-by-blocks treatment. See sur-tokenomics.md section 6.
        uint256 membershipFeesThisEpoch = pendingMembershipFees;
        pendingMembershipFees = 0;
        prep.effectiveTotalFees = totalFees + membershipFeesThisEpoch;

        require(totalRewards + prep.effectiveTotalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalRewards + prep.effectiveTotalFees <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        // ✅ NEW: burn a fixed 30% — but ONLY of ordinary transaction fees (totalFees),
        // deliberately NOT of membershipFeesThisEpoch. Rationale (see sur-tokenomics.md
        // section 6): the membership fee is not a general network fee at all — it is a
        // targeted, one-time dilution-compensation payment to existing validators, triggered
        // by a new validator's entry. Burning part of it would silently weaken that specific
        // incentive mechanism as an unintended side effect of a later, unrelated decision
        // (the general fee-burn). Ordinary fees have no such earmarked purpose, so they are
        // the correct — and only — burn target.
        prep.feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS_DENOMINATOR;
        prep.feesToDistribute = prep.effectiveTotalFees - prep.feeBurnAmount;

        prep.totalBlocks = _sumBlocks(blocksMined);
        require(prep.totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
    }

    /// @dev Sums the reported per-validator block counts. Split out of distributeRewards purely
    ///      to keep that function's own stack frame small (see the refactor note above) — no
    ///      behavior change from the original inline loop.
    function _sumBlocks(uint256[] calldata blocksMined) private pure returns (uint256 totalBlocks) {
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
    }

    /// @dev Bundles the four scalar inputs `_payValidators` needs into a single memory struct —
    ///      a struct is passed as one pointer (one stack slot) instead of four separate slots,
    ///      which is what let this function's own frame fit under the 16-slot limit (see the
    ///      refactor note above `distributeRewards`).
    struct EpochContext {
        uint256 epochId;
        uint256 remainingRewards;
        uint256 totalFees;
        uint256 totalBlocks;
    }

    /// @dev Pays every eligible validator a single combined (reward share + fee share) transfer,
    ///      by block ratio. Same behavior as the original inline loop body from
    ///      distributeRewards; the actual per-validator storage writes, transfer, and event now
    ///      live in `_payOneValidator` (its own stack frame) so that even this loop's own frame
    ///      stays small — no behavior, event, or ordering change.
    function _payValidators(
        address[] calldata validators,
        uint256[] calldata blocksMined,
        EpochContext memory ctx
    ) private returns (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) {
        for (uint256 i = 0; i < validators.length; i++) {
            // L07 (audit 2026-09-30, owner decision): addresses must be STRICTLY ascending. This rejects duplicates
            // (which previously overwrote the per-epoch records while paying every entry) and unsorted lists. The
            // RewardRouter must aggregate blocks per miner and sort by address before submitting.
            if (i > 0) {
                require(validators[i] > validators[i - 1], "BlockRewardDistributor: validators must be strictly ascending");
            }
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            // ✅ FINAL DECISION (reward-policy simplification, 2026-09-29 — replaces the
            // earlier claimableRewards design, which was fully drafted with a numeric proof but
            // never implemented): past legitimate work is always paid, regardless of the
            // validator's CURRENT status. `isValidator()` would incorrectly reject a validator
            // that has since exited or been suspended, even for blocks it mined while genuinely
            // Active — this is exactly the bug the policy fixes. `everActivated()` is a
            // permanent, append-only Registry flag that survives `withdrawStake()`'s deletion; it
            // proves only "was legitimately activated at least once," not "was Active when this
            // specific block was mined" — that timing verification is NOT and CANNOT be done
            // on-chain (Solidity has no access to historical Registry state beyond the current
            // block) and remains entirely RewardRouter's responsibility: it must determine, from
            // chain data, both the true miner of each block in the settled range (`eth_getBlockByNumber`)
            // and that this miner was genuinely Active at that block's height (via a historical
            // `eth_call` on an archive node, or by replaying `StatusDecisionRecorded` events) before
            // including it here. This check is only a minimal backstop against an address that was
            // never a real validator at all — it is not a substitute for that oracle-side proof, and
            // does not make this contract's payout self-verifying.
            require(REGISTRY.everActivated(validator), "BlockRewardDistributor: address was never a legitimate validator");

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

    /// @dev Records one validator's epoch shares, transfers their combined payout, and emits the
    ///      per-validator event. Split out of `_payValidators` purely so these locals (payout,
    ///      success) live in their own minimal stack frame — no behavior, event, or ordering
    ///      change from the original single-function version.
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

        // single combined transfer per validator for the entire call
        (bool success, ) = validator.call{value: payout}("");
        require(success, "BlockRewardDistributor: validator transfer failed");

        emit ValidatorRewarded(epochId, validator, blocksMinedByValidator, rewardShare, feeShare, payout);
        return true;
    }

    /// @dev Rounds dust into the treasury, transfers the treasury's share, updates lifetime
    ///      totals, records the epoch, and emits the final event — exactly the original inline
    ///      tail of distributeRewards, moved into its own function purely for stack-depth
    ///      reasons (see the refactor note above). No behavior, event, or ordering change.
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
        // Rounding dust from both reward and fee division is added to the treasury's amount
        // so that no wei is left stuck in the contract. The reward-side dust formula subtracts
        // treasuryAmount, foundationAmount, AND distributedRewards from totalRewards — since
        // totalRewards is algebraically exactly foundationAmount + validatorDirectAmount +
        // treasuryAmount (treasuryAmount is defined as the remainder, so there is no dust at
        // that level), what's left over here is exactly validatorDirectAmount - distributedRewards
        // — the integer-division remainder from splitting validatorDirectAmount by block share.
        uint256 rewardDust = totalRewards - treasuryAmount - foundationAmount - distributedRewards;
        // ✅ CHANGED: totalFees here is the FULL pre-burn fee pool (for the epoch record/event's
        // transparency — see distributeRewards). feeDust must therefore subtract feeBurnAmount
        // as well as distributedFees, or the burned 30% would be silently miscounted as
        // "rounding dust" and sent to the treasury a second time on top of already being burned.
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

        // ✅ NEW: actually burn the fee-burn portion — sent last, after the treasury/foundation
        // transfers, purely for a consistent call ordering; the amount was already carved out
        // of feesToDistribute before _payValidators ran, so this is simply moving Suren that
        // was never paid to anyone into permanent, verifiable non-circulation.
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
    // View / reporting functions
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
