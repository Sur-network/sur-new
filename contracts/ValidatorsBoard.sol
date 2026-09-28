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
    // ✅ FIXED / اصلاح‌شده — لایه‌ی دوم دفاع در برابر بازگشتِ اختیار کرسی کهنه؛ ValidatorsRegistry.sol را ببین.
    function membershipEpoch(address who) external view returns (uint256);
    /// @dev `status` is ValidatorsRegistry.Status's ABI-compatible uint8 encoding:
    ///      0=None, 1=Probation, 2=Active, 3=Demoted, 4=Exiting.
    /// @dev ✅ UPDATED (off-chain verification architecture redesign): the real
    ///      ValidatorsRegistry.getValidatorInfo() no longer has any liveness-ratio fields at all
    ///      (they were removed entirely — liveness is checked off-chain now). It returns exactly
    ///      6 outputs in this order: status, lockedStake, periodStartedAt, demotedAt,
    ///      pendingSlashEpoch, isPaidEntrant. This interface MUST match that exactly, in the same
    ///      order — see the real function's own doc comment in ValidatorsRegistry.sol for why a
    ///      mismatch here caused a real, silent cross-contract bug in an earlier version (fixed
    ///      then, and worth re-checking any time the real function's signature changes again).
    function getValidatorInfo(address who) external view returns (
        uint8 status,
        uint256 lockedStake,
        uint256 periodStartedAt,
        uint256 demotedAt,
        uint256 pendingSlashEpoch,
        bool isPaidEntrant
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

    /// @dev ✅ HARDENED (related to the stale-vote bug class found in review, though less
    ///      severe here since `required` is always derived from the fixed BOARD_SIZE, not a
    ///      shrinking count): without an expiry, a board action could still sit open long
    ///      enough that the ORIGINAL board membership shifts (via _recomputeBoard) before
    ///      enough votes accumulate — meaning votes cast by since-replaced ex-board-members
    ///      could combine with a current member's vote to reach majority, even though no real
    ///      5-person board ever agreed on it at the same time. `expiresAt` bounds that window.
    /// @dev ✅ FIXED (this was only PARTIALLY fixed before — the earlier pass added `expiresAt`
    ///      but incorrectly reasoned that `required` didn't need snapshotting because it's
    ///      "always derived from the fixed BOARD_SIZE." That reasoning was wrong: refreshBoard()
    ///      below fills the board with however many DISTINCT candidates received at least one
    ///      vote, up to BOARD_SIZE — if fewer than 5 candidates qualify (realistic early in the
    ///      network's life, or after a wave of validators leave), `boardMembers.length` is
    ///      genuinely less than 5, and `_voteAction()` computed `required` from that LIVE,
    ///      shrinkable length, not the constant. This is the exact same stale-vote bug class as
    ///      every other proposal mechanism in this project: `votes` only ever increases, while
    ///      `required` could shrink between votes as the board is refreshed. `requiredVotes` is
    ///      now snapshotted at creation, exactly like BlockRewardDistributor's ShareProposal,
    ///      ValidatorsRegistry's ParamProposal, ValidatorsTreasury's Expenditure/ParamProposal,
    ///      and FoundationDAO's Proposal.
    struct BoardAction {
        ActionType atype;
        address target;      // new oracle address, or budget recipient (unused for economic-param actions)
        uint256 amount;       // budget amount for ApproveBudget, OR the new value for economic-param actions
        string description;   // only used for ApproveBudget
        uint256 votes;
        uint256 requiredVotes; // ✅ NEW — snapshotted at creation, never recomputed
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        /// @notice ✅ FIXED (bug found in independent review — critical for spending decisions
        ///         specifically): `votes` used to be a simple counter with no link to WHICH
        ///         addresses cast them or whether those addresses are still board members. Since
        ///         `refreshBoard()` below can completely replace the board's membership, a
        ///         proposal created and partly voted on under the OLD board could still reach its
        ///         vote threshold using votes from members who have since left — e.g., two former
        ///         members vote, then refreshBoard() replaces them, then just ONE current member
        ///         casts the "third" vote, and the action executes with only 1 of its 3 counted
        ///         votes coming from someone who is currently a board member. Fixed by snapshotting
        ///         the board's version number here at creation, and invalidating (requiring a
        ///         fresh proposal for) any action whose version no longer matches the current one
        ///         — see boardVersion below and _voteAction()'s check.
        uint256 boardVersionAtCreation;
    }

    uint256 public constant BOARD_ACTION_EXPIRY = 14 days;

    /// @notice ✅ Increments ONLY when refreshBoard() below installs a membership that genuinely
    ///         differs (as an order-independent SET) from the previous one. A refresh that
    ///         reproduces the identical member set does NOT bump it. (An earlier version bumped on
    ///         every refresh; because refreshBoard() is permissionless with no cooldown, that let
    ///         anyone keep invalidating open actions at will — an indefinitely repeatable
    ///         griefing vector, found in independent review and fixed by the set comparison in
    ///         refreshBoard().) Every open action records the version it was proposed under and
    ///         becomes invalid once the version moves on — see boardVersionAtCreation.
    uint256 public boardVersion = 1;

    /// @notice P01: an ORDINARY change of board composition (refreshBoard) is applied at most once every 30 days.
    uint256 public constant BOARD_REFRESH_INTERVAL = 30 days;
    /// @notice Time of the last ordinary refresh. Genesis must overlay this with the genesis timestamp when the board is
    ///         seeded (otherwise the first refresh is allowed immediately).
    uint256 public lastBoardRefreshAt;
    /// @notice Seats freed by exit-driven loss of authority that have not yet been filled by succession.
    uint256 public pendingVacancies;
    event BoardMemberAuthorityEnded(address indexed member);
    event BoardSuccession(address indexed newMember);

    /// @notice ✅ FIXED (independent review — closes a real bug: `_hasAuthority` used to treat
    ///         "has a seat AND status not None/Exiting" as sufficient, so a member who exited,
    ///         withdrew, and later re-registered under the SAME address could land back in
    ///         Probation and regain the OLD seat's authority before anyone called syncBoard()).
    ///         Stamped with `REGISTRY.membershipEpoch(addr)` the moment an address takes a seat
    ///         (refreshBoard / _fillVacancies); `_hasAuthority` requires this to still match the
    ///         registry's current value. `ValidatorsRegistry.requestExit()` now also permanently
    ///         bans the address from ever calling requestMembership() again — the two fixes are
    ///         independent layers, not alternatives.
    mapping(address => uint256) public seatMembershipEpoch;

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

    /// @notice P02: board authority = holding a seat AND not having requested voluntary exit. Loses effect the moment an exit is
    ///         requested (no waiting for the monthly refresh). Suspension (Demoted) alone does NOT cut authority within the period.
    ///         If any seat holder has requested exit and the seat has not been cleaned up yet, board actions REVERT with a clear
    ///         message until someone calls the permissionless syncBoard() (a separate transaction, so the cleanup itself is never
    ///         rolled back). This also means a vote can never silently "succeed" on an invalidated proposal: see voteAction().
    modifier onlyBoardMember() {
        require(_hasAuthority(msg.sender), "ValidatorsBoard: caller has no board authority");
        require(!_syncNeeded(), "ValidatorsBoard: a seat holder has requested exit - call syncBoard() first");
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

    /// @notice P01/P02: ordinary re-selection — the BOARD_SIZE validators with the most current votes, applied at most once every 30
    ///         days (a fully empty board may be filled at any time). Membership is conditional on being an ACTIVE validator at this
    ///         moment: only votes cast BY active validators FOR active candidates count, so a suspended member cannot stay on the
    ///         board past the monthly re-selection. Voting and changing votes stay free at all times (voteFor / unvoteFor).
    function refreshBoard() external {
        require(
            boardMembers.length == 0 || block.timestamp >= lastBoardRefreshAt + BOARD_REFRESH_INTERVAL,
            "ValidatorsBoard: ordinary board changes are applied once every 30 days"
        );
        (address[] memory newBoard, uint256[] memory newBoardVotes, uint256 filled) = _topCandidates(BOARD_SIZE, false);

        // ✅ FIXED (bug found in independent review — the previous version of this fix bumped
        // boardVersion UNCONDITIONALLY on every successful refreshBoard() call, even when the
        // resulting membership was identical to before. Since this function is permissionless
        // and has no cooldown, anyone could call it repeatedly — even with zero actual
        // membership change — purely to keep invalidating any board action sitting open for a
        // vote, an indefinitely repeatable griefing vector). Compare the actual member SET
        // (order-independent) BEFORE clearing the old isBoardMember flags below — only bump the
        // version if membership genuinely changed.
        bool membershipChanged = (boardMembers.length != filled);
        if (!membershipChanged) {
            for (uint256 i = 0; i < filled; i++) {
                if (!isBoardMember[newBoard[i]]) {
                    membershipChanged = true;
                    break;
                }
            }
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
            seatMembershipEpoch[newBoard[i]] = REGISTRY.membershipEpoch(newBoard[i]);
            finalBoard[i] = newBoard[i];
            finalVotes[i] = newBoardVotes[i];
        }

        // ✅ FIXED: bump the board version ONLY when membership genuinely changed (see
        // membershipChanged above) — so any action proposed and partly voted on under the old
        // membership is correctly invalidated when the board actually changes, without giving
        // anyone a free, repeatable way to invalidate open actions by calling refreshBoard()
        // with no real effect.
        if (membershipChanged) {
            boardVersion++;
        }


        lastBoardRefreshAt = block.timestamp;
        pendingVacancies = 0; // the ordinary re-selection recomputes the whole board; vacancies are not carried over

        emit BoardRefreshed(finalBoard, finalVotes);
    }

    /// @dev Ephemeral per-refreshBoard()-call tally storage. Always 0 between calls — see
    ///      refreshBoard()'s reset loop. Declared as contract storage (not `memory`) only
    ///      because Solidity has no mapping type in memory.
    mapping(address => uint256) private _voteTally;

    // ------------------------------------------------------------------
    // Authority, monthly re-selection, and exit-driven succession (final decisions P01/P02)
    // ------------------------------------------------------------------

    /// @dev P02 authority test (see the onlyBoardMember doc comment).
    function _hasAuthority(address who) private view returns (bool) {
        if (!isBoardMember[who]) return false;
        if (REGISTRY.membershipEpoch(who) != seatMembershipEpoch[who]) return false; // ✅ FIXED: exited since being seated
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(who);
        return status != 0 && status != 4; // not None (withdrawn / never a validator), not Exiting
    }

    function hasBoardAuthority(address who) external view returns (bool) {
        return _hasAuthority(who);
    }


    /// @dev True if some seat holder has lost authority (requested exit / withdrew) and syncBoard() has not run yet.
    function _syncNeeded() private view returns (bool) {
        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (!_hasAuthority(boardMembers[i])) return true;
        }
        return false;
    }

    /// @notice Permissionless. Drops seats whose holder requested exit (immediate cut-off), then tries succession for those seats.
    function syncBoard() external {
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
        if (changed) boardVersion++; // real composition change: open actions of the old composition become invalid
    }

    /// @notice Permissionless succession for seats freed by exit: the highest-voted ELIGIBLE (currently active, not already seated)
    ///         candidates by the live tally take the pending vacancies. Fills only exit-freed seats — never an extra ordinary
    ///         change. If no eligible candidate exists the seat stays vacant (and with fewer than 3 seated members, treasury
    ///         payments are halted) until one appears or the next monthly refresh.
    function fillVacancies() external {
        if (_fillVacancies()) boardVersion++;
    }

    function _fillVacancies() private returns (bool filledAny) {
        uint256 room = BOARD_SIZE - boardMembers.length;
        uint256 want = pendingVacancies < room ? pendingVacancies : room;
        if (want == 0) return false;
        (address[] memory picks, , uint256 n) = _topCandidates(want, true);
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

    /// @dev Live tally: votes cast BY currently active validators FOR currently active candidates (same rule as before).
    function _tallyVotes() private returns (address[] memory seenCandidates, uint256 seenCount) {
        address[] memory active = REGISTRY.getValidators();
        seenCandidates = new address[](active.length * MAX_VOTES_PER_VOTER);
        for (uint256 i = 0; i < active.length; i++) {
            address[] storage cands = voterCandidates[active[i]];
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
    }

    /// @dev Top-k candidates by live tally (ties keep the earlier-inserted one). Resets the ephemeral tally before returning.
    function _topCandidates(uint256 k, bool excludeMembers) private returns (address[] memory picks, uint256[] memory pickVotes, uint256 filled) {
        (address[] memory seen, uint256 seenCount) = _tallyVotes();
        picks = new address[](k);
        pickVotes = new uint256[](k);
        for (uint256 i = 0; i < seenCount && k > 0; i++) {
            address c = seen[i];
            if (excludeMembers && isBoardMember[c]) continue;
            uint256 v = _voteTally[c];
            if (filled < k) {
                picks[filled] = c;
                pickVotes[filled] = v;
                filled++;
            } else {
                uint256 minIdx = 0;
                for (uint256 m = 1; m < k; m++) {
                    if (pickVotes[m] < pickVotes[minIdx]) minIdx = m;
                }
                if (v > pickVotes[minIdx]) {
                    picks[minIdx] = c;
                    pickVotes[minIdx] = v;
                }
            }
        }
        for (uint256 i = 0; i < seenCount; i++) {
            _voteTally[seen[i]] = 0; // reset the ephemeral tally
        }
    }

    /// @notice Purge every vote a long-inactive validator cast (as a voter) AND every vote they
    ///         received (as a candidate), freeing up the other validators' vote slots.
    ///         Permissionless. Requires the validator to have been continuously Demoted for at
    ///         least `ValidatorsRegistry.recoveryPeriod() + STALE_VOTE_CLEAR_DELAY` (30 days).
    ///         Before this point, their votes already don't count in refreshBoard() (see above)
    ///         — this function only frees storage/vote-slots, it does not itself change who is
    ///         currently on the board.
    function clearStaleVotes(address validator) external {
        (uint8 status, , , uint256 demotedAt, , ) = REGISTRY.getValidatorInfo(validator);
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
        id = _createAction(ActionType.RotateOracle, newOracle, 0, "", 0);
    }

    /// @notice ✅ NEW guarantee (explicit user decision): unlike every other board action, an
    ///         ApproveBudget proposal requires a HARD MINIMUM of 3 affirmative votes, regardless
    ///         of how small the current board has shrunk to (e.g., with only 3 members, the
    ///         plain-majority formula would need just 2 — not enough for a spending decision).
    ///         If fewer than 3 eligible board members currently exist, spending halts entirely
    ///         (this function reverts) until the board's composition is repaired back to at
    ///         least 3 — no smaller quorum can ever approve a payment, no matter how urgent.
    function proposeApproveBudget(address to, uint256 amount, string calldata description)
        external
        onlyBoardMember
        returns (uint256 id)
    {
        require(to != address(0), "ValidatorsBoard: zero recipient address");
        require(amount > 0, "ValidatorsBoard: zero amount");
        require(boardMembers.length >= 3, "ValidatorsBoard: fewer than 3 board members - spending halted");
        id = _createAction(ActionType.ApproveBudget, to, amount, description, 3);
    }

    /// @notice Propose a new entryThresholdBase on ValidatorsRegistry (economic entry
    ///         parameter — board-governed; see contract-level doc comment).
    function proposeSetEntryThresholdBase(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        id = _createAction(ActionType.SetEntryThresholdBase, address(0), newValue, "", 0);
    }

    /// @notice Propose a new growthFactorPerValidator on ValidatorsRegistry (fixed-point, 18
    ///         decimals; must be > 1.0, i.e. > 1_000000000000000000).
    function proposeSetGrowthFactorPerValidator(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue > 1_000000000000000000, "ValidatorsBoard: growth factor must be > 1.0");
        id = _createAction(ActionType.SetGrowthFactorPerValidator, address(0), newValue, "", 0);
    }

    /// @notice Propose a new membershipFeeBps on ValidatorsRegistry.
    function proposeSetMembershipFeeBps(uint256 newValue) external onlyBoardMember returns (uint256 id) {
        require(newValue <= 10000, "ValidatorsBoard: membershipFeeBps too high");
        id = _createAction(ActionType.SetMembershipFeeBps, address(0), newValue, "", 0);
    }

    /// @notice Propose rotating the identity-verification key (`verifier`) on
    ///         ValidatorsRegistry — a routine operational-key rotation, same pattern as
    ///         proposeRotateOracle.
    function proposeRotateVerifier(address newVerifier) external onlyBoardMember returns (uint256 id) {
        require(newVerifier != address(0), "ValidatorsBoard: zero verifier address");
        id = _createAction(ActionType.RotateVerifier, newVerifier, 0, "", 0);
    }

    function voteAction(uint256 id) external onlyBoardMember {
        // An action proposed under an older composition is invalid: _voteAction() REVERTS ("board membership changed since this
        // action was proposed - propose again"). The transaction fails visibly instead of returning as a no-op, so nobody can
        // mistake a successful receipt for "my vote was recorded".
        _voteAction(id, msg.sender);
    }

    /// @notice ✅ NEW parameter (explicit user decision — ApproveBudget specifically must never
    ///         execute with fewer than 3 affirmative votes, even if the board has shrunk below
    ///         its full size of 5). `minRequiredVotes` is 0 for every OTHER action type (meaning
    ///         "use the plain majority formula, no extra floor") and 3 only for ApproveBudget —
    ///         see proposeApproveBudget below for why spending specifically needs this stricter
    ///         floor while routine actions like key rotation do not.
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
            requiredVotes: majority > minRequiredVotes ? majority : minRequiredVotes, // ✅ hard
            // floor, frozen now from the ACTUAL current board size — see the doc comment above
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
        // ✅ FIXED (bug found in independent review — see boardVersionAtCreation's doc comment
        // in the BoardAction struct above): if the board's membership has changed since this
        // action was proposed, it is invalidated — voters must propose it again under the
        // current board. This is what actually prevents stale votes from former members (who
        // voted before leaving) from ever counting toward a fresh board's decisions; simply
        // checking `isBoardMember` at vote time (which already existed) was not enough, since it
        // only validates the CURRENT voter, not the historical votes already tallied.
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
                // ✅ NEW: re-checked at EXECUTION time, not just at proposal time — the user's
                // decision explicitly said "اعضای فعلی" (CURRENT members), meaning even if this
                // action already gathered its required votes while the board still had ≥3
                // members, execution must still be blocked if the board has since shrunk below
                // 3 before this final vote lands. The whole vote transaction (including this
                // very vote) reverts in that case, so nothing is silently skipped or partially
                // recorded — the board's composition must be repaired first.
                require(boardMembers.length >= 3, "ValidatorsBoard: fewer than 3 board members - spending halted");
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
