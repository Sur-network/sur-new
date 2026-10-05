// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IBlockRewardDistributor {
    function receiveMembershipFee() external payable;
}

interface IValidatorsBoardSync {
    function syncVoter(address voter) external;
}

/// @title ValidatorsRegistry
/// @notice Deployed at the fixed genesis address SurAddresses.VALIDATORS_REGISTRY (0x3333...3333). Serves two roles:
///
///         1) CONSENSUS: implements Besu's QBFT contract-mode interface
///            `getValidators() external view returns (address[] memory)`. The address is set as
///            `qbft.validatorcontractaddress` in genesis.json. A change to the returned list takes effect from the
///            block in which it is mined: the proposer of block N is taken from the list as it stands after block N-1.
///
///         2) PAYMENT ELIGIBILITY: `BlockRewardDistributor` pays a block's reward to a validator only if
///            `everActivated(validator)` is true here. Whether the address was Active when it produced the block is
///            checked off-chain by the RewardRouter.
///
///         It is deliberately separate from `ValidatorsTreasury`: a bug in treasury spending logic can never change
///         who is recognised as a validator.
///
///         GENESIS DEPLOYMENT: this contract, with the other structural contracts, is injected into the genesis
///         `alloc` (code and storage) and has no constructor. The founding validator set, the genesis timestamp and
///         every security parameter are written by the off-chain genesis tool (see the GENESIS FILL-IN notes in this
///         file and "sur-contracts-deploy-notes.md").
///
///         Lifecycle of a validator address:
///           None -> Probation (stake locked, node being checked, not yet in getValidators())
///                -> Active (in getValidators(), payment-eligible)
///                -> Demoted when the verifier records a suspension (removed from getValidators())
///                -> Active again when the verifier records a recovery
///           From Probation, Active or Demoted an address may choose Exiting (voluntary withdrawal after a cooldown)
///           to reclaim its stake.
///
///         The active set never drops below MIN_ACTIVE_VALIDATORS: the last active validator can neither be suspended
///         nor leave.
///
///         Governance has two tracks:
///           - ECONOMIC ENTRY PARAMETERS (entryThresholdBase, growthFactorPerValidator, membershipFeeBps) are changed
///             only by ValidatorsBoard's internal vote.
///           - EVERYTHING ELSE (rate limit, probation length, recovery period, slashing bps, exit cooldown) requires a
///             majority of the validators that were Active when the proposal was created
///             (proposeParameterChange / voteParameterChange).
///
///         MEMBERSHIP PAYMENT: a new validator pays two amounts in native currency (Suren) with requestMembership:
///           - COLLATERAL (= currentEntryThreshold()): locked here, refundable on exit, slashable.
///           - MEMBERSHIP FEE (= currentMembershipFee(), a governed percentage of the collateral): forwarded to
///             BlockRewardDistributor and paid pro rata by blocks to the validators active in the next epoch, exempt
///             from the ordinary-fee burn. A slashed portion of the collateral goes to ValidatorsTreasury.
///
///         BOARD SYNCHRONISATION: whenever a validator's active status changes, this contract calls
///         `ValidatorsBoard.syncVoter(validator)` so the board's vote counters follow the active set. The call is
///         best-effort and cannot block a status change.
contract ValidatorsRegistry {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — destination for slashed stake.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice BlockRewardDistributor. Membership fees are forwarded here (receiveMembershipFee()) and paid pro rata by
    ///         blocks to the validators active in the next epoch.
    IBlockRewardDistributor public constant DISTRIBUTOR = IBlockRewardDistributor(payable(SurAddresses.BLOCK_REWARD_DISTRIBUTOR));

    /// @notice ValidatorsBoard — the only address allowed to change the economic entry
    ///         parameters below (entryThresholdBase, growthFactorPerValidator, membershipFeeBps).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    // ------------------------------------------------------------------
    // Validator state
    // ------------------------------------------------------------------

    enum Status { None, Probation, Active, Demoted, Exiting }

    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;   // start of current probation OR recovery OR exit-cooldown window
        // Status changes are decided off-chain by the verifier and recorded on-chain with a hash of the evidence package
        // (see StatusDecision below); no liveness ratio is kept on-chain.
        uint256 pendingSlashEpoch; // nonzero while this validator has an unresolved
        // inactivity-slash decision (mass-failure check pending, OR delivery/appeal pending —
        // see StatusDecision and DemotionEpoch below for the full mechanism). Zero means "no
        // pending slash." It blocks withdrawStake() while set.
        uint256 demotedAt;          // 0 if never demoted / currently not in Demoted status
        bool isPaidEntrant;        // true only for validators that paid via requestMembership(); false for
        // genesis-seeded founders (injected with lockedStake = 0), so the growth curve reflects paid entries only.
    }

    mapping(address => ValidatorInfo) public validators;

    /// @notice Number of paid entrants (joined via requestMembership()) that have not called requestExit(). It spans
    ///         Probation, Active and Demoted alike: a paid validator that is merely on probation or temporarily demoted
    ///         still counts; only a full exit removes it. Genesis-seeded founders are not counted (they never call
    ///         requestMembership()), so their free entry does not raise the cost for later entrants.
    ///         currentEntryThreshold() uses this value as its exponent.
    uint256 public paidValidatorCount;

    // ------------------------------------------------------------------
    // Identity (name/person type, mobile/Telegram/KYC verification) lives in the independent contract
    // `IdentityRegistry.sol`, because its population (all network users) is separate from the validator population;
    // `ValidatorsBoard.voteFor` checks `IdentityRegistry.hasIdentity(...)` directly.
    //
    // `verifier` is used here for a single purpose: recording validator status decisions (recordActivation,
    // recordSuspension, recordRecovery, recordPreExitViolation). It is a completely separate key from `identityOracle` in
    // `IdentityRegistry.sol`: node liveness and identity verification are independent roles.
    // ------------------------------------------------------------------

    /// @notice Operational key trusted to record validator status decisions (recordActivation, recordSuspension,
    ///         recordRecovery, recordPreExitViolation). Rotated by ValidatorsBoard through setVerifier. The initial
    ///         value comes from SurAddresses.sol.
    address public verifier = SurAddresses.VERIFIER;

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    modifier onlyVerifier() {
        require(msg.sender == verifier, "ValidatorsRegistry: caller is not the verifier");
        _;
    }

    /// @notice Rotate the verifier key. Board-only — mirrors how distributionOracle is rotated
    ///         on BlockRewardDistributor (a routine operational-key rotation, not a security
    ///         parameter change).
    function setVerifier(address newVerifier) external onlyBoard {
        require(newVerifier != address(0), "ValidatorsRegistry: zero verifier address");
        emit VerifierUpdated(verifier, newVerifier);
        verifier = newVerifier;
    }

    // ------------------------------------------------------------------
    // GENESIS FILL-IN: the founding validator set. `activeValidators` is a dynamic array and `activeIndex` / `validators`
    // are mappings, so the initial state cannot be written as state-variable initialisers. The genesis tool either
    // simulates the seeding logic on a temporary local chain and copies the resulting storage into `alloc`, or writes the
    // storage slots directly (see "sur-contracts-deploy-notes.md" and
    // genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol). For each founding validator v:
    //   validators[v] = ValidatorInfo({ status: Active, lockedStake: 0, periodStartedAt: GENESIS_TIMESTAMP,
    //     pendingSlashEpoch: 0, demotedAt: 0, isPaidEntrant: false });
    //   activeIndex[v] = activeValidators.length + 1;  activeValidators.push(v);
    //   everActivated[v] = true;  activationSeq[v] = ++activationCount;
    //   paidValidatorCount is not incremented for founders.
    // ------------------------------------------------------------------
    // Active validator set, exposed via getValidators(). Removal is swap-and-pop through a 1-based index.
    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // Governed parameters (changeable only via full validator vote — see below)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Economic entry parameters: initial values below; changeable only by ValidatorsBoard (not a constructor argument and
    // not a full-validator vote). The initial entryThresholdBase is 500,000 Suren.
    // ------------------------------------------------------------------

    /// @notice Hard bounds and a shared cooldown for ValidatorsBoard's authority over the three economic entry parameters
    ///         (entryThresholdBase, growthFactorPerValidator, membershipFeeBps). The bounds close off extreme values (free
    ///         entry, impossibly steep growth, a fee of up to 100%); one cooldown shared by all three prevents several
    ///         rapid changes from combining into an extreme effect.
    uint256 public constant ENTRY_THRESHOLD_BASE_MIN = 100_000 ether;
    uint256 public constant ENTRY_THRESHOLD_BASE_MAX = 2_000_000 ether;
    uint256 public constant MEMBERSHIP_FEE_BPS_MIN = 100; // 1%
    uint256 public constant MEMBERSHIP_FEE_BPS_MAX = 1000; // 10%
    /// @dev Bounds are expressed as the doubling period they imply: the factor for a period p is 2^(1/p). Fastest
    ///      allowed: doubles every 20 paid validators. Slowest allowed: every 80.
    uint256 public constant GROWTH_FACTOR_MIN = 1_008701983790398976; // 2^(1/80), doubling every 80
    uint256 public constant GROWTH_FACTOR_MAX = 1_035264923841377536; // 2^(1/20), doubling every 20
    uint256 public constant ECONOMIC_PARAM_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastEconomicParamChangeTime;

    /// @notice Base stake required to request membership when there are 0 paid validators (the first person to call
    ///         requestMembership(), regardless of how many free genesis founders are active).
    uint256 public entryThresholdBase = 500_000 ether; // 500,000 Suren (18 decimals, like ETH)

    /// @notice The entry threshold grows continuously, compounding per additional paid validator:
    ///         current threshold = entryThresholdBase * growthFactorPerValidator^paidValidatorCount. Founders do not count
    ///         toward the exponent. The factor is fixed-point with 18 decimals; 1_017479692102686336 (~1.017480) multiplies
    ///         the threshold by 2 every 40 paid validators. The curve makes buying more than a third of the seats
    ///         exponentially, not linearly, expensive.
    uint256 public growthFactorPerValidator = 1_017479692102686336;

    /// @notice Fixed-point precision used by growthFactorPerValidator and _fixedPow (18 decimals,
    ///         like Suren/ETH itself). 1_000000000000000000 represents 1.0 (no growth).
    uint256 private constant FIXED_POINT_ONE = 1_000000000000000000;

    /// @notice Safety and gas cap: the paid-validator count is clamped to this value when computing the entry threshold,
    ///         so the exponent never grows without bound. The largest multiplier it allows depends on the current
    ///         growthFactorPerValidator, from 2^16 (slowest allowed growth) to 2^64 (fastest), far below any overflow
    ///         risk in the 18-decimal arithmetic used here.
    uint256 private constant MAX_GROWTH_VALIDATORS = 1280;

    /// @notice Membership fee, as a fraction of currentEntryThreshold(), paid in addition to the collateral and
    ///         non-refundable. It is forwarded to BlockRewardDistributor.receiveMembershipFee(), folded into the next
    ///         distribution epoch and paid pro rata by blocks to active validators (exempt from the ordinary-fee burn).
    ///         400 = 4% of the collateral.
    uint256 public membershipFeeBps = 400;

    /// @notice Maximum number of new membership requests allowed within entryWindowSeconds.
    uint256 public maxEntriesPerWindow = 1;
    uint256 public entryWindowSeconds = 86400; // 24 hours — at most 1 new validator/day

    uint256 public probationPeriod = 604800; // 1 week

    /// @notice Minimum time between a suspension and the recording of a recovery (48 hours initially).
    uint256 public recoveryPeriod = 172800;      // 48 hours
    uint256 public slashBps = 100;               // 1% — deliberately light: the entry threshold is kept low to broaden who
    // can afford to become a validator, so a heavy slash on that smaller collateral would punish an honest infrastructure
    // mistake too hard. 1% is a real consequence without being catastrophic for any collateral size.
    uint256 public exitCooldown = 604800;        // 1 week

    /// @notice A fixed time window (MASS_DEMOTION_WINDOW) during which suspensions are grouped. A suspension's slash is
    ///         not decided when the validator is suspended: once the window has closed, a single permissionless call
    ///         (resolveMassFailureCheck) decides, uniformly for every validator suspended in that window, whether the
    ///         final suspension count exceeded the mass-failure threshold. The outcome therefore depends on the pattern
    ///         across the whole window, never on which transaction landed first. Removal from the active set is never
    ///         delayed by this mechanism: a suspended validator leaves getValidators() immediately, which lets QBFT's
    ///         quorum shrink with the pool of live signers; only the slash decision waits.
    struct DemotionEpoch {
        uint256 startedAt;
        uint256 referenceCount; // active-validator count snapshotted once when the epoch begins; fixed for its whole lifetime
        uint256 demotionCount; // suspensions recorded in this epoch; grows only while the epoch is open
        bool resolved;
        bool wasMassFailure;
    }

    mapping(uint256 => DemotionEpoch) public demotionEpochs;
    uint256 public currentDemotionEpochId; // 0 means "no epoch opened yet"

    uint256 public constant MASS_DEMOTION_WINDOW = 1 hours;
    uint256 public constant MASS_DEMOTION_SLASH_PAUSE_BPS = 2000; // 20% — see resolveMassFailureCheck()

    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @dev Set by the genesis tool to the real genesis timestamp (not the block.timestamp of the machine that runs the
    ///      seeding simulation); see sur-contracts-deploy-notes.md.
    // rolling rate-limit window state
    uint256 public windowStart = 0;
    uint256 public entriesInWindow;

    // ------------------------------------------------------------------
    // Off-chain verification. The verifier checks every node's liveness off-chain (hourly) and records on-chain only
    // STATUS CHANGES: activation after probation, suspension, or recovery. Each decision carries the hash of the
    // off-chain evidence package that justified it (validator address, decision type and reason, time range checked,
    // the rules and threshold version in effect, timestamped check results, observation source, block-production and
    // peer-connection data, geo-detection result where it mattered, the verifier's signature, and for Activation and
    // Recovery the total and positive counts and the 95% ratio computation). The raw evidence is never stored on-chain:
    // it stays off-chain, encrypted, held by at least two custodians independent of the verifier operator, for 90 days
    // or until a case closes. The hash defends against a verifier changing its story after being challenged; it does
    // not prove the story was true from the start.
    //
    // Suspension is the only decision type that can lead to a slash, so it alone has the delivery / appeal / vote
    // machinery below. Activation and Recovery are purely positive and only need the evidence hash.
    //
    // Flow of a Suspension's slash decision:
    //   1. recordSuspension(): the validator leaves the active set immediately and unconditionally and is registered
    //      into the DemotionEpoch mass-failure window.
    //   2. Once that DemotionEpoch closes, resolveMassFailureCheck() (permissionless) runs first. A mass failure ends
    //      the case (SlashOutcome.ExemptMassFailure); otherwise the case moves to the delivery step.
    //   3. The validator can confirm at any time that it received the evidence package (confirmDelivery()). This proves
    //      delivery (deliveryProvenAt) and starts the 72-hour appeal-filing window. It is not an admission that the
    //      accusation is true.
    //   4. If the validator does not confirm within DELIVERY_DISPUTE_GRACE_PERIOD, anyone (typically the verifier) may
    //      call assertDeliveryDisputed(): the assembly then votes (voteOnDelivery()). This vote must resolve before any
    //      slash vote can be filed. If delivery was never genuinely made, the slash is voided
    //      (SlashOutcome.VoidedNoDelivery); the suspension itself stays.
    //   5. Once delivery is proven, the validator may fileAppeal() within 72 hours. The assembly then votes
    //      confirmSlash(): a simple majority of the validators that were active when the appeal was filed, excluding the
    //      subject, with a 7-day deadline. Without a majority by the deadline the slash is rejected, but the suspension
    //      is not reversed: returning to consensus still requires the recovery path.
    //   6. If no appeal is filed within the 72 hours, anyone may call executeUncontestedSlash().
    // ------------------------------------------------------------------

    enum DecisionType { Activation, Suspension, Recovery }
    enum DeliveryStatus { NotApplicable, Pending, Confirmed, Disputed }
    enum SlashOutcome { Undetermined, ExemptMassFailure, VoidedNoDelivery, Confirmed, RejectedByVote, RejectedNoQuorum, ExecutedUncontested }

    struct StatusDecision {
        address validator;
        DecisionType decisionType;
        uint256 decidedAt;
        bytes32 evidenceHash; // hash of the full off-chain evidence package — see the off-chain
        // verification note above for exactly what that package must contain.
        uint256 demotionEpochId; // only meaningful for Suspension — links to DemotionEpoch above
        DeliveryStatus delivery;
        uint256 deliveryProvenAt; // 0 until proven (by self-confirmation or a delivery-dispute vote)
        bool appealFiled;
        uint256 appealFiledAt;
        uint256 appealVotingDeadline;
        uint256 confirmVotes;
        uint256 requiredConfirmVotes; // snapshotted at filing time, from active validators EXCLUDING the subject
        SlashOutcome slashOutcome;
    }

    /// @notice Whether resolveMassFailureCheck() has run for this decision. It is set for every decision individually,
    ///         whether or not its epoch was a mass failure, and every step that moves a suspension's case forward
    ///         requires it. It is a separate mapping rather than a StatusDecision field to keep functions within the
    ///         compiler's stack-depth limit.
    mapping(uint256 => bool) private massFailureChecked;

    /// @notice Permanent, append-only record that this address was legitimately brought into the active set at least
    ///         once. It is set when the address is first activated (recordActivation and recordRecovery both go through
    ///         _activate()), never cleared, and survives withdrawStake(). BlockRewardDistributor reads it, not
    ///         isValidator(), to decide whether an address may still be paid for blocks it mined before exiting or being
    ///         suspended. It proves only "was once legitimately activated", not "was Active when block N was mined": that
    ///         timing check belongs to the RewardRouter.
    mapping(address => bool) public everActivated;

    /// @notice Set forever when an address calls requestExit(); requestMembership() refuses any such address. Returning
    ///         means a brand-new membership under a brand-new address: no vote, board seat or history carries over,
    ///         including for a zero-stake genesis founder.
    mapping(address => bool) public permanentlyExited;
    /// @notice Incremented each time this address exits voluntarily. ValidatorsBoard stamps the epoch when it seats an
    ///         address and treats a later mismatch as "no longer this membership", independent of permanentlyExited.
    mapping(address => uint256) public membershipEpoch;

    // ------------------------------------------------------------------
    // Exit handling, reserved amount and exact case binding
    // ------------------------------------------------------------------
    /// @notice The exact decision currently holding this validator's pending-slash lock (0 = none).
    mapping(address => uint256) public pendingSlashDecisionId;
    /// @notice Amount at stake for a case, fixed when the case is recorded (stake x slashBps at that moment). It is what
    ///         withdrawStake() reserves and what _executeSlash() takes (capped by the remaining stake).
    mapping(uint256 => uint256) public decisionSlashAmount;
    /// @notice Start time of the alleged violation for pre-exit cases (0 for ordinary suspensions). The evidence
    ///         package (hash on-chain) must show it; the assembly can review it through the normal appeal path.
    mapping(uint256 => uint256) public decisionViolationAt;
    /// @notice The validator's status at the moment it requested exit (only an Active validator can have
    ///         validation-duty violations to answer for).
    mapping(address => uint8) public statusBeforeExit;
    /// @notice How long after an exit request the Verifier may still file a case about conduct BEFORE the request.
    uint256 public constant PRE_EXIT_CLAIM_WINDOW = 72 hours;

    /// @notice The active set never drops below this size: the last active validator can neither be suspended nor exit.
    uint256 public constant MIN_ACTIVE_VALIDATORS = 1;

    /// @dev Gas forwarded to ValidatorsBoard.syncVoter from a status change. The call is best-effort: a failure is ignored,
    ///      and anyone can repair the board's counters later by calling syncVoter.
    uint256 internal constant BOARD_SYNC_GAS = 600_000;
    event PreExitCaseRecorded(uint256 indexed decisionId, address indexed validator, uint256 violationAt, uint256 exitRequestedAt, bytes32 evidenceHash);

    mapping(uint256 => StatusDecision) public statusDecisions;
    uint256 public statusDecisionCount;
    mapping(uint256 => mapping(address => bool)) private hasVotedOnSlash;

    /// @notice A separate, smaller vote used ONLY when a validator does not self-confirm
    ///         delivery within DELIVERY_DISPUTE_GRACE_PERIOD — resolves the narrow factual
    ///         question "was the evidence package genuinely made available," never the merits of
    ///         the suspension itself. At most one per decision (a second assertDeliveryDisputed()
    ///         call on the same decision after one is already open/resolved is rejected).
    struct DeliveryDispute {
        uint256 decisionId;
        uint256 filedAt;
        uint256 votingDeadline;
        uint256 votesConfirmingDelivery;
        uint256 requiredVotes; // snapshotted, from ALL active validators (the subject validator
        // is NOT excluded here — unlike the slash vote, this question isn't about their guilt,
        // it's about whether a package reached them, which they have every right to weigh in on).
        bool resolved;
        bool deliveryConfirmed;
    }

    mapping(uint256 => DeliveryDispute) public deliveryDisputes; // keyed by decisionId
    mapping(uint256 => mapping(address => bool)) private hasVotedOnDelivery;

    uint256 public constant APPEAL_FILING_WINDOW = 72 hours;
    uint256 public constant APPEAL_VOTING_PERIOD = 7 days;
    /// @dev How long a validator has to confirm delivery itself before anyone may force the question to a
    ///      delivery-dispute vote (7 days). It determines how long a case can stay unresolved.
    uint256 public constant DELIVERY_DISPUTE_GRACE_PERIOD = 7 days;
    uint256 public constant DELIVERY_DISPUTE_VOTING_PERIOD = 7 days;

    // ------------------------------------------------------------------
    // Events for the off-chain verification architecture
    // ------------------------------------------------------------------
    event StatusDecisionRecorded(uint256 indexed decisionId, address indexed validator, DecisionType decisionType, bytes32 evidenceHash);
    event DeliveryConfirmed(uint256 indexed decisionId, address indexed validator, uint256 provenAt);
    event DeliveryDisputeFiled(uint256 indexed decisionId, uint256 votingDeadline);
    event DeliveryDisputeVoted(uint256 indexed decisionId, address indexed voter, uint256 votesConfirming, uint256 required);
    event DeliveryDisputeResolved(uint256 indexed decisionId, bool deliveryConfirmed);
    event AppealFiled(uint256 indexed decisionId, uint256 votingDeadline);
    event SlashVoted(uint256 indexed decisionId, address indexed voter, uint256 votes, uint256 required);
    event SlashResolved(uint256 indexed decisionId, address indexed validator, SlashOutcome outcome, uint256 slashedAmount);

    bool private locked; // reentrancy guard

    // ------------------------------------------------------------------
    // Parameter governance (full validator vote) — everything EXCEPT the three economic entry
    // parameters above (those are ValidatorsBoard-governed; see ValidatorsBoard.sol).
    // ------------------------------------------------------------------

    enum ParamKey {
        MaxEntriesPerWindow,
        EntryWindowSeconds,
        ProbationPeriod,
        RecoveryPeriod,
        SlashBps,
        ExitCooldown
    }

    /// @dev `requiredVotes` and `expiresAt` are fixed when a proposal is created and never recomputed, so a proposal
    ///      cannot become executable merely because the active count later shrinks.
    struct ParamProposal {
        ParamKey key;
        uint256 newValue;
        uint256 votes;
        uint256 requiredVotes; // snapshotted at creation, never recomputed
        uint256 createdAt;
        uint256 expiresAt; // the proposal can no longer be voted on or executed after this
        bool executed;
        // statusNonce at creation: a voter must have been Active at exactly that point.
        uint256 createdAtNonce;
    }

    /// @notice How long a parameter-change proposal stays votable and executable; after that it must be proposed again
    ///         with a fresh electorate.
    uint256 public constant PARAM_PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    // ActiveCheckpoint: the ordered history of each validator's Active status. It snapshots the electorate of every
    // assembly proposal (here, in ValidatorsTreasury and in BlockRewardDistributor) without invalidating it on later joins
    // or exits. statusNonce increments on every transition into or out of Active and a checkpoint {nonce, active} is
    // appended. Genesis founders are seeded with the checkpoint {0, true}.
    struct ActiveCheckpoint {
        uint64 nonce;
        bool active;
    }
    uint256 public statusNonce;
    mapping(address => ActiveCheckpoint[]) private activeCheckpoints;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event MembershipRequested(address indexed validator, uint256 collateralAmount, uint256 feeAmount);
    event ValidatorActivated(address indexed validator);
    // ValidatorDemoted carries the DemotionEpoch id (the slash is decided later), so monitoring can find the eventual
    // SlashResolved event for the same epoch.
    event ValidatorDemoted(address indexed validator, uint256 pendingSlashEpoch);
    event ValidatorReactivated(address indexed validator);
    event ExitRequested(address indexed validator, uint256 cooldownEnd);
    event StakeWithdrawn(address indexed validator, uint256 amount);
    event ParameterChangeProposed(uint256 indexed id, ParamKey key, uint256 newValue, address indexed proposer);
    event ParameterChangeVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event ParameterChangeApplied(ParamKey key, uint256 newValue);
    event EconomicParamUpdatedByBoard(string paramName, uint256 oldValue, uint256 newValue);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(validators[msg.sender].status == Status.Active, "ValidatorsRegistry: caller is not an active validator");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "ValidatorsRegistry: caller is not the validators board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "ValidatorsRegistry: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // Besu QBFT contract-mode interface — signature is hardcoded in Besu, do not change.
    // ------------------------------------------------------------------
    function getValidators() external view returns (address[] memory) {
        return activeValidators;
    }

    /// @notice Was `who` Active at status point `nonce`? False if `who` has no history at or before `nonce`. Binary
    ///         search over the append-only checkpoints.
    function wasActiveAt(address who, uint256 nonce) public view returns (bool) {
        ActiveCheckpoint[] storage cps = activeCheckpoints[who];
        uint256 lo = 0;
        uint256 hi = cps.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (cps[mid].nonce <= nonce) lo = mid + 1;
            else hi = mid;
        }
        return lo == 0 ? false : cps[lo - 1].active;
    }

    function _recordActiveCheckpoint(address who, bool active) private {
        statusNonce++;
        activeCheckpoints[who].push(ActiveCheckpoint({nonce: uint64(statusNonce), active: active}));
    }

    /// @notice Payment-eligibility check used directly by BlockRewardDistributor.
    function isValidator(address who) external view returns (bool) {
        return validators[who].status == Status.Active;
    }

    function getActiveValidatorCount() public view returns (uint256) {
        return activeValidators.length;
    }

    // ------------------------------------------------------------------
    // Entry threshold / rate limiting
    // ------------------------------------------------------------------

    /// @notice Current stake required to request membership. Grows continuously (compounding
    ///         per additional PAID validator — see paidValidatorCount — not per discrete jump,
    ///         and NOT counting free genesis-seeded founders). Capped at MAX_GROWTH_VALIDATORS
    ///         worth of growth, to avoid overflow/unbounded gas.
    function currentEntryThreshold() public view returns (uint256) {
        uint256 n = paidValidatorCount;
        if (n > MAX_GROWTH_VALIDATORS) n = MAX_GROWTH_VALIDATORS;
        uint256 multiplier = _fixedPow(growthFactorPerValidator, n);
        return (entryThresholdBase * multiplier) / FIXED_POINT_ONE;
    }

    /// @dev Fixed-point (FIXED_POINT_ONE = 1e18) exponentiation by squaring: returns
    ///      base1e18^exponent, expressed in the same 1e18 fixed-point representation.
    ///      O(log2(exponent)) multiplications — cheap even for large exponents.
    function _fixedPow(uint256 base1e18, uint256 exponent) private pure returns (uint256 result1e18) {
        result1e18 = FIXED_POINT_ONE; // 1.0
        uint256 b = base1e18;
        uint256 e = exponent;
        while (e > 0) {
            if (e & 1 == 1) {
                result1e18 = (result1e18 * b) / FIXED_POINT_ONE;
            }
            b = (b * b) / FIXED_POINT_ONE;
            e >>= 1;
        }
    }

    /// @notice Current membership fee: a governed fraction of currentEntryThreshold(), paid on top of the collateral and
    ///         forwarded to BlockRewardDistributor (paid to active validators in the next epoch).
    function currentMembershipFee() public view returns (uint256) {
        return (currentEntryThreshold() * membershipFeeBps) / BPS_DENOMINATOR;
    }

    // ------------------------------------------------------------------
    // Economic entry parameter setters — ValidatorsBoard only (its own internal board majority
    // has already approved the change before calling these; see ValidatorsBoard.sol's
    // proposeSetEntryThresholdBase / proposeSetGrowthFactorPerValidator / proposeSetMembershipFeeBps).
    // ------------------------------------------------------------------
    function setEntryThresholdBase(uint256 newValue) external onlyBoard {
        require(
            newValue >= ENTRY_THRESHOLD_BASE_MIN && newValue <= ENTRY_THRESHOLD_BASE_MAX,
            "ValidatorsRegistry: entryThresholdBase outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("entryThresholdBase", entryThresholdBase, newValue);
        entryThresholdBase = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setGrowthFactorPerValidator(uint256 newValue) external onlyBoard {
        require(
            newValue >= GROWTH_FACTOR_MIN && newValue <= GROWTH_FACTOR_MAX,
            "ValidatorsRegistry: growthFactorPerValidator outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("growthFactorPerValidator", growthFactorPerValidator, newValue);
        growthFactorPerValidator = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(
            newValue >= MEMBERSHIP_FEE_BPS_MIN && newValue <= MEMBERSHIP_FEE_BPS_MAX,
            "ValidatorsRegistry: membershipFeeBps outside allowed bounds"
        );
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function _enforceRateLimit() private {
        if (block.timestamp >= windowStart + entryWindowSeconds) {
            windowStart = block.timestamp;
            entriesInWindow = 0;
        }
        require(entriesInWindow < maxEntriesPerWindow, "ValidatorsRegistry: entry rate limit reached");
        entriesInWindow++;
    }

    // ------------------------------------------------------------------
    // Membership request -> probation
    //
    // Payable: the caller sends native Suren in msg.value, which must equal the sum of two amounts:
    //   1. `threshold` (currentEntryThreshold()): kept here as refundable, slashable collateral.
    //   2. `fee` (currentMembershipFee()): forwarded to BlockRewardDistributor.
    // ------------------------------------------------------------------
    function requestMembership() external payable nonReentrant {
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");
        require(!permanentlyExited[msg.sender], "ValidatorsRegistry: this address has exited before and may not rejoin");

        uint256 threshold = currentEntryThreshold();
        uint256 fee = currentMembershipFee();
        require(msg.value == threshold + fee, "ValidatorsRegistry: incorrect payment amount");

        _enforceRateLimit();

        if (fee > 0) {
            DISTRIBUTOR.receiveMembershipFee{value: fee}();
        }
        // `threshold` intentionally stays in this contract's own native balance as locked
        // collateral — no transfer needed, it arrived with this same call via msg.value.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: threshold,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: true
        });
        paidValidatorCount++;

        emit MembershipRequested(msg.sender, threshold, fee);
    }

    // ------------------------------------------------------------------
    // Status decisions. Only the `verifier` records them, after checking the validator off-chain:
    //   - Probation / Demoted (recovery): whether the candidate's own node is up and synced.
    //   - Active: real block production (the `miner` field of recent blocks) over a recent window.
    // The method used is recorded off-chain in the evidence package behind each decision hash.
    // ------------------------------------------------------------------
    // Activation after probation — Verifier-reported, off-chain-verified (no dispute path: a
    // purely positive outcome nobody has a stake-losing reason to contest).
    // ------------------------------------------------------------------
    function recordActivation(address candidate, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[candidate];
        require(v.status == Status.Probation, "ValidatorsRegistry: not in probation");
        require(block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        _activate(candidate);
        decisionId = _recordDecision(candidate, DecisionType.Activation, evidenceHash, 0);
        _notifyBoard(candidate);
    }

    // ------------------------------------------------------------------
    // Recovery after a demotion's recoveryPeriod — same "no dispute path" reasoning as activation.
    // ------------------------------------------------------------------
    function recordRecovery(address validator, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        // A still-unresolved pendingSlashEpoch from the demotion being recovered from must be settled first, otherwise a later
        // re-demotion could overwrite it.
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: resolve the pending slash first");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        _activate(validator);
        decisionId = _recordDecision(validator, DecisionType.Recovery, evidenceHash, 0);
        emit ValidatorReactivated(validator);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // Suspension — Verifier-reported. Removal from the active set is IMMEDIATE and
    // UNCONDITIONAL (see the off-chain verification note above); only the eventual slash decision goes
    // through the mass-failure check, then the delivery/appeal/vote machinery below.
    // ------------------------------------------------------------------
    function recordSuspension(address validator, bytes32 evidenceHash) external onlyVerifier nonReentrant returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - suspension blocked");

        _removeFromActive(validator);
        _recordActiveCheckpoint(validator, false); // L04

        uint256 epochId = _recordDemotion(v, true); // slash decision deferred — see resolveMassFailureCheck()
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp; // recovery period starts now

        decisionId = _recordDecision(validator, DecisionType.Suspension, evidenceHash, epochId);
        emit ValidatorDemoted(validator, epochId);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // A case about conduct BEFORE an exit request. An exit request ends validation duty at once and starts the 1-week
    // withdrawal wait; for 72 hours the verifier may still file a case about earlier conduct. Inactivity AFTER the request
    // is never a violation. The verifier's bare claim is not enough: the evidence hash, the violation time and the normal
    // mass-failure exemption / delivery / appeal / assembly-vote machinery all apply.
    // ------------------------------------------------------------------
    function recordPreExitViolation(address validator, bytes32 evidenceHash, uint256 violationAt) external onlyVerifier nonReentrant returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Exiting, "ValidatorsRegistry: validator is not exiting");
        require(statusBeforeExit[validator] == uint8(Status.Active), "ValidatorsRegistry: had no validation duty when exiting");
        uint256 exitRequestedAt = v.periodStartedAt; // requestExit() stamps this
        require(block.timestamp <= exitRequestedAt + PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: pre-exit claim window closed");
        require(violationAt < exitRequestedAt, "ValidatorsRegistry: violation must precede the exit request");
        require(violationAt > v.demotedAt, "ValidatorsRegistry: violation predates the last suspension");
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: a case is already pending");

        uint256 epochId = _recordDemotion(v, false); // not removed from the active set just now (removed at exit request)
        decisionId = _recordDecision(validator, DecisionType.Suspension, evidenceHash, epochId);
        decisionViolationAt[decisionId] = violationAt;
        emit PreExitCaseRecorded(decisionId, validator, violationAt, exitRequestedAt, evidenceHash);
    }

    function _recordDecision(address validator, DecisionType dtype, bytes32 evidenceHash, uint256 demotionEpochId) private returns (uint256 id) {
        statusDecisionCount++;
        id = statusDecisionCount;
        statusDecisions[id] = StatusDecision({
            validator: validator,
            decisionType: dtype,
            decidedAt: block.timestamp,
            evidenceHash: evidenceHash,
            demotionEpochId: demotionEpochId,
            delivery: dtype == DecisionType.Suspension ? DeliveryStatus.Pending : DeliveryStatus.NotApplicable,
            deliveryProvenAt: 0,
            appealFiled: false,
            appealFiledAt: 0,
            appealVotingDeadline: 0,
            confirmVotes: 0,
            requiredConfirmVotes: 0,
            slashOutcome: SlashOutcome.Undetermined
        });
        if (dtype == DecisionType.Suspension) {
            pendingSlashDecisionId[validator] = id;
            decisionSlashAmount[id] = (validators[validator].lockedStake * slashBps) / BPS_DENOMINATOR;
        }
        emit StatusDecisionRecorded(id, validator, dtype, evidenceHash);
    }

    // ------------------------------------------------------------------
    // Records this suspension into the current (or a freshly opened) DemotionEpoch and marks the validator as having a
    // pending slash decision. It does not touch lockedStake or transfer anything, and it never touches active-set
    // membership. Called by recordSuspension() and recordPreExitViolation().
    // ------------------------------------------------------------------
    function _recordDemotion(ValidatorInfo storage v, bool validatorJustRemovedFromActive) private returns (uint256 epochId) {
        if (currentDemotionEpochId == 0 || block.timestamp >= demotionEpochs[currentDemotionEpochId].startedAt + MASS_DEMOTION_WINDOW) {
            currentDemotionEpochId++;
            DemotionEpoch storage fresh = demotionEpochs[currentDemotionEpochId];
            fresh.startedAt = block.timestamp;
            fresh.referenceCount = activeValidators.length + (validatorJustRemovedFromActive ? 1 : 0); // +1: the caller already removed this validator; snapshotted once per epoch
        }
        epochId = currentDemotionEpochId;
        demotionEpochs[epochId].demotionCount++;
        v.pendingSlashEpoch = epochId;
    }

    /// @notice Permissionless: anyone may call it once a validator's DemotionEpoch has closed. It is only the
    ///         mass-failure gate: if the exemption applies the case is closed here (ExemptMassFailure); otherwise the case
    ///         moves on to the delivery / appeal / vote machinery below.
    function resolveMassFailureCheck(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(!massFailureChecked[decisionId], "ValidatorsRegistry: already checked for this decision");
        DemotionEpoch storage epoch = demotionEpochs[d.demotionEpochId];
        require(block.timestamp >= epoch.startedAt + MASS_DEMOTION_WINDOW, "ValidatorsRegistry: demotion epoch not yet closed");

        if (!epoch.resolved) {
            epoch.resolved = true;
            epoch.wasMassFailure = epoch.demotionCount * BPS_DENOMINATOR > epoch.referenceCount * MASS_DEMOTION_SLASH_PAUSE_BPS;
        }

        // Set unconditionally for every decision individually, whether or not the epoch was a mass failure;
        // _massFailureResolved() checks exactly this flag. The shared computation (epoch.wasMassFailure) is not repeated.
        massFailureChecked[decisionId] = true;

        if (epoch.wasMassFailure) {
            d.slashOutcome = SlashOutcome.ExemptMassFailure;
            _clearPendingSlashIfCurrent(decisionId); // fully closed — no delivery/appeal ever needed
            emit SlashResolved(decisionId, d.validator, SlashOutcome.ExemptMassFailure, 0);
        }
        // If not a mass failure: d.delivery is already DeliveryStatus.Pending from _recordDecision, so nothing else
        // happens here. pendingSlashEpoch stays nonzero and keeps blocking withdrawStake() until the flow below resolves.
    }

    // ------------------------------------------------------------------
    // Delivery of the evidence package — the validator's own on-chain confirmation is the
    // primary proof. See the off-chain verification note above for the full rationale.
    // ------------------------------------------------------------------

    /// @notice The pending-slash lock lives on the VALIDATOR, so it is bound to the exact DECISION that created it
    ///         (`pendingSlashDecisionId`). A decision may clear the lock only while it is still the one holding it, so
    ///         resolving an old case can never wipe the lock of a newer case. `pendingSlashEpoch` is kept in step only for
    ///         the external getValidatorInfo() ABI.
    function _clearPendingSlashIfCurrent(uint256 decisionId) private {
        address who = statusDecisions[decisionId].validator;
        if (pendingSlashDecisionId[who] == decisionId) {
            pendingSlashDecisionId[who] = 0;
            validators[who].pendingSlashEpoch = 0;
        }
    }

    /// @notice True once resolveMassFailureCheck() has run for this decision. Every function that moves a suspension's
    ///         case forward (confirmDelivery, assertDeliveryDisputed, fileAppeal, executeUncontestedSlash) requires it
    ///         first, so the mass-failure exemption always takes precedence over any individual dispute.
    function _massFailureResolved(uint256 decisionId) private view returns (bool) {
        return massFailureChecked[decisionId];
    }

    /// @notice Confirms only that the evidence package was received, not that the accusation is true. Starts the
    ///         72-hour appeal-filing window (distinct from the appeal-voting period, which starts when an appeal is filed).
    function confirmDelivery(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(msg.sender == d.validator, "ValidatorsRegistry: only the subject validator may confirm delivery");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(d.delivery == DeliveryStatus.Pending || d.delivery == DeliveryStatus.Disputed, "ValidatorsRegistry: delivery already confirmed");

        d.delivery = DeliveryStatus.Confirmed;
        d.deliveryProvenAt = block.timestamp;
        // If a delivery dispute is open for this decision, the validator's own confirmation resolves it immediately and
        // consistently; leaving it open would let resolveDeliveryDisputeIfExpired() later overwrite this confirmation with
        // VoidedNoDelivery.
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        if (disp.filedAt != 0 && !disp.resolved) {
            disp.resolved = true;
            disp.deliveryConfirmed = true;
            emit DeliveryDisputeResolved(decisionId, true);
        }
        emit DeliveryConfirmed(decisionId, d.validator, block.timestamp);
    }

    /// @notice If the validator does not self-confirm within DELIVERY_DISPUTE_GRACE_PERIOD,
    ///         anyone (typically the Verifier) may force the question in front of the assembly
    ///         instead. This does NOT itself decide anything — it opens a dedicated
    ///         delivery-dispute vote (voteOnDelivery below) that must resolve BEFORE any
    ///         slash-confirmation vote can even be filed (per the user's explicit requirement
    ///         that the review authority decide delivery before addressing the merits).
    function assertDeliveryDisputed(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        // A case that already reached a final outcome (e.g. ExemptMassFailure) is never reopened: resolveMassFailureCheck()
        // leaves `delivery` at Pending even when it exempts the case.
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(d.delivery == DeliveryStatus.Pending, "ValidatorsRegistry: delivery not pending");
        require(block.timestamp >= d.decidedAt + DELIVERY_DISPUTE_GRACE_PERIOD, "ValidatorsRegistry: grace period not elapsed");
        require(deliveryDisputes[decisionId].filedAt == 0, "ValidatorsRegistry: delivery dispute already filed");

        d.delivery = DeliveryStatus.Disputed;
        uint256 votingDeadline = block.timestamp + DELIVERY_DISPUTE_VOTING_PERIOD;
        deliveryDisputes[decisionId] = DeliveryDispute({
            decisionId: decisionId,
            filedAt: block.timestamp,
            votingDeadline: votingDeadline,
            votesConfirmingDelivery: 0,
            requiredVotes: (getActiveValidatorCount() / 2) + 1, // snapshotted; full assembly. The subject is not excluded, but it is no longer Active, so it cannot vote.
            resolved: false,
            deliveryConfirmed: false
        });
        deliveryDisputeNonce[decisionId] = statusNonce;
        emit DeliveryDisputeFiled(decisionId, votingDeadline);
    }

    /// @notice Assembly vote on the narrow factual question "was the evidence package genuinely
    ///         made available to this validator" — never the merits of the suspension itself.
    function voteOnDelivery(uint256 decisionId, bool confirmsDelivery) external onlyActiveValidator {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        require(disp.filedAt != 0, "ValidatorsRegistry: no delivery dispute for this decision");
        require(!disp.resolved, "ValidatorsRegistry: delivery dispute already resolved");
        require(block.timestamp <= disp.votingDeadline, "ValidatorsRegistry: delivery-dispute voting period has ended");
        require(wasActiveAt(msg.sender, deliveryDisputeNonce[decisionId]), "ValidatorsRegistry: not eligible - not Active when this dispute was filed");
        require(!hasVotedOnDelivery[decisionId][msg.sender], "ValidatorsRegistry: already voted");
        hasVotedOnDelivery[decisionId][msg.sender] = true;

        if (confirmsDelivery) {
            disp.votesConfirmingDelivery++;
        }
        emit DeliveryDisputeVoted(decisionId, msg.sender, disp.votesConfirmingDelivery, disp.requiredVotes);

        if (disp.votesConfirmingDelivery >= disp.requiredVotes) {
            _resolveDeliveryDispute(decisionId, true);
        }
    }

    /// @notice Permissionless — if the delivery-dispute voting period expires without reaching
    ///         quorum to CONFIRM delivery, delivery is treated as never proven (same
    ///         burden-of-proof default used everywhere else in this mechanism: the party
    ///         seeking the penalty bears the risk of an inconclusive vote).
    function resolveDeliveryDisputeIfExpired(uint256 decisionId) external {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        require(disp.filedAt != 0, "ValidatorsRegistry: no delivery dispute for this decision");
        require(!disp.resolved, "ValidatorsRegistry: already resolved");
        require(block.timestamp > disp.votingDeadline, "ValidatorsRegistry: voting period not yet over");
        _resolveDeliveryDispute(decisionId, false);
    }

    function _resolveDeliveryDispute(uint256 decisionId, bool confirmed) private {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        disp.resolved = true;
        disp.deliveryConfirmed = confirmed;
        StatusDecision storage d = statusDecisions[decisionId];
        // If the case already reached a final outcome by another route, this dispute only closes its own record; it never
        // overwrites the outcome or touches the validator's lock.
        if (d.slashOutcome != SlashOutcome.Undetermined) {
            emit DeliveryDisputeResolved(decisionId, confirmed);
            return;
        }
        if (confirmed) {
            d.delivery = DeliveryStatus.Confirmed;
            d.deliveryProvenAt = block.timestamp;
        } else {
            // A delivery dispute lost by the accuser voids only the slash. It does not return the validator to consensus: that
            // still requires the normal recovery path.
            d.slashOutcome = SlashOutcome.VoidedNoDelivery;
            _clearPendingSlashIfCurrent(decisionId);
            emit SlashResolved(decisionId, d.validator, SlashOutcome.VoidedNoDelivery, 0);
        }
        emit DeliveryDisputeResolved(decisionId, confirmed);
    }

    // ------------------------------------------------------------------
    // Appeal filing and the slash-confirmation vote
    // ------------------------------------------------------------------

    /// @notice Only the subject validator (the one with the most direct interest, and the only
    ///         one this mechanism is designed to protect) may file — within 72 hours of PROVEN
    ///         delivery, not of the Verifier's claim of having sent it.
    function fileAppeal(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(msg.sender == d.validator, "ValidatorsRegistry: only the subject validator may file an appeal");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.delivery == DeliveryStatus.Confirmed, "ValidatorsRegistry: delivery not proven yet");
        require(!d.appealFiled, "ValidatorsRegistry: appeal already filed");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(block.timestamp <= d.deliveryProvenAt + APPEAL_FILING_WINDOW, "ValidatorsRegistry: appeal filing window has passed");

        d.appealFiled = true;
        appealNonce[decisionId] = statusNonce;
        d.appealFiledAt = block.timestamp;
        d.appealVotingDeadline = block.timestamp + APPEAL_VOTING_PERIOD;
        // Required votes: majority of active validators — the subject validator is not
        // separately excluded because they are already Demoted (not Active), so
        // onlyActiveValidator below already keeps them out.
        d.requiredConfirmVotes = (getActiveValidatorCount() / 2) + 1;
        emit AppealFiled(decisionId, d.appealVotingDeadline);
    }

    /// @notice Assembly vote to CONFIRM the slash — only reached if an appeal was actually
    ///         filed. Simple majority, snapshotted at filing time, hard 7-day deadline separate
    ///         from the 72-hour filing window above.
    function confirmSlash(uint256 decisionId) external onlyActiveValidator nonReentrant {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.appealFiled, "ValidatorsRegistry: no appeal filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp <= d.appealVotingDeadline, "ValidatorsRegistry: voting period has ended");
        require(wasActiveAt(msg.sender, appealNonce[decisionId]), "ValidatorsRegistry: not eligible - not Active when the appeal was filed");
        require(!hasVotedOnSlash[decisionId][msg.sender], "ValidatorsRegistry: already voted");

        hasVotedOnSlash[decisionId][msg.sender] = true;
        d.confirmVotes++;
        emit SlashVoted(decisionId, msg.sender, d.confirmVotes, d.requiredConfirmVotes);

        if (d.confirmVotes >= d.requiredConfirmVotes) {
            _executeSlash(decisionId, SlashOutcome.Confirmed);
        }
    }

    /// @notice Permissionless — if the appeal-voting deadline passes without reaching quorum to
    ///         confirm, the slash is REJECTED (burden of proof sits with whoever wants to
    ///         slash). The consensus-suspension itself is untouched — returning to Active still
    ///         requires the independent recordRecovery() path above, regardless of this outcome.
    function resolveAppealIfExpired(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.appealFiled, "ValidatorsRegistry: no appeal filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp > d.appealVotingDeadline, "ValidatorsRegistry: voting period not yet over");
        d.slashOutcome = SlashOutcome.RejectedNoQuorum;
        _clearPendingSlashIfCurrent(decisionId);
        emit SlashResolved(decisionId, d.validator, SlashOutcome.RejectedNoQuorum, 0);
    }

    /// @notice Permissionless — if delivery was proven and 72 hours passed with no appeal ever
    ///         filed, the slash executes uncontested (an unchallenged accusation still results
    ///         in the penalty, exactly as an uncontested civil claim would).
    function executeUncontestedSlash(uint256 decisionId) external nonReentrant {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.delivery == DeliveryStatus.Confirmed, "ValidatorsRegistry: delivery not proven yet");
        require(!d.appealFiled, "ValidatorsRegistry: an appeal was filed for this decision");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: already resolved");
        require(block.timestamp > d.deliveryProvenAt + APPEAL_FILING_WINDOW, "ValidatorsRegistry: appeal filing window still open");

        _executeSlash(decisionId, SlashOutcome.ExecutedUncontested);
    }

    function _executeSlash(uint256 decisionId, SlashOutcome outcome) private {
        StatusDecision storage d = statusDecisions[decisionId];
        d.slashOutcome = outcome;
        ValidatorInfo storage v = validators[d.validator];
        _clearPendingSlashIfCurrent(decisionId);

        uint256 slashAmount = decisionSlashAmount[decisionId]; // fixed when the case was recorded (P04)
        if (slashAmount > v.lockedStake) slashAmount = v.lockedStake;
        v.lockedStake -= slashAmount;
        if (slashAmount > 0) {
            (bool success, ) = TREASURY.call{value: slashAmount}("");
            require(success, "ValidatorsRegistry: slash transfer failed");
        }
        emit SlashResolved(decisionId, d.validator, outcome, slashAmount);
    }

    function _activate(address who) private {
        ValidatorInfo storage v = validators[who];
        v.status = Status.Active;
        activeIndex[who] = activeValidators.length + 1;
        activeValidators.push(who);
        if (!everActivated[who]) {
            everActivated[who] = true;
            activationSeq[who] = ++activationCount;
        }
        _recordActiveCheckpoint(who, true); // L04
        emit ValidatorActivated(who);
    }

    /// @dev Tells ValidatorsBoard that `who`'s status changed so it can add or remove that validator's votes. The call is
    ///      best-effort with a gas cap: a failure never blocks the status change.
    function _notifyBoard(address who) private {
        (bool ok, ) = SurAddresses.VALIDATORS_BOARD.call{gas: BOARD_SYNC_GAS}(
            abi.encodeWithSelector(IValidatorsBoardSync.syncVoter.selector, who)
        );
        ok; // intentionally ignored
    }

    function _removeFromActive(address who) private {
        uint256 idx = activeIndex[who]; // 1-based
        require(idx != 0, "ValidatorsRegistry: not in active set");
        uint256 lastIdx = activeValidators.length; // 1-based last position

        if (idx != lastIdx) {
            address lastAddr = activeValidators[lastIdx - 1];
            activeValidators[idx - 1] = lastAddr;
            activeIndex[lastAddr] = idx;
        }
        activeValidators.pop();
        delete activeIndex[who];
    }

    // ------------------------------------------------------------------
    // Voluntary exit
    // ------------------------------------------------------------------
    function requestExit() external {
        ValidatorInfo storage v = validators[msg.sender];
        require(
            v.status == Status.Active || v.status == Status.Probation || v.status == Status.Demoted,
            "ValidatorsRegistry: nothing to exit"
        );

        if (v.status == Status.Active) {
            require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - exit blocked");
            // An exit request ends validation duty immediately: removal from the active set (and so from the QBFT validator set
            // and from board authority). It does not erase accountability: for PRE_EXIT_CLAIM_WINDOW (72 h) the verifier can still
            // file a case about earlier conduct (recordPreExitViolation), and the amount at stake stays reserved by
            // withdrawStake() until any such case is settled.
            _removeFromActive(msg.sender);
            _recordActiveCheckpoint(msg.sender, false); // L04
        }

        // A paid entrant leaving frees its slot in the growth curve. Founders (isPaidEntrant == false) never incremented the
        // counter, so they never decrement it.
        if (v.isPaidEntrant) {
            paidValidatorCount--;
        }

        statusBeforeExit[msg.sender] = uint8(v.status); // read BEFORE the status changes below
        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;
        // From this moment the membership's board authority is over: permanentlyExited blocks the address from registering
        // again and membershipEpoch invalidates any board seat stamped with the old epoch.
        permanentlyExited[msg.sender] = true;
        membershipEpoch[msg.sender]++;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
        _notifyBoard(msg.sender);
    }

    /// @notice Withdrawal after exitCooldown. If no case is pending the whole stake is paid. If a case is pending, only
    ///         the amount at stake (fixed when the case was recorded) stays reserved; the rest is paid now, and the reserved
    ///         remainder can be withdrawn by calling again once the case is settled (after any slash).
    function withdrawStake() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Exiting, "ValidatorsRegistry: not exiting");
        require(block.timestamp >= v.periodStartedAt + exitCooldown, "ValidatorsRegistry: exit cooldown not elapsed");

        uint256 reserved = 0;
        if (v.pendingSlashEpoch != 0) {
            reserved = decisionSlashAmount[pendingSlashDecisionId[msg.sender]];
            if (reserved > v.lockedStake) reserved = v.lockedStake;
        }
        uint256 amount = v.lockedStake - reserved;
        v.lockedStake = reserved;
        if (v.pendingSlashEpoch == 0) {
            delete validators[msg.sender];
            delete statusBeforeExit[msg.sender];
        }

        if (amount > 0) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ValidatorsRegistry: withdraw transfer failed");
        }

        emit StakeWithdrawn(msg.sender, amount);
    }

    // ------------------------------------------------------------------
    // Parameter governance — full active-validator majority vote
    // ------------------------------------------------------------------
    function proposeParameterChange(ParamKey key, uint256 newValue) external onlyActiveValidator returns (uint256 id) {
        // recoveryPeriod must stay strictly longer than MASS_DEMOTION_WINDOW: _clearPendingSlashIfCurrent() identifies a case
        // by its demotion epoch, which is unambiguous only if one validator can never be suspended twice inside one epoch
        // (suspend, recover, suspend). Validated at proposal time (so an invalid proposal can neither be created nor jam its own
        // final vote) and again in _applyParam().
        if (key == ParamKey.RecoveryPeriod) {
            require(newValue > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
        } else if (key == ParamKey.ExitCooldown) {
            require(newValue > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
        }
        paramProposalCount++;
        id = paramProposalCount;
        paramProposals[id] = ParamProposal({
            key: key,
            newValue: newValue,
            votes: 0,
            requiredVotes: (getActiveValidatorCount() / 2) + 1, // frozen now, see struct doc comment
            createdAt: block.timestamp,
            expiresAt: block.timestamp + PARAM_PROPOSAL_EXPIRY,
            executed: false,
            createdAtNonce: statusNonce
        });
        emit ParameterChangeProposed(id, key, newValue, msg.sender);
        _voteParam(id, msg.sender);
    }

    function voteParameterChange(uint256 id) external onlyActiveValidator {
        _voteParam(id, msg.sender);
    }

    function _voteParam(uint256 id, address voter) private {
        ParamProposal storage p = paramProposals[id];
        require(p.createdAt != 0, "ValidatorsRegistry: proposal not found");
        require(!p.executed, "ValidatorsRegistry: already executed");
        require(block.timestamp <= p.expiresAt, "ValidatorsRegistry: proposal has expired");
        require(!paramHasVoted[id][voter], "ValidatorsRegistry: already voted");
        // The voter must have been Active when the proposal was created (electorate snapshot) and be Active now
        // (onlyActiveValidator). A temporary suspension does not remove a voter from the original electorate; it only blocks
        // voting while suspended.
        require(wasActiveAt(voter, p.createdAtNonce), "ValidatorsRegistry: not eligible - not Active when this proposal was created");

        paramHasVoted[id][voter] = true;
        p.votes++;

        emit ParameterChangeVoted(id, voter, p.votes, p.requiredVotes);

        if (p.votes >= p.requiredVotes) {
            p.executed = true;
            _applyParam(p.key, p.newValue);
        }
    }

    function _applyParam(ParamKey key, uint256 value) private {
        if (key == ParamKey.MaxEntriesPerWindow) {
            maxEntriesPerWindow = value;
        } else if (key == ParamKey.EntryWindowSeconds) {
            entryWindowSeconds = value;
        } else if (key == ParamKey.ProbationPeriod) {
            probationPeriod = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            require(value > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
            recoveryPeriod = value;
        } else if (key == ParamKey.SlashBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: slashBps too high");
            slashBps = value;
        } else if (key == ParamKey.ExitCooldown) {
            require(value > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
            exitCooldown = value;
        }
        emit ParameterChangeApplied(key, value);
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------
    /// @notice Returns 6 outputs in this exact order: status, lockedStake, periodStartedAt, demotedAt, pendingSlashEpoch,
    ///         isPaidEntrant. Any external interface that declares this function (for example the copy in
    ///         ValidatorsBoard.sol) must match the order and count, since Solidity decodes external call results
    ///         positionally, not by name.
    function getValidatorInfo(address who) external view returns (
        Status status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
    ) {
        ValidatorInfo storage v = validators[who];
        return (
            v.status,
            v.lockedStake,
            v.periodStartedAt,
            v.demotedAt,
            v.pendingSlashEpoch,
            v.isPaidEntrant
        );
    }

    function requiredVotesNow() external view returns (uint256) {
        return (getActiveValidatorCount() / 2) + 1;
    }

    // ------------------------------------------------------------------
    // Reject any plain native-currency transfer that isn't part of requestMembership() — this
    // contract's balance must always exactly equal the sum of locked collateral amounts, with
    // no stray, unaccounted-for funds.
    // ------------------------------------------------------------------
    receive() external payable {
        revert("ValidatorsRegistry: use requestMembership() to send funds");
    }

    // ------------------------------------------------------------------
    // Additional state. These variables are declared last so that every earlier storage slot (and therefore the genesis
    // seed helper's layout) stays where it is.
    // ------------------------------------------------------------------

    /// @notice Number of addresses that have ever been activated; the next first activation receives this value + 1.
    uint256 public activationCount;

    /// @notice Order of first activation (1 = oldest; founders are numbered in genesis order; 0 = never activated).
    ///         ValidatorsBoard uses it to break ties between candidates with equal votes: the older validator wins.
    mapping(address => uint256) public activationSeq;

    /// @notice statusNonce when a delivery dispute was filed, per decision: only validators that were Active then may vote on it.
    mapping(uint256 => uint256) public deliveryDisputeNonce;

    /// @notice statusNonce when an appeal was filed, per decision: only validators that were Active then may vote on the slash.
    mapping(uint256 => uint256) public appealNonce;
}
