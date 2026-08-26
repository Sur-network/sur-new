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
///         GENESIS DEPLOYMENT: ValidatorsRegistry, ValidatorsTreasury, and ValidatorsBoard
///         addresses are fixed constants (see SurAddresses.sol) rather than constructor
///         arguments, because all five structural contracts share a common, pre-agreed genesis
///         address map. Only the initial distributionOracle key (a genuinely rotatable
///         operational credential, not a structural contract) and `_genesisTimestamp` (see
///         "sur-contracts-deploy-notes.md" for why this can't just be `block.timestamp` inside
///         a genesis-simulated constructor) remain constructor arguments.
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
    address public distributionOracle;

    uint256 public immutable deployTime;
    uint256 public lastDistributionTime;
    uint256 public epochCount;

    bool private locked; // simple reentrancy guard

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
    // Constructor — executed once, off-chain, to compute the genesis storage snapshot.
    // See "sur-contracts-deploy-notes.md" for the full recipe.
    // ------------------------------------------------------------------
    constructor(address _distributionOracle, uint256 _genesisTimestamp) {
        require(_distributionOracle != address(0), "BlockRewardDistributor: zero distribution oracle address");

        distributionOracle = _distributionOracle;
        deployTime = _genesisTimestamp;
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

        uint256 totalToDistribute = totalRewards + totalFees;
        require(totalToDistribute > 0, "BlockRewardDistributor: nothing to distribute");
        require(totalToDistribute <= address(this).balance, "BlockRewardDistributor: insufficient contract balance");

        uint256 totalBlocks = 0;
        for (uint256 i = 0; i < blocksMined.length; i++) {
            totalBlocks += blocksMined[i];
        }
        require(totalBlocks > 0, "BlockRewardDistributor: total blocks is zero");

        // --- sanity check: reported block count cannot exceed the physical maximum for this
        // time window. Skipped for epoch 0: deployTime reflects the genesis timestamp, but
        // there is no reliable way to bound "time since genesis" more tightly than "since
        // deployTime", and a network's first distribution call may legitimately cover a long
        // initial period (e.g. more than MIN_DISTRIBUTION_INTERVAL if the oracle was started
        // late) — the bound is only meaningful once lastDistributionTime is a real, on-chain
        // timestamp from a prior call.
        if (epochCount > 0) {
            uint256 elapsed = block.timestamp - lastDistributionTime;
            uint256 maxPossibleBlocks = elapsed / MIN_BLOCK_PERIOD_SECONDS;
            require(totalBlocks <= maxPossibleBlocks, "BlockRewardDistributor: reported blocks exceed physical maximum");
        }

        epochCount++;
        uint256 epochId = epochCount;

        // Treasury's cut is taken only from REWARDS, never from FEES
        uint256 treasuryAmount = (totalRewards * TREASURY_SHARE_BPS) / BPS_DENOMINATOR;
        uint256 remainingRewards = totalRewards - treasuryAmount;

        // Distribute remainingRewards (by block ratio) + all of totalFees (by block ratio) —
        // each validator receives a single combined payout.
        uint256 distributedRewards = 0;
        uint256 distributedFees = 0;
        uint256 validatorCount = 0;

        for (uint256 i = 0; i < validators.length; i++) {
            if (blocksMined[i] == 0) continue;

            address validator = validators[i];
            require(validator != address(0), "BlockRewardDistributor: zero validator address");
            require(REGISTRY.isValidator(validator), "BlockRewardDistributor: address is not an active validator");

            uint256 rewardShare = (remainingRewards * blocksMined[i]) / totalBlocks;
            uint256 feeShare = (totalFees * blocksMined[i]) / totalBlocks;
            uint256 payout = rewardShare + feeShare;
            if (payout == 0) continue;

            distributedRewards += rewardShare;
            distributedFees += feeShare;
            validatorCount++;

            epochValidatorRewardShare[epochId][validator] = rewardShare;
            epochValidatorFeeShare[epochId][validator] = feeShare;
            epochValidatorBlocks[epochId][validator] = blocksMined[i];
            totalRewardsPaid[validator] += rewardShare;
            totalFeesPaid[validator] += feeShare;
            totalBlocksRecorded[validator] += blocksMined[i];

            // single combined transfer per validator for the entire call
            (bool success, ) = validator.call{value: payout}("");
            require(success, "BlockRewardDistributor: validator transfer failed");

            emit ValidatorRewarded(epochId, validator, blocksMined[i], rewardShare, feeShare, payout);
        }

        // Rounding dust from both reward and fee division is added to the treasury's amount
        // so that no wei is left stuck in the contract.
        uint256 rewardDust = remainingRewards - distributedRewards;
        uint256 feeDust = totalFees - distributedFees;
        uint256 totalTreasuryAmount = treasuryAmount + rewardDust + feeDust;

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
