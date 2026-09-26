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
        uint256 lastLivenessConfirmation;
        uint256 livenessConfirmationsInPeriod; // positive liveness reports since periodStartedAt (reset each period)
        uint256 totalLivenessChecksInPeriod; // ✅ NEW: ALL liveness reports (positive + negative)
        // since periodStartedAt — see requiredLivenessRatioBps below for why counting only
        // positives was not enough on its own.
        uint256 lastCheckedAt; // ✅ NEW: timestamp of the last liveness report that was actually
        // COUNTED (toward totalLivenessChecksInPeriod) — separate from lastLivenessConfirmation
        // (which only updates on positive reports). See MIN_LIVENESS_CHECK_INTERVAL below for why
        // this exists: without it, any rapid/duplicate calls to reportLiveness() (a bug in the
        // off-chain Verifier service, or a compromised verifier key firing repeatedly) would each
        // count as an independent "turn" toward the ratio, even if they happened seconds apart —
        // meaning "48 hours of 95% positive reports" would not actually mean 48 hours of
        // real-world monitoring at the expected ~10-15 minute cadence.
        uint256 pendingSlashEpoch; // ✅ NEW: nonzero while this validator has an unresolved
        // inactivity-slash decision awaiting resolvePendingSlash() — see DemotionEpoch's doc
        // comment above for the full mechanism this supports. Zero means "no pending slash."
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
    // `verifier` remains here, but for a single purpose only: reporting `reportLiveness`
    // (further below in this file). This is a completely separate key from `identityOracle` in
    // `IdentityRegistry.sol` — these two roles (node liveness vs. identity verification) are
    // deliberately kept independent.
    // ------------------------------------------------------------------

    /// @notice Operational key trusted to report validator liveness — see reportLiveness below.
    ///         Rotatable by ValidatorsBoard — see setVerifier.
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
    //     livenessConfirmationsInPeriod: 0, totalLivenessChecksInPeriod: 0, lastCheckedAt: 0, pendingSlashEpoch: 0, demotedAt: 0, isPaidEntrant: false });
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

    /// @notice ✅ FIXED (found during a follow-up review — the previous version had a real
    ///         numerical bug, since resolved by a firm decision): the minimum FRACTION of checks
    ///         that must actually have been recorded before the ratio requirement is even
    ///         evaluated. ⚠️ The earlier version computed the "maximum possible checks" using
    ///         MIN_LIVENESS_CHECK_INTERVAL when it was still a 5-minute THROTTLE bound (how fast
    ///         a check CAN legally be counted), separate from the Verifier's real-world cadence
    ///         (previously an ambiguous "10-15 minutes"). That mismatch could have made this
    ///         requirement impossible to satisfy for a perfectly healthy validator. ✅ RESOLVED:
    ///         MIN_LIVENESS_CHECK_INTERVAL is now DECIDED at a firm 10 minutes — the Verifier's
    ///         actual, real polling interval, not just a loose bound below an uncertain range —
    ///         so it is now correct to use it directly as this calculation's basis (see
    ///         _minRequiredChecks() below). Both this coverage requirement AND the interval
    ///         throttle above are deliberately kept as two separate, independent requirements:
    ///         the interval stops rapid/duplicate counting, this stops too few checks overall.
    ///         Without this coverage check, a single positive check arriving at any point — even
    ///         right at the end of the window — would otherwise have produced a 100% ratio and
    ///         satisfied requiredLivenessRatioBps with zero real monitoring history.
    /// @dev ⚠️ Known residual limitation, deliberately accepted rather than solved with
    ///      additional complexity: a minimum TOTAL count does not by itself guarantee the checks
    ///      were spread evenly across the period — they could legally cluster near the end (e.g.,
    ///      the required count for probation could all land within the last ~3.5 days of the
    ///      week, at the 10-minute interval) while the earlier days went unmonitored. This was
    ///      raised explicitly during design and kept as-is: adding a maximum-gap constraint on
    ///      top would close it, but was judged not worth the added contract complexity given the
    ///      other layers already in place (the interval throttle, the 95% ratio requirement
    ///      itself, and the separate recency check below) — this can be revisited later if
    ///      real-world monitoring shows validators exploiting the gap in practice.
    uint256 public constant MIN_CHECK_COVERAGE_BPS = 5000; // 50%

    /// @notice ✅ REDESIGNED (replaces the earlier minLivenessConfirmationsToActivate — a raw
    ///         count of positive reports, found during review to have a real flaw): a raw count
    ///         only ever increases on a positive report and is completely unaffected by
    ///         negative ones — meaning a validator that was reliably online for only the last
    ///         few days of probation, after being offline earlier, could pass exactly as easily
    ///         as one that was reliable the entire period, as long as they accumulated enough
    ///         late positives. This field instead requires a MINIMUM SUCCESS RATE across every
    ///         liveness check made during the period (positive and negative both count toward
    ///         the denominator — see totalLivenessChecksInPeriod above), so intermittent
    ///         unreliability anywhere in the window is reflected proportionally, not hidden by a
    ///         strong finish. ✅ DECIDED: 9500 = 95% — see sur-tokenomics.md section 6 for the
    ///         full discussion of why 95% (not a looser 90%) was chosen, and why a ratio was
    ///         chosen over a fixed "N failures resets everything" rule (rejected: an all-or-
    ///         nothing reset near the finish line was judged more punishing than informative,
    ///         and a global reset even for a single UNLUCKY late failure was seen as
    ///         disproportionate to a validator's real overall reliability).
    /// @dev ✅ SPLIT (found during review — was a single shared field for both probation and
    ///      recovery, which meant they could never have different minimums even if a future
    ///      decision wanted recovery to be stricter or looser than initial activation). Now two
    ///      independent parameters — both currently 95%, but each governable on its own.
    uint256 public requiredLivenessRatioBps = 9500; // used by promoteAfterProbation
    uint256 public requiredRecoveryLivenessRatioBps = 9500; // used by promoteAfterRecovery

    /// @notice ✅ DECIDED (10 minutes, final): the minimum time that must pass since a
    ///         validator's last COUNTED liveness check before another one is counted — this now
    ///         IS the Verifier's real, firm polling interval (no longer a "10-15 minute" range;
    ///         see sur-verifier-service-spec.md for the confirmed decision), not just a loose
    ///         anti-abuse throttle set below it. Without this, nothing stopped a malfunctioning
    ///         or compromised verifier key from firing reportLiveness() many times in rapid
    ///         succession — each call would count as an independent "check" toward the ratio
    ///         above, even seconds apart. See MIN_CHECK_COVERAGE_BPS above for how this interval
    ///         also feeds into the separate minimum-total-checks requirement.
    uint256 public constant MIN_LIVENESS_CHECK_INTERVAL = 10 minutes;

    uint256 public inactivityThreshold = 3600;   // 1 hour
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

    bool private locked; // reentrancy guard

    // ------------------------------------------------------------------
    // Parameter governance (full validator vote) — everything EXCEPT the three economic entry
    // parameters above (those are ValidatorsBoard-governed; see ValidatorsBoard.sol).
    // ------------------------------------------------------------------

    enum ParamKey {
        MaxEntriesPerWindow,
        EntryWindowSeconds,
        ProbationPeriod,
        RequiredLivenessRatioBps,
        RequiredRecoveryLivenessRatioBps,
        InactivityThreshold,
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
            lastLivenessConfirmation: block.timestamp,
            livenessConfirmationsInPeriod: 0,
            totalLivenessChecksInPeriod: 0,
            lastCheckedAt: 0,
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

    /// @notice Report whether `validator` was confirmed live (see method notes above). Only
    ///         updates state on a positive confirmation — a negative report is logged (for
    ///         transparency/audit) but does not touch the stored counters, since the whole
    ///         point of inactivity detection is the ABSENCE of positive confirmations over time.
    function reportLiveness(address validator, bool isLive) external onlyVerifier {
        ValidatorInfo storage v = validators[validator];
        require(
            v.status == Status.Probation || v.status == Status.Active || v.status == Status.Demoted,
            "ValidatorsRegistry: validator not eligible for liveness reporting"
        );
        emit LivenessReported(validator, isLive, block.timestamp);
        // ✅ NEW: skip counting (but still emit the event above, for full audit visibility) if
        // this report arrived too soon after the last COUNTED one — see
        // MIN_LIVENESS_CHECK_INTERVAL's doc comment for why. Deliberately does not revert: the
        // onlyVerifier caller made a valid call and should not see a failed transaction just
        // because its own polling cadence (or a bug in it) was too fast this one time.
        if (block.timestamp < v.lastCheckedAt + MIN_LIVENESS_CHECK_INTERVAL) {
            return;
        }
        v.lastCheckedAt = block.timestamp;
        v.totalLivenessChecksInPeriod++; // every COUNTED check toward the denominator, positive
        // or not — see requiredLivenessRatioBps's doc comment for why.
        if (isLive) {
            v.lastLivenessConfirmation = block.timestamp;
            v.livenessConfirmationsInPeriod++;
        }
    }

    // ------------------------------------------------------------------
    // Activation after probation — permissionless
    // ------------------------------------------------------------------
    /// @notice ✅ FIXED: now that MIN_LIVENESS_CHECK_INTERVAL is DECIDED as the Verifier's real,
    ///         firm 10-minute polling interval (not just an ambiguous throttle bound below an
    ///         uncertain 10-15 minute range), it is correct to use it directly here — see
    ///         MIN_CHECK_COVERAGE_BPS's doc comment above for the numerical bug this fixes.
    function _minRequiredChecks(uint256 periodDuration) private pure returns (uint256) {
        return (periodDuration / MIN_LIVENESS_CHECK_INTERVAL) * MIN_CHECK_COVERAGE_BPS / BPS_DENOMINATOR;
    }

    function promoteAfterProbation(address candidate) external {
        ValidatorInfo storage v = validators[candidate];
        require(v.status == Status.Probation, "ValidatorsRegistry: not in probation");
        require(block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        require(
            v.totalLivenessChecksInPeriod >= _minRequiredChecks(probationPeriod),
            "ValidatorsRegistry: not enough liveness checks recorded yet"
        );
        require(
            v.livenessConfirmationsInPeriod * BPS_DENOMINATOR >= v.totalLivenessChecksInPeriod * requiredLivenessRatioBps,
            "ValidatorsRegistry: liveness success rate too low"
        );
        require(block.timestamp - v.lastLivenessConfirmation <= inactivityThreshold, "ValidatorsRegistry: liveness confirmation stale");

        _activate(candidate);
    }

    // ------------------------------------------------------------------
    // Demotion for inactivity — permissionless
    // ------------------------------------------------------------------
    /// @notice ✅ NEW: records this demotion into the current (or a freshly-opened) DemotionEpoch
    ///         and marks the validator as having a pending slash decision — does NOT touch
    ///         lockedStake or transfer anything. Called by demoteForInactivity() and
    ///         requestExit()'s anti-flee check below. Never touches active-set membership (see
    ///         DemotionEpoch's doc comment for why that separation is a hard requirement).
    function _recordDemotion(ValidatorInfo storage v) private returns (uint256 epochId) {
        if (currentDemotionEpochId == 0 || block.timestamp >= demotionEpochs[currentDemotionEpochId].startedAt + MASS_DEMOTION_WINDOW) {
            currentDemotionEpochId++;
            DemotionEpoch storage fresh = demotionEpochs[currentDemotionEpochId];
            fresh.startedAt = block.timestamp;
            fresh.referenceCount = activeValidators.length + 1; // +1: this validator was already
            // removed from activeValidators by the caller before this runs — snapshotted ONCE
            // here and never touched again, so later removals within the same epoch cannot shift
            // what this epoch's demotions are being measured against.
        }
        epochId = currentDemotionEpochId;
        demotionEpochs[epochId].demotionCount++;
        v.pendingSlashEpoch = epochId;
    }

    /// @notice ✅ NEW: permissionless — anyone may call this once a validator's DemotionEpoch has
    ///         fully closed, to resolve whether their slash actually applies. Deliberately
    ///         separate from _recordDemotion(): by the time this runs, the epoch's final
    ///         demotionCount is fixed (the window has closed, so no more demotions can be added
    ///         to it), so every validator demoted within the same epoch gets exactly the same
    ///         answer, regardless of the order their individual demotions or resolve calls
    ///         happened in.
    function resolvePendingSlash(address validator) external nonReentrant {
        ValidatorInfo storage v = validators[validator];
        uint256 epochId = v.pendingSlashEpoch;
        require(epochId != 0, "ValidatorsRegistry: no pending slash for this validator");
        DemotionEpoch storage epoch = demotionEpochs[epochId];
        require(block.timestamp >= epoch.startedAt + MASS_DEMOTION_WINDOW, "ValidatorsRegistry: demotion epoch not yet closed");

        if (!epoch.resolved) {
            epoch.resolved = true;
            epoch.wasMassFailure = epoch.demotionCount * BPS_DENOMINATOR > epoch.referenceCount * MASS_DEMOTION_SLASH_PAUSE_BPS;
        }

        v.pendingSlashEpoch = 0;

        uint256 slashAmount = 0;
        if (!epoch.wasMassFailure) {
            slashAmount = (v.lockedStake * slashBps) / BPS_DENOMINATOR;
            v.lockedStake -= slashAmount;
            if (slashAmount > 0) {
                (bool success, ) = TREASURY.call{value: slashAmount}("");
                require(success, "ValidatorsRegistry: slash transfer failed");
            }
        }

        emit SlashResolved(validator, slashAmount, epoch.wasMassFailure);
    }

    function demoteForInactivity(address validator) external nonReentrant {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(block.timestamp - v.lastLivenessConfirmation >= inactivityThreshold, "ValidatorsRegistry: not yet inactive");

        // ✅ UNCONDITIONAL — see DemotionEpoch's doc comment: this must never be paused or
        // delayed, regardless of the mass-failure question resolved later, to protect QBFT's
        // ability to shrink its quorum requirement alongside a shrinking pool of genuinely live
        // validators.
        _removeFromActive(validator);

        uint256 epochId = _recordDemotion(v); // slash decision deferred — see resolvePendingSlash()
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp; // recovery period starts now
        v.livenessConfirmationsInPeriod = 0;
        v.totalLivenessChecksInPeriod = 0;
        v.lastCheckedAt = 0; // ✅ NEW — so the very first liveness check of the fresh recovery
        // period is never accidentally throttled by MIN_LIVENESS_CHECK_INTERVAL referencing a
        // check from before this reset.

        emit ValidatorDemoted(validator, epochId);
    }

    // ------------------------------------------------------------------
    // Reactivation after recovery — permissionless
    // ------------------------------------------------------------------
    function promoteAfterRecovery(address validator) external {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        // ✅ NEW (found during a follow-up review — a real accounting gap): without this, a
        // validator could return to Active with a still-unresolved pendingSlashEpoch from THIS
        // demotion, then be demoted again later — at which point _recordDemotion() would
        // OVERWRITE pendingSlashEpoch with the new epoch's ID, permanently losing any way to
        // reach the first pending slash decision (it would never be resolved, and its Suren
        // would sit stuck in this contract's balance forever, tracked nowhere). Requiring
        // resolution first closes this cleanly, using the same permissionless
        // resolvePendingSlash() anyone can already call.
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: resolve the pending slash first");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        require(
            v.totalLivenessChecksInPeriod >= _minRequiredChecks(recoveryPeriod),
            "ValidatorsRegistry: not enough liveness checks recorded yet"
        );
        require(
            v.livenessConfirmationsInPeriod * BPS_DENOMINATOR >= v.totalLivenessChecksInPeriod * requiredRecoveryLivenessRatioBps,
            "ValidatorsRegistry: recovery liveness success rate too low"
        );
        require(block.timestamp - v.lastLivenessConfirmation <= inactivityThreshold, "ValidatorsRegistry: liveness confirmation stale");

        _activate(validator);
        emit ValidatorReactivated(validator);
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

        bool hasPendingSlash = false;
        if (v.status == Status.Active) {
            // ✅ NEW (closes the "flee before demotion" loophole found during review): if this
            // validator was ALREADY eligible for demoteForInactivity() at this exact moment
            // (same criterion that function itself checks), record the same deferred slash
            // decision right here, before removal — otherwise an operator watching their own
            // node fail could simply call requestExit() a moment before someone calls
            // demoteForInactivity() on them, and walk away with their full collateral after
            // nothing but the ordinary exitCooldown. This does not introduce any NEW judgment
            // call: it is the exact same "already past inactivityThreshold" test
            // demoteForInactivity() uses, applied here instead of there — a validator that was
            // genuinely still within the threshold owes nothing extra, exactly as before.
            // ✅ FIXED (found during a follow-up review): _removeFromActive() must run BEFORE
            // _recordDemotion() here, exactly matching demoteForInactivity()'s order — otherwise
            // the epoch's referenceCount snapshot (activeValidators.length + 1) would be taken
            // while this validator was STILL counted in activeValidators, making it exactly one
            // higher than an equivalent demotion via demoteForInactivity() would produce. Near
            // the 20% mass-failure boundary, that one-off difference could change the outcome
            // depending purely on which code path triggered the demotion — not anything about
            // the actual failure pattern.
            _removeFromActive(msg.sender);
            if (block.timestamp - v.lastLivenessConfirmation >= inactivityThreshold) {
                _recordDemotion(v);
                hasPendingSlash = true;
            }
        }

        // ✅ NEW: a paid entrant leaving frees up their slot in the growth curve — the next
        // paid joiner should not be charged as if this departed validator were still counted.
        // Genesis-seeded founders (isPaidEntrant == false) never incremented this counter, so
        // they correctly never decrement it either.
        if (v.isPaidEntrant) {
            paidValidatorCount--;
        }

        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
        if (hasPendingSlash) {
            emit ValidatorDemoted(msg.sender, v.pendingSlashEpoch); // ✅ same event
            // demoteForInactivity() would have emitted — an exit that was really a late-caught
            // inactivity demotion should be visible to any off-chain monitoring exactly the same
            // way, resolvePendingSlash() included.
        }
    }

    function withdrawStake() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Exiting, "ValidatorsRegistry: not exiting");
        require(block.timestamp >= v.periodStartedAt + exitCooldown, "ValidatorsRegistry: exit cooldown not elapsed");
        // ✅ NEW: closes a residual loophole — without this, a validator with a still-unresolved
        // pending slash (see DemotionEpoch's doc comment) could withdraw their FULL collateral
        // before resolvePendingSlash() ever gets a chance to run, permanently avoiding it.
        // MASS_DEMOTION_WINDOW (1 hour) is always far shorter than exitCooldown (1 week), so this
        // should essentially never actually block a legitimate withdrawal in practice — it exists
        // purely as a safety net.
        require(v.pendingSlashEpoch == 0, "ValidatorsRegistry: resolve the pending slash first");

        uint256 amount = v.lockedStake;
        delete validators[msg.sender];

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
        } else if (key == ParamKey.RequiredLivenessRatioBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: ratio cannot exceed 100%");
            requiredLivenessRatioBps = value;
        } else if (key == ParamKey.RequiredRecoveryLivenessRatioBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: ratio cannot exceed 100%");
            requiredRecoveryLivenessRatioBps = value;
        } else if (key == ParamKey.InactivityThreshold) {
            inactivityThreshold = value;
        } else if (key == ParamKey.RecoveryPeriod) {
            recoveryPeriod = value;
        } else if (key == ParamKey.SlashBps) {
            require(value <= BPS_DENOMINATOR, "ValidatorsRegistry: slashBps too high");
            slashBps = value;
        } else if (key == ParamKey.ExitCooldown) {
            exitCooldown = value;
        }
        emit ParameterChangeApplied(key, value);
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------
    function getValidatorInfo(address who) external view returns (
        Status status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 lastLivenessConfirmation,
        uint256 livenessConfirmationsInPeriod,
        uint256 totalLivenessChecksInPeriod,
        uint256 demotedAt,
        bool isPaidEntrant
    ) {
        ValidatorInfo storage v = validators[who];
        return (v.status, v.lockedStake, v.periodStartedAt, v.lastLivenessConfirmation, v.livenessConfirmationsInPeriod, v.totalLivenessChecksInPeriod, v.demotedAt, v.isPaidEntrant);
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
