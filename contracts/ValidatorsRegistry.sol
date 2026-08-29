// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

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
///         deployed by a transaction. The initial validator set is therefore passed as a
///         constructor argument (`initialValidators`) and applied immediately in the
///         constructor, instead of a separate post-deploy `bootstrap()` call. Likewise
///         `_genesisTimestamp` must be passed in explicitly — code running inside a constructor
///         that is only ever *simulated* locally to compute the genesis storage snapshot cannot
///         reliably read the real chain's genesis `block.timestamp`; see
///         "sur-contracts-deploy-notes.md" for the exact recipe and why this matters for the
///         rate-limit window and each genesis validator's liveness-confirmation timestamps.
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
///             forwarded immediately and irrevocably to ValidatorsTreasury on entry, exactly
///             like the collateral's slashed portion is. This is what makes new-validator
///             entries add spendable funds to the assembly's shared treasury right away,
///             without turning the collateral itself into communal property (which would break
///             the exit guarantee and blunt slashing as a personal deterrent — see the
///             project's governance-design discussion for why the hybrid split was chosen over
///             making the whole stake treasury-owned).
contract ValidatorsRegistry {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — destination for slashed stake.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

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
        uint256 demotedAt;          // 0 if never demoted / currently not in Demoted status
    }

    mapping(address => ValidatorInfo) public validators;

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
    address public verifier;

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
    // $0.0005, 2,000,000 Suren ~= $1000 collateral per validator seat.
    // ------------------------------------------------------------------

    /// @notice Base stake required to request membership when there are 0 active validators.
    uint256 public entryThresholdBase = 2_000_000 ether; // 2,000,000 Suren (18 decimals, like ETH)

    /// @notice The entry threshold grows CONTINUOUSLY (compounding per additional active
    ///         validator, not in discrete steps): current threshold =
    ///         entryThresholdBase * growthFactorPerValidator^activeValidators.length.
    ///         `growthFactorPerValidator` is a fixed-point number with 18 decimals (see
    ///         FIXED_POINT_ONE below); e.g. 1_044273782427413840 (~1.044274) means the threshold
    ///         grows by ~4.4274% for every additional active validator — chosen so that 16
    ///         consecutive validators joining multiplies the threshold by exactly 2x
    ///         (2^(1/16) ≈ 1.044274), i.e. the threshold doubles every 16 active validators,
    ///         smoothly instead of jumping at each 16th validator. This is the "ascending cost
    ///         curve" from the design doc: it makes simultaneously buying >1/3 of the seats
    ///         exponentially, not linearly, expensive.
    uint256 public growthFactorPerValidator = 1_044273782427413840;

    /// @notice Fixed-point precision used by growthFactorPerValidator and _fixedPow (18 decimals,
    ///         like Suren/ETH itself). 1_000000000000000000 represents 1.0 (no growth).
    uint256 private constant FIXED_POINT_ONE = 1_000000000000000000;

    /// @notice Safety/gas cap: active validator count is clamped to this many when computing the
    ///         entry threshold, so the exponent — and therefore the multiplier — never grows
    ///         unboundedly. 512 = 16 * 32, preserving the same maximum multiplier (2^32) the
    ///         cap has always represented, now scaled to a 16-validator doubling period.
    uint256 private constant MAX_GROWTH_VALIDATORS = 512;

    /// @notice Membership fee, as a fraction of currentEntryThreshold(), paid IN ADDITION to
    ///         the collateral and sent immediately to ValidatorsTreasury (non-refundable — see
    ///         "MEMBERSHIP FEE" note above). 400 = 4% of the collateral amount.
    uint256 public membershipFeeBps = 400;

    /// @notice Maximum number of new membership requests allowed within entryWindowSeconds.
    uint256 public maxEntriesPerWindow;
    uint256 public entryWindowSeconds;

    uint256 public probationPeriod;          // e.g. 1 week
    uint256 public minLivenessConfirmationsToActivate;  // positive liveness reports required during probation before activation
    uint256 public inactivityThreshold;      // continuous absence of positive liveness reports before demotion is allowed
    uint256 public recoveryPeriod;           // continuous period of positive liveness reports required after demotion
    uint256 public slashBps;                 // fraction of locked stake slashed on inactivity demotion
    uint256 public exitCooldown;             // wait time between requestExit() and withdrawStake()

    uint256 private constant BPS_DENOMINATOR = 10000;

    // rolling rate-limit window state
    uint256 public windowStart;
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
        MinLivenessConfirmationsToActivate,
        InactivityThreshold,
        RecoveryPeriod,
        SlashBps,
        ExitCooldown
    }

    struct ParamProposal {
        ParamKey key;
        uint256 newValue;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event MembershipRequested(address indexed validator, uint256 collateralAmount, uint256 feeAmount);
    event ValidatorActivated(address indexed validator);
    event ValidatorDemoted(address indexed validator, uint256 slashedAmount);
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
    // Constructor — executed once, off-chain, to compute the genesis storage snapshot.
    // See "sur-contracts-deploy-notes.md" for the full recipe.
    // ------------------------------------------------------------------
    constructor(
        uint256 _genesisTimestamp,
        address[] memory initialValidators,
        address _verifier,
        uint256 _maxEntriesPerWindow,
        uint256 _entryWindowSeconds,
        uint256 _probationPeriod,
        uint256 _minLivenessConfirmationsToActivate,
        uint256 _inactivityThreshold,
        uint256 _recoveryPeriod,
        uint256 _slashBps,
        uint256 _exitCooldown
    ) {
        require(_slashBps <= BPS_DENOMINATOR, "ValidatorsRegistry: slashBps too high");
        require(_verifier != address(0), "ValidatorsRegistry: zero verifier address");

        verifier = _verifier;
        maxEntriesPerWindow = _maxEntriesPerWindow;
        entryWindowSeconds = _entryWindowSeconds;
        probationPeriod = _probationPeriod;
        minLivenessConfirmationsToActivate = _minLivenessConfirmationsToActivate;
        inactivityThreshold = _inactivityThreshold;
        recoveryPeriod = _recoveryPeriod;
        slashBps = _slashBps;
        exitCooldown = _exitCooldown;

        windowStart = _genesisTimestamp;

        // Seed the genesis validator set directly — no active stake, no probation. These are
        // the network's founding validators, trusted by construction of the genesis block itself.
        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "ValidatorsRegistry: zero address");
            require(validators[v].status == Status.None, "ValidatorsRegistry: duplicate initial validator");

            validators[v] = ValidatorInfo({
                status: Status.Active,
                lockedStake: 0,
                periodStartedAt: _genesisTimestamp,
                lastLivenessConfirmation: _genesisTimestamp,
                livenessConfirmationsInPeriod: 0,
                demotedAt: 0
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
        }
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
    ///         per additional active validator, not in discrete jumps) — see
    ///         `growthFactorPerValidator` above. Capped at MAX_GROWTH_VALIDATORS active
    ///         validators worth of growth, to avoid overflow/unbounded gas.
    function currentEntryThreshold() public view returns (uint256) {
        uint256 n = activeValidators.length;
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
    ///         top of the collateral and sent straight to ValidatorsTreasury. See the
    ///         "MEMBERSHIP FEE" note in the contract-level doc comment above.
    function currentMembershipFee() public view returns (uint256) {
        return (currentEntryThreshold() * membershipFeeBps) / BPS_DENOMINATOR;
    }

    // ------------------------------------------------------------------
    // Economic entry parameter setters — ValidatorsBoard only (its own internal board majority
    // has already approved the change before calling these; see ValidatorsBoard.sol's
    // proposeSetEntryThresholdBase / proposeSetGrowthFactorPerValidator / proposeSetMembershipFeeBps).
    // ------------------------------------------------------------------
    function setEntryThresholdBase(uint256 newValue) external onlyBoard {
        emit EconomicParamUpdatedByBoard("entryThresholdBase", entryThresholdBase, newValue);
        entryThresholdBase = newValue;
    }

    function setGrowthFactorPerValidator(uint256 newValue) external onlyBoard {
        require(newValue > FIXED_POINT_ONE, "ValidatorsRegistry: growth factor must be > 1.0 (must actually grow)");
        emit EconomicParamUpdatedByBoard("growthFactorPerValidator", growthFactorPerValidator, newValue);
        growthFactorPerValidator = newValue;
    }

    function setMembershipFeeBps(uint256 newValue) external onlyBoard {
        require(newValue <= BPS_DENOMINATOR, "ValidatorsRegistry: membershipFeeBps too high");
        emit EconomicParamUpdatedByBoard("membershipFeeBps", membershipFeeBps, newValue);
        membershipFeeBps = newValue;
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
    //   2. `fee` (currentMembershipFee()) — forwarded straight to ValidatorsTreasury, non-refundable.
    // msg.value must equal the exact sum of both — no leftover/overpayment to reason about.
    // ------------------------------------------------------------------
    function requestMembership() external payable nonReentrant {
        require(validators[msg.sender].status == Status.None, "ValidatorsRegistry: already registered");

        uint256 threshold = currentEntryThreshold();
        uint256 fee = currentMembershipFee();
        require(msg.value == threshold + fee, "ValidatorsRegistry: incorrect payment amount");

        _enforceRateLimit();

        if (fee > 0) {
            (bool success, ) = TREASURY.call{value: fee}("");
            require(success, "ValidatorsRegistry: membership fee transfer failed");
        }
        // `threshold` intentionally stays in this contract's own native balance as locked
        // collateral — no transfer needed, it arrived with this same call via msg.value.

        validators[msg.sender] = ValidatorInfo({
            status: Status.Probation,
            lockedStake: threshold,
            periodStartedAt: block.timestamp,
            lastLivenessConfirmation: block.timestamp,
            livenessConfirmationsInPeriod: 0,
            demotedAt: 0
        });

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
        if (isLive) {
            v.lastLivenessConfirmation = block.timestamp;
            v.livenessConfirmationsInPeriod++;
        }
        emit LivenessReported(validator, isLive, block.timestamp);
    }

    // ------------------------------------------------------------------
    // Activation after probation — permissionless
    // ------------------------------------------------------------------
    function promoteAfterProbation(address candidate) external {
        ValidatorInfo storage v = validators[candidate];
        require(v.status == Status.Probation, "ValidatorsRegistry: not in probation");
        require(block.timestamp >= v.periodStartedAt + probationPeriod, "ValidatorsRegistry: probation period not elapsed");
        require(v.livenessConfirmationsInPeriod >= minLivenessConfirmationsToActivate, "ValidatorsRegistry: insufficient liveness confirmations");
        require(block.timestamp - v.lastLivenessConfirmation <= inactivityThreshold, "ValidatorsRegistry: liveness confirmation stale");

        _activate(candidate);
    }

    // ------------------------------------------------------------------
    // Demotion for inactivity — permissionless
    // ------------------------------------------------------------------
    function demoteForInactivity(address validator) external nonReentrant {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Active, "ValidatorsRegistry: not active");
        require(block.timestamp - v.lastLivenessConfirmation >= inactivityThreshold, "ValidatorsRegistry: not yet inactive");

        _removeFromActive(validator);

        uint256 slashAmount = (v.lockedStake * slashBps) / BPS_DENOMINATOR;
        v.lockedStake -= slashAmount;
        v.status = Status.Demoted;
        v.demotedAt = block.timestamp;
        v.periodStartedAt = block.timestamp; // recovery period starts now
        v.livenessConfirmationsInPeriod = 0;

        if (slashAmount > 0) {
            (bool success, ) = TREASURY.call{value: slashAmount}("");
            require(success, "ValidatorsRegistry: slash transfer failed");
        }

        emit ValidatorDemoted(validator, slashAmount);
    }

    // ------------------------------------------------------------------
    // Reactivation after recovery — permissionless
    // ------------------------------------------------------------------
    function promoteAfterRecovery(address validator) external {
        ValidatorInfo storage v = validators[validator];
        require(v.status == Status.Demoted, "ValidatorsRegistry: not demoted");
        require(block.timestamp >= v.periodStartedAt + recoveryPeriod, "ValidatorsRegistry: recovery period not elapsed");
        require(v.livenessConfirmationsInPeriod >= minLivenessConfirmationsToActivate, "ValidatorsRegistry: insufficient recovery liveness confirmations");
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

        if (v.status == Status.Active) {
            _removeFromActive(msg.sender);
        }

        v.status = Status.Exiting;
        v.periodStartedAt = block.timestamp;

        emit ExitRequested(msg.sender, block.timestamp + exitCooldown);
    }

    function withdrawStake() external nonReentrant {
        ValidatorInfo storage v = validators[msg.sender];
        require(v.status == Status.Exiting, "ValidatorsRegistry: not exiting");
        require(block.timestamp >= v.periodStartedAt + exitCooldown, "ValidatorsRegistry: exit cooldown not elapsed");

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
            createdAt: block.timestamp,
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
        require(!paramHasVoted[id][voter], "ValidatorsRegistry: already voted");

        paramHasVoted[id][voter] = true;
        p.votes++;

        uint256 required = (getActiveValidatorCount() / 2) + 1;
        emit ParameterChangeVoted(id, voter, p.votes, required);

        if (p.votes >= required) {
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
        } else if (key == ParamKey.MinLivenessConfirmationsToActivate) {
            minLivenessConfirmationsToActivate = value;
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
        uint256 demotedAt
    ) {
        ValidatorInfo storage v = validators[who];
        return (v.status, v.lockedStake, v.periodStartedAt, v.lastLivenessConfirmation, v.livenessConfirmationsInPeriod, v.demotedAt);
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
