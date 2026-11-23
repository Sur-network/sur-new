// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IBlockRewardDistributor {
    function receiveMembershipFee() external payable;
    function migrateClaimable(address from, address to) external; // seat migration after a lost owner key: moves what is owed to the old owner
}

interface IValidatorsBoardSync {
    function syncVoter(address voter) external;
    function onSeatMigrated(address oldOwner, address newOwner) external; // seat migration: REQUIRED call (a failure reverts the migration); the board seat and election votes follow the person to the new address
}

interface IValidatorSeatNFT {
    function mintSeat(address to) external returns (uint256);
    function burnSeat(address owner) external;
    function reassignSeat(address from, address to) external returns (uint256 seatId); // seat migration: moves the token, no hook
    function ownerOf(uint256 tokenId) external view returns (address); // reverts for a token that does not exist
}

interface IBoardAuthority {
    function hasBoardAuthority(address who) external view returns (bool);
}

interface IIdentityFullyVerified {
    function isFullyVerified(address who) external view returns (bool);
    function migratedTo(address who) external view returns (address); // non-zero: the identity was migrated (old address burned) to that address
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
///           - ECONOMIC ENTRY PARAMETERS (entryCollateral, membershipFeeBps) are changed
///             only by ValidatorsBoard's internal vote.
///           - THE REMAINING PARAMETERS (entry window length, recovery period, exit cooldown) require a
///             majority of the validators that were Active when the proposal was created
///             (proposeParameterChange / voteParameterChange). The maximum of one paid entry per window, the 1-week probation and the
///             1% slash are FIXED constants (owner decision) and cannot be changed by any vote.
///
///         MEMBERSHIP PAYMENT: a new validator pays two amounts in native currency (Suren) with requestMembership(operator, agreementHash)
///         (agreementHash = the hash of the validators' agreement it signed beforehand; see the note above requestMembership):
///           - COLLATERAL (= currentEntryThreshold()): locked here, refundable on exit, slashable.
///           - MEMBERSHIP FEE (= currentMembershipFee(), a governed percentage of the collateral): forwarded to
///             BlockRewardDistributor and paid pro rata by blocks to the validators active in the next epoch, exempt
///             from the ordinary-fee burn. A slashed portion of the collateral goes to ValidatorsTreasury.
///
///         BOARD SYNCHRONISATION: whenever a validator's active status changes, this contract calls
///         `ValidatorsBoard.syncVoter(validator)` so the board's vote counters follow the active set. The call is
///         best-effort and cannot block a status change.
///
///         One call to the board is NOT best-effort: `migrateSeat` calls `ValidatorsBoard.onSeatMigrated(old, new)` and reverts if that
///         call fails, because a lost board seat or lost election votes would otherwise go unnoticed. A seat SALE never calls it.
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
    ///         parameters below (entryCollateral, membershipFeeBps).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    // ------------------------------------------------------------------
    // Validator state
    // ------------------------------------------------------------------

    /// @dev RemovedInRecovery (v2.5, appended so earlier values keep their encoding): removed from the validator list after
    ///      shutting down their node during a network recovery. Not a penalty: collateral is locked until exitAllowedAt.
    ///      SelfSuspended (v2.5, appended): voluntary, free suspension by the owner; no rewards, no votes, out of getValidators().
    enum Status { None, Probation, Active, Demoted, Exiting, RemovedInRecovery, SelfSuspended }

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
    address[] internal activeValidators;
    mapping(address => uint256) internal activeIndex;

    // ------------------------------------------------------------------
    // Governed parameters (changeable only via full validator vote — see below)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Economic entry parameters: initial values below; changeable only by ValidatorsBoard (not a constructor argument and
    // not a full-validator vote). The initial entryCollateral is 500,000 Suren.
    // ------------------------------------------------------------------

    /// @notice v2.5: the entry collateral is FIXED for every paying entrant (the v2.2 growth curve with the number of paid
    ///         validators is gone). Only ValidatorsBoard (3 of 5) can change it and the membership fee, within hard bounds:
    ///         each change at most +-10% relative to the current value, collateral between 100,000 and 2,000,000 Suren, fee
    ///         between 1% and 10% of the collateral, and one shared 180-day timer between any two changes. A change affects
    ///         only later entrants.
    uint256 public constant ENTRY_COLLATERAL_MIN = 100_000 ether;
    uint256 public constant ENTRY_COLLATERAL_MAX = 2_000_000 ether;
    uint256 public constant MEMBERSHIP_FEE_BPS_MIN = 100; // 1%
    uint256 public constant MEMBERSHIP_FEE_BPS_MAX = 1000; // 10%
    uint256 public constant ECONOMIC_PARAM_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastEconomicParamChangeTime;

    /// @notice Collateral every paying entrant locks here (refundable on exit, slashable). Initial value 500,000 Suren.
    uint256 public entryCollateral = 500_000 ether;

    /// @notice Membership fee as a fraction of the collateral, paid on top of it and non-refundable. It is forwarded to
    ///         BlockRewardDistributor.receiveMembershipFee(), folded into the next distribution epoch and paid pro rata by
    ///         blocks to active validators (exempt from the ordinary-fee burn). 400 = 4% of the collateral.
    uint256 public membershipFeeBps = 400;


    /// @notice FIXED (owner decision; no longer a parameter, no vote can change it): at most ONE new paid membership per entry window.
    ///         It is counted when the Verifier ACTIVATES a paying entrant (recordActivation), not when the membership is requested.
    ///         Kept as a constant under the old getter name so the ABI getter and the genesis-builder checks stay valid.
    uint256 public constant maxEntriesPerWindow = 1;
    /// @notice The entry window: at most one paid activation per window. The only entry parameter the validators can still change
    ///         (1..30 days, +-1 day per change, 6 months between changes, none in the first 6 months).
    uint256 public entryWindowSeconds = 7 days; // v2.5: at most one new paying validator per week

    /// @notice FIXED (owner decision): the minimum probation of a paying entrant before activation, 1 week. A constant under the old getter name.
    uint256 public constant probationPeriod = 7 days;

    /// @notice Minimum time between a suspension and the recording of a recovery (48 hours initially).
    uint256 public recoveryPeriod = 172800;      // 48 hours
    /// @notice FIXED (owner decision; no vote can change it): the slash is 1% (100 bps) of the locked collateral. Deliberately light: the
    ///         entry threshold is kept low to broaden who can afford to become a validator, so a heavy slash on that smaller collateral
    ///         would punish an honest infrastructure mistake too hard. 1% is a real consequence without being catastrophic for any
    ///         collateral size. A constant under the old getter name.
    uint256 public constant slashBps = 100;
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
    // entry window state: the time of the last PAID activation (0 = none yet). Lottery winners and founders are exempt and never set it.
    uint256 public lastPaidActivationAt;

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

    enum DecisionType { Activation, Suspension, Recovery, Resume }
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

    /// @dev The ORDER is part of the ABI and is not changed. MaxEntriesPerWindow (0), ProbationPeriod (2) and SlashBps (4) are FIXED by owner
    ///      decision and kept only so the numbering of the other keys stays: they are refused when proposed and when applied.
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
    mapping(address => ActiveCheckpoint[]) internal activeCheckpoints;

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
    /// @notice Operator (node) keys of the Active validators — what Besu reads as the QBFT validator set.
    function getValidators() external view returns (address[] memory out) {
        out = new address[](activeValidators.length);
        for (uint256 i = 0; i < out.length; i++) out[i] = operatorOf[activeValidators[i]];
    }

    /// @notice Owner addresses of the Active validators.
    function getActiveOwners() external view returns (address[] memory) {
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
    // Entry threshold / entry window
    // ------------------------------------------------------------------

    /// @notice Collateral needed to request membership NOW (fixed; see entryCollateral).
    function currentEntryThreshold() public view returns (uint256) {
        return entryCollateral;
    }

    /// @notice Current membership fee = entryCollateral * membershipFeeBps / 10000, paid on top of the collateral.
    function currentMembershipFee() public view returns (uint256) {
        return (entryCollateral * membershipFeeBps) / BPS_DENOMINATOR;
    }

    // ------------------------------------------------------------------
    // Economic entry parameter setters — ValidatorsBoard only (3 of 5 already approved the change)
    // ------------------------------------------------------------------
    function setEntryCollateral(uint256 newValue) external onlyBoard {
        require(newValue >= ENTRY_COLLATERAL_MIN && newValue <= ENTRY_COLLATERAL_MAX, "ValidatorsRegistry: entryCollateral outside allowed bounds");
        _requireWithinTenPercent(entryCollateral, newValue);
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("entryCollateral", entryCollateral, newValue);
        entryCollateral = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(newValue >= MEMBERSHIP_FEE_BPS_MIN && newValue <= MEMBERSHIP_FEE_BPS_MAX, "ValidatorsRegistry: membershipFeeBps outside allowed bounds");
        _requireWithinTenPercent(membershipFeeBps, newValue);
        require(
            block.timestamp >= lastEconomicParamChangeTime + ECONOMIC_PARAM_CHANGE_MIN_INTERVAL,
            "ValidatorsRegistry: too soon since the last economic-parameter change"
        );
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
        lastEconomicParamChangeTime = block.timestamp;
    }

    /// @dev Each change is at most +-10% relative to the current value.
    function _requireWithinTenPercent(uint256 current, uint256 proposed) private pure {
        require(proposed * 10 >= current * 9 && proposed * 10 <= current * 11, "ValidatorsRegistry: change exceeds +-10%");
    }

    /// @dev The entry window rule (owner decision): at most ONE new paid membership per entry window, counted at ACTIVATION. A paying entrant
    ///      may request membership at any time and waits in Probation; the Verifier's recordActivation is refused while the window is used
    ///      (the last paid activation is less than entryWindowSeconds ago). With the fixed maximum of one, "per window" is exactly
    ///      "at least entryWindowSeconds after the previous paid activation". The first paid activation is never delayed.
    function _enforceEntryWindow() private {
        require(
            lastPaidActivationAt == 0 || block.timestamp >= lastPaidActivationAt + entryWindowSeconds,
            "ValidatorsRegistry: entry window used - only one new paid validator per window"
        );
        lastPaidActivationAt = block.timestamp;
    }

    /// @notice Earliest time the Verifier can activate the next paying entrant (0 = no paid activation yet, so any time after probation).
    ///         Not a promise: the probation period of the candidate still applies.
    function nextPaidActivationAllowedAt() external view returns (uint256) {
        return lastPaidActivationAt == 0 ? 0 : lastPaidActivationAt + entryWindowSeconds;
    }

    // ------------------------------------------------------------------
    // Membership request -> probation
    //
    // Payable: the caller sends native Suren in msg.value, which must equal the sum of two amounts:
    //   1. `threshold` (currentEntryThreshold()): kept here as refundable, slashable collateral.
    //   2. `fee` (currentMembershipFee()): forwarded to BlockRewardDistributor.
    //
    // The validators' agreement (owner decision 2026-11-23): the applicant signs it electronically with the Foundation BEFORE requesting
    // membership (the Foundation countersigns afterwards; the signed text and both signatures live in an off-chain archive). The request
    // carries the hash of the signed agreement text, which is stored as the seat's agreement hash (seatAgreementHash) and emitted
    // (EntryAgreementRecorded). The chain cannot check that the document behind the hash exists or is signed: the Verifier checks the
    // off-chain archive against this hash before it activates the entrant.
    // ------------------------------------------------------------------
    /// @notice Direct entry: the caller (a plain wallet) pays collateral + fee, claims `operator` as its node key and enters Probation
    ///         with a new seat NFT. `agreementHash` is the hash of the agreement text the caller signed with the Foundation before
    ///         requesting (non-zero, or the call reverts); it is recorded as the seat's agreement hash (`seatAgreementHash(seatId)`) and
    ///         emitted in EntryAgreementRecorded. Lottery winners (enterAsLotteryWinner) and genesis founders take no agreement hash here:
    ///         their agreement is checked by the Verifier in the off-chain archive before activation and is not recorded on-chain at entry.
    function requestMembership(address operator, bytes32 agreementHash) external payable nonReentrant {
        require(msg.sender.code.length == 0 && msg.sender == tx.origin, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12
        require(agreementHash != bytes32(0), "ValidatorsRegistry: empty agreement hash");
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");
        require(!permanentlyExited[msg.sender], "ValidatorsRegistry: this address has exited before and may not rejoin");
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(msg.sender), "ValidatorsRegistry: identity not fully verified");
        _claimOperator(msg.sender, operator);

        uint256 collateral = entryCollateral;
        uint256 fee = currentMembershipFee();
        require(msg.value == collateral + fee, "ValidatorsRegistry: incorrect payment amount");

        if (fee > 0) {
            DISTRIBUTOR.receiveMembershipFee{value: fee}();
        }
        // `collateral` intentionally stays in this contract's own native balance as locked collateral.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: collateral,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: true
        });
        paidValidatorCount++;
        uint256 seatId = IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).mintSeat(msg.sender);
        seatAgreementHash[seatId] = agreementHash;

        emit MembershipRequested(msg.sender, collateral, fee);
        emit EntryAgreementRecorded(msg.sender, seatId, agreementHash);
    }

    // ------------------------------------------------------------------
    // v2.5: two keys per validator. The OWNER holds rewards, collateral, votes, identity and the seat; the OPERATOR is only
    // the node key that signs blocks. getValidators() returns operator keys.
    // ------------------------------------------------------------------
    /// @notice The owner whose operator key this is NOW. Once an address has been an operator it is never freed for someone
    ///         else, so a node-key swap by the same owner keeps old keys mapped to that owner. BUT a seat transfer re-points
    ///         the operator key to the buyer, so this mapping alone does NOT tell who owned the key at an earlier block:
    ///         the RewardRouter must replay SeatTransferred, OperatorSet and OperatorChangeConfirmed events to attribute
    ///         each block to the owner at that block (owner decision 2026-11-19).
    mapping(address => address) public ownerOfOperator;
    /// @notice The CURRENT operator (node key) of an owner (zero until set).
    mapping(address => address) public operatorOf;
    /// @notice Genesis founders: no collateral, outside the entry window, no probation wait before activation.
    mapping(address => bool) public isFounder;
    /// @notice Genesis timestamp (set by the seed helper).
    uint256 public genesisTime;
    uint256 public lastEntryWindowChange;
    /// @notice Total Suren burned by slashing (sent to address(0)).
    uint256 public totalSlashBurned;

    event OperatorSet(address indexed owner, address indexed operator);

    function _claimOperator(address owner_, address operator) internal {
        require(operator != address(0), "ValidatorsRegistry: zero operator");
        require(!_reservedForOther(operator, owner_), "ValidatorsRegistry: operator reserved by another owner's pending change");
        address attached = ownerOfOperator[operator];
        require(attached == address(0) || attached == owner_, "ValidatorsRegistry: operator belongs to another owner");
        require(operator == owner_ || validators[operator].status == Status.None, "ValidatorsRegistry: operator is another owner");
        require(ownerOfOperator[owner_] == address(0) || ownerOfOperator[owner_] == owner_, "ValidatorsRegistry: this address is an operator key");
        ownerOfOperator[operator] = owner_;
        operatorOf[owner_] = operator;
        emit OperatorSet(owner_, operator);
    }

    // ------------------------------------------------------------------
    // Changing the node key.
    //   * Probation, Demoted, SelfSuspended (not in the QBFT set): `setOperator` is immediate. Nothing can go wrong for the
    //     network now; the Verifier checks the node before the validator (re)enters the set.
    //   * ACTIVE (the node signs blocks): TWO steps (owner decision 2026-11-19, from Besu finding F-5):
    //       1. proposeOperator(newKey)            the owner reserves the new key; nothing changes in consensus yet;
    //       2. confirmOperatorReady(owner, newOperator, hash)  the Verifier checks the new node is up, synced and signing-capable and then
    //                                             applies the switch in one transaction.
    //     This way a swap to a node that is not running can never reach the QBFT set (a dead node would cost a 10+ second
    //     round change on every one of its turns, and enough of them could stop the chain).
    //     cancelOperatorChange() drops the proposal; a proposal also lapses after OPERATOR_PROPOSAL_EXPIRY.
    // ------------------------------------------------------------------
    mapping(address => address) public pendingOperator;
    mapping(address => uint256) public pendingOperatorExpiresAt;
    /// @dev new key => owner that reserved it in a still-open proposal
    mapping(address => address) public operatorReservedBy;
    uint256 public constant OPERATOR_PROPOSAL_EXPIRY = 7 days;

    event OperatorChangeProposed(address indexed owner, address indexed newOperator, uint256 expiresAt);
    event OperatorChangeConfirmed(address indexed owner, address indexed newOperator, bytes32 evidenceHash);
    event OperatorChangeCancelled(address indexed owner, address indexed newOperator);

    function _reservedForOther(address operator, address owner_) private view returns (bool) {
        address r = operatorReservedBy[operator];
        return r != address(0) && r != owner_ && pendingOperator[r] == operator && pendingOperatorExpiresAt[r] > block.timestamp;
    }

    /// @notice Immediate node-key change for an owner that is NOT in the consensus set (Probation, Demoted, SelfSuspended).
    function setOperator(address newOperator) external {
        Status st = validators[msg.sender].status;
        require(st != Status.Active, "ValidatorsRegistry: an Active validator changes the node key in two steps (proposeOperator)");
        require(
            st == Status.Probation || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: cannot change the operator in this status"
        );
        require(newOperator != address(0), "ValidatorsRegistry: zero operator");
        require(operatorOf[msg.sender] != newOperator, "ValidatorsRegistry: same operator");
        _claimOperator(msg.sender, newOperator);
    }

    /// @notice Step 1 for an ACTIVE validator: reserve the new node key. Consensus is untouched until the Verifier confirms.
    function proposeOperator(address newOperator) external {
        require(validators[msg.sender].status == Status.Active, "ValidatorsRegistry: only an Active validator proposes (others use setOperator)");
        require(operatorOf[msg.sender] != newOperator, "ValidatorsRegistry: same operator");
        require(
            pendingOperator[msg.sender] == address(0) || pendingOperatorExpiresAt[msg.sender] <= block.timestamp,
            "ValidatorsRegistry: a proposal is already open"
        );
        _checkOperatorFree(msg.sender, newOperator);
        pendingOperator[msg.sender] = newOperator;
        pendingOperatorExpiresAt[msg.sender] = block.timestamp + OPERATOR_PROPOSAL_EXPIRY;
        operatorReservedBy[newOperator] = msg.sender;
        emit OperatorChangeProposed(msg.sender, newOperator, pendingOperatorExpiresAt[msg.sender]);
    }

    /// @notice Step 2, Verifier only, after its health check of the new node: applies the switch (immediately visible in
    ///         getValidators() and so in QBFT).
    ///         VD-13: the Verifier names the key it checked (`newOperator`); if the owner cancelled and re-proposed a different
    ///         key between the check and this transaction, the call reverts instead of applying an unchecked key.
    function confirmOperatorReady(address owner_, address newOperator, bytes32 evidenceHash) external onlyVerifier {
        address newOp = pendingOperator[owner_];
        require(newOp != address(0), "ValidatorsRegistry: no open proposal");
        require(newOp == newOperator, "ValidatorsRegistry: operator differs from the open proposal");
        require(pendingOperatorExpiresAt[owner_] > block.timestamp, "ValidatorsRegistry: proposal expired");
        require(validators[owner_].status == Status.Active, "ValidatorsRegistry: owner is no longer Active");
        require(evidenceHash != bytes32(0), "ValidatorsRegistry: empty evidence hash");
        delete pendingOperator[owner_];
        delete pendingOperatorExpiresAt[owner_];
        delete operatorReservedBy[newOp];
        _claimOperator(owner_, newOp);
        emit OperatorChangeConfirmed(owner_, newOp, evidenceHash);
    }

    function cancelOperatorChange() external {
        address newOp = pendingOperator[msg.sender];
        require(newOp != address(0), "ValidatorsRegistry: no open proposal");
        delete pendingOperator[msg.sender];
        delete pendingOperatorExpiresAt[msg.sender];
        delete operatorReservedBy[newOp];
        emit OperatorChangeCancelled(msg.sender, newOp);
    }

    /// @dev The same uniqueness rules as _claimOperator, without writing (used when a proposal is made).
    function _checkOperatorFree(address owner_, address operator) private view {
        require(operator != address(0), "ValidatorsRegistry: zero operator");
        require(!_reservedForOther(operator, owner_), "ValidatorsRegistry: operator reserved by another owner's pending change");
        address attached = ownerOfOperator[operator];
        require(attached == address(0) || attached == owner_, "ValidatorsRegistry: operator belongs to another owner");
        require(operator == owner_ || validators[operator].status == Status.None, "ValidatorsRegistry: operator is another owner");
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
        require(operatorOf[candidate] != address(0), "ValidatorsRegistry: operator key not set");
        require(isFounder[candidate] || block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        // The entry window counts here, at activation. Only a PAYING entrant (isPaidEntrant, also after a seat sale) uses a window slot: founders
        // and lottery winners are exempt by decision (their record has isPaidEntrant == false).
        if (v.isPaidEntrant) _enforceEntryWindow();
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
            totalSlashBurned += slashAmount;
            (bool success, ) = address(0).call{value: slashAmount}(""); // 100% burned (v2.5), not paid to the treasury
            require(success, "ValidatorsRegistry: slash burn failed");
        }
        emit SlashResolved(decisionId, d.validator, outcome, slashAmount);
    }

    /// @dev Genesis seeding (used ONLY by genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol, which inherits this contract,
    ///      so the storage layout is identical by construction; never reachable on the real chain). The FIRST validator (the
    ///      genesis launcher) is Active with its operator key; the other founders are registered with their owner address,
    ///      no collateral and status Probation, and become Active after they set an operator key and the Verifier confirms
    ///      their node is up.
    function _seedFirstValidator(address owner_, address operator, uint256 genesisTimestamp) internal {
        require(genesisTime == 0, "seed: first validator already seeded");
        genesisTime = genesisTimestamp;
        _seedFounderEntry(owner_, genesisTimestamp, Status.Active);
        ownerOfOperator[operator] = owner_;
        operatorOf[owner_] = operator;
        activeIndex[owner_] = activeValidators.length + 1;
        activeValidators.push(owner_);
        everActivated[owner_] = true;
        activationSeq[owner_] = ++activationCount;
        activeCheckpoints[owner_].push(ActiveCheckpoint({nonce: 0, active: true}));
    }

    function _seedFounder(address owner_, uint256 genesisTimestamp) internal {
        _seedFounderEntry(owner_, genesisTimestamp, Status.Probation);
    }

    /// @dev A founder's agreement hash is not recorded on-chain (no seat NFT is minted here and no hash is passed in): the Verifier checks the
    ///      off-chain archive before activating a founder.
    function _seedFounderEntry(address owner_, uint256 genesisTimestamp, Status status) private {
        require(owner_ != address(0), "seed: zero address");
        require(validators[owner_].status == Status.None, "seed: duplicate founder");
        validators[owner_] = ValidatorInfo({
            status: status,
            lockedStake: 0,
            periodStartedAt: genesisTimestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: false
        });
        isFounder[owner_] = true;
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
        if (v.status == Status.RemovedInRecovery) {
            _exitAfterRecoveryRemoval(v);
            return;
        }
        require(
            v.status == Status.Active || v.status == Status.Probation || v.status == Status.Demoted || v.status == Status.SelfSuspended,
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
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).burnSeat(msg.sender);

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
        require(
            key != ParamKey.MaxEntriesPerWindow && key != ParamKey.ProbationPeriod && key != ParamKey.SlashBps,
            "ValidatorsRegistry: this parameter is fixed and cannot be changed"
        );
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
        if (key == ParamKey.EntryWindowSeconds) {
            // v2.5: 1..30 days, each change at most +-1 day, at least 6 months between changes, none in the first 6 months
            require(value >= 1 days && value <= 30 days, "ValidatorsRegistry: entryWindowSeconds outside 1-30 days");
            require(
                value + 1 days >= entryWindowSeconds && value <= entryWindowSeconds + 1 days,
                "ValidatorsRegistry: entryWindowSeconds may change by at most one day"
            );
            require(block.timestamp >= genesisTime + 180 days, "ValidatorsRegistry: no change in the first 6 months after genesis");
            require(block.timestamp >= lastEntryWindowChange + 180 days, "ValidatorsRegistry: at least 6 months between changes");
            lastEntryWindowChange = block.timestamp;
            entryWindowSeconds = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            require(value > MASS_DEMOTION_WINDOW, "ValidatorsRegistry: recoveryPeriod must exceed MASS_DEMOTION_WINDOW");
            recoveryPeriod = value;
        } else if (key == ParamKey.ExitCooldown) {
            require(value > PRE_EXIT_CLAIM_WINDOW, "ValidatorsRegistry: exitCooldown must exceed PRE_EXIT_CLAIM_WINDOW");
            exitCooldown = value;
        } else {
            revert("ValidatorsRegistry: this parameter is fixed and cannot be changed"); // MaxEntriesPerWindow, ProbationPeriod, SlashBps
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

    // ------------------------------------------------------------------
    // v2.5: removal from the validator list during network recovery (decision 2026-11-19)
    //
    // There is NO expulsion. A validator who shut down their node and so halted the network is, after the network is back in
    // `contract` mode, removed from the list by the Verifier's record. This is not a penalty:
    //   * collateral is never slashed; it stays locked until recoveryTimestamp + 90 days, then the owner calls requestExit()
    //     (and waits exitCooldown) as usual;
    //   * the permanent validator ban applies (permanentlyExited), exactly as after a voluntary exit;
    //   * the removed validator has 72 hours to object; objections are decided by ValidatorsBoard (3 of 5, the subject has no
    //     vote) within 7 days; with fewer than 3 impartial board members the case goes to the validators (two thirds of the
    //     validators eligible at referral); no decision in time = the removal is cancelled and the validator is reinstated
    //     (VD-4: into SelfSuspended with a resume request open; only the Verifier's recordResume, after a node health check, makes it Active again).
    // ------------------------------------------------------------------
    // ------------------------------------------------------------------
    // v2.5: lottery winners (ValidatorLottery.drawBatch calls this for every winner)
    // ------------------------------------------------------------------
    /// @notice The only caller of enterAsLotteryWinner(): the ValidatorLottery contract.
    address public constant LOTTERY = SurAddresses.VALIDATOR_LOTTERY;

    event LotteryWinnerEntered(address indexed winner);

    /// @notice A lottery winner takes a seat WITHOUT collateral and WITHOUT membership fee, outside the entry window (its activation
    ///         neither waits for nor uses a window slot) and not counted as a paid entrant. The seat starts in Probation like any entry: the node still has to be verified
    ///         (and the agreement signed) before the Verifier activates it, so the vote is not live before that. An address
    ///         that is already registered or has ever exited cannot take a seat (one seat per person, permanent ban).
    ///         No agreement hash is recorded on-chain at this entry (the signature is off-chain; the Verifier checks the archive before activation).
    function enterAsLotteryWinner(address winner) external {
        require(msg.sender == LOTTERY, "ValidatorsRegistry: caller is not the lottery");
        require(winner != address(0) && validators[winner].status == Status.None, "ValidatorsRegistry: already registered");
        require(winner.code.length == 0, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12 (the lottery's try/catch records entryFailed)
        require(!permanentlyExited[winner], "ValidatorsRegistry: this address has exited before and may not rejoin");
        validators[winner] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: 0,
            periodStartedAt: block.timestamp,
            pendingSlashEpoch: 0,
            demotedAt: 0,
            isPaidEntrant: false
        });
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).mintSeat(winner);
        emit LotteryWinnerEntered(winner);
    }

    enum RecoveryRemovalState { None, Recorded, Objected, ReferredToAssembly, Upheld, Cancelled }

    struct RecoveryRemoval {
        RecoveryRemovalState state;
        uint256 recoveryTimestamp;   // when the network returned to contract mode (given by the Verifier)
        bytes32 evidenceHash;        // hash of the evidence package (e.g. qbft_getSignerMetrics output)
        uint256 recordedAt;
        uint256 objectionDeadline;   // recordedAt + 72 h
        uint256 resolutionDeadline;  // set when an objection (or an assembly referral) opens the 7-day decision window
        uint256 exitAllowedAt;       // recoveryTimestamp + 90 days
        uint256 referralNonce;       // statusNonce at assembly referral (only validators Active then may vote)
        uint256 eligibleCount;       // active validators at referral = the assembly electorate size
    }

    uint256 public constant RECOVERY_OBJECTION_WINDOW = 72 hours;
    uint256 public constant RECOVERY_RESOLUTION_WINDOW = 7 days;
    uint256 public constant RECOVERY_COLLATERAL_LOCK = 90 days;
    /// @dev 🔶 not fixed by the decision: how old recoveryTimestamp may be when the Verifier records the removal.
    uint256 public constant RECOVERY_RECORD_MAX_AGE = 30 days;

    mapping(address => RecoveryRemoval) public recoveryRemovals;

    event RecoveryRemovalRecorded(address indexed validator, uint256 recoveryTimestamp, bytes32 evidenceHash, uint256 exitAllowedAt);
    event RecoveryRemovalObjected(address indexed validator, uint256 resolutionDeadline);
    event RecoveryCaseReferredToAssembly(address indexed validator, uint256 referralNonce, uint256 eligibleCount, uint256 resolutionDeadline);
    event RecoveryRemovalUpheld(address indexed validator);
    event RecoveryRemovalCancelled(address indexed validator, bool expired);

    /// @notice Verifier only, and only after the network is back in contract mode. Removes an Active validator from the
    ///         consensus list (no rewards, no votes, no board authority) without touching their collateral.
    function recordRecoveryRemoval(address validator, uint256 recoveryTimestamp, bytes32 evidenceHash) external onlyVerifier nonReentrant {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: validator is not active");
        require(evidenceHash != bytes32(0), "ValidatorsRegistry: empty evidence hash");
        require(
            recoveryTimestamp <= block.timestamp && block.timestamp - recoveryTimestamp <= RECOVERY_RECORD_MAX_AGE,
            "ValidatorsRegistry: recoveryTimestamp out of range"
        );
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count");
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(r.state == RecoveryRemovalState.None || r.state == RecoveryRemovalState.Cancelled, "ValidatorsRegistry: removal case exists");

        _removeFromActive(validator);
        _recordActiveCheckpoint(validator, false);
        if (v.isPaidEntrant) paidValidatorCount--;
        v.status = Status.RemovedInRecovery;
        v.periodStartedAt = block.timestamp;
        permanentlyExited[validator] = true; // the permanent ban applies
        membershipEpoch[validator]++;        // ends any board seat

        r.state = RecoveryRemovalState.Recorded;
        r.recoveryTimestamp = recoveryTimestamp;
        r.evidenceHash = evidenceHash;
        r.recordedAt = block.timestamp;
        r.objectionDeadline = block.timestamp + RECOVERY_OBJECTION_WINDOW;
        r.resolutionDeadline = 0;
        r.exitAllowedAt = recoveryTimestamp + RECOVERY_COLLATERAL_LOCK;
        r.referralNonce = 0;
        r.eligibleCount = 0;
        emit RecoveryRemovalRecorded(validator, recoveryTimestamp, evidenceHash, r.exitAllowedAt);
        _notifyBoard(validator);
    }

    /// @notice The removed validator objects within 72 hours; this opens the 7-day decision window.
    function objectRecoveryRemoval() external {
        RecoveryRemoval storage r = recoveryRemovals[msg.sender];
        require(validators[msg.sender].status == Status.RemovedInRecovery && r.state == RecoveryRemovalState.Recorded, "ValidatorsRegistry: nothing to object to");
        require(block.timestamp <= r.objectionDeadline, "ValidatorsRegistry: objection window over");
        r.state = RecoveryRemovalState.Objected;
        r.resolutionDeadline = block.timestamp + RECOVERY_RESOLUTION_WINDOW;
        emit RecoveryRemovalObjected(msg.sender, r.resolutionDeadline);
    }

    /// @notice ValidatorsBoard only: fewer than 3 impartial board members, so the validators decide. A new 7-day window starts.
    function setRecoveryCaseReferred(address validator) external onlyBoard {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(r.state == RecoveryRemovalState.Objected && block.timestamp <= r.resolutionDeadline, "ValidatorsRegistry: case cannot be referred");
        r.state = RecoveryRemovalState.ReferredToAssembly;
        r.referralNonce = statusNonce;
        r.eligibleCount = activeValidators.length;
        r.resolutionDeadline = block.timestamp + RECOVERY_RESOLUTION_WINDOW;
        emit RecoveryCaseReferredToAssembly(validator, r.referralNonce, r.eligibleCount, r.resolutionDeadline);
    }

    /// @notice ValidatorsBoard only, with the decision of the board (3 of 5) or of the validators (two thirds).
    ///         upheld = the removal stands; otherwise the removal is cancelled and the validator returns to SelfSuspended (VD-4).
    function resolveRecoveryRemoval(address validator, bool upheld) external onlyBoard nonReentrant {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(
            (r.state == RecoveryRemovalState.Objected || r.state == RecoveryRemovalState.ReferredToAssembly) && block.timestamp <= r.resolutionDeadline,
            "ValidatorsRegistry: no open case"
        );
        if (upheld) {
            r.state = RecoveryRemovalState.Upheld;
            emit RecoveryRemovalUpheld(validator);
        } else {
            _cancelRecoveryRemoval(validator, false);
        }
    }

    /// @notice Anyone, after the decision window ended without a decision: the removal is cancelled.
    function expireRecoveryRemoval(address validator) external nonReentrant {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        require(
            (r.state == RecoveryRemovalState.Objected || r.state == RecoveryRemovalState.ReferredToAssembly) && block.timestamp > r.resolutionDeadline,
            "ValidatorsRegistry: nothing to expire"
        );
        _cancelRecoveryRemoval(validator, true);
    }

    function _cancelRecoveryRemoval(address validator, bool expired) private {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.RemovedInRecovery, "ValidatorsRegistry: not removed");
        recoveryRemovals[validator].state = RecoveryRemovalState.Cancelled;
        permanentlyExited[validator] = false;
        if (v.isPaidEntrant) paidValidatorCount++;
        // VD-4: NOT straight back to Active (the node was never checked after the removal). The validator returns to
        // SelfSuspended with a resume request already open, so the Verifier's recordResume (node health check) is the only way
        // back into the validator list.
        v.status = Status.SelfSuspended;
        v.periodStartedAt = block.timestamp;
        resumeRequested[validator] = true;
        emit ResumeRequested(validator);
        emit RecoveryRemovalCancelled(validator, expired);
        _notifyBoard(validator);
    }

    /// @dev requestExit() for a validator removed in recovery: only when the case is settled and the 90-day collateral lock has
    ///      elapsed. The rest (exitCooldown, withdrawStake) is the ordinary exit.
    function _exitAfterRecoveryRemoval(ValidatorInfo storage v) private {
        RecoveryRemoval storage r = recoveryRemovals[msg.sender];
        require(
            r.state == RecoveryRemovalState.Upheld ||
            (r.state == RecoveryRemovalState.Recorded && block.timestamp > r.objectionDeadline),
            "ValidatorsRegistry: removal case still open"
        );
        require(block.timestamp >= r.exitAllowedAt, "ValidatorsRegistry: collateral locked for 90 days after recovery");
        statusBeforeExit[msg.sender] = uint8(Status.RemovedInRecovery);
        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;
        IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).burnSeat(msg.sender);
        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
    }

    /// @notice Narrow views for ValidatorsBoard (positional decoding): state, recordedAt, resolutionDeadline.
    function recoveryCaseInfo(address validator) external view returns (uint8 state, uint256 recordedAt, uint256 resolutionDeadline) {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        return (uint8(r.state), r.recordedAt, r.resolutionDeadline);
    }

    function recoveryReferral(address validator) external view returns (uint256 referralNonce, uint256 eligibleCount) {
        RecoveryRemoval storage r = recoveryRemovals[validator];
        return (r.referralNonce, r.eligibleCount);
    }

    // ------------------------------------------------------------------
    // v2.5: voluntary suspension (SelfSuspended) — free, no time or count limit
    //   selfSuspend()      owner, Active -> SelfSuspended: out of getValidators() at once; collateral stays locked; no rewards, no votes
    //   requestResume()    owner, SelfSuspended: asks the Verifier to check the node
    //   recordResume()     Verifier only, after a successful node health check: SelfSuspended -> Active, NO probation
    // A member of the validators' board cannot suspend voluntarily (it would silently shrink the board's quorum), and nobody can
    // suspend below MIN_ACTIVE_VALIDATORS. Voluntary suspension is never a violation and never leads to a slash.
    // ------------------------------------------------------------------
    mapping(address => bool) public resumeRequested;

    event SelfSuspendedEvent(address indexed validator);
    event ResumeRequested(address indexed validator);
    event ResumeRecorded(address indexed validator, bytes32 evidenceHash);

    function selfSuspend() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(activeValidators.length > MIN_ACTIVE_VALIDATORS, "ValidatorsRegistry: at the minimum validator count - suspension blocked");
        require(!IBoardAuthority(BOARD).hasBoardAuthority(msg.sender), "ValidatorsRegistry: a board member cannot suspend voluntarily");
        _removeFromActive(msg.sender);
        _recordActiveCheckpoint(msg.sender, false);
        v.status = Status.SelfSuspended;
        v.periodStartedAt = block.timestamp;
        resumeRequested[msg.sender] = false;
        emit SelfSuspendedEvent(msg.sender);
        _notifyBoard(msg.sender);
    }

    function requestResume() external {
        require(validators[msg.sender].status == Status.SelfSuspended, "ValidatorsRegistry: not self-suspended");

        resumeRequested[msg.sender] = true;
        emit ResumeRequested(msg.sender);
    }

    function recordResume(address validator, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        require(validators[validator].status == Status.SelfSuspended, "ValidatorsRegistry: not self-suspended");
        require(resumeRequested[validator], "ValidatorsRegistry: no resume request");
        require(operatorOf[validator] != address(0), "ValidatorsRegistry: operator key not set");
        resumeRequested[validator] = false;
        _activate(validator);
        decisionId = _recordDecision(validator, DecisionType.Resume, evidenceHash, 0);
        emit ResumeRecorded(validator, evidenceHash);
        _notifyBoard(validator);
    }

    // ------------------------------------------------------------------
    // v2.5: seat NFT. The owner of ValidatorSeatNFT token = the owner of the seat (reference doc §9).
    // ------------------------------------------------------------------
    // The buyer's acceptance of the validators' agreement is a GATE (owner decision): a seat cannot be transferred to an address that
    // has not recorded its acceptance FOR THAT SEAT beforehand, so nobody becomes the owner of a seat without having accepted.
    //
    // Legal flow (owner decision): the buyer signs the agreement with the Foundation BEFORE the transfer, effective from the transfer;
    // the Foundation countersigns AFTER the transfer and is obliged to sign, so NOTHING waits on the Foundation on-chain. The signature
    // itself stays off-chain; the chain records only that the buyer's OWN key accepted, for this seat id, an agreement document with the
    // given hash (acceptSeatAgreement). The acceptance is made BEFORE the transfer, is bound to one seat id and one agreement hash, and is
    // CONSUMED by the transfer that uses it (a later transfer of the same seat to the same address needs a fresh one). The hash travels
    // into the transfer: it is stored as the seat's agreement hash and emitted (SeatAgreementBound) so the document that binds the
    // current owner can always be found.
    // Seats minted at entry, by the lottery or at genesis never pass through the transfer hook, so this gate does not touch those
    // paths; they never used the old post-transfer acceptance either. A direct entrant signs the same agreement BEFORE requesting
    // membership and its hash comes in with requestMembership (EntryAgreementRecorded); lottery winners and genesis founders have no
    // hash recorded at entry.

    /// @notice The seat id for which `buyer` has recorded the acceptance of the validators' agreement (0 = none). One acceptance at a
    ///         time per address: accepting another seat replaces it. Seat ids start at 1 and are never reused, so an acceptance can
    ///         never be applied to a different seat than the one it names. Set by the buyer's own key only
    ///         (acceptSeatAgreement), cleared by revokeSeatAcceptance or consumed by the transfer.
    mapping(address => uint256) public seatAcceptedFor;
    /// @notice The hash of the signed agreement document recorded together with that acceptance (non-zero while an acceptance is open).
    mapping(address => bytes32) public seatAcceptedAgreementHash;
    /// @notice The hash of the signed validators' agreement that governs the CURRENT owner of a seat, whatever the path: set at direct entry
    ///         (requestMembership), overwritten by every transfer (the buyer's accepted hash), kept by a migration after a lost owner key
    ///         (same person, same agreement). 0 = no hash on-chain: a seat that came by the lottery or at genesis takes no hash at entry (the
    ///         Verifier checks the off-chain archive before activation) and has none until a transfer binds one. The full history is in
    ///         the EntryAgreementRecorded and SeatAgreementBound events.
    mapping(uint256 => bytes32) public seatAgreementHash;

    event SeatTransferred(uint256 indexed seatId, address indexed from, address indexed to, Status statusAfter);
    /// @notice Emitted by requestMembership: `owner` entered directly with seat `seatId` under the signed agreement with this hash.
    event EntryAgreementRecorded(address indexed owner, uint256 indexed seatId, bytes32 agreementHash);
    event SeatAgreementAccepted(address indexed buyer, uint256 indexed seatId, bytes32 agreementHash);
    event SeatAcceptanceRevoked(address indexed buyer, uint256 indexed seatId);
    /// @notice Emitted by the transfer that consumed an acceptance: `owner` now holds `seatId` under the agreement with this hash.
    event SeatAgreementBound(uint256 indexed seatId, address indexed owner, bytes32 agreementHash);

    /// @notice The future buyer records, with its own key and BEFORE the seat is transferred to it, that it accepts the validators'
    ///         agreement for seat `seatId`; `agreementHash` is the hash of the signed agreement document (non-zero; the signature itself is
    ///         off-chain). Nobody can record it for another address. The seat must exist and must not already be owned by the caller.
    ///         The record only authorises the transfer of THIS seat to the caller; every other transfer rule is still checked when the
    ///         seat moves. Replaces any earlier acceptance of the caller.
    function acceptSeatAgreement(uint256 seatId, bytes32 agreementHash) external {
        require(agreementHash != bytes32(0), "ValidatorsRegistry: empty agreement hash");
        require(IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).ownerOf(seatId) != msg.sender, "ValidatorsRegistry: caller already owns this seat");
        seatAcceptedFor[msg.sender] = seatId;
        seatAcceptedAgreementHash[msg.sender] = agreementHash;
        emit SeatAgreementAccepted(msg.sender, seatId, agreementHash);
    }

    /// @notice The buyer withdraws its recorded acceptance (for example the sale fell through), so the seat can no longer be
    ///         transferred to it until it accepts again.
    function revokeSeatAcceptance() external {
        uint256 seatId = seatAcceptedFor[msg.sender];
        require(seatId != 0, "ValidatorsRegistry: no acceptance recorded");
        delete seatAcceptedFor[msg.sender];
        delete seatAcceptedAgreementHash[msg.sender];
        emit SeatAcceptanceRevoked(msg.sender, seatId);
    }

    /// @notice Called by ValidatorSeatNFT after the token moved; reverts (so the token transfer reverts) unless the transfer is
    ///         allowed. Moves the whole validator record from `from` to `to`. Besides the seat-status and penalty rules, the buyer
    ///         must be new, fully verified and not an operator key, and must have recorded the acceptance of the agreement for
    ///         exactly this seat (acceptSeatAgreement); that acceptance is consumed here and its agreement hash is bound to the seat.
    function onSeatTransferred(uint256 seatId, address from, address to) external nonReentrant {
        require(msg.sender == SurAddresses.VALIDATOR_SEAT_NFT, "ValidatorsRegistry: caller is not the seat NFT");
        ValidatorInfo storage v = validators[from];
        Status st = v.status;
        require(
            st == Status.Probation || st == Status.Active || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: seat cannot be transferred in this status"
        );
        require(v.pendingSlashEpoch == 0 && pendingSlashDecisionId[from] == 0, "ValidatorsRegistry: open penalty case - transfer blocked");
        // the buyer: never a validator, fully verified, not an operator key, not an owner of a seat already
        require(validators[to].status == Status.None && !permanentlyExited[to] && !everActivated[to], "ValidatorsRegistry: buyer was a validator before");
        require(ownerOfOperator[to] == address(0) && operatorOf[to] == address(0), "ValidatorsRegistry: buyer is an operator key");
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(to), "ValidatorsRegistry: buyer identity not fully verified");
        require(to != from, "ValidatorsRegistry: same owner");
        // the buyer must have accepted the validators' agreement for THIS seat before the transfer; the acceptance is used up now
        require(seatAcceptedFor[to] == seatId, "ValidatorsRegistry: buyer has not accepted the validators' agreement for this seat");
        bytes32 agreementHash = seatAcceptedAgreementHash[to];
        delete seatAcceptedFor[to];
        delete seatAcceptedAgreementHash[to];

        _moveSeatRecord(from, to, st, false);

        seatAgreementHash[seatId] = agreementHash;
        emit SeatAgreementBound(seatId, to, agreementHash);
        emit SeatTransferred(seatId, from, to, st);
    }

    /// @dev Moves the whole validator record of a seat from `from` to `to` (shared by a sale and by a migration after a lost owner key; the
    ///      callers have already checked every rule). An Active seat STAYS Active (decision 2026-11-19): the new owner takes the owner place in
    ///      the active set at the same position, with the same operator key, so the node keeps validating without interruption. The old
    ///      owner's vote ends and the new owner is a new voter from now (fresh checkpoints), so it cannot vote on proposals created before.
    ///      The old address is marked permanentlyExited (it can never be a validator again) and its board authority ends. On a SALE that is
    ///      the whole story (the buyer is a different person and takes no board seat). On a MIGRATION the person is the same, so migrateSeat
    ///      then hands the board seat and the election votes of the old address to the new one (ValidatorsBoard.onSeatMigrated).
    ///      `keepResumeRequest`: a migration keeps an open resume request (same person), a sale does not.
    function _moveSeatRecord(address from, address to, Status st, bool keepResumeRequest) private {
        ValidatorInfo storage v = validators[from];
        if (st == Status.Active) {
            uint256 idx = activeIndex[from];
            activeValidators[idx - 1] = to;
            activeIndex[to] = idx;
            delete activeIndex[from];
            _recordActiveCheckpoint(from, false);
            _recordActiveCheckpoint(to, true);
        }

        // move the record
        validators[to] = v;
        delete validators[from];
        address op = operatorOf[from];
        if (op != address(0)) {
            operatorOf[to] = op;
            ownerOfOperator[op] = to; // the node key stays with the seat
            delete operatorOf[from];
        }
        if (isFounder[from]) {
            isFounder[to] = true;
            delete isFounder[from];
        }
        everActivated[to] = everActivated[from];
        activationSeq[to] = activationSeq[from];
        resumeRequested[to] = keepResumeRequest && resumeRequested[from];
        resumeRequested[from] = false;
        {
            // the old owner's leftovers must not survive: an open node-key proposal (and its key reservation) and any
            // acceptance it had recorded as a possible buyer; the new owner starts clean and must make its own proposal if it
            // wants another node key
            address proposed = pendingOperator[from];
            if (proposed != address(0)) {
                delete operatorReservedBy[proposed];
                delete pendingOperator[from];
                delete pendingOperatorExpiresAt[from];
            }
            delete seatAcceptedFor[from];
            delete seatAcceptedAgreementHash[from];
            // the new owner's own pending acceptance (it may have recorded one for another seat as a prospective buyer) must not outlive
            // the move either: once it owns a seat it can never be a buyer, so a stale acceptance would only mislead. A sale has already
            // consumed the buyer's acceptance (it is zero here); only a migration can find one.
            uint256 staleSeatId = seatAcceptedFor[to];
            if (staleSeatId != 0) {
                delete seatAcceptedFor[to];
                delete seatAcceptedAgreementHash[to];
                emit SeatAcceptanceRevoked(to, staleSeatId);
            }
        }

        // the old owner is treated as exited: permanent ban, board authority over (a migration then gives the board seat to the new address)
        permanentlyExited[from] = true;
        membershipEpoch[from]++;

        _notifyBoard(from);
        _notifyBoard(to);
    }

    // ------------------------------------------------------------------
    // Lost owner key: the whole seat moves to the person's new address after an authorised identity migration (audit A4)
    // ------------------------------------------------------------------
    /// @notice A seat was moved to a new address of the SAME person after the owner key was lost.
    event SeatMigrated(uint256 indexed seatId, address indexed from, address indexed to, Status statusAfter);

    /// @notice Lost owner key (validator agreement 5-5, change proposal 32 answer 6): moves the WHOLE seat from `oldOwner` to `newOwner`
    ///         (the validator record with its collateral and status, the operator (node-key) link, the founder flag, the activation history,
    ///         the place in the active set and the vote as a new voter from now, the seat NFT, and what BlockRewardDistributor owes to the old
    ///         owner). It is the single exception to the permanent ban: the person is the same, so the new address is NOT treated as exited,
    ///         while the old address becomes permanently exited.
    ///
    ///         BOARD SEAT FOLLOWS THE PERSON (ValidatorsBoard.onSeatMigrated, a REQUIRED call: if it reverts, the migration reverts): if the
    ///         old address holds a seat on the validators' board, the new address takes that seat IN PLACE for the rest of the board's month
    ///         (same position, no vacancy, no board-version change), and the election votes the old address cast and received move with it.
    ///         A person never counts twice: its vote on a board action or a board chamber of the Distributor is recorded once across the old
    ///         and the new address, while its validator vote starts anew from the migration (a new voter from now). A seat SALE does none of
    ///         this: the buyer is a different person, the seller's board authority ends and no board seat is handed over.
    ///
    ///         AUTHORISATION (two independent keys, the strictest reading of the documents): (1) the identity oracle must already have run
    ///         IdentityRegistry.migrateIdentity(oldOwner, newOwner) after the off-chain identity check (this contract reads
    ///         migratedTo(oldOwner) == newOwner), and (2) this call is made by the Verifier. Neither key alone can move a seat: the identity
    ///         oracle cannot touch the Registry, and the Verifier cannot name an address the oracle did not migrate to. The old owner cannot
    ///         call it (its key is lost). The new address must be fully verified (the migration copies the flags), a plain wallet (EOA), must
    ///         never have been a validator or an operator key, and must hold no seat. The old seat must be Probation, Active, Demoted or
    ///         SelfSuspended with no open penalty case; an Exiting or RemovedInRecovery seat cannot be migrated.
    function migrateSeat(address oldOwner, address newOwner) external onlyVerifier nonReentrant {
        require(newOwner != address(0) && newOwner != oldOwner, "ValidatorsRegistry: bad new owner");
        ValidatorInfo storage v = validators[oldOwner];
        Status st = v.status;
        require(
            st == Status.Probation || st == Status.Active || st == Status.Demoted || st == Status.SelfSuspended,
            "ValidatorsRegistry: seat cannot be migrated in this status"
        );
        require(v.pendingSlashEpoch == 0 && pendingSlashDecisionId[oldOwner] == 0, "ValidatorsRegistry: open penalty case - migration blocked");
        require(
            IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).migratedTo(oldOwner) == newOwner,
            "ValidatorsRegistry: the identity of the old owner was not migrated to this address"
        );
        require(IIdentityFullyVerified(SurAddresses.IDENTITY_REGISTRY).isFullyVerified(newOwner), "ValidatorsRegistry: new owner identity not fully verified");
        require(newOwner.code.length == 0, "ValidatorsRegistry: a seat owner must be a plain wallet (EOA)"); // RD-12
        require(validators[newOwner].status == Status.None && !permanentlyExited[newOwner] && !everActivated[newOwner], "ValidatorsRegistry: new owner was a validator before");
        require(ownerOfOperator[newOwner] == address(0) && operatorOf[newOwner] == address(0), "ValidatorsRegistry: new owner is an operator key");

        uint256 seatId = IValidatorSeatNFT(SurAddresses.VALIDATOR_SEAT_NFT).reassignSeat(oldOwner, newOwner);
        _moveSeatRecord(oldOwner, newOwner, st, true);
        IValidatorsBoardSync(BOARD).onSeatMigrated(oldOwner, newOwner); // REQUIRED (unlike the best-effort _notifyBoard): the board seat and election votes of the old address go to the new one, or nothing moves
        DISTRIBUTOR.migrateClaimable(oldOwner, newOwner);

        emit SeatMigrated(seatId, oldOwner, newOwner, st);
    }
}
