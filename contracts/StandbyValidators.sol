// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @dev The only two ValidatorsRegistry getters this contract needs.
interface IStandbyRegistry {
    function ownerOfOperator(address operator) external view returns (address);
    function operatorOf(address owner) external view returns (address);
}

/// @title StandbyValidators
/// @notice Genesis contract, deployed at `SurAddresses.STANDBY_VALIDATORS` (0xcCcC...cCcC). It is a prepared validator list for
///         EMERGENCY CONSENSUS RECOVERY and for nothing else. Besu in `contract` validator-selection mode asks a contract
///         `getValidators()` who may produce blocks. In normal life that contract is ValidatorsRegistry. If more than a third of
///         the validators die the chain stops and no transaction can fix it; the only way out is a new `transitions.qbft` entry in
///         genesis that switches the selection to THIS contract (research record testing-evidence/recovery-research-v26, experiment
///         e5; a `blockheader` transition does not work on Shanghai/Cancun). The target contract must already exist in the state,
///         because changing `alloc` after launch makes every node refuse the genesis: this is why it is deployed at genesis.
///
///         It has NO effect on a healthy chain: nothing reads it until node operators, by a coordinated social decision, restart
///         with a genesis that points to it. So its power is small even if the foundation board were hostile: a list change alone
///         changes nothing.
///
///         Who writes: ONLY the FoundationDAO (an `Execute` proposal calling `setStandby`, 3 of 5). Not ValidatorsBoard, because
///         if the validators fail their board is probably unable to act; the foundation board does not depend on the validator
///         set being alive. Every change replaces the whole list and is checked here: size, strictly ascending addresses (so no
///         duplicates, same rule as payPage), non-zero, and every member must be the CURRENT operator (node key) of a seat
///         registered in ValidatorsRegistry.
///
///         Maintenance: operator keys change (setOperator, seat transfer). `staleMembers()` and `isReady()` tell dashboards and the
///         recovery tool whether the list is still valid; the foundation should refresh it in the same governance step as any
///         change that touches a member.
///
///         QBFT arithmetic: n members need at least ceil(2n/3) of them online to produce blocks; the minimum list is 4 (tolerates one
///         down). The recovery plan should list members that are well run and reachable.
///
///         GENESIS: no constructor, no storage seed. Injected into `alloc` with its runtime bytecode only. The list starts EMPTY, so
///         the foundation must set it right after launch (launch-kit checklist), or the GenesisBuilder may seed it.
contract StandbyValidators {
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;
    IStandbyRegistry public constant REGISTRY = IStandbyRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice Smallest valid standby list (QBFT with 4 tolerates one faulty node).
    uint256 public constant MIN_MEMBERS = 4;
    /// @notice Upper bound on the list; keeps getValidators() cheap for Besu.
    uint256 public constant MAX_MEMBERS = 100;

    address[] private _members;
    /// @notice Number of times the list was replaced (0 = never set).
    uint256 public version;
    /// @notice Timestamp of the last replacement (0 = never set).
    uint256 public updatedAt;

    event StandbyUpdated(uint256 indexed version, address[] members);

    /// @notice The list Besu reads. Pure storage read: it never reverts and never depends on any other contract.
    function getValidators() external view returns (address[] memory) {
        return _members;
    }

    function memberCount() external view returns (uint256) {
        return _members.length;
    }

    /// @notice Replace the whole list. Only the FoundationDAO (through its Execute proposal).
    function setStandby(address[] calldata members) external {
        require(msg.sender == FOUNDATION, "StandbyValidators: only FoundationDAO");
        uint256 n = members.length;
        require(n >= MIN_MEMBERS, "StandbyValidators: too few members");
        require(n <= MAX_MEMBERS, "StandbyValidators: too many members");
        address prev = address(0);
        for (uint256 i = 0; i < n; i++) {
            address m = members[i];
            require(m > prev, "StandbyValidators: members must be strictly ascending and non-zero");
            require(_isCurrentOperator(m), "StandbyValidators: not the current operator key of a registered seat");
            prev = m;
        }
        _members = members;
        version += 1;
        updatedAt = block.timestamp;
        emit StandbyUpdated(version, members);
    }

    /// @notice Members that are no longer the current operator key of a seat (the list needs a refresh).
    function staleMembers() public view returns (address[] memory stale) {
        uint256 n = _members.length;
        address[] memory tmp = new address[](n);
        uint256 c;
        for (uint256 i = 0; i < n; i++) {
            if (!_isCurrentOperator(_members[i])) tmp[c++] = _members[i];
        }
        stale = new address[](c);
        for (uint256 j = 0; j < c; j++) stale[j] = tmp[j];
    }

    /// @notice True when the list is usable for recovery now: at least MIN_MEMBERS and no stale member.
    function isReady() external view returns (bool) {
        return _members.length >= MIN_MEMBERS && staleMembers().length == 0;
    }

    function _isCurrentOperator(address m) private view returns (bool) {
        address owner_ = REGISTRY.ownerOfOperator(m);
        return owner_ != address(0) && REGISTRY.operatorOf(owner_) == m;
    }
}
