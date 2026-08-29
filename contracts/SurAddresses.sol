// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SurAddresses
/// @notice Fixed, genesis-assigned addresses for the SUR network's six structural contracts.
///         All six are deployed directly in the genesis block's `alloc` section (bytecode +
///         storage injected directly, not via a regular deployment transaction — see
///         "sur-contracts-deploy-notes.md" for the exact recipe). Because every one of these
///         addresses is therefore known and fixed before any contract's constructor logic is
///         even simulated, each contract can hardcode references to the others as constants
///         instead of needing a runtime "wire()" step after deployment (the previous approach,
///         now retired).
///
///         Do not change these values after genesis has been generated — they are baked into
///         every other contract's bytecode as constants, not stored in mutable state.
library SurAddresses {
    /// @dev FoundationDAO — SUR Foundation governance (15 members)
    address internal constant FOUNDATION_DAO = 0x1111111111111111111111111111111111111111;

    /// @dev BlockRewardDistributor — receives block reward + fees as miningbeneficiary,
    ///      periodically pays out validators + ValidatorsTreasury
    address internal constant BLOCK_REWARD_DISTRIBUTOR = 0x2222222222222222222222222222222222222222;

    /// @dev ValidatorsRegistry — source of truth for consensus (getValidators()) and payment
    ///      eligibility (isValidator()). This is the address that must also be set as
    ///      qbft.validatorcontractaddress in genesis.json.
    address internal constant VALIDATORS_REGISTRY = 0x3333333333333333333333333333333333333333;

    /// @dev ValidatorsBoard — small elected/recallable board with narrow delegated powers
    address internal constant VALIDATORS_BOARD = 0x4444444444444444444444444444444444444444;

    /// @dev ValidatorsTreasury — holds and spends the validators' 50% reward share
    address internal constant VALIDATORS_TREASURY = 0x5555555555555555555555555555555555555555;

    /// @dev IdentityRegistry — the sixth structural contract (added in a later revision). The
    ///      single source of truth for self-attested identity (name/person type) and
    ///      verification status (mobile/Telegram/full KYC) for **all network users**, not just
    ///      validators — which is why it is kept independent from ValidatorsRegistry.
    address internal constant IDENTITY_REGISTRY = 0x6666666666666666666666666666666666666666;
}
