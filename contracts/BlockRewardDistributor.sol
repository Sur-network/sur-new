// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
    function statusNonce() external view returns (uint256);
    function wasActiveAt(address who, uint256 nonce) external view returns (bool);
    function everActivated(address who) external view returns (bool); // permanent flag: true once the address was ever legitimately activated
    function getActiveValidatorCount() external view returns (uint256); // used for the two-thirds-of-assembly threshold of the share-change vote
}

/// @notice Minimal interface onto ValidatorsBoard, used to check board authority for the bicameral votes below
///         (see proposeShareChange and proposeRateChange).
interface IValidatorsBoard {
    function isBoardMember(address who) external view returns (bool);
    /// @dev LIVE authority — false immediately after requestExit(), even while the raw seat flag
    ///      isBoardMember is still true until syncBoard(). A suspended (Demoted) member keeps authority until the end of the
    ///      board's month. The Distributor relies on this exact definition instead of re-implementing it.
    function hasBoardAuthority(address who) external view returns (bool);
    /// @dev Incremented by ValidatorsBoard ONLY on a real composition change (refresh/sync/succession), never by a
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
///         Distribution rules (see sur-tokenomics.md sections 6.5, 6 and 11 for the economic and
///         governance reasoning behind each piece below):
///           - From total REWARDS: FoundationDAO's 15% (FOUNDATION_SHARE_BPS) is taken DIRECTLY off
///             the top of total rewards — fixed, automatic, no vote, and deliberately not computed
///             as a percentage of anything else, so Foundation income does not move when the
///             treasury/validator split below is changed.
///           - Of the REMAINING 85%, the split between validators (direct, block-share-based) and
///             ValidatorsTreasury is governed by `validatorDirectShareBps`: changeable via a
///             bicameral vote (proposeShareChange/boardVoteShareChange/validatorVoteShareChange),
///             bounded to [40%, 65%] of TOTAL rewards, with a mandatory 6-month cooldown between
///             successful changes. Both chambers — a simple majority of ValidatorsBoard AND a
///             two-thirds majority of the full active validator assembly — must independently
///             approve the same proposal before it takes effect. This uses the two chambers'
///             opposing incentives (rank-and-file validators are pulled toward a bigger direct
///             share; the board is pulled toward a bigger treasury, since a bigger treasury means
///             more discretionary spending under its own approval power) as a built-in check
///             against either chamber unilaterally draining the other's share over time.
///           - From total ORDINARY FEES (not membership fees — see below): a fixed 30%
///             (FEE_BURN_BPS) is permanently burned (sent to BURN_ADDRESS = address(0)) every
///             epoch; the remaining 70% is split among validators proportionally to blocks mined
///             (no treasury or foundation cut on the distributed portion). See FEE_BURN_BPS's
///             doc comment and sur-tokenomics.md section 7 for why fees (not rewards) are the
///             burn target, and why 30%.
///           - PENDING MEMBERSHIP FEES: ValidatorsRegistry.requestMembership() forwards the
///             membership fee here via receiveMembershipFee(), where it accumulates in
///             `pendingMembershipFees` and is folded into the *next* epoch's fee pool: fully
///             exempt from the 30% burn (100% of it reaches validators) and otherwise paid
///             pro-rata by blocks like ordinary fees — see sur-tokenomics.md section 6: this gives
///             existing validators a direct, traceable cash incentive tied to every new validator
///             that joins. A new member's fee is therefore not paid out in the block of their
///             registration but at the next distributionOracle epoch (~23 hours later).
///           - Each validator receives exactly one payment per call (a single combined transfer
///             of reward share + fee share, where "fee share" includes any pending membership
///             fees folded in for that epoch).
///
///         Validator eligibility is checked directly, on-chain, against ValidatorsRegistry —
///         there is no internal whitelist and no separate sync oracle: ValidatorsRegistry is the
///         single source of truth for both consensus and payment.
///
///         GENESIS DEPLOYMENT: this contract has no constructor — it is injected directly into
///         the genesis `alloc`, so a constructor would never execute on the real chain.
///         ValidatorsRegistry, ValidatorsTreasury, and ValidatorsBoard addresses are fixed
///         constants (see SurAddresses.sol), because all six structural contracts share a
///         common, pre-agreed genesis address map. The initial distributionOracle key (a
///         genuinely rotatable operational credential, not a structural contract) is instead
///         seeded via the off-chain genesis-building tool (see the GENESIS FILL-IN note below
///         and "sur-contracts-deploy-notes.md").
contract BlockRewardDistributor {
    // ------------------------------------------------------------------
    // Constants and configuration
    // ------------------------------------------------------------------

    /// @notice Foundation's share of TOTAL rewards (not of any sub-cut) — basis points out of
    ///         10000 = 100%. Fixed, applied directly to totalRewards, and deliberately independent
    ///         of validatorDirectShareBps below — see sur-tokenomics.md section 6.5 and the
    ///         contract-level doc comment above for why this stays decoupled from the governable
    ///         treasury/validator split.
    uint256 public constant FOUNDATION_SHARE_BPS = 1500; // 15% of total rewards, always

    /// @notice Validators' direct, block-share-based cut of TOTAL rewards — basis points out of 10000. Starts at 50% and is
    ///         a governable state variable, changeable only via the bicameral vote below (proposeShareChange /
    ///         boardVoteShareChange / validatorVoteShareChange), bounded to
    ///         [VALIDATOR_SHARE_MIN_BPS, VALIDATOR_SHARE_MAX_BPS]. ValidatorsTreasury receives
    ///         whatever remains after Foundation's fixed 15% and this share are both taken out:
    ///         treasuryShare = 10000 - FOUNDATION_SHARE_BPS - validatorDirectShareBps.
    uint256 public validatorDirectShareBps = 5000; // 50% initially

    uint256 public constant VALIDATOR_SHARE_MIN_BPS = 4000; // 40% floor
    uint256 public constant VALIDATOR_SHARE_MAX_BPS = 6500; // 65% ceiling
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice Fixed fraction of ordinary transaction fees (NOT membership fees — see
    /// _prepareEpoch()'s comment for why they are deliberately exempt) that is permanently
    /// burned every epoch, before the remaining 70% is distributed 100%-pro-rata-by-blocks to
    /// validators. See sur-tokenomics.md section 7 for the full reasoning: rewards (not fees)
    /// are the dominant source of Suren inflation, so burning fees alone cannot offset it, but
    /// it creates a usage-linked scarcity mechanism that grows in effect as real network
    /// activity grows — the closest analogue this project's fixed-gasPrice design allows to
    /// Ethereum's EIP-1559 base-fee burn, without adopting a dynamic gas price (which would
    /// break the "predictable Suren-denominated cost" design goal).
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

    // The block count of a distribution is bounded by the range control in _settleRange, not by elapsed time.

    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — receives whatever remains of the reward pool after
    ///         Foundation's fixed 15% and validators' governable direct share are both
    ///         removed (see validatorDirectShareBps).
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

    /// @notice Read-only view onto ValidatorsBoard, used to check board authority for the bicameral votes below.
    IValidatorsBoard public constant BOARD_CONTRACT = IValidatorsBoard(SurAddresses.VALIDATORS_BOARD);

    /// @notice Mirrors ValidatorsBoard.BOARD_SIZE — the board is always exactly this many
    ///         members, so a simple majority is BOARD_SIZE/2 + 1 (i.e. 3 of 5).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice Minimum time between two successful validatorDirectShareBps changes —
    ///         deliberately slow (~6 months) so this parameter cannot be nudged repeatedly in
    ///         quick succession by either chamber. See sur-tokenomics.md section 11 for why.
    uint256 public constant SHARE_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastShareChangeTime;

    /// @notice Address of the oracle authorized to call the periodic distribution function.
    ///         Its only job is to report block counts and reward/fee totals; it cannot pay out
    ///         to any address that ValidatorsRegistry does not currently recognize as active.
    /// @dev Initial distributionOracle address, read from SurAddresses.sol (single
    ///      source of truth for all four oracle addresses — see that file for rationale).
    address public distributionOracle = SurAddresses.DISTRIBUTION_ORACLE;

    // This contract has no immutable, so the genesis builder has nothing to patch in the bytecode.
    uint256 public lastDistributionTime;
    uint256 public epochCount;

    // ------------------------------------------------------------------
    // Range control: every distribution declares the REAL block range it settles; the contract keeps the last settled
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


    mapping(address => uint256) public totalRewardsPaid;
    mapping(address => uint256) public totalFeesPaid;
    mapping(address => uint256) public totalBlocksRecorded;

    uint256 public totalDistributedToValidators;
    uint256 public totalDistributedToTreasury;
    uint256 public totalDistributedToFoundation;

    /// @notice Membership fees forwarded by ValidatorsRegistry since the last distribution
    ///         epoch, waiting to be folded into that epoch's 100%-pro-rata-by-blocks fee pool.
    ///         Reset to zero when openDistribution() folds it into the fee pool.
    uint256 public pendingMembershipFees;

    /// @notice A bicameral proposal to change validatorDirectShareBps. Requires
    ///         independent approval from BOTH a simple majority of ValidatorsBoard AND a
    ///         two-thirds majority of the full active validator assembly before it applies —
    ///         see proposeShareChange/boardVoteShareChange/validatorVoteShareChange below.
    /// @dev `requiredValidatorApprovals` is snapshotted ONCE at proposal creation (from the
    ///      active-validator count at that moment), not recomputed on every vote. The bar a
    ///      given proposal must clear is therefore fixed the moment it is proposed: a proposal
    ///      that fails to reach quorum cannot later become executable with no new votes merely
    ///      because the active count shrank. Together with `expiresAt`, a proposal that does not
    ///      reach its own frozen bar within a bounded window simply expires.
    struct ShareProposal {
        uint256 newValidatorShareBps;
        uint256 createdAt;
        uint256 expiresAt; // proposal can no longer be voted on or executed after this
        uint256 requiredValidatorApprovals; // snapshotted at creation, never recomputed
        uint256 boardApprovals;
        uint256 validatorApprovals;
        bool boardPassed;
        bool validatorPassed;
        bool executed;
        /// @dev ValidatorsBoard.boardVersion() when the proposal was created. Board votes and the
        ///      final execution are accepted only while the board composition is still this one — the same rule
        ///      ValidatorsBoard applies to its own actions (boardVersionAtCreation). A real composition change voids the
        ///      proposal; it must be proposed again.
        uint256 boardVersionAtCreation;
        // ValidatorsRegistry.statusNonce at creation; voters must have been Active at exactly that point.
        uint256 validatorNonceAtCreation;
    }

    /// @notice How long a proposal remains votable/executable after creation. Chosen to
    ///         be comfortably shorter than SHARE_CHANGE_MIN_INTERVAL (180 days) — a proposal
    ///         that can't gather the required votes within 30 days should be re-proposed fresh
    ///         (with a fresh electorate snapshot) rather than left open indefinitely.
    uint256 public constant PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ShareProposal) public shareProposals;
    mapping(uint256 => mapping(address => bool)) private shareBoardVoted;
    mapping(uint256 => mapping(address => bool)) private shareValidatorVoted;
    uint256 public shareProposalCount;

    // Approved block-reward rate history, used to cap totalRewards per settled range.
    // The initial rate INITIAL_REWARD_PER_BLOCK applies from block 1 until the first entry. Entries are append-only and take effect
    // only from a FUTURE point; past effective history is never rewritten.
    //
    // Each entry is created from a proposal that names the moment the change takes effect as a UNIX TIMESTAMP (`activationTime`,
    // the same value operators write into `transitions.qbft` of the Besu genesis; on a Shanghai/Cancun genesis that field is a
    // timestamp, not a block number) together with an ESTIMATED start block. The first block whose timestamp is at or after
    // `activationTime` is not known in advance, so the entry is PROVISIONAL until the distribution oracle certifies the actual start
    // block with certifyRateStart. A certified block must lie within RATE_START_TOLERANCE_BLOCKS of the estimate.
    // While an entry is provisional, blocks inside [estimate - tolerance, estimate + tolerance) are capped at the LARGER of the old and
    // the new rate; blocks before that window use the old rate and blocks from its end use the new rate. After certification the
    // change is exact at the certified block. The cap of a range therefore never rejects a correctly configured network, and the oracle's
    // influence is bounded by tolerance x |new rate - old rate| for each change.
    // TRUST BOUNDARY: this contract does not read Besu's actual block reward or block times. The approved rates and activation times
    // must be kept in line with the network's genesis transitions operationally; the cap does not prove fee correctness, block
    // attribution, or that the recorded rate equals Besu's. It only bounds the gross reward the oracle can report for a range.
    // If operators configure a transition whose real start block falls outside the tolerance window, the certification is rejected and
    // ranges containing blocks whose real reward exceeds the approved rate cannot be distributed.
    // Governance: proposals need 3 of the 5 board members (live authority + board-composition guard) AND two thirds of the validators
    // eligible when the proposal was created. The 30-day voting expiry applies to the voting phase only; once both chambers have
    // completed, a 7-day delay starts, and execution re-checks everything (see executeRateChange). The distribution oracle cannot add,
    // change or remove a rate; it can only certify the start block of an approved entry within the tolerance window.
    uint256 public constant INITIAL_REWARD_PER_BLOCK = 2 ether;
    struct RewardRateChange {
        uint128 startBlock; // estimated first block of the new rate until certified; the actual first block afterwards
        uint128 ratePerBlock; // wei per block
        uint64 activationTime; // unix seconds; the moment configured in the Besu transition
        bool certified; // true once the oracle has certified the actual start block
    }
    RewardRateChange[] private rewardRateChanges;

    // ------------------------------------------------------------------
    // Governance — approved reward-rate changes
    // ------------------------------------------------------------------
    /// @notice Board approvals needed: 3 of the 5-member board (== BOARD_SIZE / 2 + 1).
    uint256 public constant RATE_CHANGE_BOARD_APPROVALS = 3;
    /// @notice Voting phase only. An approved proposal waiting for its delay/execution is NOT removed by this expiry.
    uint256 public constant RATE_VOTING_EXPIRY = 30 days;
    /// @notice Starts when BOTH chambers have completed.
    uint256 public constant RATE_CHANGE_DELAY = 7 days;
    /// @notice Minimum distance in SECONDS between the executing block and a change's activation time. It is a time, independent of
    ///         RATE_CHANGE_DELAY, and gives every operator a week to update the genesis of every node.
    uint256 public constant MIN_RATE_CHANGE_LEAD_SECONDS = 7 days;
    /// @notice Half-width, in blocks, of the window around the estimated start block in which the larger of the two rates is
    ///         allowed until the start block is certified, and the largest distance between a certified start block and its estimate.
    uint256 public constant RATE_START_TOLERANCE_BLOCKS = 10_000;

    struct RateProposal {
        uint128 startBlock; // estimated first block of the new rate
        uint128 ratePerBlock;
        uint64 activationTime; // unix seconds
        uint256 createdAt;
        uint256 votingExpiresAt;
        uint256 requiredValidatorApprovals; // ceil(2/3) of the validators active at creation, frozen
        uint256 boardApprovals;
        uint256 validatorApprovals;
        uint256 approvedAt; // 0 until both chambers have completed
        bool executed;
        uint256 boardVersionAtCreation; // a real change of board composition voids the proposal
        uint256 validatorNonceAtCreation; // snapshot of the validator electorate
    }
    mapping(uint256 => RateProposal) public rateProposals;
    mapping(uint256 => mapping(address => bool)) private rateBoardVoted;
    mapping(uint256 => mapping(address => bool)) private rateValidatorVoted;
    uint256 public rateProposalCount;

    event RateChangeProposed(uint256 indexed id, uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock, address indexed proposer);
    event RateChangeBoardVoted(uint256 indexed id, address indexed boardMember, uint256 approvals, uint256 required);
    event RateChangeValidatorVoted(uint256 indexed id, address indexed validator, uint256 approvals, uint256 required);
    event RateChangeApproved(uint256 indexed id, uint256 approvedAt, uint256 executableAt);
    event RateChangeExecuted(uint256 indexed id, uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock);
    event RateStartCertified(uint256 indexed index, uint256 activationTime, uint256 actualStartBlock);

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
    ///         behavior). The amount simply accumulates until the next openDistribution()
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
    // Bicameral governance for validatorDirectShareBps (the validator-vs-treasury
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
        // Live authority, not the raw seat flag — a member who requested exit loses the right to
        // vote immediately, even before syncBoard() clears the seat.
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

    /// @notice The other required vote — the full validator assembly chamber. Checked against
    ///         `requiredValidatorApprovals`, snapshotted once at proposal creation — see the
    ///         ShareProposal struct's doc comment.
    function validatorVoteShareChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(block.timestamp <= p.expiresAt, "BlockRewardDistributor: proposal has expired");
        require(!shareValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");
        // The voter must have been Active when the proposal was created (electorate snapshot) AND be Active now (onlyActiveValidator).
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
            // A board chamber that passed under an older composition cannot be completed later by the validator
            // chamber — the composition is checked again at execution, not only at the board vote.
            require(
                p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
                "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
            );
            // The minimum interval between SUCCESSFUL changes is enforced here, where the change is applied. The vote that
            // would complete a too-early proposal reverts; since PROPOSAL_EXPIRY (30 days) < SHARE_CHANGE_MIN_INTERVAL
            // (180 days), such a proposal can never execute and simply expires.
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
    // The logic is split into three functions, each with its own stack frame, so the contract compiles without viaIR
    // (which many verification services cannot verify against — see sur-contracts-deploy-notes.md).
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // Paginated distribution (RD-18, owner decision 2026-11-21)
    //
    // One distribution = openDistribution() + payPage() x N + closeDistribution(); only the distribution oracle calls them.
    //   open   declares the block range, the TOTAL block count and the totals; settles the range (lastSettledBlock moves NOW), burns the excess,
    //          reserves the needed amount (budgetLeft) and starts the 23-hour gap; RewardsDistributed is NOT emitted yet.
    //   page   pays some payees. Addresses must be strictly ascending ACROSS pages (each page starts above the last address of the page before).
    //   close  requires the paged block counts to add up EXACTLY to the declared total, then pays treasury, foundation and the fee burn and emits RewardsDistributed.
    // There is NO escape path: an open distribution can only be continued and closed (by the current oracle key); nothing, including the board, can abandon it or move its money.
    // No page-size cap is coded: a page that does not fit the gas limit simply reverts as a whole (no state change), so an oversized page can only fail its own transaction. The Router chooses the page size.
    // ------------------------------------------------------------------
    struct OpenDistribution {
        bool isOpen;
        uint256 epochId;
        uint256 totalBlocks;            // declared at open; the pages must add up to exactly this
        uint256 paidBlocks;             // sum of the blocks paged so far
        uint256 totalRewards;           // approved rewards (after the excess burn)
        uint256 totalFees;              // full fee pool incl. membership fees, before the burn (for the epoch record)
        uint256 feeBurnAmount;
        uint256 feesToDistribute;
        uint256 validatorDirectAmount;
        uint256 budgetLeft;             // reserved amount not yet paid, credited to claimable or spent at close
        uint256 distributedRewards;
        uint256 distributedFees;
        uint256 validatorCount;
        address lastPayee;
    }
    OpenDistribution private cur;

    event DistributionOpened(
        uint256 indexed epochId,
        uint256 fromBlock,
        uint256 toBlock,
        uint256 totalBlocks,
        uint256 approvedRewards,
        uint256 feePoolToDistribute
    );
    event DistributionPage(uint256 indexed epochId, uint256 payees, uint256 blocksInPage, uint256 paidBlocksSoFar);

    /// @notice Opens the distribution of `range`. The range must start at lastSettledBlock + 1, end before the current block, and the declared totalBlocks cannot exceed its size. totalRewards is the reported actual reward (the part above the approved amount is burned at once); totalFees the ordinary fees of the range.
    function openDistribution(BlockRange calldata range, uint256 totalBlocks, uint256 totalRewards, uint256 totalFees)
        external
        onlyDistributionOracle
        nonReentrant
    {
        OpenDistribution storage c = cur;
        require(!c.isOpen, "BlockRewardDistributor: another distribution is open");
        require(
            block.timestamp >= lastDistributionTime + MIN_DISTRIBUTION_INTERVAL || epochCount == 0,
            "BlockRewardDistributor: too soon since last distribution"
        );
        EpochPrep memory prep = _prepareEpoch(totalBlocks, totalRewards, totalFees);
        _settleRange(range, totalBlocks);
        // v2.5: only the APPROVED amount of the range is split; the excess over it is burned at once (never halts the distribution).
        totalRewards = _capAndBurnExcess(range, totalRewards);

        epochCount++;
        epochBlockRanges[epochCount] = range;
        emit EpochRangeSettled(epochCount, range.fromBlock, range.toBlock);
        lastDistributionTime = block.timestamp; // the 23-hour gap is counted from OPEN

        c.isOpen = true;
        c.epochId = epochCount;
        c.totalBlocks = totalBlocks;
        c.paidBlocks = 0;
        c.totalRewards = totalRewards;
        c.totalFees = prep.effectiveTotalFees;
        c.feeBurnAmount = prep.feeBurnAmount;
        c.feesToDistribute = prep.feesToDistribute;
        c.validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS_DENOMINATOR;
        c.budgetLeft = totalRewards + prep.effectiveTotalFees; // the reservation: nothing else can spend it
        c.distributedRewards = 0;
        c.distributedFees = 0;
        c.validatorCount = 0;
        c.lastPayee = address(0);
        emit DistributionOpened(epochCount, range.fromBlock, range.toBlock, totalBlocks, totalRewards, prep.feesToDistribute);
    }

    /// @notice Pays one page of the open distribution. `validators` must be strictly ascending and every address above the last payee of the previous page. Each payee gets its share of the declared totals by blocksMined / totalBlocks: directly if it has no code, otherwise credited to claimable (RD-12b).
    function payPage(address[] calldata validators, uint256[] calldata blocksMined)
        external
        onlyDistributionOracle
        nonReentrant
    {
        OpenDistribution storage c = cur;
        require(c.isOpen, "BlockRewardDistributor: no open distribution");
        require(validators.length > 0, "BlockRewardDistributor: empty validator list");
        require(validators.length == blocksMined.length, "BlockRewardDistributor: length mismatch");
        address prev = c.lastPayee;
        uint256 pageBlocks;
        for (uint256 i = 0; i < validators.length; i++) {
            address validator = validators[i];
            // strictly ascending across pages: rejects duplicates, unsorted lists, the zero address and an address paid in an earlier page
            require(validator > prev, "BlockRewardDistributor: validators must be strictly ascending");
            prev = validator;
            uint256 b = blocksMined[i];
            // an entry with zero blocks is refused: it would only advance lastPayee, and an address such as 0xFF…FF would then make closing impossible forever (review finding)
            require(b > 0, "BlockRewardDistributor: zero blocks - leave the address out");
            pageBlocks += b;
            require(c.paidBlocks + pageBlocks <= c.totalBlocks, "BlockRewardDistributor: paged blocks exceed the declared total");
            _payOne(c, validator, b);
        }
        c.lastPayee = prev;
        c.paidBlocks += pageBlocks;
        require(c.paidBlocks <= c.totalBlocks, "BlockRewardDistributor: paged blocks exceed the declared total");
        emit DistributionPage(c.epochId, validators.length, pageBlocks, c.paidBlocks);
    }

    /// @notice Closes the open distribution: the paged blocks must equal the declared total EXACTLY. Pays the treasury (its share plus all rounding dust), the foundation and the fee burn, and emits RewardsDistributed.
    function closeDistribution() external onlyDistributionOracle nonReentrant {
        OpenDistribution storage c = cur;
        require(c.isOpen, "BlockRewardDistributor: no open distribution");
        require(c.paidBlocks == c.totalBlocks, "BlockRewardDistributor: paged blocks differ from the declared total");
        _finalizeEpoch(c);
    }

    /// @notice State of the open distribution (isOpen = false when none).
    function openDistributionInfo()
        external
        view
        returns (bool isOpen, uint256 epochId, uint256 totalBlocks, uint256 paidBlocks, address lastPayee, uint256 budgetLeft)
    {
        OpenDistribution storage c = cur;
        return (c.isOpen, c.epochId, c.totalBlocks, c.paidBlocks, c.lastPayee, c.budgetLeft);
    }

    /// @notice Cumulative Suren burned because the actual reward of a settled range exceeded the approved one.
    uint256 public totalExcessBurned;

    /// @dev Public on-chain alert for off-chain monitors (RewardRouter alerts by e-mail etc.).
    event RewardExcessBurned(uint256 indexed epochId, uint256 fromBlock, uint256 toBlock, uint256 approvedRewards, uint256 excessBurned);

    /// @dev Returns the amount that is split three ways: min(reported, approved for the range). Any excess is burned right
    ///      here (before the payments; the balance check in _prepareEpoch already covered reported + fees). The epoch id the
    ///      event carries is the one this distribution is about to take.
    function _capAndBurnExcess(BlockRange calldata range, uint256 reportedRewards) private returns (uint256 approved) {
        approved = maxRewardsForRange(range.fromBlock, range.toBlock);
        if (reportedRewards <= approved) return reportedRewards;
        uint256 excess = reportedRewards - approved;
        totalExcessBurned += excess;
        emit RewardExcessBurned(epochCount + 1, range.fromBlock, range.toBlock, approved, excess);
        (bool ok, ) = BURN_ADDRESS.call{value: excess}("");
        require(ok, "BlockRewardDistributor: excess burn transfer failed");
    }

    /// @notice Propose an approved-rate change taking effect at `activationTime` (unix seconds, the Besu transition time), with the
    ///         proposer's estimate of the first block at or after that time. Only an active validator may propose.
    ///         Early rejection only: every condition is checked again at execution. Proposals are independent; several
    ///         may be open at once, and whichever is executed first can make another one unexecutable (it is then left as it is).
    function proposeRateChange(uint256 activationTime, uint256 estimatedStartBlock, uint256 ratePerBlock) external returns (uint256 id) {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: only an active validator may propose a rate change");
        require(
            activationTime <= type(uint64).max && estimatedStartBlock <= type(uint128).max && ratePerBlock <= type(uint128).max,
            "BlockRewardDistributor: value does not fit its type"
        );
        _requireRateStartOk(activationTime, estimatedStartBlock);
        id = ++rateProposalCount;
        RateProposal storage p = rateProposals[id];
        p.startBlock = uint128(estimatedStartBlock);
        p.ratePerBlock = uint128(ratePerBlock);
        p.activationTime = uint64(activationTime);
        p.createdAt = block.timestamp;
        p.votingExpiresAt = block.timestamp + RATE_VOTING_EXPIRY;
        p.requiredValidatorApprovals = (REGISTRY.getActiveValidatorCount() * 2 + 2) / 3; // ceil(2/3), frozen now
        p.boardVersionAtCreation = BOARD_CONTRACT.boardVersion();
        p.validatorNonceAtCreation = REGISTRY.statusNonce();
        emit RateChangeProposed(id, activationTime, estimatedStartBlock, ratePerBlock, msg.sender);
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

    /// @notice Validator chamber: eligible = Active when the proposal was created and Active now.
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
    ///         Re-checks: board composition, activation time still at least MIN_RATE_CHANGE_LEAD_SECONDS away, the estimated start block
    ///         still in the future, and strictly ascending history with non-overlapping tolerance windows. If any check fails the
    ///         proposal stays exactly as it is: no time or height is ever moved automatically. The new entry is provisional until
    ///         certifyRateStart.
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
        _requireRateStartOk(p.activationTime, p.startBlock);
        p.executed = true;
        rewardRateChanges.push(
            RewardRateChange({startBlock: p.startBlock, ratePerBlock: p.ratePerBlock, activationTime: p.activationTime, certified: false})
        );
        emit RateChangeExecuted(id, p.activationTime, p.startBlock, p.ratePerBlock);
    }

    /// @notice The distribution oracle certifies the first block whose timestamp is at or after the entry's activation time. Possible
    ///         only once that time has been reached, only once per entry, and only within RATE_START_TOLERANCE_BLOCKS of the estimate.
    ///         The contract cannot read old block timestamps, so the value is trusted within that window; certification only tightens
    ///         the cap from "larger of both rates inside the window" to "exact at the certified block".
    function certifyRateStart(uint256 index, uint256 actualStartBlock) external onlyDistributionOracle {
        require(index < rewardRateChanges.length, "BlockRewardDistributor: no such rate change");
        RewardRateChange storage c = rewardRateChanges[index];
        require(!c.certified, "BlockRewardDistributor: start block already certified");
        require(block.timestamp >= c.activationTime, "BlockRewardDistributor: activation time has not been reached");
        require(actualStartBlock <= block.number, "BlockRewardDistributor: start block is in the future");
        uint256 estimate = c.startBlock;
        uint256 distance = actualStartBlock > estimate ? actualStartBlock - estimate : estimate - actualStartBlock;
        require(distance <= RATE_START_TOLERANCE_BLOCKS, "BlockRewardDistributor: start block is outside the tolerance window");
        c.startBlock = uint128(actualStartBlock);
        c.certified = true;
        emit RateStartCertified(index, c.activationTime, actualStartBlock);
    }

    /// @notice Status as of the latest block. status: 0 not found, 1 voting, 2 voting expired (never approved), 3 executed,
    ///         4 approved and waiting for the delay, 5 executable now, 6 approved but currently unexecutable,
    ///         7 not yet approved and unable to continue (voting can no longer lead to an executable change).
    ///         problem (status 6 or 7): 1 board composition changed, 2 activation time not in the future, 3 activation time closer than
    ///         MIN_RATE_CHANGE_LEAD_SECONDS, 4 not after the last approved change (time, or tolerance windows would overlap), 5 estimated
    ///         start block not in the future. Every problem is permanent (time and block numbers only grow, the history only grows, a
    ///         board change cannot be undone for a proposal), so status 7 never goes back to 1.
    ///         Execution happens in a later block, so this is advisory.
    function rateChangeStatus(uint256 id) external view returns (uint8 status, uint8 problem) {
        RateProposal storage p = rateProposals[id];
        if (p.createdAt == 0) return (0, 0);
        if (p.executed) return (3, 0);
        problem = BOARD_CONTRACT.boardVersion() != p.boardVersionAtCreation ? 1 : _rateStartProblem(p.activationTime, p.startBlock);
        if (p.approvedAt == 0) {
            if (block.timestamp > p.votingExpiresAt) return (2, 0);
            if (problem != 0) return (7, problem);
            return (1, 0);
        }
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
            // Both chambers count as complete only if the proposal still belongs to the CURRENT board composition. The board vote
            // checks this itself; a completing validator vote must not register approval (nor emit RateChangeApproved) for a proposal
            // whose board has since changed - execution would refuse it anyway. The vote is not recorded; the proposal can no longer succeed.
            require(
                p.boardVersionAtCreation == BOARD_CONTRACT.boardVersion(),
                "BlockRewardDistributor: board membership changed since this proposal was created - propose again"
            );
            p.approvedAt = block.timestamp;
            emit RateChangeApproved(id, block.timestamp, block.timestamp + RATE_CHANGE_DELAY);
        }
    }

    function _rateStartProblem(uint256 activationTime, uint256 estimatedStartBlock) private view returns (uint8) {
        if (activationTime <= block.timestamp) return 2;
        if (activationTime < block.timestamp + MIN_RATE_CHANGE_LEAD_SECONDS) return 3;
        if (estimatedStartBlock <= block.number) return 5;
        uint256 n = rewardRateChanges.length;
        if (n > 0) {
            RewardRateChange storage last = rewardRateChanges[n - 1];
            if (activationTime <= last.activationTime) return 4;
            uint256 lastEnd = last.certified ? last.startBlock : uint256(last.startBlock) + RATE_START_TOLERANCE_BLOCKS;
            if (estimatedStartBlock <= lastEnd + RATE_START_TOLERANCE_BLOCKS) return 4;
        }
        return 0;
    }

    function _requireRateStartOk(uint256 activationTime, uint256 estimatedStartBlock) private view {
        uint8 r = _rateStartProblem(activationTime, estimatedStartBlock);
        require(r != 2, "BlockRewardDistributor: activation time is not in the future");
        require(r != 3, "BlockRewardDistributor: activation time is closer than MIN_RATE_CHANGE_LEAD_SECONDS");
        require(r != 5, "BlockRewardDistributor: estimated start block is not in the future");
        require(r != 4, "BlockRewardDistributor: activation time and start block must be after the last approved rate change");
    }

    /// @dev Binary search: number of history entries whose effect has ended by `blockNumber`. An entry's effect ends at its certified
    ///      start block, or at estimate + tolerance while it is provisional. Ends are strictly ascending.
    function _rateEntriesEnded(uint256 blockNumber) private view returns (uint256 lo) {
        uint256 hi = rewardRateChanges.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            RewardRateChange storage c = rewardRateChanges[mid];
            uint256 end = c.certified ? c.startBlock : uint256(c.startBlock) + RATE_START_TOLERANCE_BLOCKS;
            if (end <= blockNumber) lo = mid + 1;
            else hi = mid;
        }
    }

    /// @notice Approved gross block reward for blocks [fromBlock, toBlock], summed segment by segment over the rate history. Inside the
    ///         tolerance window of a provisional entry the larger of the old and the new rate applies; a certified entry is exact.
    ///         Cost = O(log n) to find the rate at fromBlock + a constant number of steps per rate change INSIDE the range; it
    ///         depends neither on the number of blocks nor on how many older changes the history holds.
    function maxRewardsForRange(uint256 fromBlock, uint256 toBlock) public view returns (uint256 total) {
        require(fromBlock <= toBlock, "BlockRewardDistributor: invalid range");
        uint256 n = rewardRateChanges.length;
        uint256 i = _rateEntriesEnded(fromBlock);
        uint256 rate = i == 0 ? INITIAL_REWARD_PER_BLOCK : rewardRateChanges[i - 1].ratePerBlock;
        uint256 cursor = fromBlock;
        for (; i < n; i++) {
            RewardRateChange memory c = rewardRateChanges[i];
            if (c.certified) {
                if (c.startBlock > toBlock) break;
                if (c.startBlock > cursor) {
                    total += (c.startBlock - cursor) * rate;
                    cursor = c.startBlock;
                }
                rate = c.ratePerBlock;
            } else {
                uint256 windowStart = c.startBlock > RATE_START_TOLERANCE_BLOCKS ? c.startBlock - RATE_START_TOLERANCE_BLOCKS : 0;
                uint256 windowEnd = uint256(c.startBlock) + RATE_START_TOLERANCE_BLOCKS;
                if (windowStart > toBlock) break;
                if (windowStart > cursor) {
                    total += (windowStart - cursor) * rate;
                    cursor = windowStart;
                }
                if (c.ratePerBlock > rate) rate = c.ratePerBlock; // inside the window: the larger of the two rates
                if (windowEnd > toBlock) break;
                total += (windowEnd - cursor) * rate;
                cursor = windowEnd;
                rate = c.ratePerBlock;
            }
        }
        total += (toBlock - cursor + 1) * rate;
    }

    /// @notice Largest approved reward per block that may apply at `blockNumber` (inside the tolerance window of a provisional entry
    ///         this is the larger of the old and the new rate).
    function rewardRateAt(uint256 blockNumber) external view returns (uint256) {
        return maxRewardsForRange(blockNumber, blockNumber);
    }

    /// @notice Number of approved rate changes and one entry, for dashboards and audits.
    function rewardRateChangeCount() external view returns (uint256) {
        return rewardRateChanges.length;
    }

    function rewardRateChange(uint256 index) external view returns (uint256 startBlock, uint256 ratePerBlock, uint256 activationTime, bool certified) {
        RewardRateChange memory c = rewardRateChanges[index];
        return (c.startBlock, c.ratePerBlock, c.activationTime, c.certified);
    }

    /// @dev Range control (see the BlockRange comment). Kept in its own stack frame.
    ///
    ///      Why there is no time-based cap: a check of the form totalBlocks <= (block.timestamp - lastDistributionTime) / 3
    ///      would compare two things that measure different things — the block count belongs to the range after
    ///      lastSettledBlock, while lastDistributionTime is when the previous distribution TRANSACTION ran, which may have
    ///      settled only up to an earlier block. Any settlement behind head (normal oracle lag) or any block cadence faster
    ///      than 3 s would make correct payments revert, and once one cycle reverted every later, longer range would too.
    ///      What bounds the count instead, entirely on-chain and exactly:
    ///        (1) continuity   fromBlock == lastSettledBlock + 1           -> no gap, no overlap, no duplicate range;
    ///        (2) past only    toBlock < block.number                      -> never settles the current or a future block;
    ///        (3) size         sum(blocksMined) <= toBlock - fromBlock + 1 -> never more blocks than really exist in it.
    ///      (3) is an upper bound, not an equality. Per sur-reward-router-spec.md section 3, the sum
    ///      should NORMALLY equal the range length; a producer's later exit/suspension is never a reason to omit its blocks
    ///      (everActivated policy). NOTE: payouts divide by sum(blocksMined), not by the range length, so whether the
    ///      reward/fee of an omitted block stays in this contract or is redistributed to the listed producers depends only
    ///      on the totalRewards/totalFees the oracle reports — the contract enforces neither. Once lastSettledBlock moves
    ///      past an omitted block, there is no on-chain path to pay that block to its producer.
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
    }

    /// @dev Pre-computation of openDistribution(): folds the membership fees in, checks the balance (claimable is a debt, never distributable) and splits off the fee burn.
    function _prepareEpoch(uint256 totalBlocks, uint256 totalRewards, uint256 totalFees)
        private
        returns (EpochPrep memory prep)
    {
        // Fold the membership fees forwarded since the last distribution into this fee pool (exempt from the fee burn; see sur-tokenomics.md section 6).
        uint256 membershipFeesThisEpoch = pendingMembershipFees;
        pendingMembershipFees = 0;
        prep.effectiveTotalFees = totalFees + membershipFeesThisEpoch;

        require(totalRewards + prep.effectiveTotalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
        // RD-12b: amounts already owed to owners with code (claimable) are a debt of this contract and never distributable.
        require(
            totalRewards + prep.effectiveTotalFees + totalClaimable <= address(this).balance,
            "BlockRewardDistributor: insufficient contract balance"
        );

        // Burn a fixed 30% of the ORDINARY fees only (not of the membership fees).
        prep.feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS_DENOMINATOR;
        prep.feesToDistribute = prep.effectiveTotalFees - prep.feeBurnAmount;
    }

    /// @dev Pays or credits one payee of a page. Past legitimate work is always paid (everActivated); the timing check (was the miner Active at that block) remains the RewardRouter's job. Per-payee records are the events only (no per-epoch storage).
    function _payOne(OpenDistribution storage c, address validator, uint256 blocksMinedByValidator) private {
        require(REGISTRY.everActivated(validator), "BlockRewardDistributor: address was never a legitimate validator");
        uint256 rewardShare = (c.validatorDirectAmount * blocksMinedByValidator) / c.totalBlocks;
        uint256 feeShare = (c.feesToDistribute * blocksMinedByValidator) / c.totalBlocks;
        uint256 payout = rewardShare + feeShare;
        if (payout == 0) return;

        totalRewardsPaid[validator] += rewardShare;
        totalFeesPaid[validator] += feeShare;
        totalBlocksRecorded[validator] += blocksMinedByValidator;
        c.budgetLeft -= payout;
        c.distributedRewards += rewardShare;
        c.distributedFees += feeShare;
        c.validatorCount++;

        // RD-12b: direct payment only to an address WITHOUT code; an address with code is never called: it is credited to claimable and the owner calls claim().
        if (validator.code.length == 0) {
            (bool success, ) = validator.call{value: payout}("");
            require(success, "BlockRewardDistributor: validator transfer failed");
            emit ValidatorRewarded(c.epochId, validator, blocksMinedByValidator, rewardShare, feeShare, payout);
        } else {
            claimable[validator] += payout;
            totalClaimable += payout;
            emit ValidatorRewardDeferred(c.epochId, validator, blocksMinedByValidator, rewardShare, feeShare, payout);
        }
    }

    /// @dev Tail of closeDistribution(): rounding dust goes to the treasury, then treasury, foundation and fee burn are paid, totals and the epoch record are written and RewardsDistributed is emitted.
    function _finalizeEpoch(OpenDistribution storage c) private {
        uint256 epochId = c.epochId;
        uint256 foundationAmount = (c.totalRewards * FOUNDATION_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 treasuryAmount = c.totalRewards - foundationAmount - c.validatorDirectAmount;
        // dust: what the integer division by block share left of the validators' reward share and of the fee pool
        uint256 rewardDust = c.validatorDirectAmount - c.distributedRewards;
        uint256 feeDust = c.feesToDistribute - c.distributedFees;
        uint256 totalTreasuryAmount = treasuryAmount + rewardDust + feeDust;
        uint256 feeBurnAmount = c.feeBurnAmount;

        if (totalTreasuryAmount > 0) {
            (bool tsuccess, ) = TREASURY.call{value: totalTreasuryAmount}("");
            require(tsuccess, "BlockRewardDistributor: treasury transfer failed");
        }

        if (foundationAmount > 0) {
            (bool fsuccess, ) = FOUNDATION.call{value: foundationAmount}("");
            require(fsuccess, "BlockRewardDistributor: foundation transfer failed");
            emit FoundationFunded(epochId, foundationAmount);
        }

        if (feeBurnAmount > 0) {
            (bool bsuccess, ) = BURN_ADDRESS.call{value: feeBurnAmount}("");
            require(bsuccess, "BlockRewardDistributor: fee burn transfer failed");
            totalFeesBurned += feeBurnAmount;
            emit FeesBurned(epochId, feeBurnAmount, totalFeesBurned);
        }

        totalDistributedToValidators += (c.distributedRewards + c.distributedFees);
        totalDistributedToTreasury += totalTreasuryAmount;
        totalDistributedToFoundation += foundationAmount;

        epochs[epochId] = Epoch({
            timestamp: block.timestamp,
            totalRewards: c.totalRewards,
            totalFees: c.totalFees,
            treasuryAmount: totalTreasuryAmount,
            totalBlocksMined: c.totalBlocks,
            validatorCount: c.validatorCount
        });

        emit RewardsDistributed(epochId, c.totalRewards, c.totalFees, totalTreasuryAmount, c.totalBlocks, c.validatorCount);
        delete cur; // closed: the reservation is released (its money has just been spent)
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

    // ------------------------------------------------------------------
    // RD-12b: deferred payment to an owner that has code
    // ------------------------------------------------------------------
    /// @notice Amount held for an owner that has code; only that owner withdraws it, with claim().
    mapping(address => uint256) public claimable;
    /// @notice Sum of all claimable: a debt of this contract, deducted in every distribution's balance check.
    uint256 public totalClaimable;

    /// @dev Emitted INSTEAD of ValidatorRewarded for a payout that was not sent directly (address with code). RewardRouter must accept both.
    event ValidatorRewardDeferred(
        uint256 indexed epochId,
        address indexed validator,
        uint256 blocksMined,
        uint256 rewardShare,
        uint256 feeShare,
        uint256 totalPayout
    );
    event ClaimableWithdrawn(address indexed owner, uint256 amount);

    /// @notice The owner (with code) withdraws its own deferred balance. Only the caller's own balance; if its receive() reverts only this claim fails.
    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "BlockRewardDistributor: nothing to claim");
        claimable[msg.sender] = 0;
        totalClaimable -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "BlockRewardDistributor: claim transfer failed");
        emit ClaimableWithdrawn(msg.sender, amount);
    }

    /// @notice Balance a distribution may spend = contract balance minus the claimable debt.
    function getDistributableBalance() external view returns (uint256) {
        return address(this).balance - totalClaimable - cur.budgetLeft - pendingMembershipFees;
    }
}
