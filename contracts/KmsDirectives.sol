// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title KmsDirectives
/// @notice Tiny genesis contract, deployed at `SurAddresses.KMS_DIRECTIVES` (0xBbBb...BbBb). It holds ONE fact per signing key of the
///         SurKMS service: whether that key is FROZEN. The KMS reads `frozen(slot)` (at start, at regular intervals and on the event)
///         and refuses to sign with a frozen key. It has no money, no other power and no other state.
///         Key rotation is NOT here: it stays in the existing contracts (ValidatorsRegistry.setVerifier, BlockRewardDistributor.
///         setDistributionOracle, IdentityRegistry.setIdentityOracle). The server list and the per-key rules are NOT on-chain either.
///
///         Who may change a flag (owner decision 2026-11-21, sur-kms-spec.md section 10):
///           - Slot.Verifier, Slot.DistributionOracle: only ValidatorsBoard (a `KmsFreeze` board action: at least 3 votes and a
///             majority, 14 days, void on a board change).
///           - Slot.IdentityOracle: only FoundationDAO, through its existing `Execute` proposal (no change in FoundationDAO).
///         Setting a flag to the value it already has is a silent no-op (no event), so a duplicate proposal can never get stuck.
///
///         GENESIS: no constructor, no storage seed (all flags start false). Injected into `alloc` with its runtime bytecode only.
contract KmsDirectives {
    /// @dev The three signing keys of the SurKMS service. The numbers are part of the ABI (uint8) and must not change.
    enum Slot { Verifier, DistributionOracle, IdentityOracle }

    address public constant BOARD = SurAddresses.VALIDATORS_BOARD;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @notice True while the key of this slot is frozen (the KMS must not sign with it).
    mapping(Slot => bool) public frozen;

    event FrozenChanged(Slot indexed slot, bool frozen);

    function setFrozen(Slot slot, bool isFrozen) external {
        if (slot == Slot.IdentityOracle) {
            require(msg.sender == FOUNDATION, "KmsDirectives: identityOracle is frozen only by FoundationDAO");
        } else {
            require(msg.sender == BOARD, "KmsDirectives: this key is frozen only by ValidatorsBoard");
        }
        if (frozen[slot] == isFrozen) return; // idempotent: nothing changes, no event
        frozen[slot] = isFrozen;
        emit FrozenChanged(slot, isFrozen);
    }
}
