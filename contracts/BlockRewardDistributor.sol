// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function isValidator(address who) external view returns (bool);
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
///         Distribution rules (final model — design doc section 3):
///           - From total REWARDS: 50% (TREASURY_SHARE_BPS) goes to ValidatorsTreasury, the
///             rest is split among validators proportionally to blocks mined.
///           - From total FEES: 100% is split among validators proportionally to blocks mined
///             (no treasury cut on fees).
///           - Each validator receives exactly one payment per call (a single combined
///             transfer of reward share + fee share).
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

    /// @notice Treasury's share of total REWARDS (not fees) — basis points out of 10000 = 100%.
    uint256 public constant TREASURY_SHARE_BPS = 5000; // 50%
    uint256 private constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum allowed interval between two consecutive distribution calls.
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 23 hours;

    /// @notice Minimum block production period on the network (from genesis: qbft.blockperiodseconds).
    ///         Used to sanity-check the block count reported by the oracle.
    uint256 public constant MIN_BLOCK_PERIOD_SECONDS = 3;

    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice ValidatorsTreasury — receives the 50% reward cut.
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    /// @notice ValidatorsBoard — the only address allowed to rotate distributionOracle (a
    ///         delegated power explicitly granted to the board; see design doc section 4).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    /// @notice ValidatorsRegistry — single source of truth for validator eligibility, checked
    ///         directly on every payout, no intermediary oracle.
    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

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

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event DistributionOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RewardsReceived(address indexed from, uint256 amount);
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
        require(totalRewards + totalFees > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalRewards + totalFees <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        uint256 totalBlocks = _sumBlocks(blocksMined);
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");
        _checkPhysicalMaximum(totalBlocks);

        epochCount++;
        uint256 epochId = epochCount;

        // Treasury's cut is taken only from REWARDS, never from FEES
        uint256 treasuryAmount = (totalRewards * TREASURY_SHARE_BPS) / BPS_DENOMINATOR;

        (uint256 distributedRewards, uint256 distributedFees, uint256 validatorCount) =
            _payValidators(
                validators,
                blocksMined,
                EpochContext({
                    epochId: epochId,
                    remainingRewards: totalRewards - treasuryAmount,
                    totalFees: totalFees,
                    totalBlocks: totalBlocks
                })
            );

        _finalizeEpoch(
            epochId,
            totalRewards,
            totalFees,
            treasuryAmount,
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
        uint256 treasuryAmount,
        uint256 totalBlocks,
        uint256 validatorCount,
        uint256 distributedRewards,
        uint256 distributedFees
    ) private {
        // Rounding dust from both reward and fee division is added to the treasury's amount
        // so that no wei is left stuck in the contract.
        uint256 totalTreasuryAmount = treasuryAmount + (totalRewards - treasuryAmount - distributedRewards) + (totalFees - distributedFees);

        if (totalTreasuryAmount > 0) {
            (bool tsuccess, ) = TREASURY.call{value: totalTreasuryAmount}("");
            require(tsuccess, "BlockRewardDistributor: treasury transfer failed");
        }

        totalDistributedToValidators += (distributedRewards + distributedFees);
        totalDistributedToTreasury += totalTreasuryAmount;
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
