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

    /// @dev ValidatorsTreasury — holds and spends the validators' share of the reward pool
    ///      (the remainder after Foundation's fixed 15% and validators' governable direct
    ///      share — no longer a fixed 50%; see BlockRewardDistributor.validatorDirectShareBps)
    address internal constant VALIDATORS_TREASURY = 0x5555555555555555555555555555555555555555;

    /// @dev IdentityRegistry — the sixth structural contract (added in a later revision). The
    ///      single source of truth for self-attested identity (name/person type) and
    ///      verification status (mobile/Telegram/full KYC) for **all network users**, not just
    ///      validators — which is why it is kept independent from ValidatorsRegistry.
    address internal constant IDENTITY_REGISTRY = 0x6666666666666666666666666666666666666666;

    // ------------------------------------------------------------------
    // v2.5 structural contracts (addresses PROPOSED here; the reference doc still marks them 🔶
    // undetermined — fixing them is part of the genesis design, same 0xNNNN...NNNN pattern).
    // ------------------------------------------------------------------

    /// @dev FoundationMembers — member ledger and share accounts of the foundation.
    address internal constant FOUNDATION_MEMBERS = 0x7777777777777777777777777777777777777777;

    /// @dev ValidatorSeatNFT — ERC-721 validator seats (not implemented yet).
    address internal constant VALIDATOR_SEAT_NFT = 0x8888888888888888888888888888888888888888;

    /// @dev GenesisClaimsVault — genesis claims released in 24 monthly instalments (not implemented yet).
    address internal constant GENESIS_CLAIMS_VAULT = 0x9999999999999999999999999999999999999999;

    /// @dev ValidatorLottery — validator-seat lottery against validator monopoly.
    address internal constant VALIDATOR_LOTTERY = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;

    // ------------------------------------------------------------------
    // Operational oracle addresses — unlike the six structural contract addresses above, these
    // are NOT immutable constants baked into every consumer forever: each contract still stores
    // its own oracle address in ordinary (mutable) state, initialized from here, and can later
    // rotate it via its own governance path (ValidatorsBoard for distributionOracle/verifier,
    // FoundationDAO for identityOracle). Centralizing the *initial* value here, in one file,
    // means updating an oracle before genesis only requires editing one line instead of hunting
    // through several contract files. All three are checksummed per EIP-55. (v2.5 has exactly
    // three oracles: verifier, distributionOracle, identityOracle.)
    // ------------------------------------------------------------------

    /// @dev Initial distributionOracle for BlockRewardDistributor.sol.
    address internal constant DISTRIBUTION_ORACLE = 0xbCBAc7d286eA11EC57fb4e0f5D16d960D6d202b6;

    /// @dev Initial verifier for ValidatorsRegistry.sol.
    address internal constant VERIFIER = 0x1A5E86f3333291B3332C0f9Eddb04269940566bc;

    /// @dev Initial identityOracle for IdentityRegistry.sol.
    address internal constant IDENTITY_ORACLE = 0xbE7e65512Eada6F4c6a9DEDDf2eFb75547A065e9;

    // (v2.5: the former PAYMENT_ORACLE is gone — SurenSale has no oracle; sales go through licensed exchanges.)
}
