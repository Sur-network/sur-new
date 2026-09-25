// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// WARNING: GENESIS SEEDING HELPER — TEMPORARY, NEVER DEPLOYED ON THE REAL CHAIN
//
// This is the TEMPORARY counterpart of: contracts/ValidatorsRegistry.sol
//
// ✅ FIXED (critical bug found in review): this file had fallen out of sync with the real
// contract in two ways that would have corrupted genesis storage if used as-is:
//   1. The ValidatorInfo struct here was missing the `isPaidEntrant` field added later to the
//      real contract.
//   2. The real contract now declares TWO scalar variables (`paidValidatorCount`, `verifier`)
//      BETWEEN `validators` and `activeValidators`/`activeIndex` — but this helper previously
//      declared `activeValidators`/`activeIndex` immediately after `validators`, with nothing
//      in between. Since a `mapping` or dynamic `array` type occupies exactly one storage slot
//      for its own "base" (the actual entries live at computed keccak256 offsets from that
//      base), every variable declared AFTER the mapping/array shifts by exactly one slot for
//      each scalar inserted before it. Without the two placeholder declarations below in the
//      SAME relative position, this helper's computed slot for `activeValidators.length` would
//      have been off by 2 relative to the real contract — meaning naively copying "helper slot
//      N → real contract slot N" would have written the founding validator *array* data into
//      what the real contract reads as `paidValidatorCount`/`verifier`, and vice versa.
//
// Purpose: the real ValidatorsRegistry.sol has no constructor (it is injected directly into the
// genesis alloc). But `validators` (a mapping to a struct), `activeValidators` (a dynamic
// array), and `activeIndex` (a mapping) cannot be populated with any contract-level Solidity
// syntax. This helper contract implements that exact seeding logic inside a real, NO-ARGUMENT
// constructor — the genesis timestamp and initial validator addresses are hardcoded directly
// below, not passed in as constructor arguments — so that running it once on a temporary local
// chain (Anvil/Hardhat) lets the EVM itself perform the keccak256 storage-slot math required for
// each mapping/array entry.
//
// How the genesis-building tool should use this file:
//   1. 🔶 FILL_IN: replace the placeholder genesis timestamp and every placeholder validator
//      address below with the real, final values before deploying this file anywhere. The
//      NUMBER OF ENTRIES in the array (currently 7, matching the real founding validator count)
//      must also be adjusted if that count ever changes — add or remove array entries as
//      needed, updating every place the array length is written (the type declaration and the
//      literal list itself).
//   2. Deploy this file (no constructor arguments) on a temporary local chain.
//   3. Extract its full final storage (via eth_getStorageAt for every touched slot, or a
//      state-dump tool).
//   4. Write that storage — together with the REAL ValidatorsRegistry.sol's compiled runtime
//      bytecode (NOT this file's bytecode) — under address 0x3333...3333 in genesis.json's
//      `alloc` section. ⚠️ The `paidValidatorCount` and `verifier` placeholder slots below will
//      extract as 0 / address(0) from THIS helper (their constructor never touches them) — do
//      NOT copy those two specific slots verbatim from the helper. `paidValidatorCount` should
//      genuinely be left at 0 (founders don't count toward the paid curve — see the real
//      contract's own doc comment), which needs no action at all (0 is Solidity's storage
//      default, so simply omitting that slot from the genesis alloc write already gives the
//      correct result). `verifier` must instead be set to its real, final operational-key
//      address directly in the genesis alloc at its own slot (immediately after
//      `paidValidatorCount`'s slot) — exactly like every other simple scalar (entryThresholdBase,
//      growthFactorPerValidator, membershipFeeBps, and the rest), none of which need this
//      helper either, per the real contract's own "GENESIS FILL-IN" comment.
//
// WARNING: the field order and types below must exactly match the real ValidatorsRegistry.sol,
// or the extracted storage slots will not line up with the final contract. Whenever the real
// ValidatorsRegistry.sol changes, this file must be manually kept in sync.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed {
    // --- Exact copy of the real ValidatorsRegistry.sol, up to the point where mappings/arrays start ---
    enum Status { None, Probation, Active, Demoted, Exiting }

    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;
        uint256 lastLivenessConfirmation;
        uint256 livenessConfirmationsInPeriod;
        uint256 totalLivenessChecksInPeriod; // ✅ ADDED — must match the real struct exactly
        // (same reasoning as isPaidEntrant below: struct size affects every subsequent
        // mapping-entry slot computation).
        uint256 lastCheckedAt; // ✅ ADDED — same reasoning
        uint256 pendingSlashEpoch; // ✅ ADDED — same reasoning
        uint256 demotedAt;
        bool isPaidEntrant; // ✅ ADDED — must match the real struct exactly, or the per-entry
        // struct size (and therefore every subsequent mapping-entry slot computation) would be
        // wrong even for the `validators` mapping itself, not just the scalars after it.
    }

    mapping(address => ValidatorInfo) public validators;

    // ✅ ADDED — placeholder ONLY, to reserve the correct relative slot position (see the
    // warning above). This helper's constructor deliberately never writes to it — it must stay
    // at its Solidity storage default (0), which is exactly the correct genesis value for
    // founding validators (see the real contract's own doc comment on this field).
    uint256 public paidValidatorCount;

    // ✅ ADDED — placeholder ONLY, same reasoning as paidValidatorCount above. The real
    // verifier address is set directly in the genesis alloc at this slot, NOT via this helper —
    // this declaration exists purely to occupy the correct slot position so that
    // `activeValidators`/`activeIndex` below land where the real contract expects them.
    address public verifier;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // ------------------------------------------------------------------
    // No-argument constructor — the genesis timestamp and initial validator set are hardcoded
    // directly below.
    // 🔶 FILL_IN: replace the placeholder timestamp (0) and every 0x000...000 address with the
    // real, final, agreed-upon founding validator set before this file is ever deployed
    // anywhere.
    // ------------------------------------------------------------------
    constructor() {
        uint256 genesisTimestamp = 0; // 🔶 FILL_IN — the real genesis timestamp of the live network

        address[7] memory initialValidators = [
            address(0), // Alireza Zojaji
            address(0), // Citex Corp. 1
            address(0), // Citex Corp. 2
            address(0), // Mahkameh Sharifzad
            address(0), // Mostafa Naghipoorfar
            address(0), // Sepehr Mohammadi
            address(0) // Siavash Tafazzoli
        ];

        for (uint256 i = 0; i < initialValidators.length; i++) {
            address v = initialValidators[i];
            require(v != address(0), "GenesisSeed: zero address - fill in real values first");
            require(validators[v].status == Status.None, "GenesisSeed: duplicate initial validator");

            validators[v] = ValidatorInfo({
                status: Status.Active,
                lockedStake: 0,
                periodStartedAt: genesisTimestamp,
                lastLivenessConfirmation: genesisTimestamp,
                livenessConfirmationsInPeriod: 0,
                totalLivenessChecksInPeriod: 0,
                lastCheckedAt: 0,
                pendingSlashEpoch: 0,
                demotedAt: 0,
                isPaidEntrant: false // founders are always free, never paid entrants
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
        }
        // paidValidatorCount and verifier are deliberately left untouched — see the doc
        // comments on their declarations above.
    }

    // Convenience view for manual inspection during testing — plays no role in storage
    // extraction itself.
    function getActiveValidators() external view returns (address[] memory) {
        return activeValidators;
    }
}
