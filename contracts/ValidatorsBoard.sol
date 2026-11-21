// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IValidatorsRegistry {
    function getValidators() external view returns (address[] memory);
    function isValidator(address who) external view returns (bool);
    function setEntryCollateral(uint256 newValue) external;
    function setMembershipFeeBps(uint256 newValue) external;
    function setVerifier(address newVerifier) external;
    function recoveryPeriod() external view returns (uint256);

    // v2.5: removal in network recovery
    function recoveryCaseInfo(address validator) external view returns (uint8 state, uint256 recordedAt, uint256 resolutionDeadline);
    function recoveryReferral(address validator) external view returns (uint256 referralNonce, uint256 eligibleCount);
    function setRecoveryCaseReferred(address validator) external;
    function resolveRecoveryRemoval(address validator, bool upheld) external;
    function wasActiveAt(address who, uint256 nonce) external view returns (bool);

    /// @dev Incremented each time an address exits voluntarily; a seat is valid only while the epoch
    ///      still equals the value stamped when the seat was taken.
    function membershipEpoch(address who) external view returns (uint256);

    /// @dev Position of `who` in the order in which addresses were first activated (1 = oldest);
    ///      0 for an address that was never activated. Used as the tie-break between candidates
    ///      with equal vote counts: the older validator wins.
    function activationSeq(address who) external view returns (uint256);

    /// @dev `status` uses ValidatorsRegistry.Status's ABI encoding:
    ///      0=None, 1=Probation, 2=Active, 3=Demoted, 4=Exiting, 5=RemovedInRecovery. The six outputs must match the
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

interface IKmsDirectives {
    function setFrozen(uint8 slot, bool isFrozen) external;
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
    address[] internal boardMembers;
    mapping(address => bool) public isBoardMember;

    /// @notice Candidates a voter currently votes for (up to MAX_VOTES_PER_VOTER).
    mapping(address => address[]) private voterCandidates;

    /// @notice voter => candidate => whether that vote is currently held.
    mapping(address => mapping(address => bool)) public hasVotedFor;

    /// @notice Voters currently voting for a candidate (used to purge received votes).
    mapping(address => address[]) private candidateVoters;

    /// @notice 1-based position of `voter` inside `candidateVoters[candidate]`, for O(1) removal.
    mapping(address => mapping(address => uint256)) private voterIndexInCandidateVoters;

    enum ActionType { RotateOracle, ApproveBudget, SetEntryCollateral, SetMembershipFeeBps, RotateVerifier, KmsFreeze }

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
    event KmsFreezeApplied(uint8 indexed slot, bool frozen);

    modifier onlyActiveValidator() {
        require(REGISTRY.isValidator(msg.sender), "ValidatorsBoard: caller is not an active validator");
        _;
    }

    /// @notice A caller acts as a board member only if (a) the board's month is the current month,
    ///         (b) it holds a seat and has not requested exit, and (c) no seat holder has requested
    ///         exit without the seat having been cleaned up yet (anyone may call `syncBoard()` for that).
    modifier onlyBoardMember() {
        require(_boardIsCurrent(), "ValidatorsBoard: board term ended - call refreshBoard for the new month");
        require(_canAct(msg.sender), "ValidatorsBoard: caller has no board authority");
        require(!_syncNeeded(), "ValidatorsBoard: a seat holder has requested exit - call syncBoard() first");
        _;
    }

    // ------------------------------------------------------------------
    // Calendar
    // ------------------------------------------------------------------

    /// @notice Month identifier (UTC) of a timestamp: year * 12 + (month - 1).
    /// @dev Genesis seeding of the founding board. Used ONLY by genesis-seed-helpers/ValidatorsBoard_GenesisSeed.sol (which
    ///      inherits this contract). `boardMonthId` must be the month of the genesis timestamp, otherwise the founding board
    ///      has no authority until the first refreshBoard().
    function _seedBoard(address[] memory members, uint256 genesisTimestamp) internal {
        require(members.length == BOARD_SIZE, "seed: exactly 5 board members");
        for (uint256 i = 0; i < members.length; i++) {
            address m = members[i];
            require(m != address(0) && !isBoardMember[m], "seed: bad or duplicate member");
            boardMembers.push(m);
            isBoardMember[m] = true;
        }
        boardMonthId = monthIdOf(genesisTimestamp);
    }

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
        // not None, not Exiting, and (v2.5) not removed in a network recovery
        return status != 0 && status != 4 && status != 5;
    }

    /// @notice True while `who` may act as a board member: the board's month is the current month
    ///         and the seat is valid.
    /// @dev A seat holder may ACT (propose, vote, count in the recovery quorum) only once it is a validator that has left
    ///      Probation: founders seeded as Probation on the genesis board hold their seat but cannot act until the Verifier
    ///      activates them. Seat validity (_hasAuthority) is unchanged, so anyone calling syncBoard() does NOT remove a founder
    ///      who is still in Probation. A suspended member (Demoted or SelfSuspended) keeps acting for the rest of its month, as
    ///      before (suspension alone does not end authority).
    function _canAct(address who) private view returns (bool) {
        if (!_hasAuthority(who)) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        return status != 1; // 1 = Probation
    }

    function hasBoardAuthority(address who) external view returns (bool) {
        return _boardIsCurrent() && _canAct(who);
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
        (uint8 status, , uint256 periodStartedAt, uint256 demotedAt, , ) = REGISTRY.getValidatorInfo(validator);
        // Demoted (3): the recovery period plus the delay after the suspension. SelfSuspended (6): there is no recovery
        // period for a voluntary suspension, so the delay counts from the moment it began (Registry stores that in periodStartedAt).
        require(status == 3 || status == 6, "ValidatorsBoard: validator is not currently suspended");
        uint256 threshold = status == 3
            ? demotedAt + REGISTRY.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY
            : periodStartedAt + STALE_VOTE_CLEAR_DELAY;
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
    function proposeSetEntryCollateral(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryCollateral, address(0), newValue, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice Rotate the `verifier` key on ValidatorsRegistry. Needs at least
    ///         MIN_VOTES_SENSITIVE_ACTION votes and takes effect as soon as the quorum is reached.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key rotation halted");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "", MIN_VOTES_SENSITIVE_ACTION);
    }

    /// @notice Freeze or unfreeze the verifier (slot 0) or distributionOracle (slot 1) key in KmsDirectives. identityOracle (slot 2) belongs to FoundationDAO, not here. Same _createAction rules: at least 3 votes and a majority, BOARD_ACTION_EXPIRY, void on a boardVersion change.
    ///         The slot and the flag are packed into `amount`: bits 0..7 = slot, bit 8 = frozen.
    function proposeKmsFreeze(uint8 slot, bool isFrozen) external onlyBoardMember returns (uint256 id) {
        require(slot <= 1, "ValidatorsBoard: the board freezes only the verifier and distributionOracle keys");
        require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key control halted");
        id = _createAction(ActionType.KmsFreeze, address(0), uint256(slot) | (isFrozen ? 0x100 : 0), "", MIN_VOTES_SENSITIVE_ACTION);
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
            } else if (a.atype == ActionType.SetEntryCollateral) {
                REGISTRY.setEntryCollateral(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.SetMembershipFeeBps) {
                REGISTRY.setMembershipFeeBps(a.amount);
                emit RegistryEconomicParamSet(a.atype, a.amount);
            } else if (a.atype == ActionType.RotateVerifier) {
                REGISTRY.setVerifier(a.target);
                emit VerifierRotated(a.target);
            } else if (a.atype == ActionType.KmsFreeze) {
                require(boardMembers.length >= MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: fewer than 3 board members - key control halted");
                IKmsDirectives(SurAddresses.KMS_DIRECTIVES).setFrozen(uint8(a.amount & 0xff), (a.amount & 0x100) != 0);
                emit KmsFreezeApplied(uint8(a.amount & 0xff), (a.amount & 0x100) != 0);
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

    // ------------------------------------------------------------------
    // v2.5: objections to a removal during network recovery (decision 2026-11-19)
    //
    // The removed validator objects in the Registry within 72 hours. The board then decides within 7 days: 3 votes to uphold
    // or 3 votes to cancel; the subject never votes (it holds no seat anyway). If fewer than 3 impartial board members hold
    // authority, ANYONE can refer the case to the validators: every validator that was Active at the referral moment may
    // vote, two thirds of that electorate decide. No decision in time = the removal is cancelled (Registry.expire...).
    // Registry case states: 2 = Objected (board), 3 = ReferredToAssembly (validators).
    // ------------------------------------------------------------------
    struct RecoveryTally {
        uint256 uphold;
        uint256 cancel;
    }

    /// @dev keyed by (validator, recordedAt) so a later case against the same address starts from zero.
    mapping(address => mapping(uint256 => RecoveryTally)) public boardRecoveryTallies;
    mapping(address => mapping(uint256 => RecoveryTally)) public assemblyRecoveryTallies;
    mapping(address => mapping(uint256 => mapping(address => bool))) private recoveryVoted;
    mapping(address => mapping(uint256 => mapping(address => bool))) private recoveryAssemblyVoted;

    event RecoveryRemovalVote(address indexed validator, address indexed voter, bool uphold, uint256 upholdVotes, uint256 cancelVotes);
    event RecoveryAssemblyVote(address indexed validator, address indexed voter, bool uphold, uint256 upholdVotes, uint256 cancelVotes);
    event RecoveryCaseDecided(address indexed validator, bool upheld, bool byAssembly);

    function voteRecoveryRemoval(address validator, bool uphold) external onlyBoardMember {
        (uint8 state, uint256 recordedAt, uint256 deadline) = REGISTRY.recoveryCaseInfo(validator);
        require(state == 2, "ValidatorsBoard: no open board case");
        require(block.timestamp <= deadline, "ValidatorsBoard: decision window over");
        require(msg.sender != validator, "ValidatorsBoard: the subject of a case cannot vote");
        require(!recoveryVoted[validator][recordedAt][msg.sender], "ValidatorsBoard: already voted");
        recoveryVoted[validator][recordedAt][msg.sender] = true;
        RecoveryTally storage t = boardRecoveryTallies[validator][recordedAt];
        if (uphold) t.uphold++; else t.cancel++;
        emit RecoveryRemovalVote(validator, msg.sender, uphold, t.uphold, t.cancel);
        if (t.uphold >= MIN_VOTES_SENSITIVE_ACTION) {
            REGISTRY.resolveRecoveryRemoval(validator, true);
            emit RecoveryCaseDecided(validator, true, false);
        } else if (t.cancel >= MIN_VOTES_SENSITIVE_ACTION) {
            REGISTRY.resolveRecoveryRemoval(validator, false);
            emit RecoveryCaseDecided(validator, false, false);
        }
    }

    /// @notice Anyone, when fewer than 3 board members other than the subject hold authority: the validators decide.
    function referRecoveryRemovalToAssembly(address validator) external {
        require(_impartialAuthorityCount(validator) < MIN_VOTES_SENSITIVE_ACTION, "ValidatorsBoard: enough impartial board members");
        REGISTRY.setRecoveryCaseReferred(validator); // checks the case is Objected and still open
    }

    function _impartialAuthorityCount(address subject) private view returns (uint256 n) {
        if (!_boardIsCurrent()) return 0;
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (boardMembers[i] != subject && _canAct(boardMembers[i])) n++;
        }
    }

    /// @notice A validator that was Active when the case was referred votes; two thirds of that electorate decide.
    function voteRecoveryAssembly(address validator, bool uphold) external {
        (uint8 state, uint256 recordedAt, uint256 deadline) = REGISTRY.recoveryCaseInfo(validator);
        require(state == 3, "ValidatorsBoard: no open assembly case");
        require(block.timestamp <= deadline, "ValidatorsBoard: decision window over");
        require(msg.sender != validator, "ValidatorsBoard: the subject of a case cannot vote");
        (uint256 referralNonce, uint256 eligible) = REGISTRY.recoveryReferral(validator);
        require(REGISTRY.isValidator(msg.sender) && REGISTRY.wasActiveAt(msg.sender, referralNonce), "ValidatorsBoard: not an eligible validator");
        require(!recoveryAssemblyVoted[validator][recordedAt][msg.sender], "ValidatorsBoard: already voted");
        recoveryAssemblyVoted[validator][recordedAt][msg.sender] = true;
        RecoveryTally storage t = assemblyRecoveryTallies[validator][recordedAt];
        if (uphold) t.uphold++; else t.cancel++;
        emit RecoveryAssemblyVote(validator, msg.sender, uphold, t.uphold, t.cancel);
        uint256 need = (2 * eligible + 2) / 3; // ceil(2n/3)
        if (t.uphold >= need) {
            REGISTRY.resolveRecoveryRemoval(validator, true);
            emit RecoveryCaseDecided(validator, true, true);
        } else if (t.cancel > eligible - need) {
            REGISTRY.resolveRecoveryRemoval(validator, false); // the two-thirds needed to uphold can no longer be reached
            emit RecoveryCaseDecided(validator, false, true);
        }
    }
}
