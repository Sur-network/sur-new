// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
}

/// @title ValidatorsTreasury
/// @notice Deployed at the fixed genesis address SurAddresses.VALIDATORS_TREASURY (0x5555...5555).
///         Holds native Suren only — Suren is the SUR chain's own base/gas currency (like ETH on
///         Ethereum, credited via genesis `alloc` balances and ordinary value transfers), NOT an
///         ERC20 token, so there is no separate token contract or `transferFrom` involved
///         anywhere in this system.
///
///         Two inflows, both native currency:
///           - 50% of every block's reward share from BlockRewardDistributor (see design doc
///             section 3: "50% of the block reward goes to the validators' treasury").
///             Transaction fees never flow here — 100% of fees go directly to validators by
///             block ratio.
///           - The membership fee (+ slashed collateral) forwarded directly by ValidatorsRegistry
///             on every new validator's entry / every inactivity-demotion (see
///             ValidatorsRegistry's "MEMBERSHIP FEE" doc comment for the hybrid stake model).
///
///         Two spending paths, matching the governance structure in the design doc:
///
///           1. FULL VALIDATOR VOTE (this contract): any expenditure, proposed by an active
///              validator, approved by a majority of currently active validators.
///              ⚠️ FoundationDAO has NO access to this contract at all (an earlier
///              foundation-initiated "budget request" path was removed as unnecessary — see
///              FoundationDAO.sol). If the foundation needs funds, an active validator or a
///              ValidatorsBoard member must propose it themselves.
///           2. BOARD-DELEGATED (ValidatorsBoard only, a fixed genesis address): routine,
///              small expenditures below SMALL_BUDGET_CAP, callable only after ValidatorsBoard's
///              own internal board majority has approved the request. The cap itself, like
///              every other security parameter here, can only be changed by full validator
///              vote — the board cannot raise its own spending limit.
///
///         GENESIS DEPLOYMENT: ValidatorsBoard's address is a fixed constant (see
///         SurAddresses.sol) rather than mutable state set via a runtime `wire()` step,
///         because all five structural contracts share a common, pre-agreed genesis address map.
contract ValidatorsTreasury {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------

    /// @notice The only address allowed to call boardApproveExpenditure (path 2 below).
    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice Ceiling for board-approved expenditures. Anything at or above this must go
    ///         through the full validator vote path instead. Changeable only by full
    ///         validator vote (see proposeSmallBudgetCap below) — the board cannot raise its
    ///         own limit.
    uint256 public smallBudgetCap;

    bool private locked; // reentrancy guard

    // ------------------------------------------------------------------
    // Full-vote expenditure proposals
    // ------------------------------------------------------------------
    struct Expenditure {
        address to;
        uint256 amount;
        string description;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => Expenditure) public expenditures;
    mapping(uint256 => mapping(address => bool)) private expenditureHasVoted;
    uint256 public expenditureCount;

    uint256 public totalDistributedToTreasury; // lifetime inflow received (reward share + membership fees/slashed stake)
    uint256 public totalSpent;                 // lifetime amount paid out (both spending paths combined)

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event RewardsReceived(address indexed from, uint256 amount);
    event ExpenditureProposed(uint256 indexed id, address indexed to, uint256 amount, string description, address indexed proposer);
    event ExpenditureVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event ExpenditureExecuted(uint256 indexed id, address indexed to, uint256 amount);
    event BoardExpenditureExecuted(address indexed to, uint256 amount, string description);
    event SmallBudgetCapUpdated(uint256 oldCap, uint256 newCap);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsTreasury: caller is not an active validator");
        _;
    }

    modifier onlyBoard() {
        require(msg.sender == BOARD, "ValidatorsTreasury: caller is not the board");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "ValidatorsTreasury: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // ------------------------------------------------------------------
    // Constructor — executed once, off-chain, to compute the genesis storage snapshot.
    // See "sur-contracts-deploy-notes.md" for the full recipe.
    // ------------------------------------------------------------------
    constructor(uint256 _smallBudgetCap) {
        smallBudgetCap = _smallBudgetCap;
    }

    // ------------------------------------------------------------------
    // Automatic receipt of native Suren — from BlockRewardDistributor's 50% reward share, and
    // from ValidatorsRegistry's membership fees / slashed collateral.
    // ------------------------------------------------------------------
    receive() external payable {
        totalDistributedToTreasury += msg.value;
        emit RewardsReceived(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // Path 1: full validator vote
    // ------------------------------------------------------------------

    /// @notice Propose an expenditure. Callable only by an active validator — FoundationDAO has
    ///         no connection to this contract at all (an earlier `proposeRequestTreasuryBudget`
    ///         path on FoundationDAO was removed as unnecessary; if the foundation ever needs
    ///         SUR funds, an active validator or ValidatorsBoard member must propose it here or
    ///         via boardApproveExpenditure themselves).
    function proposeExpenditure(address to, uint256 amount, string calldata description) external onlyActiveValidator returns (uint256 id) {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0, "ValidatorsTreasury: zero amount");

        expenditureCount++;
        id = expenditureCount;
        expenditures[id] = Expenditure({
            to: to,
            amount: amount,
            description: description,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        emit ExpenditureProposed(id, to, amount, description, msg.sender);

        _voteExpenditure(id, msg.sender);
    }

    function voteExpenditure(uint256 id) external onlyActiveValidator {
        _voteExpenditure(id, msg.sender);
    }

    function _voteExpenditure(uint256 id, address voter) private {
        Expenditure storage e = expenditures[id];
        require(e.createdAt != 0, "ValidatorsTreasury: expenditure not found");
        require(!e.executed, "ValidatorsTreasury: already executed");
        require(!expenditureHasVoted[id][voter], "ValidatorsTreasury: already voted");

        expenditureHasVoted[id][voter] = true;
        e.votes++;

        uint256 activeCount = REGISTRY.getValidators().length;
        uint256 required = (activeCount / 2) + 1;
        emit ExpenditureVoted(id, voter, e.votes, required);

        if (e.votes >= required) {
            _executeExpenditure(id);
        }
    }

    function _executeExpenditure(uint256 id) private nonReentrant {
        Expenditure storage e = expenditures[id];
        require(!e.executed, "ValidatorsTreasury: already executed");
        require(e.amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");
        e.executed = true;

        totalSpent += e.amount;
        (bool success, ) = e.to.call{value: e.amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit ExpenditureExecuted(id, e.to, e.amount);
    }

    // ------------------------------------------------------------------
    // Path 2: board-delegated small budgets
    // ------------------------------------------------------------------

    /// @notice Called only by ValidatorsBoard, only after its own internal board majority has
    ///         approved the request. Capped at smallBudgetCap regardless of what the board
    ///         voted for.
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external onlyBoard nonReentrant {
        require(to != address(0), "ValidatorsTreasury: zero recipient address");
        require(amount > 0 && amount < smallBudgetCap, "ValidatorsTreasury: amount outside board cap");
        require(amount <= address(this).balance, "ValidatorsTreasury: insufficient balance");

        totalSpent += amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "ValidatorsTreasury: transfer failed");

        emit BoardExpenditureExecuted(to, amount, description);
    }

    // ------------------------------------------------------------------
    // Parameter governance — full active-validator majority vote. The board cap is the only
    // remaining treasury-specific parameter; BOARD is a fixed genesis address (SurAddresses.sol)
    // and cannot be changed without a full contract redeployment.
    // ------------------------------------------------------------------

    struct ParamProposal {
        uint256 newCap;
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => ParamProposal) public paramProposals;
    mapping(uint256 => mapping(address => bool)) private paramHasVoted;
    uint256 public paramProposalCount;

    function proposeSmallBudgetCap(uint256 newCap) external onlyActiveValidator returns (uint256 id) {
        paramProposalCount++;
        id = paramProposalCount;
        paramProposals[id] = ParamProposal({
            newCap: newCap,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        _voteParam(id, msg.sender);
    }

    function voteParameterChange(uint256 id) external onlyActiveValidator {
        _voteParam(id, msg.sender);
    }

    function _voteParam(uint256 id, address voter) private {
        ParamProposal storage p = paramProposals[id];
        require(p.createdAt != 0, "ValidatorsTreasury: proposal not found");
        require(!p.executed, "ValidatorsTreasury: already executed");
        require(!paramHasVoted[id][voter], "ValidatorsTreasury: already voted");

        paramHasVoted[id][voter] = true;
        p.votes++;

        uint256 activeCount = REGISTRY.getValidators().length;
        uint256 required = (activeCount / 2) + 1;

        if (p.votes >= required) {
            p.executed = true;
            emit SmallBudgetCapUpdated(smallBudgetCap, p.newCap);
            smallBudgetCap = p.newCap;
        }
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
