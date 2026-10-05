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

    /// @dev Incremented each time an address exits voluntarily; a seat is valid only while the epoch
    ///      still equals the value stamped when the seat was taken.
    function membershipEpoch(address who) external view returns (uint256);

    /// @dev Position of `who` in the order in which addresses were first activated (1 = oldest);
    ///      0 for an address that was never activated. Used as the tie-break between candidates
    ///      with equal vote counts: the older validator wins.
    function activationSeq(address who) external view returns (uint256);

    /// @dev `status` uses ValidatorsRegistry.Status's ABI encoding:
    ///      0=None, 1=Probation, 2=Active, 3=Demoted, 4=Exiting. The six outputs must match the
    ///      real function exactly, in this order.
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
    );
}

/// @dev Identity lives in the independent `IdentityRegistry` contract (fixed address `0x6666...6666`).
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
/// @notice The validators' board of directors, deployed at `SurAddresses.VALIDATORS_BOARD` (0x4444...4444).
///
///         BOARD MEMBERSHIP — approval voting, five seats, one board per calendar month:
///           - Every active validator that has registered an identity may vote FOR up to
///             MAX_VOTES_PER_VOTER (5) active validators (`voteFor`) and withdraw any vote at any
///             time (`unvoteFor`). There is no nomination step and no voting window. Votes persist
///             until the voter changes them.
///           - The board of a calendar month (UTC) takes office when `refreshBoard` is first
///             called in that month. Anyone may call it. The five active validators with the most
///             votes become the board; ties are broken in favour of the validator that was
///             activated first. Previous membership gives no advantage, and all five seats may
///             change at once.
///           - Until `refreshBoard` has been called in a new month, the previous board has no
///             authority. Within a month, `refreshBoard` succeeds once (an empty board may be
///             filled at any time).
///           - Votes are counted incrementally. Each candidate has a running counter that
///             `voteFor` and `unvoteFor` update. Only votes cast by currently active validators
///             are included. When a validator's status changes, the registry calls `syncVoter`,
///             which adds or removes that validator's votes; anyone may also call it to repair
///             the counters. A candidate's own eligibility is checked live when the board is
///             selected.
///           - If a validator stays Demoted for longer than the registry's `recoveryPeriod()` plus
///             STALE_VOTE_CLEAR_DELAY (30 days), anyone may call `clearStaleVotes` to purge every
///             vote that validator cast and received.
///
///         BOARD POWERS (narrow and explicit):
///           1. Rotate the `distributionOracle` key on BlockRewardDistributor.
///           2. Rotate the `verifier` key on ValidatorsRegistry.
///           3. Approve routine treasury payments up to the treasury's caps.
///           4. Set the three economic entry parameters on ValidatorsRegistry
///              (entryThresholdBase, growthFactorPerValidator, membershipFeeBps).
///         Every board action needs an internal vote among the current board members. Key
///         rotations and budget approvals require at least three votes and take effect as soon as
///         that many members have voted. The board cannot change the security parameters or any
///         core contract address.
///
///         GENESIS DEPLOYMENT: the contract has no constructor; it is injected into the genesis
///         `alloc`. The initial five members, `boardVersion`, `boardMonthId` and each member's
///         `seatMembershipEpoch` are written by the off-chain genesis tool (see
///         `genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol`). `boardMonthId` must equal the
///         month of the genesis timestamp, otherwise the founding board has no authority until the
///         first refresh.
contract ValidatorsBoard {
    address public constant DISTRIBUTOR = SurAddresses.BLOCK_REWARD_DISTRIBUTOR;
    address public constant TREASURY = SurAddresses.VALIDATORS_TREASURY;

    IValidatorsRegistry public constant REGISTRY = IValidatorsRegistry(SurAddresses.VALIDATORS_REGISTRY);
    IIdentityRegistry public constant IDENTITY_REGISTRY = IIdentityRegistry(SurAddresses.IDENTITY_REGISTRY);

    /// @notice Number of board seats.
    uint256 public constant BOARD_SIZE = 5;

    /// @notice Maximum number of candidates one validator may vote for at once.
    uint256 public constant MAX_VOTES_PER_VOTER = 5;

    /// @notice How long after a validator's recovery period ends (still without recovering) anyone
    ///         may purge its votes via clearStaleVotes.
    uint256 public constant STALE_VOTE_CLEAR_DELAY = 30 days;

    /// @notice Minimum number of board votes for a key rotation or a budget approval.
    uint256 public constant MIN_VOTES_SENSITIVE_ACTION = 3;

    /// @notice A board action that has not reached its quorum within this time expires.
    uint256 public constant BOARD_ACTION_EXPIRY = 14 days;

    // ------------------------------------------------------------------
    // Storage. The order of the first variables must match the genesis seed helper.
    // ------------------------------------------------------------------
    address[] private boardMembers;
    mapping(address => bool) public isBoardMember;

    /// @notice Candidates a voter currently votes for (up to MAX_VOTES_PER_VOTER).
    mapping(address => address[]) private voterCandidates;

    /// @notice voter => candidate => whether that vote is currently held.
    mapping(address => mapping(address => bool)) public hasVotedFor;

    /// @notice Voters currently voting for a candidate (used to purge received votes).
    mapping(address => address[]) private candidateVoters;

    /// @notice 1-based position of `voter` inside `candidateVoters[candidate]`, for O(1) removal.
    mapping(address => mapping(address => uint256)) private voterIndexInCandidateVoters;

    enum ActionType { RotateOracle, ApproveBudget, SetEntryThresholdBase, SetGrowthFactorPerValidator, SetMembershipFeeBps, RotateVerifier }

    /// @dev `requiredVotes` is fixed when the action is created and never recomputed. `expiresAt`
    ///      bounds how long an action stays open. `boardVersionAtCreation` ties the action to the
    ///      board composition that proposed it: once the composition changes, the action can no
    ///      longer be voted on.
    struct BoardAction {
        ActionType atype;
        address target;       // new oracle / verifier address, or budget recipient
        uint256 amount;       // budget amount, or the new value for an economic-parameter action
        string description;   // used by ApproveBudget only
        uint256 votes;
        uint256 requiredVotes;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        uint256 boardVersionAtCreation;
    }

    /// @notice Incremented whenever the set of board members really changes.
    uint256 public boardVersion = 1;

    /// @notice Identifier of the calendar month (UTC, year * 12 + month - 1) the current board serves.
    uint256 public boardMonthId;

    /// @notice Seats freed by an exit that have not been filled yet.
    uint256 public pendingVacancies;

    event BoardMemberAuthorityEnded(address indexed member);
    event BoardSuccession(address indexed newMember);

    /// @notice The epoch of an address's registry membership at the moment it took a seat.
    mapping(address => uint256) public seatMembershipEpoch;

    mapping(uint256 => BoardAction) public actions;
    mapping(uint256 => mapping(address => bool)) private actionHasVoted;
    uint256 public actionCount;

    /// @notice Running number of counted votes each candidate holds.
    mapping(address => uint256) public voteCount;

    /// @dev Candidates with voteCount > 0.
    address[] private candidateList;

    /// @dev 1-based position of a candidate inside candidateList (0 = absent).
    mapping(address => uint256) private candidateListIndex;

    /// @notice Whether a voter's votes are currently included in `voteCount`.
    mapping(address => bool) public votesCounted;

    event VoteCast(address indexed voter, address indexed candidate);
    event VoteWithdrawn(address indexed voter, address indexed candidate);
    event VoterSynced(address indexed voter, bool counted);
    event BoardRefreshed(uint256 indexed monthId, address[] newBoard, uint256[] voteCounts);
    event StaleVotesCleared(address indexed validator, uint256 votesGivenCleared, uint256 votesReceivedCleared);
    event ActionProposed(uint256 indexed id, ActionType atype, address indexed target, uint256 amount, address indexed proposer);
    event ActionVoted(uint256 indexed id, address indexed voter, uint256 votes, uint256 required);
    event OracleRotated(address indexed newOracle);
    event BudgetApproved(address indexed to, uint256 amount, string description);
    event RegistryEconomicParamSet(ActionType indexed atype, uint256 newValue);
    event VerifierRotated(address indexed newVerifier);

    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsBoard: caller is not an active validator");
        _;
    }

    /// @notice A caller acts as a board member only if (a) the board's month is the current month,
    ///         (b) it holds a seat and has not requested exit, and (c) no seat holder has requested
    ///         exit without the seat having been cleaned up yet (anyone may call `syncBoard()` for that).
    modifier onlyBoardMember() {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        require(_hasAuthority(msg.sender), "ValidatorsBoard: caller has no board authority");
        require(!_syncNeeded(), "ValidatorsBoard: a seat holder has requested exit - call syncBoard() first");
        _;
    }

    // ------------------------------------------------------------------
    // Calendar
    // ------------------------------------------------------------------

    /// @notice Month identifier (UTC) of a timestamp: year * 12 + (month - 1).
    function monthIdOf(uint256 timestamp) public pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    function currentMonthId() public view returns (uint256) {
        return monthIdOf(block.timestamp);
    }

    /// @notice True when `refreshBoard` can currently succeed.
    function refreshDue() public view returns (bool) {
        return boardMembers.length == 0 || currentMonthId() > boardMonthId;
    }

    function _boardIsCurrent() private view returns (bool) {
        return boardMonthId == currentMonthId();
    }

    // ------------------------------------------------------------------
    // Approval voting
    // ------------------------------------------------------------------

    /// @notice Vote for `candidate` to be on the board. Callable by any active validator that has
    ///         registered an identity, for any active validator (self-votes are allowed). The vote
    ///         counts at the next `refreshBoard`.
    function voteFor(address candidate) external onlyActiveValidator {
        require(IDENTITY_REGISTRY.hasIdentity(msg.sender), "ValidatorsBoard: register identity before voting");
        require(REGISTRY.isValidator(candidate), "ValidatorsBoard: candidate is not an active validator");
        require(!hasVotedFor[msg.sender][candidate], "ValidatorsBoard: already voted for this candidate");
        require(voterCandidates[msg.sender].length < MAX_VOTES_PER_VOTER, "ValidatorsBoard: max votes already used");

        _syncVoter(msg.sender); // the caller is active, so its existing votes are counted from here on

        hasVotedFor[msg.sender][candidate] = true;
        voterCandidates[msg.sender].push(candidate);

        candidateVoters[candidate].push(msg.sender);
        voterIndexInCandidateVoters[candidate][msg.sender] = candidateVoters[candidate].length;

        _increase(candidate);
        emit VoteCast(msg.sender, candidate);
    }

    /// @notice Withdraw a vote. Callable at any time.
    function unvoteFor(address candidate) external {
        require(hasVotedFor[msg.sender][candidate], "ValidatorsBoard: no such active vote");
        _removeVote(msg.sender, candidate);
    }

    /// @notice Bring the vote counters in line with a validator's current status: its votes are
    ///         counted while it is active and not counted otherwise. Anyone may call this; it is
    ///         idempotent. The registry calls it whenever a validator's status changes.
    function syncVoter(address voter) external {
        _syncVoter(voter);
    }

    function syncVoters(address[] calldata voters) external {
        for (uint256 i = 0; i < voters.length; i++) {
            _syncVoter(voters[i]);
        }
    }

    function _syncVoter(address voter) private {
        bool active = REGISTRY.isValidator(voter);
        if (active == votesCounted[voter]) return;
        address[] storage cands = voterCandidates[voter];
        uint256 n = cands.length;
        if (active) {
            votesCounted[voter] = true;
            for (uint256 i = 0; i < n; i++) _increase(cands[i]);
        } else {
            votesCounted[voter] = false;
            for (uint256 i = 0; i < n; i++) _decrease(cands[i]);
        }
        emit VoterSynced(voter, active);
    }

    function _increase(address candidate) private {
        if (voteCount[candidate]++ == 0) {
            candidateList.push(candidate);
            candidateListIndex[candidate] = candidateList.length;
        }
    }

    /// @dev Never reverts on a bookkeeping mismatch, so a stale counter can never lock voting.
    function _decrease(address candidate) private {
        uint256 current = voteCount[candidate];
        if (current == 0) return;
        voteCount[candidate] = current - 1;
        if (current == 1) {
            uint256 idx = candidateListIndex[candidate]; // 1-based
            uint256 last = candidateList.length;
            if (idx != last) {
                address moved = candidateList[last - 1];
                candidateList[idx - 1] = moved;
                candidateListIndex[moved] = idx;
            }
            candidateList.pop();
            delete candidateListIndex[candidate];
        }
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
        uint256 idx = voterIndexInCandidateVoters[candidate][voter];
        uint256 lastIdx = cv.length;
        if (idx != lastIdx) {
            address lastVoter = cv[lastIdx - 1];
            cv[idx - 1] = lastVoter;
            voterIndexInCandidateVoters[candidate][lastVoter] = idx;
        }
        cv.pop();
        delete voterIndexInCandidateVoters[candidate][voter];

        if (votesCounted[voter]) _decrease(candidate);
        emit VoteWithdrawn(voter, candidate);
    }

    // ------------------------------------------------------------------
    // Monthly board selection
    // ------------------------------------------------------------------

    /// @notice Seat the board of the current calendar month: the BOARD_SIZE active validators with
    ///         the most votes, ties broken by earlier activation. Callable by anyone; succeeds once
    ///         per month (and at any time while the board is empty). Fewer than BOARD_SIZE seats
    ///         are filled if fewer candidates hold votes.
    ///
    ///         `votersToSync` lists validators whose vote counters are brought in line with their
    ///         current status (see `syncVoter`) before the board is selected, so a repair and the
    ///         refresh happen in one transaction. The list is normally empty: the registry already
    ///         calls `syncVoter` on every status change.
    function refreshBoard(address[] calldata votersToSync) external {
        uint256 month = currentMonthId();
        require(boardMembers.length == 0 || month > boardMonthId, "ValidatorsBoard: this month's board is already set");

        for (uint256 i = 0; i < votersToSync.length; i++) {
            _syncVoter(votersToSync[i]);
        }

        uint256 priorCount = boardMembers.length;
        (address[] memory picks, uint256[] memory pickVotes, uint256 n) = _selectTop(BOARD_SIZE, false);

        uint256 kept = 0;
        for (uint256 i = 0; i < n; i++) {
            if (isBoardMember[picks[i]]) kept++;
        }
        bool changed = (kept != n) || (kept != priorCount);

        for (uint256 i = 0; i < priorCount; i++) {
            isBoardMember[boardMembers[i]] = false;
        }
        delete boardMembers;

        address[] memory finalBoard = new address[](n);
        uint256[] memory finalVotes = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            boardMembers.push(picks[i]);
            isBoardMember[picks[i]] = true;
            seatMembershipEpoch[picks[i]] = REGISTRY.membershipEpoch(picks[i]);
            finalBoard[i] = picks[i];
            finalVotes[i] = pickVotes[i];
        }

        if (changed) boardVersion++;
        boardMonthId = month;
        pendingVacancies = 0;

        emit BoardRefreshed(month, finalBoard, finalVotes);
    }

    /// @dev The up-to-`k` active candidates with the most votes (ties: lower activationSeq wins).
    ///      Candidates that cannot enter the top `k` are skipped without any external call.
    function _selectTop(uint256 k, bool excludeMembers)
        private
        view
        returns (address[] memory picks, uint256[] memory votes, uint256 filled)
    {
        picks = new address[](k);
        votes = new uint256[](k);
        if (k == 0) return (picks, votes, 0);
        uint256[] memory seqs = new uint256[](k);

        uint256 len = candidateList.length;
        for (uint256 i = 0; i < len; i++) {
            address c = candidateList[i];
            if (excludeMembers && isBoardMember[c]) continue;
            uint256 v = voteCount[c];

            uint256 weakest = 0;
            if (filled == k) {
                weakest = _weakestIndex(votes, seqs, k);
                if (v < votes[weakest]) continue;
            }
            if (!REGISTRY.isValidator(c)) continue;
            uint256 s = REGISTRY.activationSeq(c);

            if (filled < k) {
                picks[filled] = c;
                votes[filled] = v;
                seqs[filled] = s;
                filled++;
            } else if (v > votes[weakest] || (v == votes[weakest] && s < seqs[weakest])) {
                picks[weakest] = c;
                votes[weakest] = v;
                seqs[weakest] = s;
            }
        }
    }

    /// @dev Index of the entry that would be displaced first: fewest votes, and among equals the
    ///      one activated last.
    function _weakestIndex(uint256[] memory votes, uint256[] memory seqs, uint256 k) private pure returns (uint256 w) {
        for (uint256 i = 1; i < k; i++) {
            if (votes[i] < votes[w] || (votes[i] == votes[w] && seqs[i] > seqs[w])) w = i;
        }
    }

    // ------------------------------------------------------------------
    // Authority and exit-driven succession
    // ------------------------------------------------------------------

    /// @dev A seat is valid while the holder has not exited (membership epoch unchanged) and its
    ///      status is neither None nor Exiting. Suspension (Demoted) alone does not end authority
    ///      within the month.
    function _hasAuthority(address who) private view returns (bool) {
        if (!isBoardMember[who]) return false;
        if (REGISTRY.membershipEpoch(who) != seatMembershipEpoch[who]) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        return status != 0 && status != 4;
    }

    /// @notice True while `who` may act as a board member: the board's month is the current month
    ///         and the seat is valid.
    function hasBoardAuthority(address who) external view returns (bool) {
        return _boardIsCurrent() && _hasAuthority(who);
    }

    function _syncNeeded() private view returns (bool) {
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (!_hasAuthority(boardMembers[i])) return true;
        }
        return false;
    }

    /// @notice Remove seat holders whose authority has ended and fill their seats from the
    ///         candidates with the most votes. Callable by anyone, within the board's month.
    function syncBoard() external {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        _syncBoard();
    }

    function _syncBoard() private {
        uint256 removed = 0;
        uint256 i = 0;
        while (i < boardMembers.length) {
            address m = boardMembers[i];
            if (_hasAuthority(m)) {
                i++;
                continue;
            }
            isBoardMember[m] = false;
            boardMembers[i] = boardMembers[boardMembers.length - 1];
            boardMembers.pop();
            removed++;
            emit BoardMemberAuthorityEnded(m);
        }
        bool changed = removed > 0;
        if (removed > 0) {
            pendingVacancies += removed;
            if (_fillVacancies()) changed = true;
        }
        if (changed) boardVersion++;
    }

    /// @notice Fill seats freed by an exit with the eligible candidates (active, not seated) that
    ///         hold the most votes. Never creates an extra ordinary change. With fewer than three
    ///         seated members, treasury payments and key rotations are halted until a seat is filled.
    function fillVacancies() external {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        if (_fillVacancies()) boardVersion++;
    }

    function _fillVacancies() private returns (bool filledAny) {
        uint256 room = BOARD_SIZE - boardMembers.length;
        uint256 want = pendingVacancies < room ? pendingVacancies : room;
        if (want == 0) return false;
        (address[] memory picks, , uint256 n) = _selectTop(want, true);
        for (uint256 i = 0; i < n; i++) {
            boardMembers.push(picks[i]);
            isBoardMember[picks[i]] = true;
            seatMembershipEpoch[picks[i]] = REGISTRY.membershipEpoch(picks[i]);
            emit BoardSuccession(picks[i]);
        }
        if (n > 0) {
            pendingVacancies -= n;
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Stale-vote cleanup
    // ------------------------------------------------------------------

    /// @notice Purge every vote `validator` cast and received once it has been Demoted for longer
    ///         than `recoveryPeriod() + STALE_VOTE_CLEAR_DELAY`. Callable by anyone.
    function clearStaleVotes(address validator) external {
        (uint8 status, , , uint256 demotedAt, , ) = REGISTRY.getValidatorInfo(validator);
        require(status == 3, "ValidatorsBoard: validator is not currently demoted");
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
    // Board actions
    // ------------------------------------------------------------------

    /// @notice Rotate the distributionOracle key. Needs at least MIN_VOTES_SENSITIVE_ACTION votes
    ///         and takes effect as soon as the quorum is reached.
    function proposeRotateOracle(address newOracle) external onlyBoardMember returns (uint256 id) {
        require(newOracle != address(0), "ValidatorsBoard: zero oracle address");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key rotation halted");
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice Approve a routine treasury payment below the treasury's caps. Needs at least
    ///         MIN_VOTES_SENSITIVE_ACTION votes; halted while fewer than three members are seated.
    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - spending halted");
        id = _createAction(ActionType.ApproveBudget, to, amount, description, MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice Economic entry parameters: majority of the board.
    function proposeSetEntryThresholdBase(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryThresholdBase, address(0), newValue, "", 0);
    }

    function proposeSetGrowthFactorPerValidator(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue > 1_000000000000000000, "ValidatorsBoard: growth factor must be > 1.0");
        id = _createAction(ActionType.SetGrowthFactorPerValidator, address(0), newValue, "", 0);
    }

    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "", 0);
    }

    /// @notice Rotate the `verifier` key on ValidatorsRegistry. Needs at least
    ///         MIN_VOTES_SENSITIVE_ACTION votes and takes effect as soon as the quorum is reached.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key rotation halted");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    function voteAction(uint256 id) external onlyBoardMember {
        _voteAction(id, msg.sender);
    }

    /// @dev The required vote count is the board's majority at creation time, raised to
    ///      `minRequiredVotes` for sensitive actions, and then fixed for the life of the action.
    function _createAction(ActionType atype, address target, uint256 amount, string memory description, uint256 minRequiredVotes) private returns (uint256 id) {
        uint256 majority = (boardMembers.length / 2) + 1;
        actionCount++;
        id = actionCount;
        actions[id] = BoardAction({
            atype: atype,
            target: target,
            amount: amount,
            description: description,
            votes: 0,
            requiredVotes: majority > minRequiredVotes ? majority : minRequiredVotes,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + BOARD_ACTION_EXPIRY,
            executed: false,
            boardVersionAtCreation: boardVersion
        });
        emit ActionProposed(id, atype, target, amount, msg.sender);
        _voteAction(id, msg.sender);
    }

    function _voteAction(uint256 id, address voter) private {
        BoardAction storage a = actions[id];
        require(a.createdAt != 0, "ValidatorsBoard: action not found");
        require(!a.executed, "ValidatorsBoard: already executed");
        require(block.timestamp <= a.expiresAt, "ValidatorsBoard: action has expired");
        require(a.boardVersionAtCreation == boardVersion, "ValidatorsBoard: board membership changed since this action was proposed - propose again");
        require(!actionHasVoted[id][voter], "ValidatorsBoard: already voted");

        actionHasVoted[id][voter] = true;
        a.votes++;

        emit ActionVoted(id, voter, a.votes, a.requiredVotes);

        if (a.votes >= a.requiredVotes) {
            a.executed = true;
            if (a.atype == ActionType.RotateOracle) {
                IBlockRewardDistributor(DISTRIBUTOR).setDistributionOracle(a.target);
                emit OracleRotated(a.target);
            } else if (a.atype == ActionType.ApproveBudget) {
                require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - spending halted");
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
    // Views
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

    /// @notice Candidates that currently hold at least one counted vote.
    function getCandidateList() external view returns (address[] memory) {
        return candidateList;
    }
}
