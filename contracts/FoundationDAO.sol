// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal ERC20 interface for token transfers
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title FoundationDAO
/// @notice Deployed at the fixed genesis address SurAddresses.FOUNDATION_DAO (0x1111...1111).
///         Governance contract for the SUR Foundation (renamed from MemberDAO). Manages the
///         foundation's own members and funds.
///
///         GOVERNANCE THRESHOLDS (updated decision — no longer uniform across proposal types):
///           - AddMember, RemoveMember, SendETH: TWO-THIRDS supermajority, ceil(2n/3) of
///             current members. A deliberately higher bar for membership changes and for
///             spending native currency (Suren) — including this contract's genesis-allocated
///             20,000,000 Suren balance (see design doc section 6 / foundation charter article
///             3-6), since Suren is the chain's native currency and SendETH is how any native
///             transfer, from any balance this contract holds, is made.
///           - SendERC20, Execute: unchanged, simple majority, floor(n/2) + 1.
///
///         ⚠️ REMOVED (updated decision): `proposeRequestTreasuryBudget` / `RequestTreasuryBudget`
///         — judged not useful and removed entirely. This contract now has NO connection
///         whatsoever to ValidatorsTreasury; it cannot request, propose, or trigger any
///         expenditure there. The only way SUR funds now reach the foundation from
///         ValidatorsTreasury is if an active validator or a ValidatorsBoard member initiates
///         that proposal themselves (see ValidatorsTreasury.sol / ValidatorsBoard.sol) — the
///         foundation has no self-service request path any more.
///
///         Being a foundation member does NOT restrict a person's other civil rights — a
///         foundation member may simultaneously be a network validator and/or a member of
///         ValidatorsBoard; nothing in this contract or ValidatorsRegistry/ValidatorsBoard
///         checks for or restricts this overlap.
///
///         IMPORTANT — governance boundary (design doc section 4): the foundation has NO
///         control whatsoever over the network, validators, or any oracle. The earlier design
///         where this contract (as `MemberDAO`) held `setDistributionOracle` /
///         `setValidatorSyncOracle` power over BlockRewardDistributor has been fully retired —
///         those functions, the old BLOCK_REWARD_DISTRIBUTOR constant, and the corresponding
///         proposal types have been removed entirely, not just deprecated. Oracle control now
///         belongs exclusively to ValidatorsBoard (routine rotation) and a full validator vote
///         (structural changes) — see ValidatorsBoard.sol and BlockRewardDistributor.sol.
///
///         GENESIS DEPLOYMENT: the initial 15 foundation members are passed directly into the
///         constructor and applied immediately, instead of the old single-caller `register()`
///         bootstrap. Separately, the genesis `alloc` credits this contract's own address with
///         20,000,000 Suren (native currency, not a token transfer) — the "توزیع توکن‌های پایه‌ی
///         شبکه" the foundation is responsible for per the charter's article 3-6; distributed
///         onward via proposeSendETH proposals, subject to the two-thirds threshold above.
contract FoundationDAO {
    // ------------------------------------------------------------------
    // Data structures
    // ------------------------------------------------------------------
    struct Member {
        string name;
        address account;
    }

    enum ProposalType { AddMember, RemoveMember, SendETH, SendERC20, Execute }
    enum ProposalStatus { Pending, Executed }

    struct Proposal {
        uint256 id;
        ProposalType pType;
        string description;
        address proposer;
        string newMemberName;   // only for AddMember
        address targetAccount;  // target member, transfer/call destination, or treasury budget recipient
        uint256 amount;         // ETH or token amount, or value for Execute
        address tokenAddress;   // only for SendERC20
        bytes data;             // only for Execute
        uint256 votes;
        uint256 createdAt;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    // ------------------------------------------------------------------
    // State variables
    // ------------------------------------------------------------------
    Member[] public memberList;
    mapping(address => uint256) private memberIndex; // 1-based index into memberList, 0 means not a member
    mapping(address => bool) public isMember;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private proposals;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event ProposalCreated(uint256 indexed id, ProposalType pType, address indexed proposer);
    event Voted(uint256 indexed id, address indexed voter, uint256 totalVotes, uint256 requiredVotes);
    event ProposalExecuted(uint256 indexed id, ProposalType pType);
    event MemberAdded(address indexed account, string name);
    event MemberRemoved(address indexed account);

    modifier onlyMember() {
        require(isMember[msg.sender], "FoundationDAO: caller is not a member");
        _;
    }

    receive() external payable {}

    // ------------------------------------------------------------------
    // Constructor — executed once, off-chain, to compute the genesis storage snapshot.
    // See "sur-contracts-deploy-notes.md" for the full recipe.
    // ------------------------------------------------------------------
    constructor(string[] memory names, address[] memory accounts) {
        require(names.length == accounts.length, "FoundationDAO: length mismatch");
        require(names.length > 0, "FoundationDAO: empty initial member list");
        for (uint256 i = 0; i < names.length; i++) {
            require(bytes(names[i]).length > 0, "FoundationDAO: empty name");
            _addMember(accounts[i], names[i]);
        }
    }

    // ------------------------------------------------------------------
    // Proposal creation — members only
    // ------------------------------------------------------------------
    function proposeAddMember(string calldata description, string calldata name, address account) external onlyMember returns (uint256) {
        require(account != address(0), "FoundationDAO: zero address");
        require(!isMember[account], "FoundationDAO: already a member");
        require(bytes(name).length > 0, "FoundationDAO: empty name");
        return _createProposal(description, ProposalType.AddMember, name, account, 0, address(0), "");
    }

    function proposeRemoveMember(string calldata description, address account) external onlyMember returns (uint256) {
        require(isMember[account], "FoundationDAO: not a member");
        return _createProposal(description, ProposalType.RemoveMember, "", account, 0, address(0), "");
    }

    function proposeSendETH(string calldata description, address to, uint256 amount) external onlyMember returns (uint256) {
        // Note: this is also the mechanism for Article 3-6 of the foundation's charter (initial
        // distribution of genesis-minted Suren, the chain's native currency, by the foundation
        // to network participants) — no separate distribution contract is needed. Suren credited
        // to this contract's own genesis `alloc` balance can simply be sent out member-by-member
        // proposal through this same function, since Suren is native currency, not a token.
        require(to != address(0), "FoundationDAO: zero address");
        return _createProposal(description, ProposalType.SendETH, "", to, amount, address(0), "");
    }

    function proposeSendERC20(string calldata description, address token, address to, uint256 amount) external onlyMember returns (uint256) {
        require(token != address(0) && to != address(0), "FoundationDAO: zero address");
        return _createProposal(description, ProposalType.SendERC20, "", to, amount, token, "");
    }

    /// @notice Execute arbitrary code (data) on a target address, subject to majority member consensus
    function proposeExecute(string calldata description, address target, uint256 value, bytes calldata data) external onlyMember returns (uint256) {
        require(target != address(0), "FoundationDAO: zero address");
        return _createProposal(description, ProposalType.Execute, "", target, value, address(0), data);
    }

    function _createProposal(
        string memory description,
        ProposalType pType,
        string memory name,
        address target,
        uint256 amount,
        address token,
        bytes memory data
    ) private returns (uint256) {
        proposalCount++;
        uint256 id = proposalCount;

        Proposal storage p = proposals[id];
        p.id = id;
        p.description = description;
        p.pType = pType;
        p.proposer = msg.sender;
        p.newMemberName = name;
        p.targetAccount = target;
        p.amount = amount;
        p.tokenAddress = token;
        p.data = data;
        p.createdAt = block.timestamp;
        p.status = ProposalStatus.Pending;

        emit ProposalCreated(id, pType, msg.sender);

        // the proposer is automatically counted as a "yes" vote
        _vote(id, msg.sender);

        return id;
    }

    // ------------------------------------------------------------------
    // Voting — once the majority threshold is reached, the proposal executes immediately
    // ------------------------------------------------------------------
    function vote(uint256 proposalId) external onlyMember {
        _vote(proposalId, msg.sender);
    }

    function _vote(uint256 proposalId, address voter) private {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "FoundationDAO: proposal not found");
        require(p.status == ProposalStatus.Pending, "FoundationDAO: proposal not pending");
        require(!p.hasVoted[voter], "FoundationDAO: already voted");

        p.hasVoted[voter] = true;
        p.votes++;

        uint256 required = _requiredVotes(p.pType);
        emit Voted(proposalId, voter, p.votes, required);

        if (p.votes >= required) {
            _execute(p);
        }
    }

    /// @dev Voting threshold depends on the proposal type:
    ///      - AddMember, RemoveMember, SendETH (i.e. spending the genesis-allocated 20,000,000
    ///        Suren balance this contract holds — Suren is native currency, see design doc
    ///        section 3-6 / the foundation charter's article 3-6): TWO-THIRDS supermajority,
    ///        ceil(2n/3) — a deliberately higher bar for membership changes and moving the
    ///        foundation's native-currency treasury.
    ///      - Everything else (SendERC20, Execute): simple majority,
    ///        floor(n/2) + 1, unchanged from before.
    ///      e.g. 15 members: simple majority -> 8, two-thirds supermajority -> 10.
    function _requiredVotes(ProposalType pType) private view returns (uint256) {
        uint256 n = memberList.length;
        if (pType == ProposalType.AddMember || pType == ProposalType.RemoveMember || pType == ProposalType.SendETH) {
            return (2 * n + 2) / 3; // ceil(2n/3)
        }
        return (n / 2) + 1;
    }

    // ------------------------------------------------------------------
    // Proposal execution once consensus is reached
    // ------------------------------------------------------------------
    function _execute(Proposal storage p) private {
        p.status = ProposalStatus.Executed;

        if (p.pType == ProposalType.AddMember) {
            _addMember(p.targetAccount, p.newMemberName);
            emit MemberAdded(p.targetAccount, p.newMemberName);

        } else if (p.pType == ProposalType.RemoveMember) {
            _removeMember(p.targetAccount);
            emit MemberRemoved(p.targetAccount);

        } else if (p.pType == ProposalType.SendETH) {
            (bool success, ) = p.targetAccount.call{value: p.amount}("");
            require(success, "FoundationDAO: ETH transfer failed");

        } else if (p.pType == ProposalType.SendERC20) {
            bool success = IERC20(p.tokenAddress).transfer(p.targetAccount, p.amount);
            require(success, "FoundationDAO: ERC20 transfer failed");

        } else if (p.pType == ProposalType.Execute) {
            (bool success, ) = p.targetAccount.call{value: p.amount}(p.data);
            require(success, "FoundationDAO: execution failed");
        }

        emit ProposalExecuted(p.id, p.pType);
    }

    // ------------------------------------------------------------------
    // Internal member management functions
    // ------------------------------------------------------------------
    function _addMember(address account, string memory name) private {
        require(account != address(0), "FoundationDAO: zero address");
        require(!isMember[account], "FoundationDAO: already a member");
        memberList.push(Member({name: name, account: account}));
        memberIndex[account] = memberList.length; // 1-based index
        isMember[account] = true;
    }

    function _removeMember(address account) private {
        require(isMember[account], "FoundationDAO: not a member");
        uint256 idx = memberIndex[account] - 1;
        uint256 lastIdx = memberList.length - 1;

        if (idx != lastIdx) {
            memberList[idx] = memberList[lastIdx];
            memberIndex[memberList[idx].account] = idx + 1;
        }
        memberList.pop();

        delete memberIndex[account];
        isMember[account] = false;
    }

    // ------------------------------------------------------------------
    // View helper functions
    // ------------------------------------------------------------------
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }

    function getAllMembers() external view returns (Member[] memory) {
        return memberList;
    }

    /// @notice Voting threshold required right now for a given proposal type — 2/3
    ///         supermajority for AddMember/RemoveMember/SendETH, simple majority otherwise.
    function requiredVotesNow(ProposalType pType) external view returns (uint256) {
        return _requiredVotes(pType);
    }

    function getProposal(uint256 id) external view returns (
        ProposalType pType,
        address proposer,
        string memory newMemberName,
        address targetAccount,
        uint256 amount,
        address tokenAddress,
        bytes memory data,
        uint256 votes,
        ProposalStatus status
    ) {
        Proposal storage p = proposals[id];
        return (
            p.pType,
            p.proposer,
            p.newMemberName,
            p.targetAccount,
            p.amount,
            p.tokenAddress,
            p.data,
            p.votes,
            p.status
        );
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getErc20Balance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasVoted[voter];
    }
}
