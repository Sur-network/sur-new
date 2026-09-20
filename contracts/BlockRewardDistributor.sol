// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
    function getActiveValidatorCount() external view returns (uint256); // ✅ NEW: needed for the 2/3-of-assembly threshold in the bicameral share-change vote below.
}

/// @notice ✅ NEW: minimal interface onto ValidatorsBoard, needed only to check board
///         membership for the bicameral share-change vote below (see proposeShareChange).
interface IValidatorsBoard {
    function isBoardMember(address who) external view returns (bool);
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

    /// @notice Minimum block production period on the network (from genesis: qbft.blockperiodseconds).
    ///         Used to sanity-check the block count reported by the oracle.
    uint256 public constant MIN_BLOCK_PERIOD_SECONDS = 3;

    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — receives whatever remains of the reward pool after
    ///         Foundation's fixed 15% and validators' governable direct share are both
    ///         removed (no longer a fixed "50% reward cut" — see validatorDirectShareBps).
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice FoundationDAO — receives the new automatic 15%-of-treasury-cut share every
    ///         epoch. This is the only inbound connection FoundationDAO has to the reward flow;
    ///         it never needs to call anything to receive it (see FoundationDAO.sol comments).
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

    /// @dev 🔶 FILL_IN: the real genesis timestamp of the live network (NOT block.timestamp of
    ///      whatever machine/moment runs the simulation — see sur-contracts-deploy-notes.md for
    ///      why block.timestamp is unreliable here). Declared `immutable` so this value is baked
    ///      directly into the deployed bytecode, exactly as it would be if set in a constructor.
    uint256 public immutable deployTime = 0;
    uint256 public lastDistributionTime;
    uint256 public epochCount;

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
    struct ShareProposal {
        uint256 newValidatorShareBps;
        uint256 createdAt;
        uint256 boardApprovals;
        uint256 validatorApprovals;
        bool boardPassed;
        bool validatorPassed;
        bool executed;
    }

    mapping(uint256 => ShareProposal) public shareProposals;
    mapping(uint256 => mapping(address => bool)) private shareBoardVoted;
    mapping(uint256 => mapping(address => bool)) private shareValidatorVoted;
    uint256 public shareProposalCount;

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
        shareProposals[id] = ShareProposal({
            newValidatorShareBps: newValidatorShareBps,
            createdAt: block.timestamp,
            boardApprovals: 0,
            validatorApprovals: 0,
            boardPassed: false,
            validatorPassed: false,
            executed: false
        });
        emit ShareChangeProposed(id, newValidatorShareBps, msg.sender);
    }

    /// @notice One of the two required votes — the ValidatorsBoard chamber. Simple majority of
    ///         the fixed BOARD_SIZE (5), i.e. 3 votes.
    function boardVoteShareChange(uint256 id) external {
        require(BOARD_CONTRACT.isBoardMember(msg.sender), "BlockRewardDistributor: caller is not a board member");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(!shareBoardVoted[id][msg.sender], "BlockRewardDistributor: board member already voted");

        shareBoardVoted[id][msg.sender] = true;
        p.boardApprovals++;
        uint256 required = (BOARD_SIZE / 2) + 1; // 3 of 5
        emit ShareChangeBoardVoted(id, msg.sender, p.boardApprovals, required);

        if (p.boardApprovals >= required) {
            p.boardPassed = true;
        }
        _tryExecuteShareChange(id);
    }

    /// @notice The other required vote — the full validator assembly chamber. Two-thirds of the
    ///         CURRENT active validator count (recomputed live, not snapshotted at proposal
    ///         time — matching the same pattern as ValidatorsRegistry's security-parameter
    ///         votes).
    function validatorVoteShareChange(uint256 id) external {
        require(REGISTRY.isValidator(msg.sender), "BlockRewardDistributor: caller is not an active validator");
        ShareProposal storage p = shareProposals[id];
        require(p.createdAt != 0, "BlockRewardDistributor: proposal not found");
        require(!p.executed, "BlockRewardDistributor: already executed");
        require(!shareValidatorVoted[id][msg.sender], "BlockRewardDistributor: validator already voted");

        shareValidatorVoted[id][msg.sender] = true;
        p.validatorApprovals++;
        uint256 activeCount = REGISTRY.getActiveValidatorCount();
        uint256 required = (activeCount * 2 + 2) / 3; // ceil(2 * activeCount / 3)
        emit ShareChangeValidatorVoted(id, msg.sender, p.validatorApprovals, required);

        if (p.validatorApprovals >= required) {
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
    function distributeRewards(
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

        // Fold any membership fees forwarded by ValidatorsRegistry since the last epoch into
        // this epoch's fee pool — they are already sitting in this contract's balance (received
        // via receiveMembershipFee()), so they simply join ordinary fees and get the exact same
        // 100%-pro-rata-by-blocks treatment. See sur-tokenomics.md section 6.
        uint256 membershipFeesThisEpoch = pendingMembershipFees;
        pendingMembershipFees = 0;
        uint256 effectiveTotalFees = totalFees + membershipFeesThisEpoch;

        require(totalRewards + effectiveTotalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalRewards + effectiveTotalFees <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        // ✅ NEW: burn a fixed 30% — but ONLY of ordinary transaction fees (totalFees),
        // deliberately NOT of membershipFeesThisEpoch. Rationale (see sur-tokenomics.md
        // section 6): the membership fee is not a general network fee at all — it is a
        // targeted, one-time dilution-compensation payment to existing validators, triggered
        // by a new validator's entry. Burning part of it would silently weaken that specific
        // incentive mechanism as an unintended side effect of a later, unrelated decision
        // (the general fee-burn). Ordinary fees have no such earmarked purpose, so they are
        // the correct — and only — burn target.
        uint256 feeBurnAmount = (totalFees * FEE_BURN_BPS) / BPS_DENOMINATOR;
        uint256 feesToDistribute = effectiveTotalFees - feeBurnAmount;

        uint256 totalBlocks = _sumBlocks(blocksMined);
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
        _checkPhysicalMaximum(totalBlocks);

        epochCount++;
        uint256 epochId = epochCount;

        // ✅ CHANGED: Foundation's cut is now a fixed 15% of TOTAL rewards, taken independently
        // off the top — never affected by validatorDirectShareBps below. Only REWARDS are
        // split this way; FEES (below) are never touched by any of these three shares.
        uint256 foundationAmount = (totalRewards * FOUNDATION_SHARE_BPS) / BPS_DENOMINATOR;
        // validatorDirectShareBps is governable (bicameral vote, [40%, 65%]) — see the
        // contract-level doc comment. ValidatorsTreasury receives whatever remains of the
        // reward pool after Foundation's fixed share and this governable share are both
        // removed.
        uint256 validatorDirectAmount = (totalRewards * validatorDirectShareBps) / BPS_DENOMINATOR;
        uint256 treasuryAmount = totalRewards - foundationAmount - validatorDirectAmount;

        (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) =
            _payValidators(
                validators,
                blocksMined,
                EpochContext({
                    epochId: epochId,
                    remainingRewards: validatorDirectAmount,
                    totalFees: feesToDistribute,
                    totalBlocks: totalBlocks
                })
            );

        _finalizeEpoch(
            epochId,
            totalRewards,
            effectiveTotalFees,
            feeBurnAmount,
            treasuryAmount,
            foundationAmount,
            totalBlocks,
            validatorCount,
            distributedRewards,
            distributedFees
        );
    }

    /// @dev Sums the reported per-validator block counts. Split out of distributeRewards purely
    ///      to keep that function's own stack frame small (see the refactor note above) — no
    ///      behavior change from the original inline loop.
    function _sumBlocks(uint256[] calldata blocksMined) private pure returns (uint256 totalBlocks) {
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
    }

    /// @dev Sanity check: reported block count cannot exceed the physical maximum for this time
    ///      window. Skipped for epoch 0 — see the original inline comment this was moved from,
    ///      preserved in full below. Split out purely for stack-depth reasons.
    ///
    ///      Skipped for epoch 0: deployTime reflects the genesis timestamp, but there is no
    ///      reliable way to bound "time since genesis" more tightly than "since deployTime", and
    ///      a network's first distribution call may legitimately cover a long initial period
    ///      (e.g. more than MIN_DISTRIBUTION_INTERVAL if the oracle was started late) — the
    ///      bound is only meaningful once lastDistributionTime is a real, on-chain timestamp
    ///      from a prior call.
    function _checkPhysicalMaximum(uint256 totalBlocks) private view {
        if (epochCount > 0) {
            uint256 elapsed = block.timestamp - lastDistributionTime;
            uint256 maxPossibleBlocks = elapsed / MIN_BLOCK_PERIOD_SECONDS;
            require(totalBlocks <= maxPossibleBlocks, "BlockRewardDistributor: reported blocks exceed physical maximum");
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
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            require(REGISTRY.isValidator(validator), "BlockRewardDistributor: address is not an active validator");

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
