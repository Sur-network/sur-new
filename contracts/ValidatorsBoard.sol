// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
    function setEntryThresholdBase(uint256 newValue) external;
    function setGrowthFactorPerValidator(uint256 newValue) external;
    function setMembershipFeeBps(uint256 newValue) external;
    function setVerifier(address newVerifier) external;
    function recoveryPeriod() external view returns (uint256);
    /// @dev `status` is ValidatorsRegistry.Status's ABI-compatible uint8 encoding:
    ///      0=None, 1=Probation, 2=Active, 3=Demoted, 4=Exiting.
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 lastLivenessConfirmation,
        uint256 livenessConfirmationsInPeriod,
        uint256 demotedAt
    );
}

/// @dev Architecture note: identity no longer lives inside ValidatorsRegistry — it was moved to
///      a fully independent, sixth structural contract, `IdentityRegistry.sol` (fixed address
///      `0x6666...6666`).
interface IIdentityRegistry {
    function hasIdentity(address who) external view returns (bool);
}

interface IBlockRewardDistributor {
    function setDistributionOracle(address newOracle) external;
}

interface IValidatorsTreasury {
    function boardApproveExpenditure(address to, uint256 amount, string calldata description) external;
}

/// @title ValidatorsBoard
/// @notice Deployed at the fixed genesis address SurAddresses.VALIDATORS_BOARD (0x4444...4444).
///         Referred to as the "validators' board of directors" in the project's
///         Persian-language documentation.
///
///         BOARD MEMBERSHIP — approval voting, fixed 5 seats, no recall (updated design; retires
///         the earlier one-at-a-time add/remove election model entirely):
///           - Every active validator may, at any time, vote FOR up to MAX_VOTES_PER_VOTER (5)
///             other active validators (`voteFor`), and withdraw any of those votes at any time
///             (`unvoteFor`). No nomination step, no voting window, no quorum requirement.
///             Voting requires the voter to have first self-attested identity information on
///             the separate `IdentityRegistry` contract (`registerIdentity` — name and person
///             type only, self-reported; phone number, Telegram ID, and full KYC documents live
///             off-chain — `IdentityRegistry` only records whether each was verified, not
///             required for voting itself, only `hasIdentity` is).
///           - `refreshBoard()` — permissionless, callable by anyone at any time — recomputes
///             the board as the BOARD_SIZE (5) validators with the most current votes, counting
///             only votes cast BY currently-active validators FOR currently-active validators
///             (both sides are re-checked live against ValidatorsRegistry on every refresh, so a
///             validator that becomes inactive automatically stops both voting and being
///             eligible as a candidate, with no separate "recall" step needed).
///           - Ties are broken in favor of whichever candidate was encountered first while
///             tallying (validators in ValidatorsRegistry.getValidators() order, each voter's
///             votes in the order they were cast) — i.e. first-come-first-served among equal
///             vote counts.
///           - STALE VOTE CLEANUP: if a validator stays Demoted (inactive) for longer than
///             `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (30 days) without
///             recovering, anyone may call `clearStaleVotes` to purge every vote they cast AND
///             every vote they received, freeing up the other validators' vote slots. Before
///             that 30-day mark, their votes simply stop counting in `refreshBoard()` (they are
///             not active, so they're excluded from both sides of the tally) — no cleanup is
///             needed for that to take effect, cleanup is only about freeing storage/slots.
///
///         The board's delegated powers (unchanged from before, still narrow and explicit):
///           1. Rotate the `distributionOracle` key on BlockRewardDistributor immediately,
///              with a transparent on-chain record (for compromised-key emergencies).
///           2. Approve small, routine treasury budget requests below a fixed cap.
///           3. Set the three ECONOMIC ENTRY PARAMETERS on ValidatorsRegistry —
///              entryThresholdBase, growthFactorPerValidator, membershipFeeBps (moved off the
///              full-validator-vote path because reaching a full-validator majority in practice
///              gets harder as the validator set grows, and these parameters are expected to
///              need frequent, timely tuning).
///
///         The board still CANNOT change the other, higher-trust security parameters (rate
///         limit, probation length, liveness/inactivity thresholds, recovery period, slashing
///         bps, exit cooldown) or any core contract address — those always require a full
///         validator vote via ValidatorsRegistry directly, or (for core contract addresses) a
///         full genesis redeployment, since those addresses are compile-time constants (see
///         SurAddresses.sol). Catastrophic/emergency structural actions are explicitly NOT a
///         board power; they require the higher validator-supermajority paths documented in the
///         design doc's recovery playbook, not a function on this contract.
///
///         Every delegated board action (oracle rotation, budget approval, economic parameter
///         change) still requires an internal majority vote among current board members — no
///         single board member can act unilaterally. This is separate from, and unaffected by,
///         the board-membership voting mechanism described above.
///
///         GENESIS DEPLOYMENT: this contract has no constructor — it is injected directly into
///         the genesis `alloc`, so a constructor would never execute on the real chain. The
///         initial board (exactly BOARD_SIZE = 5 members) is instead seeded via the off-chain
///         genesis-building tool (see the 🔶 GENESIS FILL-IN note below), instead of a separate
///         post-deploy election. BlockRewardDistributor, ValidatorsTreasury, and
///         ValidatorsRegistry addresses are fixed constants (see SurAddresses.sol) rather than a
///         runtime `wire()` step, because all five structural contracts share a common,
///         pre-agreed genesis address map.
contract ValidatorsBoard {
    // ------------------------------------------------------------------
    // Fixed cross-contract addresses (see SurAddresses.sol)
    // ------------------------------------------------------------------
    address public constant DISTRIBUTOR = SurAddresses.BLOCK_REWARD_DISTRIBUTOR;
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);
    IIdentityRegistry public constant IDENTITY_REGISTRY = IIdentityRegistry(SurAddresses.IDENTITY_REGISTRY);

    /// @notice Fixed board size — always exactly this many seats (fewer only transiently, if
    ///         fewer than this many candidates have ever received a vote).
    uint256 public constant BOARD_SIZE = 5;

    /// @notice Maximum number of candidates a single validator may vote for at once.
    uint256 public constant MAX_VOTES_PER_VOTER = 5;

    /// @notice How long after a validator's recovery period ends (still without recovering)
    ///         before anyone may purge their votes (given and received) via clearStaleVotes.
    uint256 public constant STALE_VOTE_CLEAR_DELAY = 30 days;

    // ------------------------------------------------------------------
    // Board membership (current snapshot, produced by the last refreshBoard() call)
    //
    // 🔶 GENESIS FILL-IN: this contract has no constructor because it is injected directly into
    // the genesis `alloc` (its constructor would never execute on the real chain). `boardMembers`
    // is a dynamic array and `isBoardMember` is a mapping — Solidity has no syntax for populating
    // either of them with a loop outside a function, so this initial state (exactly BOARD_SIZE =
    // 5 addresses) CANNOT be expressed as a simple state-variable initializer here. The off-chain
    // genesis-building tool must either (a) simulate this contract's deployment with the real
    // constructor logic below, on a temporary local chain, and copy the resulting storage into
    // the final genesis file, or (b) directly compute and write the corresponding storage slots
    // (array length + each element, and the mapping slot per member — via
    // keccak256(abi.encode(key, slot)) for the mapping) into the genesis `alloc`. See
    // "sur-contracts-deploy-notes.md" for the full recipe.
    //
    // Reference logic (not live code — for the genesis tool to reproduce, either by simulation
    // or by direct storage computation):
    //   for each of the 5 initial board member addresses:
    //     boardMembers.push(address);
    //     isBoardMember[address] = true;
    // ------------------------------------------------------------------
    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    // ------------------------------------------------------------------
    // Approval-voting state
    // ------------------------------------------------------------------

    /// @notice Candidates a given voter currently votes for (up to MAX_VOTES_PER_VOTER).
    mapping(address => address[]) private voterCandidates;

    /// @notice voter => candidate => whether that vote is currently active.
    mapping(address => mapping(address => bool)) public hasVotedFor;

    /// @notice Reverse index: candidate => list of voters currently voting for them (needed to
    ///         efficiently purge received votes in clearStaleVotes).
    mapping(address => address[]) private candidateVoters;

    /// @notice 1-based index of `voter` within `candidateVoters[candidate]`, for O(1) removal.
    mapping(address => mapping(address => uint256)) private voterIndexInCandidateVoters;

    // ------------------------------------------------------------------
    // Board-internal actions (oracle rotation, budget approval, economic parameters)
    // ------------------------------------------------------------------
    enum ActionType { RotateOracle, ApproveBudget, SetEntryThresholdBase, SetGrowthFactorPerValidator, SetMembershipFeeBps, RotateVerifier }

    struct BoardAction {
        ActionType atype;
        address target;      // new oracle address, or budget recipient (unused for economic-param actions)
        uint256 amount;       // budget amount for ApproveBudget, OR the new value for economic-param actions
        string description;   // only used for ApproveBudget
        uint256 votes;
        uint256 createdAt;
        bool executed;
    }

    mapping(uint256 => BoardAction) public actions;
    mapping(uint256 => mapping(address => bool)) private actionHasVoted;
    uint256 public actionCount;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event VoteCast(address indexed voter, address indexed candidate);
    event VoteWithdrawn(address indexed voter, address indexed candidate);
    event BoardRefreshed(address[] newBoard, uint256[] voteCounts);
    event StaleVotesCleared(address indexed validator, uint256 votesGivenCleared, uint256 votesReceivedCleared);
    event ActionProposed(uint256 indexed id, ActionType atype, address indexed target, uint256 amount, address indexed proposer);
    event ActionVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event OracleRotated(address indexed newOracle);
    event BudgetApproved(address indexed to, uint256 amount, string description);
    event RegistryEconomicParamSet(ActionType indexed atype, uint256 newValue);
    event VerifierRotated(address indexed newVerifier);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsBoard: caller is not an active validator");
        _;
    }

    modifier onlyBoardMember() {
        require(isBoardMember[msg.sender], "ValidatorsBoard: caller is not a board member");
        _;
    }

    // ------------------------------------------------------------------
    // Approval voting for board membership
    // ------------------------------------------------------------------

    /// @notice Vote for `candidate` to be on the board. Callable by any active validator, for
    ///         any other active validator (self-votes are allowed — nothing special about them).
    ///         Takes effect only once someone calls refreshBoard().
    function voteFor(address candidate) external onlyActiveValidator {
        require(IDENTITY_REGISTRY.hasIdentity(msg.sender), "ValidatorsBoard: register identity before voting");
        require(REGISTRY.isValidator(candidate), "ValidatorsBoard: candidate is not an active validator");
        require(!hasVotedFor[msg.sender][candidate], "ValidatorsBoard: already voted for this candidate");
        require(voterCandidates[msg.sender].length < MAX_VOTES_PER_VOTER, "ValidatorsBoard: max votes already used");

        hasVotedFor[msg.sender][candidate] = true;
        voterCandidates[msg.sender].push(candidate);

        candidateVoters[candidate].push(msg.sender);
        voterIndexInCandidateVoters[candidate][msg.sender] = candidateVoters[candidate].length; // 1-based

        emit VoteCast(msg.sender, candidate);
    }

    /// @notice Withdraw a previously cast vote. Callable any time, no restriction.
    function unvoteFor(address candidate) external {
        require(hasVotedFor[msg.sender][candidate], "ValidatorsBoard: no such active vote");
        _removeVote(msg.sender, candidate);
    }

    function _removeVote(address voter, address candidate) private {
        hasVotedFor[voter][candidate] = false;

        address[] storage vc = voterCandidates[voter];
        for (uint256 i = 0; i < vc.length; i++) {
            if (vc[i] == candidate) {
                vc[i] = vc[vc.length - 1];
                vc.pop();
                break;
            }
        }

        address[] storage cv = candidateVoters[candidate];
        uint256 idx = voterIndexInCandidateVoters[candidate][voter]; // 1-based
        uint256 lastIdx = cv.length;
        if (idx != lastIdx) {
            address lastVoter = cv[lastIdx - 1];
            cv[idx - 1] = lastVoter;
            voterIndexInCandidateVoters[candidate][lastVoter] = idx;
        }
        cv.pop();
        delete voterIndexInCandidateVoters[candidate][voter];

        emit VoteWithdrawn(voter, candidate);
    }

    /// @notice Recompute the board as the BOARD_SIZE validators with the most current votes.
    ///         Permissionless — callable by anyone, any time. Only votes cast BY a currently
    ///         active validator FOR a currently active validator are counted; both sides are
    ///         re-checked live against ValidatorsRegistry on every call.
    function refreshBoard() external {
        address[] memory active = REGISTRY.getValidators();

        // ephemeral per-call tally: candidate -> vote count (reset back to 0 before returning)
        address[] memory seenCandidates = new address[](active.length * MAX_VOTES_PER_VOTER);
        uint256 seenCount = 0;

        for (uint256 i = 0; i < active.length; i++) {
            address voter = active[i];
            address[] storage cands = voterCandidates[voter];
            uint256 n = cands.length;
            for (uint256 j = 0; j < n; j++) {
                address c = cands[j];
                if (!REGISTRY.isValidator(c)) continue; // candidate must currently be active too
                if (_voteTally[c] == 0) {
                    seenCandidates[seenCount] = c;
                    seenCount++;
                }
                _voteTally[c]++;
            }
        }

        // select the top BOARD_SIZE candidates by tally; ties keep whichever was inserted first
        address[] memory newBoard = new address[](BOARD_SIZE);
        uint256[] memory newBoardVotes = new uint256[](BOARD_SIZE);
        uint256 filled = 0;

        for (uint256 i = 0; i < seenCount; i++) {
            address c = seenCandidates[i];
            uint256 v = _voteTally[c];

            if (filled < BOARD_SIZE) {
                newBoard[filled] = c;
                newBoardVotes[filled] = v;
                filled++;
            } else {
                uint256 minIdx = 0;
                for (uint256 k = 1; k < BOARD_SIZE; k++) {
                    if (newBoardVotes[k] < newBoardVotes[minIdx]) minIdx = k;
                }
                if (v > newBoardVotes[minIdx]) {
                    newBoard[minIdx] = c;
                    newBoardVotes[minIdx] = v;
                }
                // v == newBoardVotes[minIdx]: keep the existing (earlier-inserted) candidate
            }
        }

        // reset the ephemeral tally so storage doesn't leak stale counts into the next call
        for (uint256 i = 0; i < seenCount; i++) {
            _voteTally[seenCandidates[i]] = 0;
        }

        // apply: clear old membership flags, install the new set
        for (uint256 i = 0; i < boardMembers.length; i++) {
            isBoardMember[boardMembers[i]] = false;
        }
        delete boardMembers;

        address[] memory finalBoard = new address[](filled);
        uint256[] memory finalVotes = new uint256[](filled);
        for (uint256 i = 0; i < filled; i++) {
            boardMembers.push(newBoard[i]);
            isBoardMember[newBoard[i]] = true;
            finalBoard[i] = newBoard[i];
            finalVotes[i] = newBoardVotes[i];
        }

        emit BoardRefreshed(finalBoard, finalVotes);
    }

    /// @dev Ephemeral per-refreshBoard()-call tally storage. Always 0 between calls — see
    ///      refreshBoard()'s reset loop. Declared as contract storage (not `memory`) only
    ///      because Solidity has no mapping type in memory.
    mapping(address => uint256) private _voteTally;

    /// @notice Purge every vote a long-inactive validator cast (as a voter) AND every vote they
    ///         received (as a candidate), freeing up the other validators' vote slots.
    ///         Permissionless. Requires the validator to have been continuously Demoted for at
    ///         least `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (30 days).
    ///         Before this point, their votes already don't count in refreshBoard() (see above)
    ///         — this function only frees storage/vote-slots, it does not itself change who is
    ///         currently on the board.
    function clearStaleVotes(address validator) external {
        (uint8 status, , , , , uint256 demotedAt) = REGISTRY.getValidatorInfo(validator);
        require(status == 3, "ValidatorsBoard: validator is not currently demoted"); // 3 = Status.Demoted
        uint256 threshold = demotedAt + REGISTRY.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY;
        require(block.timestamp >= threshold, "ValidatorsBoard: stale-vote delay not elapsed");

        address[] memory given = voterCandidates[validator];
        for (uint256 i = 0; i < given.length; i++) {
            _removeVote(validator, given[i]);
        }

        address[] memory received = candidateVoters[validator];
        for (uint256 i = 0; i < received.length; i++) {
            _removeVote(received[i], validator);
        }

        emit StaleVotesCleared(validator, given.length, received.length);
    }

    // ------------------------------------------------------------------
    // Board-internal actions — majority vote among current board members
    // ------------------------------------------------------------------
    function proposeRotateOracle(address newOracle) external onlyBoardMember returns (uint256 id) {
        require(newOracle != address(0), "ValidatorsBoard: zero oracle address");
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "");
    }

    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        id = _createAction(ActionType.ApproveBudget, to, amount, description);
    }

    /// @notice Propose a new entryThresholdBase on ValidatorsRegistry (economic entry
    ///         parameter — board-governed; see contract-level doc comment).
    function proposeSetEntryThresholdBase(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryThresholdBase, address(0), newValue, "");
    }

    /// @notice Propose a new growthFactorPerValidator on ValidatorsRegistry (fixed-point, 18
    ///         decimals; must be > 1.0, i.e. > 1_000000000000000000).
    function proposeSetGrowthFactorPerValidator(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue > 1_000000000000000000, "ValidatorsBoard: growth factor must be > 1.0");
        id = _createAction(ActionType.SetGrowthFactorPerValidator, address(0), newValue, "");
    }

    /// @notice Propose a new membershipFeeBps on ValidatorsRegistry.
    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "");
    }

    /// @notice Propose rotating the identity-verification key (`verifier`) on
    ///         ValidatorsRegistry — a routine operational-key rotation, same pattern as
    ///         proposeRotateOracle.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "");
    }

    function voteAction(uint256 id) external onlyBoardMember {
        _voteAction(id, msg.sender);
    }

    function _createAction(ActionType atype, address target, uint256 amount, string memory description) private returns (uint256 id) {
        actionCount++;
        id = actionCount;
        actions[id] = BoardAction({
            atype: atype,
            target: target,
            amount: amount,
            description: description,
            votes: 0,
            createdAt: block.timestamp,
            executed: false
        });
        emit ActionProposed(id, atype, target, amount, msg.sender);
        _voteAction(id, msg.sender);
    }

    function _voteAction(uint256 id, address voter) private {
        BoardAction storage a = actions[id];
        require(a.createdAt != 0, "ValidatorsBoard: action not found");
        require(!a.executed, "ValidatorsBoard: already executed");
        require(!actionHasVoted[id][voter], "ValidatorsBoard: already voted");

        actionHasVoted[id][voter] = true;
        a.votes++;

        uint256 required = (boardMembers.length / 2) + 1;
        emit ActionVoted(id, voter, a.votes, required);

        if (a.votes >= required) {
            a.executed = true;
            if (a.atype == ActionType.RotateOracle) {
                IBlockRewardDistributor(DISTRIBUTOR).setDistributionOracle(a.target);
                emit OracleRotated(a.target);
            } else if (a.atype == ActionType.ApproveBudget) {
                IValidatorsTreasury(TREASURY).boardApproveExpenditure(a.target, a.amount, a.description);
                emit BudgetApproved(a.target, a.amount, a.description);
            } else if (a.atype == ActionType.SetEntryThresholdBase) {
                REGISTRY.setEntryThresholdBase(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetGrowthFactorPerValidator) {
                REGISTRY.setGrowthFactorPerValidator(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetMembershipFeeBps) {
                REGISTRY.setMembershipFeeBps(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.RotateVerifier) {
                REGISTRY.setVerifier(a.target);
                emit VerifierRotated(a.target);
            }
        }
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------
    function getBoardMembers() external view returns (address[] memory) {
        return boardMembers;
    }

    function getBoardSize() external view returns (uint256) {
        return boardMembers.length;
    }

    function getVotesOf(address voter) external view returns (address[] memory) {
        return voterCandidates[voter];
    }

    function getVotersFor(address candidate) external view returns (address[] memory) {
        return candidateVoters[candidate];
    }
}
