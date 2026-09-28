// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IBlockRewardDistributor {
    function receiveMembershipFee() external payable;
}

/// @title ValidatorsRegistry
/// @notice Deployed at the fixed genesis address SurAddresses.VALIDATORS_REGISTRY
///         (0x3333...3333). Serves two roles:
///
///         1) CONSENSUS: implements Besu's hardcoded QBFT contract-mode interface
///            `getValidators() external view returns (address[] memory)`. This address must
///            also be set as `qbft.validatorcontractaddress` in genesis.json. Any change to the
///            returned list takes effect immediately, from the very block the change is mined
///            in (verified experimentally — see "Besu QBFT experiment findings", Experiment 2).
///
///         2) PAYMENT ELIGIBILITY: `BlockRewardDistributor` checks `isValidator(address)`
///            directly on this contract before paying anyone out. There is no intermediary
///            oracle for validator-set sync (the old `validatorSyncOracle` design is retired —
///            see design doc section 2.9 / 5).
///
///         Deliberately kept separate from `ValidatorsTreasury`: a bug in treasury spending
///         logic must never be able to affect who is recognized as a validator.
///
///         GENESIS DEPLOYMENT: this contract, along with the other four structural contracts,
///         is injected directly into the genesis block's `alloc` (code + final storage), not
///         deployed by a transaction — and, per that same reasoning, it has no constructor at
///         all (a constructor would never execute on the real chain). The initial validator set,
///         the real genesis timestamp, and every security parameter are instead seeded via the
///         off-chain genesis-building tool (see the 🔶 GENESIS FILL-IN notes throughout this
///         file); see "sur-contracts-deploy-notes.md" for the exact recipe and why the real
///         genesis timestamp cannot reliably be read from a simulated environment's
///         `block.timestamp`, and why this matters for the rate-limit window and each genesis
///         validator's liveness-confirmation timestamps.
///
///         Lifecycle of a validator address:
///           None -> Probation (locks stake, verifier confirms node sync, NOT yet in getValidators())
///                -> Active (in getValidators(), payment-eligible)
///                -> [continuous inactivity] -> Demoted (removed from getValidators(), stake
///                   partially slashed)
///                -> [recovery liveness confirmations] -> Active again
///           From Probation, Active, or Demoted, an address may instead choose Exiting
///           (voluntary withdrawal, subject to a cooldown) to reclaim its remaining stake.
///
///         Governance — split into two tracks (updated decision: full-validator consensus on
///         every parameter proved impractical to reach in practice as the validator set grows):
///           - ECONOMIC ENTRY PARAMETERS (entryThresholdBase, growthFactorPerValidator, membershipFeeBps):
///             changeable only by ValidatorsBoard's own internal majority vote (see
///             ValidatorsBoard.sol's proposeSetEntryThresholdBase/proposeSetGrowthFactorPerValidator/
///             proposeSetMembershipFeeBps). Board members are chosen by ongoing approval voting
///             among active validators (see ValidatorsBoard.sol's voteFor/unvoteFor/
///             refreshBoard — no recall step; a member simply stops being re-selected once they
///             lose enough support or stop being an active validator), so this is not
///             foundation or oracle control; it is a deliberate delegation to a small,
///             continuously-refreshed, validator-elected body for parameters expected to need
///             frequent tuning as the network's validator count and Suren's market value change.
///           - EVERYTHING ELSE (rate limit, probation length, liveness/inactivity thresholds,
///             recovery period, slashing bps, exit cooldown): still requires a full majority
///             vote of currently ACTIVE validators, via this contract's own
///             proposeParameterChange/voteParameterChange — never the foundation, never the
///             board. These remain the harder-to-reach, higher-trust bar because they define
///             the security assumptions of the validator set itself, not its economic tuning.
///
///         MEMBERSHIP FEE (hybrid stake model): a new validator's payment on requestMembership,
///         sent as native currency (Suren — the chain's own base/gas token, exactly like ETH on
///         Ethereum; NOT an ERC20), is split into two parts:
///           - COLLATERAL (= currentEntryThreshold()): stays locked in this contract's native
///             balance, fully refundable on voluntary exit (see withdrawStake), partially
///             slashable on inactivity demotion. This is the address's own money, never
///             spendable by the validator assembly's vote.
///           - MEMBERSHIP FEE (= currentMembershipFee(), a governed % of the collateral):
///             ✅ CHANGED: forwarded immediately to BlockRewardDistributor (not
///             ValidatorsTreasury), where it is folded into the very next reward-distribution
///             epoch's fee pool and paid out 100%-pro-rata-by-blocks to whichever validators are
///             active during that epoch — see sur-tokenomics.md section 6 for why (this turns
///             every new member's entry into a direct, traceable cash incentive for existing
///             validators, rather than a pure dilution of their block-reward share). The
///             collateral's slashed portion (below) still goes straight to ValidatorsTreasury,
///             unchanged — only the membership fee's destination changed.
contract ValidatorsRegistry {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — destination for slashed stake.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice BlockRewardDistributor — ✅ CHANGED: membership fees are now forwarded here
    ///         (via receiveMembershipFee()) instead of straight to TREASURY, so they get folded
    ///         into the next epoch's 100%-pro-rata-by-blocks fee distribution among currently
    ///         active validators. See sur-tokenomics.md section 6 for the full reasoning: this
    ///         gives existing validators a direct, traceable incentive to welcome/promote new
    ///         members, instead of every new joiner purely diluting existing validators' share.
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
        // ✅ REDESIGNED (explicit user decision — moved to fully off-chain verification): the
        // on-chain liveness-ratio tracking that used to live here (packed lastCheckedAt/
        // lastLivenessConfirmation/totalLivenessChecksInPeriod/livenessConfirmationsInPeriod)
        // has been removed entirely. The Verifier now checks every node's liveness off-chain
        // (hourly) and reports ONLY status CHANGES on-chain — activation after probation,
        // suspension, or recovery — each carrying a hash of the off-chain evidence package that
        // justified it (see StatusDecision below), not a running on-chain tally. Rationale
        // (stated by the user): most polling cycles change nothing, so paying gas for a
        // transaction every single cycle for every validator was wasteful once the decision was
        // made to trust the Verifier's off-chain computation, anchor it with a hash for later
        // dispute, and let a validator or the assembly challenge it rather than have the
        // contract re-derive the ratio itself from an on-chain log it no longer keeps.
        uint256 pendingSlashEpoch; // nonzero while this validator has an unresolved
        // inactivity-slash decision (mass-failure check pending, OR delivery/appeal pending —
        // see StatusDecision and DemotionEpoch below for the full mechanism). Zero means "no
        // pending slash." Still blocks withdrawStake() below exactly as before.
        uint256 demotedAt;          // 0 if never demoted / currently not in Demoted status
        bool isPaidEntrant;        // ✅ NEW: true only for validators who actually paid via
        // requestMembership() below. False (default) for genesis-seeded founding validators,
        // who are injected directly with lockedStake=0 and never call requestMembership(). This
        // is what lets currentEntryThreshold() below charge the founders' free entry as
        // "outside" the growth curve entirely — see paidValidatorCount and the design note
        // above currentEntryThreshold() for the full reasoning (a deliberate decision: the
        // ascending-cost curve should reflect only paid entries, not the founding cohort).
    }

    mapping(address => ValidatorInfo) public validators;

    /// @notice ✅ NEW: count of paid entrants (joined via requestMembership()) who have NOT
    ///         yet called requestExit() — increments on a successful requestMembership(), and
    ///         decrements only on requestExit() (see that function below). ⚠️ PRECISE
    ///         DEFINITION (clarified after review): despite the variable's name, this is NOT
    ///         "currently-Active paid validators" — it spans Probation, Active, AND Demoted
    ///         status alike, since none of those transitions call requestExit(). A paid
    ///         validator who is merely on Probation, or temporarily Demoted for inactivity,
    ///         still counts here; only fully exiting does not. This is the intended behavior,
    ///         not a bug: the growth curve is meant to reflect how many paid slots have been
    ///         claimed and not yet relinquished, not the narrower live-liveness-passing subset.
    ///         Genesis-seeded founding validators are deliberately NOT counted here (they never
    ///         call requestMembership()), so their free entry does not steepen the cost curve
    ///         for anyone after them. currentEntryThreshold() below uses this instead of
    ///         activeValidators.length as its exponent — see sur-tokenomics.md for the full
    ///         economic reasoning behind this distinction.
    uint256 public paidValidatorCount;

    // ------------------------------------------------------------------
    // Architecture note: identity (name/person type, mobile/Telegram/KYC verification) no
    // longer lives here — it was moved to a fully independent contract, `IdentityRegistry.sol`.
    // Reason: identity's target population (all network users) is entirely separate from the
    // validator population; `ValidatorsBoard.voteFor` now checks
    // `IdentityRegistry.hasIdentity(...)` directly, not through this contract.
    //
    // `verifier` remains here, but for a single purpose only: reporting validator status
    // decisions — recordActivation/recordSuspension/recordRecovery (further below in this
    // file). This is a completely separate key from `identityOracle` in `IdentityRegistry.sol`
    // — these two roles (node liveness vs. identity verification) are deliberately kept
    // independent.
    // ------------------------------------------------------------------

    /// @notice Operational key trusted to report validator status decisions — see
    ///         recordActivation/recordSuspension/recordRecovery below. Rotatable by
    ///         ValidatorsBoard — see setVerifier.
    /// @dev ✅ FILLED: initial verifier address, read from SurAddresses.sol (single source of
    ///      truth for all four oracle addresses — see that file for rationale).
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
    // 🔶 GENESIS FILL-IN: the founding validator set. `activeValidators` is a dynamic array and
    // `activeIndex`/`validators` are mappings — Solidity has no syntax for populating any of
    // them with a loop outside a function, so this initial state cannot be expressed as a simple
    // state-variable initializer here. The off-chain genesis-building tool must either
    // (a) simulate this contract's deployment with the real seeding logic below, on a temporary
    // local chain, and copy the resulting storage into the final genesis file, or (b) directly
    // compute and write the corresponding storage slots into the genesis `alloc`. See
    // "sur-contracts-deploy-notes.md" for the full recipe.
    //
    // Reference logic (not live code — for the genesis tool to reproduce, either by simulation
    // or by direct storage computation) — for each founding validator address v:
    //   validators[v] = ValidatorInfo({ status: Active, lockedStake: 0,
    //     periodStartedAt: GENESIS_TIMESTAMP, lastLivenessConfirmation: GENESIS_TIMESTAMP,
    //     pendingSlashEpoch: 0, demotedAt: 0, isPaidEntrant: false });
    //   activeIndex[v] = activeValidators.length + 1;
    //   activeValidators.push(v);
    //   // paidValidatorCount is NOT incremented for founders — see its doc comment above.
    // ------------------------------------------------------------------
    // Active validator set, exposed via getValidators(). Swap-and-pop removal via 1-based index.
    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // Governed parameters (changeable only via full validator vote — see below)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Economic entry parameters — hardcoded initial values, changeable only by ValidatorsBoard
    // (not a constructor argument, not full-validator-vote governed — see the governance note
    // in the contract-level doc comment above). Initial values below are a deliberate starting
    // point, not derived from any on-chain data: at an assumed initial Suren price of roughly
    // $0.0005, 500,000 Suren ~= $250 collateral per validator seat. ✅ CHANGED: lowered from
    // the original 2,000,000 Suren (~$1000) — see entryThresholdBase's own doc comment below
    // for why (reducing the capital barrier to entry, without changing the actual pure-reward
    // breakeven point, which is independent of this parameter — sur-tokenomics.md section 6).
    // ⚠️ Note: this $0.0005 assumption was never reconciled against SurenSale's actual fixed
    // sale price (100-116 Toman, roughly $0.002-0.0025 at informal exchange rates) — the real
    // dollar value of this collateral is likely several times higher than the figure quoted
    // here from day one (see sur-master-open-items.md for this open discrepancy).
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------

    /// @notice ✅ NEW (guardrail added after review): hard bounds + a shared cooldown for
    ///         ValidatorsBoard's authority over the three economic entry parameters below
    ///         (entryThresholdBase, growthFactorPerValidator, membershipFeeBps). Before this,
    ///         none of the three setters had a meaningful floor/ceiling — the board (a simple
    ///         3-of-5 majority) could have set entryThresholdBase to zero (free entry),
    ///         growthFactorPerValidator to an astronomically steep value (entry effectively
    ///         impossible after a handful of validators), or membershipFeeBps up to 100% (a new
    ///         entrant paying double their own collateral). A compromised or simply mistaken
    ///         3-person majority could have altered validator-entry economics overnight, with
    ///         no full-assembly vote involved at all. Bounds close off the extremes; the shared
    ///         cooldown (one timer for all three, not one each) prevents the board from making
    ///         several rapid, compounding changes across the three parameters in quick
    ///         succession to reach an extreme combined effect that no single bounded change
    ///         would allow on its own.
    uint256 public constant ENTRY_THRESHOLD_BASE_MIN = 100_000 ether;
    uint256 public constant ENTRY_THRESHOLD_BASE_MAX = 2_000_000 ether;
    uint256 public constant MEMBERSHIP_FEE_BPS_MIN = 100; // 1%
    uint256 public constant MEMBERSHIP_FEE_BPS_MAX = 1000; // 10%
    /// @dev Bounds expressed as the doubling period they imply (not the raw fixed-point factor
    ///      directly), since "every N paid validators" is the economically meaningful unit here
    ///      — the raw factor for a given period is computed as 2^(1/period). Fastest allowed:
    ///      doubles every 20 paid validators. Slowest allowed: every 80.
    uint256 public constant GROWTH_FACTOR_MIN = 1_008701983790398976; // 2^(1/80), doubling every 80
    uint256 public constant GROWTH_FACTOR_MAX = 1_035264923841377536; // 2^(1/20), doubling every 20
    uint256 public constant ECONOMIC_PARAM_CHANGE_MIN_INTERVAL = 180 days;
    uint256 public lastEconomicParamChangeTime;

    /// @notice Base stake required to request membership when there are 0 PAID validators yet
    ///         (i.e., the first person to ever call requestMembership() — regardless of how
    ///         many free, genesis-seeded founding validators are already active; see
    ///         paidValidatorCount above). ✅ CHANGED: lowered from 2,000,000 to 500,000 —
    ///         deliberately, to reduce the capital barrier to entry and broaden who can
    ///         realistically become a validator, reducing ownership-concentration risk. See
    ///         sur-tokenomics.md section 6 for the full reasoning: this does NOT change the
    ///         point at which pure-block-reward income turns negative against fixed operating
    ///         costs (that breakeven depends only on the reward pool and validator count, not on
    ///         this parameter) — it only changes how much capital must be locked up to find out.
    uint256 public entryThresholdBase = 500_000 ether; // 500,000 Suren (18 decimals, like ETH)

    /// @notice ✅ CHANGED: The entry threshold grows CONTINUOUSLY (compounding per additional
    ///         PAID validator, not per active validator, and not in discrete steps): current
    ///         threshold = entryThresholdBase * growthFactorPerValidator^paidValidatorCount.
    ///         Genesis-seeded founding validators do NOT count toward this exponent — see the
    ///         paidValidatorCount doc comment above for why. `growthFactorPerValidator` is a
    ///         fixed-point number with 18 decimals (see
    ///         FIXED_POINT_ONE below); ✅ CHANGED: e.g. 1_017479692102686336 (~1.017480) means
    ///         the threshold grows by ~1.7480% for every additional paid validator — chosen so
    ///         that 40 consecutive paid validators joining multiplies the threshold by exactly
    ///         2x (2^(1/40) ≈ 1.017480), i.e. the threshold doubles every 40 paid validators
    ///         (widened from the original 16 — deliberately, alongside the lower base above, to
    ///         keep the capital barrier from becoming unreasonable even at a large validator
    ///         count; see sur-tokenomics.md section 6), smoothly instead of jumping at each 40th
    ///         validator. This is the "ascending cost curve" from the design doc: it makes
    ///         simultaneously buying >1/3 of the seats exponentially, not linearly, expensive.
    uint256 public growthFactorPerValidator = 1_017479692102686336;

    /// @notice Fixed-point precision used by growthFactorPerValidator and _fixedPow (18 decimals,
    ///         like Suren/ETH itself). 1_000000000000000000 represents 1.0 (no growth).
    uint256 private constant FIXED_POINT_ONE = 1_000000000000000000;

    /// @notice Safety/gas cap: active validator count is clamped to this many when computing the
    ///         entry threshold, so the exponent — and therefore the multiplier — never grows
    ///         unboundedly. ✅ CORRECTED (was stale — the "always 2^32" claim below no longer
    ///         holds since growthFactorPerValidator became board-governable within
    ///         [GROWTH_FACTOR_MIN, GROWTH_FACTOR_MAX]): 1280 was originally chosen as
    ///         40 * 32 to preserve a 2^32 maximum multiplier at the ORIGINAL, then-fixed
    ///         40-validator doubling period. Now that the doubling period can itself range from
    ///         20 to 80 (via the board, within its own guardrail bounds — see
    ///         ENTRY_THRESHOLD_BASE_MIN and friends above), the actual maximum multiplier this
    ///         cap allows varies with whatever growthFactorPerValidator currently is: as low as
    ///         2^(1280/80) = 2^16 at the slowest allowed growth, or as high as 2^(1280/20) = 2^64
    ///         at the fastest. Both remain comfortably far from any real overflow risk in this
    ///         contract's fixed-point (18-decimal) arithmetic — entryThresholdBase (max 2,000,000
    ///         ether) times even 2^64 is many orders of magnitude below uint256's ~1.15e77
    ///         ceiling — so 1280 was never a precisely-tuned overflow boundary, just a
    ///         conservative constant that happens to keep every governable combination safe. It
    ///         does not need to change alongside growthFactorPerValidator.
    uint256 private constant MAX_GROWTH_VALIDATORS = 1280;

    /// @notice Membership fee, as a fraction of currentEntryThreshold(), paid IN ADDITION to
    ///         the collateral. ✅ CORRECTED (was stale — used to say "sent immediately to
    ///         ValidatorsTreasury," describing pre-redesign behavior): forwarded to
    ///         BlockRewardDistributor.receiveMembershipFee() instead, where it is folded into
    ///         the next distribution epoch and paid 100%-pro-rata-by-blocks to active
    ///         validators (fully exempt from the 30% ordinary-fee burn) — see
    ///         "MEMBERSHIP FEE" note above and sur-tokenomics.md section 6. Still non-refundable
    ///         either way. 400 = 4% of the collateral amount.
    uint256 public membershipFeeBps = 400;

    /// @notice Maximum number of new membership requests allowed within entryWindowSeconds.
    /// @dev ✅ FINALIZED — all 8 security parameters below now have real, decided values
    ///      (were 🔶 FILL_IN placeholders through most of this project's design process; see
    ///      sur-master-open-items.md for the discussion that settled each one).
    uint256 public maxEntriesPerWindow = 1;
    uint256 public entryWindowSeconds = 86400; // 24 hours — at most 1 new validator/day

    uint256 public probationPeriod = 604800; // 1 week

    /// @notice ✅ REMOVED (explicit user decision — moved to fully off-chain verification): this
    ///         project used to track an on-chain liveness ratio (95% success rate, minimum check
    ///         coverage, an anti-duplicate throttle tuned against the Verifier's polling cadence)
    ///         computed from a running on-chain log built up by reportLiveness()/
    ///         reportLivenessBatch(). All of that — MIN_CHECK_COVERAGE_BPS,
    ///         EXPECTED_VERIFIER_CADENCE_SECONDS, requiredLivenessRatioBps,
    ///         requiredRecoveryLivenessRatioBps, MIN_LIVENESS_CHECK_INTERVAL, and the packed
    ///         livenessPacked field itself — has been removed. The Verifier now performs this
    ///         exact same ratio computation OFF-CHAIN and reports only the resulting decision
    ///         (StatusDecision below), anchored by a hash of the full evidence package rather
    ///         than reconstructed on-chain from a log the contract no longer keeps. See
    ///         sur-tokenomics.md section 6 and sur-verifier-service-spec.md for the full
    ///         off-chain verification architecture this replaced it with.
    uint256 public recoveryPeriod = 172800;      // 48 hours
    uint256 public slashBps = 100;               // 1% — deliberately light: the entry-threshold
    // base was independently lowered (2,000,000 → 500,000 Suren) specifically to broaden who
    // can realistically afford to become a validator; a heavy slash on top of that smaller
    // collateral would claw back a meaningful chunk of a newer/smaller validator's capital for
    // an honest infrastructure mistake, working against that same goal. 1% is a real, felt
    // consequence without being close to catastrophic for any validator's collateral size.
    uint256 public exitCooldown = 604800;        // 1 week

    /// @notice ✅ REDESIGNED (found during a follow-up review to have a real fairness gap): the
    ///         first version of this safety valve applied the slash IMMEDIATELY at demotion time,
    ///         only switching to "no slash" once the running counter crossed the 20% threshold.
    ///         That meant (a) whichever validators happened to get their demotion transaction
    ///         processed FIRST within a mass-failure window were slashed while later ones in the
    ///         SAME failure were not — an outcome that depends on transaction ordering, not on
    ///         anything the validator did differently; (b) once slashed, those early validators'
    ///         penalties were never reversed even after the pattern became clearly a mass
    ///         failure; (c) the reference count used for the 20% comparison was the LIVE active-
    ///         set size, which itself kept shrinking with each removal, so the threshold being
    ///         compared against was a moving target within the same window. Fixed by deferring
    ///         the slash decision itself: every demotion within a fixed time window (a
    ///         "DemotionEpoch") is recorded but NOT slashed immediately; only once that window
    ///         has fully closed does a single, permissionless call
    ///         (resolvePendingSlash() below) decide — for every validator demoted in that epoch,
    ///         uniformly — whether the FINAL demotion count for the whole window exceeded the
    ///         mass-failure threshold. This makes the outcome depend only on the total pattern
    ///         across the whole window, never on which transaction happened to land first.
    ///         ⚠️ CRITICAL DESIGN CONSTRAINT unchanged from the original version: this must NEVER
    ///         pause or delay REMOVAL from the active set (demoteForInactivity's
    ///         _removeFromActive() call always runs, unconditionally, the moment inactivity is
    ///         detected) — only the SLASH decision is ever deferred. Removing a genuinely-
    ///         inactive validator from getValidators() is what QBFT's quorum calculation needs to
    ///         shrink alongside a shrinking pool of live signers (2f+1 of a smaller list is
    ///         easier to reach); delaying that removal would keep the quorum threshold
    ///         artificially high exactly when fewer validators can actually meet it, making a
    ///         real mass-outage scenario's chain-halting risk WORSE, not better. The slash
    ///         decision, in contrast, is a purely economic matter with zero bearing on consensus,
    ///         so it is the only part that can safely wait for the full picture.
    struct DemotionEpoch {
        uint256 startedAt;
        uint256 referenceCount; // active-validator-count snapshot taken ONCE, when this epoch
        // began — fixed for the epoch's whole lifetime, so the 20% comparison is never a moving
        // target partway through resolving it.
        uint256 demotionCount; // total demotions recorded in this epoch — only ever grows while
        // the epoch is open, then is fixed forever once resolved.
        bool resolved;
        bool wasMassFailure;
    }

    mapping(uint256 => DemotionEpoch) public demotionEpochs;
    uint256 public currentDemotionEpochId; // 0 means "no epoch opened yet"

    uint256 public constant MASS_DEMOTION_WINDOW = 1 hours;
    uint256 public constant MASS_DEMOTION_SLASH_PAUSE_BPS = 2000; // 20% — see resolvePendingSlash()

    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @dev 🔶 FILL_IN: the real genesis timestamp of the live network (NOT block.timestamp of
    ///      whatever machine/moment runs the simulation — see sur-contracts-deploy-notes.md).
    // rolling rate-limit window state
    uint256 public windowStart = 0;
    uint256 public entriesInWindow;

    // ------------------------------------------------------------------
    // ✅ NEW — off-chain verification architecture (explicit user decision, full redesign):
    //
    // The Verifier now checks every node's liveness OFF-CHAIN (hourly). Only STATUS CHANGES are
    // reported on-chain — activation after probation, suspension, or recovery — never a routine
    // "still fine" heartbeat. Each decision carries a hash of the off-chain evidence package that
    // justified it (validator address, decision type + reason, time range checked, the rules/
    // threshold version in effect, timestamped check results for that range, observation source,
    // block-production/peer-connection data, geo-detection result where it mattered, the
    // Verifier's signature, and — for Activation/Recovery — the total/positive counts and 95%
    // ratio computation). The raw evidence itself is NEVER stored on-chain (only its hash) — it
    // stays off-chain, encrypted, held by at least two custodians independent of the Verifier
    // operator, retained 90 days (or until a case closes, if longer), with controlled access for
    // the validator involved and the review authority.
    //
    // ⚠️ The hash alone proves the evidence package was not altered AFTER the fact — it does NOT
    // prove the Verifier's underlying observations were true. This is a deliberate, acknowledged
    // trade-off (stated explicitly during design): moving verification off-chain trades some of
    // the previous on-chain-log's independent verifiability for a large reduction in gas cost.
    // What this mechanism defends against is a Verifier changing its story after being
    // challenged — not a Verifier fabricating a self-consistent story from the very start.
    //
    // Suspension is the only decision type with real teeth (it can lead to a slash), so it is the
    // only one with the full delivery/appeal/vote machinery below. Activation and Recovery are
    // purely positive outcomes — nobody has a stake-losing reason to dispute being promoted — so
    // they only need the evidence hash for transparency, no dispute path.
    //
    // Flow for a Suspension's eventual slash decision:
    //   1. recordSuspension() — validator removed from the active set IMMEDIATELY and
    //      UNCONDITIONALLY (protects QBFT's quorum-shrinking ability — never delayed by anything
    //      below), registered into the existing DemotionEpoch mass-failure window above.
    //   2. Once that DemotionEpoch closes, resolveMassFailureCheck() (permissionless) runs FIRST,
    //      before anything else can happen to this decision — mass-failure exemption always takes
    //      precedence over an individual dispute, exactly as it did before this redesign:
    //        - если mass failure → SlashOutcome.ExemptMassFailure, done, no delivery/appeal ever
    //          needed for this decision.
    //        - if not mass failure → moves on to the delivery step below.
    //   3. The validator can self-confirm having received the evidence package at any time via
    //      confirmDelivery() — this alone proves delivery (deliveryProvenAt = now) and starts the
    //      72-hour appeal-FILING window. Confirming delivery is explicitly NOT an admission that
    //      the accusation itself is true — only that the package was received.
    //   4. If the validator does not self-confirm within DELIVERY_DISPUTE_GRACE_PERIOD, anyone
    //      (typically the Verifier) may call assertDeliveryDisputed() to force the question in
    //      front of the assembly via a dedicated delivery-dispute vote (voteOnDelivery()) — this
    //      MUST resolve (either way) before any slash-confirmation vote can even be filed. If the
    //      assembly finds delivery was never genuinely made available, the slash is permanently
    //      voided (SlashOutcome.VoidedNoDelivery) — the suspension itself (removal from consensus)
    //      is untouched; only the financial penalty disappears.
    //   5. Once delivery is proven (either path), a 72-hour window opens during which the
    //      validator (or anyone acting for them) may fileAppeal(). If they do, the assembly votes
    //      confirmSlash() — simple majority of active validators EXCLUDING the subject validator,
    //      snapshotted at filing time — with a hard 7-day voting deadline separate from the 72h
    //      filing window. No quorum by the deadline means the slash is REJECTED (the burden of
    //      proof sits with whoever wants to slash), but the suspension itself is NOT automatically
    //      reversed — returning to consensus still requires separately proving node health via
    //      the normal recovery path, independent of this vote's outcome.
    //   6. If no appeal is filed within the 72-hour window, anyone may call
    //      executeUncontestedSlash() to apply the slash — an uncontested accusation still results
    //      in the penalty, exactly as an uncontested civil claim would.
    // ------------------------------------------------------------------

    enum DecisionType { Activation, Suspension, Recovery }
    enum DeliveryStatus { NotApplicable, Pending, Confirmed, Disputed }
    enum SlashOutcome { Undetermined, ExemptMassFailure, VoidedNoDelivery, Confirmed, RejectedByVote, RejectedNoQuorum, ExecutedUncontested }

    struct StatusDecision {
        address validator;
        DecisionType decisionType;
        uint256 decidedAt;
        bytes32 evidenceHash; // hash of the full off-chain evidence package — see the
        // architecture note above for exactly what that package must contain.
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

    /// @notice ✅ FIXED (critical bug found in independent review): resolveMassFailureCheck()
    ///         used to only mark the shared DemotionEpoch as `resolved` and set
    ///         `slashOutcome = ExemptMassFailure` for the ONE decisionId passed to it. If two
    ///         suspensions fell in the same epoch, calling resolveMassFailureCheck() for just ONE
    ///         of them would set `demotionEpochs[...].resolved = true` — and
    ///         `_massFailureResolved()` below checked ONLY that epoch-level flag, meaning the
    ///         SECOND decision could pass straight into confirmDelivery/fileAppeal/slash
    ///         execution WITHOUT ever having resolveMassFailureCheck() called for it
    ///         specifically — even if the epoch actually was a mass failure that should have
    ///         exempted it too. This mapping (keyed by decisionId, deliberately kept as a
    ///         SEPARATE mapping rather than a field on StatusDecision above — adding one more
    ///         field there pushed several functions past Solidity's stack-depth limit under the
    ///         optimizer, a real compiler constraint hit while implementing this exact fix, not
    ///         a stylistic choice) closes that gap: resolveMassFailureCheck() now must be called
    ///         once PER DECISION (reusing the shared epoch-level wasMassFailure computation,
    ///         computed only once), and _massFailureResolved() checks this decision-level
    ///         mapping instead of the epoch-level flag.
    mapping(uint256 => bool) private massFailureChecked;

    /// @notice ✅ FIXED (found in independent review): closes a class of bug where a resigned
    ///         validator's OLD board seat/authority could be resurrected. `requestExit()` sets
    ///         this to `true` forever (never cleared, survives `delete validators[msg.sender]`),
    ///         and `requestMembership()` refuses any address for which it is `true`. Coming back
    ///         is a brand-new membership with a brand-new address — no vote, board seat, or
    ///         history carries over. Applies equally to a zero-stake genesis founder: exiting
    ///         and returning under a new address does not resurrect the founder's original terms.
    mapping(address => bool) public permanentlyExited;
    /// @notice ✅ FIXED (independent review, defense in depth against the SAME bug — a second,
    ///         independent layer that does not rely on `permanentlyExited` above): bumped every
    ///         time this address voluntarily exits. `ValidatorsBoard` stamps the epoch value at
    ///         the moment it seats an address, and treats a later mismatch as "no longer this
    ///         membership" regardless of current status — so even if some future code path ever
    ///         let an exited address reach a live status again, a stale board seat could not
    ///         resurrect authority from it.
    mapping(address => uint256) public membershipEpoch;

    // ------------------------------------------------------------------
    // P04 (final decisions): exit handling + reserved amount + exact case binding
    // ------------------------------------------------------------------
    /// @notice The exact decision currently holding this validator's pending-slash lock (0 = none).
    mapping(address => uint256) public pendingSlashDecisionId;
    /// @notice Amount at stake for a case, FIXED when the case is recorded (stake × slashBps at that moment) —
    ///         this is what withdrawStake() reserves and what _executeSlash() takes (capped by the remaining stake).
    mapping(uint256 => uint256) public decisionSlashAmount;
    /// @notice Start time of the alleged violation for pre-exit cases (0 for ordinary suspensions). The evidence
    ///         package (hash on-chain) must show it; the assembly can review it through the normal appeal path.
    mapping(uint256 => uint256) public decisionViolationAt;
    /// @notice The validator's status at the moment it requested exit (only an Active validator can have
    ///         validation-duty violations to answer for).
    mapping(address => uint8) public statusBeforeExit;
    /// @notice How long after an exit request the Verifier may still file a case about conduct BEFORE the request.
    uint256 public constant PRE_EXIT_CLAIM_WINDOW = 72 hours;
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
    /// @dev 🔶 FILL_IN: how long a validator has to self-confirm delivery before anyone may force
    ///      the question to a delivery-dispute vote instead. Not one of the two numbers the user
    ///      explicitly said not to guess, but — same caveat as CAP_CHANGE_TIMELOCK_DELAY in
    ///      ValidatorsTreasury.sol — this materially affects how long a case can sit unresolved,
    ///      so it should be confirmed rather than silently relied upon. 7 days used here only as
    ///      a working placeholder.
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

    /// @dev ✅ FIXED (critical stale-vote bug found in review — same class as
    ///      BlockRewardDistributor's bicameral vote): `required` used to be recomputed live
    ///      from getActiveValidatorCount() on every vote, while `votes` only ever increased and
    ///      was never decremented when a voting validator later exited. This meant a security-
    ///      parameter proposal (slashBps, exitCooldown, and every other ParamKey below) that
    ///      failed to reach majority at a large validator count could later become executable
    ///      with ZERO new votes, purely because the active count shrank enough that the live
    ///      threshold fell below the old, frozen tally. `requiredVotes` and `expiresAt` are now
    ///      both snapshotted/fixed at proposal creation, exactly like BlockRewardDistributor's
    ///      ShareProposal — see that struct's doc comment for the full reasoning.
    struct ParamProposal {
        ParamKey key;
        uint256 newValue;
        uint256 votes;
        uint256 requiredVotes; // ✅ NEW — snapshotted at creation, never recomputed
        uint256 createdAt;
        uint256 expiresAt; // ✅ NEW — can no longer be voted on or executed after this
        bool executed;
    }

    /// @notice ✅ NEW: how long a parameter-change proposal remains votable/executable. A
    ///         proposal that can't gather majority within this window should be re-proposed
    ///         fresh (with a fresh electorate snapshot) rather than left open indefinitely.
    uint256 public constant PARAM_PROPOSAL_EXPIRY = 30 days;

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event MembershipRequested(address indexed validator, uint256 collateralAmount, uint256 feeAmount);
    event ValidatorActivated(address indexed validator);
    event ValidatorDemoted(address indexed validator, uint256 pendingSlashEpoch); // ✅ CHANGED: no
    // longer carries a slashed amount (the slash is now deferred — see DemotionEpoch's doc
    // comment) — carries the epoch ID instead, so off-chain monitoring can find the eventual
    // SlashResolved event for this same epoch.
    event SlashResolved(address indexed validator, uint256 slashedAmount, bool wasMassFailure); // ✅ NEW
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

    /// @notice Current membership fee — a governed fraction of currentEntryThreshold(), paid on
    ///         top of the collateral. ✅ CORRECTED (was stale): NOT sent to ValidatorsTreasury —
    ///         forwarded to BlockRewardDistributor instead, paid out to active validators in the
    ///         next epoch. See the "MEMBERSHIP FEE" note in the contract-level doc comment above.
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
    // Payable: the caller sends native Suren directly with the transaction (msg.value), split
    // into two amounts:
    //   1. `threshold` (currentEntryThreshold()) — kept here as refundable/slashable collateral.
    //   2. `fee` (currentMembershipFee()) — ✅ CHANGED: forwarded to BlockRewardDistributor
    //      (not ValidatorsTreasury) — see the DISTRIBUTOR constant comment above for why.
    // msg.value must equal the exact sum of both — no leftover/overpayment to reason about.
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
    // Liveness reporting — REPLACES the earlier self-attested heartbeat() design entirely.
    // Self-reported heartbeats only proved a wallet could sign a transaction, not that a real
    // node was running or actually producing blocks. Now, only `verifier` (the same operational
    // role used for phone/Telegram verification — see the identity section above) may confirm
    // liveness, after actually checking the validator off-chain:
    //   - Probation / Demoted (recovery): verifier checks whether the candidate's own node is
    //     up and synced (e.g. comparing its reported chain head to the network's real head).
    //   - Active: verifier checks real, on-chain block production (the `miner`/`coinbase` field
    //     of recent blocks — see "Besu QBFT experiment findings", Experiment 1, which confirmed
    //     this field always reflects the true block proposer) over a recent window, not just
    //     whether the address can sign a transaction.
    // Which method verifier used is an off-chain implementation detail; this contract only
    // records the resulting yes/no confirmation. Node endpoints (IPs) are intentionally NOT
    // stored on-chain here (to avoid exposing validators to DDoS) — they live in the same
    // off-chain companion app used for phone/Telegram data, accessible to whoever holds the
    // `verifier` key.
    // ------------------------------------------------------------------

    event LivenessReported(address indexed validator, bool isLive, uint256 timestamp);

    /// @notice Shared internal logic for a single validator's liveness report — called by both
    ///         reportLiveness() (single) and reportLivenessBatch() (looped) below. Kept as one
    ///         function so the two entry points can never drift apart in behavior.
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
    }

    // ------------------------------------------------------------------
    // Recovery after a demotion's recoveryPeriod — same "no dispute path" reasoning as activation.
    // ------------------------------------------------------------------
    function recordRecovery(address validator, bytes32 evidenceHash) external onlyVerifier returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        // ✅ Same accounting-gap protection as before the redesign: a still-unresolved
        // pendingSlashEpoch from the demotion being recovered from must be settled first, or a
        // later re-demotion could overwrite it and permanently lose track of it.
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: resolve the pending slash first");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        _activate(validator);
        decisionId = _recordDecision(validator, DecisionType.Recovery, evidenceHash, 0);
        emit ValidatorReactivated(validator);
    }

    // ------------------------------------------------------------------
    // Suspension — Verifier-reported. Removal from the active set is IMMEDIATE and
    // UNCONDITIONAL (see the architecture note above); only the eventual slash decision goes
    // through the mass-failure check, then the delivery/appeal/vote machinery below.
    // ------------------------------------------------------------------
    function recordSuspension(address validator, bytes32 evidenceHash) external onlyVerifier nonReentrant returns (uint256 decisionId) {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");

        _removeFromActive(validator);

        uint256 epochId = _recordDemotion(v, true); // slash decision deferred — see resolveMassFailureCheck()
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp; // recovery period starts now

        decisionId = _recordDecision(validator, DecisionType.Suspension, evidenceHash, epochId);
        emit ValidatorDemoted(validator, epochId);
    }

    // ------------------------------------------------------------------
    // P04: a case about conduct BEFORE an exit request. An exit request ends validation duty at once and starts the
    // 1-week withdrawal wait; for 72 hours the Verifier may still file a case about earlier conduct. Inactivity AFTER
    // the request is never a violation. The Verifier's bare claim is not enough: the evidence hash, the violation
    // time and the normal mass-failure exemption / delivery / appeal / assembly-vote machinery all apply.
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
    // ✅ NEW: records this demotion into the current (or a freshly-opened) DemotionEpoch and
    //         marks the validator as having a pending slash decision — does NOT touch
    //         lockedStake or transfer anything. Called only by recordSuspension() above. Never
    //         touches active-set membership (see DemotionEpoch's doc comment for why that
    //         separation is a hard requirement).
    // ------------------------------------------------------------------
    function _recordDemotion(ValidatorInfo storage v, bool validatorJustRemovedFromActive) private returns (uint256 epochId) {
        if (currentDemotionEpochId == 0 || block.timestamp >= demotionEpochs[currentDemotionEpochId].startedAt + MASS_DEMOTION_WINDOW) {
            currentDemotionEpochId++;
            DemotionEpoch storage fresh = demotionEpochs[currentDemotionEpochId];
            fresh.startedAt = block.timestamp;
            fresh.referenceCount = activeValidators.length + (validatorJustRemovedFromActive ? 1 : 0); // +1: this validator was already
            // removed from activeValidators by the caller before this runs — snapshotted ONCE
            // here and never touched again, so later removals within the same epoch cannot shift
            // what this epoch's demotions are being measured against.
        }
        epochId = currentDemotionEpochId;
        demotionEpochs[epochId].demotionCount++;
        v.pendingSlashEpoch = epochId;
    }

    /// @notice ✅ REDESIGNED: permissionless — anyone may call this once a validator's
    ///         DemotionEpoch has fully closed. This is now ONLY the mass-failure gate — it no
    ///         longer directly executes or exempts a slash by itself for the non-mass-failure
    ///         case; it just decides whether the mass-failure exemption applies AT ALL. If it
    ///         does, the case is fully closed here (ExemptMassFailure). If it doesn't, the case
    ///         moves on to the delivery/appeal/vote machinery below — it is no longer
    ///         automatically slashed the moment mass-failure is ruled out, unlike before this
    ///         redesign.
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

        // ✅ FIXED: this MUST be set unconditionally, for every decision individually, whether
        // or not the epoch turns out to be a mass failure — this is exactly the flag
        // _massFailureResolved() checks below. Reusing epoch.wasMassFailure (computed once,
        // above) means the shared computation is not repeated, but every decision in the epoch
        // must still go through this function once for itself before it can proceed.
        massFailureChecked[decisionId] = true;

        if (epoch.wasMassFailure) {
            d.slashOutcome = SlashOutcome.ExemptMassFailure;
            _clearPendingSlashIfCurrent(decisionId); // fully closed — no delivery/appeal ever needed
            emit SlashResolved(decisionId, d.validator, SlashOutcome.ExemptMassFailure, 0);
        }
        // if not mass failure: d.delivery is already DeliveryStatus.Pending from _recordDecision
        // above — nothing else to do here. pendingSlashEpoch stays nonzero, still blocking
        // withdrawStake() until the flow below fully resolves.
    }

    // ------------------------------------------------------------------
    // Delivery of the evidence package — the validator's own on-chain confirmation is the
    // primary proof. See the architecture note above for the full rationale.
    // ------------------------------------------------------------------

    /// @notice The pending-slash lock lives on the VALIDATOR, so it is bound to the exact DECISION that
    ///         created it (`pendingSlashDecisionId`). A decision may clear the lock ONLY if it is still
    ///         the one holding it — resolving an old case can never wipe the lock of a newer case (N01).
    ///         `pendingSlashEpoch` is kept in step purely for the external getValidatorInfo() ABI.
    function _clearPendingSlashIfCurrent(uint256 decisionId) private {
        address who = statusDecisions[decisionId].validator;
        if (pendingSlashDecisionId[who] == decisionId) {
            pendingSlashDecisionId[who] = 0;
            validators[who].pendingSlashEpoch = 0;
        }
    }

    /// @notice Confirms ONLY that the evidence package was received — explicitly NOT an
    ///         admission that the suspension's underlying accusation is true. Starts the
    ///         72-hour appeal-FILING window (not the same as the appeal-VOTING period, which
    ///         only starts once an appeal is actually filed).
    /// @notice ✅ FIXED (critical bug found in independent review): every function below that
    ///         moves a suspension's case forward (confirmDelivery, assertDeliveryDisputed,
    ///         fileAppeal, executeUncontestedSlash) now requires this to be true FIRST. Before
    ///         this fix, none of them checked whether resolveMassFailureCheck() had even run —
    ///         meaning a validator could confirm delivery, file an appeal, and have the slash
    ///         voted on and executed (or rejected) BEFORE the 1-hour mass-failure window even
    ///         closed, let alone before anyone knew whether this suspension was part of a mass
    ///         failure. This directly violated the decided rule that mass-failure exemption must
    ///         take precedence over any individual dispute — and once a case reached a final
    ///         SlashOutcome this way, resolveMassFailureCheck() itself would revert afterward
    ///         (its own `slashOutcome == Undetermined` guard), permanently locking out any later
    ///         mass-failure exemption for that case.
    function _massFailureResolved(uint256 decisionId) private view returns (bool) {
        return massFailureChecked[decisionId];
    }

    function confirmDelivery(uint256 decisionId) external {
        StatusDecision storage d = statusDecisions[decisionId];
        require(d.decisionType == DecisionType.Suspension, "ValidatorsRegistry: not a suspension decision");
        require(msg.sender == d.validator, "ValidatorsRegistry: only the subject validator may confirm delivery");
        require(_massFailureResolved(decisionId), "ValidatorsRegistry: mass-failure window not resolved yet");
        require(d.slashOutcome == SlashOutcome.Undetermined, "ValidatorsRegistry: case already resolved");
        require(d.delivery == DeliveryStatus.Pending || d.delivery == DeliveryStatus.Disputed, "ValidatorsRegistry: delivery already confirmed");

        d.delivery = DeliveryStatus.Confirmed;
        d.deliveryProvenAt = block.timestamp;
        // ✅ FIXED (second bug found in the same review — see DeliveryDispute's doc comment):
        // if a delivery dispute is currently open for this decision, the validator's own
        // self-confirmation resolves it immediately and consistently — there is no longer any
        // question left for the assembly to vote on, and leaving the dispute open would let
        // resolveDeliveryDisputeIfExpired() later overwrite this confirmation with
        // VoidedNoDelivery if the vote simply times out without quorum.
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
        // ✅ FIXED (N01): a case that already reached a final outcome (e.g. ExemptMassFailure) must
        // never be reopened — resolveMassFailureCheck() leaves `delivery` at Pending even when it
        // exempts the case, so without this check the dispute path could be opened on a closed case.
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
            requiredVotes: (getActiveValidatorCount() / 2) + 1, // snapshotted — full assembly;
            // the subject validator is NOT excluded here (see DeliveryDispute's doc comment
            // above) — but since they are no longer Active (removed by recordSuspension), they
            // cannot use onlyActiveValidator below anyway, so this is moot in practice.
            resolved: false,
            deliveryConfirmed: false
        });
        emit DeliveryDisputeFiled(decisionId, votingDeadline);
    }

    /// @notice Assembly vote on the narrow factual question "was the evidence package genuinely
    ///         made available to this validator" — never the merits of the suspension itself.
    function voteOnDelivery(uint256 decisionId, bool confirmsDelivery) external onlyActiveValidator {
        DeliveryDispute storage disp = deliveryDisputes[decisionId];
        require(disp.filedAt != 0, "ValidatorsRegistry: no delivery dispute for this decision");
        require(!disp.resolved, "ValidatorsRegistry: delivery dispute already resolved");
        require(block.timestamp <= disp.votingDeadline, "ValidatorsRegistry: delivery-dispute voting period has ended");
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
        // ✅ FIXED (N01, defense in depth — the review explicitly required the RESOLVER to keep
        // the rule too, not only the function that opens a dispute): if the case already reached a
        // final outcome by any other route, this dispute may only close its own record; it must
        // never overwrite the outcome or touch the validator's lock.
        if (d.slashOutcome != SlashOutcome.Undetermined) {
            emit DeliveryDisputeResolved(decisionId, confirmed);
            return;
        }
        if (confirmed) {
            d.delivery = DeliveryStatus.Confirmed;
            d.deliveryProvenAt = block.timestamp;
        } else {
            // ✅ per the user's explicit rule: a delivery dispute lost by the accuser voids ONLY
            // the slash — it does NOT return the validator to consensus (that still requires the
            // normal, independent recovery path).
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
        emit ValidatorActivated(who);
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
            // P04 (final decision): an exit request ends validation duty IMMEDIATELY (removal from the active set — and from
            // the QBFT validator set, and from board authority). It does not erase accountability: for PRE_EXIT_CLAIM_WINDOW
            // (72 h) the Verifier can still file a case about conduct BEFORE this request (recordPreExitViolation), and the
            // amount at stake stays reserved by withdrawStake() until any such case is settled.
            _removeFromActive(msg.sender);
        }

        // ✅ NEW: a paid entrant leaving frees up their slot in the growth curve — the next
        // paid joiner should not be charged as if this departed validator were still counted.
        // Genesis-seeded founders (isPaidEntrant == false) never incremented this counter, so
        // they correctly never decrement it either.
        if (v.isPaidEntrant) {
            paidValidatorCount--;
        }

        statusBeforeExit[msg.sender] = uint8(v.status); // read BEFORE the status changes below
        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;
        // ✅ FIXED: this membership's board authority (if any) is over for good the moment exit is
        // requested — permanentlyExited blocks this address from ever registering again, and
        // membershipEpoch invalidates any board seat still stamped with the old epoch.
        permanentlyExited[msg.sender] = true;
        membershipEpoch[msg.sender]++;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
    }

    /// @notice P04: withdrawal after exitCooldown. If no case is pending the whole stake is paid. If a case is pending, only
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
        // ✅ N01 invariant, enforced in code rather than merely asserted in a comment: recoveryPeriod must stay strictly
        // longer than MASS_DEMOTION_WINDOW. _clearPendingSlashIfCurrent() identifies a case by its demotion EPOCH, which is
        // unambiguous only if one validator can never be suspended twice inside one epoch (suspend → recover → suspend).
        // Validated at proposal time (so an invalid proposal cannot be created and cannot jam its own final vote) and again
        // in _applyParam().
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
            executed: false
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
    /// @notice ✅ REDESIGNED (off-chain verification architecture — the liveness-ratio fields
    ///         this used to return no longer exist on-chain at all; see the architecture note
    ///         above recordSuspension()). ⚠️ CRITICAL for anyone consuming this ABI externally
    ///         (see ValidatorsBoard.sol's own copy of this interface, which caused a real
    ///         cross-contract bug in an earlier version when the two drifted apart): this now
    ///         returns 6 outputs, in this exact order. Any external interface declaring this
    ///         function MUST match this exact order and count, since Solidity decodes external
    ///         call results POSITIONALLY, not by name.
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
}
