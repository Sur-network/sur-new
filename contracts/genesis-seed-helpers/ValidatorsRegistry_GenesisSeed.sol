// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// GENESIS SEEDING HELPER: temporary, never deployed on the real chain.
//
// Counterpart of contracts/ValidatorsRegistry.sol. The real contract has no constructor (it is injected into the genesis
// `alloc`), but `validators` (a mapping to a struct), `activeValidators` (a dynamic array) and `activeIndex` (a mapping)
// cannot be populated with contract-level Solidity syntax. This helper runs that seeding logic in a no-argument
// constructor (the genesis timestamp and the founding addresses are written directly below), so that running it once on a
// temporary local chain (Anvil or Hardhat) lets the EVM perform the keccak256 storage-slot arithmetic for each entry.
//
// Storage-layout rule: the variable order and types below must match the real ValidatorsRegistry.sol exactly. A mapping or
// dynamic array occupies one slot for its base, so every variable declared after it depends on the number of slots before
// it; the placeholders and gaps below reserve the real contract's slots. Whenever the real contract changes, this file
// must be updated by hand (check with static-checks/check_genesis_helper_layout.js).
//
// How the genesis tool uses this file:
//   1. FILL_IN: replace the placeholder genesis timestamp and every placeholder validator address with the final values.
//      If the number of founders changes, change the array length (type and literal list).
//   2. Deploy this file (no constructor arguments) on a temporary local chain.
//   3. Extract its final storage (eth_getStorageAt for every touched slot, or a state-dump tool).
//   4. Write that storage, together with the REAL ValidatorsRegistry.sol runtime bytecode (not this file's bytecode),
//      under address 0x3333...3333 in genesis.json `alloc`. The placeholder slots (`paidValidatorCount`, `verifier`, the
//      gaps) extract as zero from this helper: do not copy them. `paidValidatorCount` stays 0 (omit the slot).
//      `verifier` and every other simple scalar (entryThresholdBase, growthFactorPerValidator, membershipFeeBps, the
//      security parameters, the genesis timestamp) are written directly into `alloc` at their own slots, as described in
//      the real contract's GENESIS FILL-IN notes.
// ============================================================================
contract ValidatorsRegistry_GenesisSeed {
    enum Status { None, Probation, Active, Demoted, Exiting }

    // Field count and order must match the real struct exactly, or every mapping-entry slot computation breaks.
    struct ValidatorInfo {
        Status status;
        uint256 lockedStake;
        uint256 periodStartedAt;
        uint256 pendingSlashEpoch;
        uint256 demotedAt;
        bool isPaidEntrant;
    }

    mapping(address => ValidatorInfo) public validators;

    // Placeholder: reserves the real contract's slot. Never written here; founders do not count toward the paid curve.
    uint256 public paidValidatorCount;

    // Placeholder: reserves the real contract's slot. The real verifier address is written directly into `alloc`.
    address public verifier;

    address[] private activeValidators;
    mapping(address => uint256) private activeIndex;

    // Slots 5-19 of the real contract: the economic and timing parameters and the `massFailureChecked` mapping. Their values
    // are set by the genesis overlay, not by this constructor.
    uint256[15] private __gap1;

    // Written by the constructor: every founder is brought in as Active with everActivated = true, so that the very first
    // distributeRewards() call can pay a founder.
    mapping(address => bool) public everActivated;

    // Slots 21-35 of the real contract (the fields declared after everActivated, up to paramProposalCount): placeholder only.
    // statusNonce (slot 36) stays 0 at genesis; every founder gets the checkpoint {nonce: 0, active: true} in
    // activeCheckpoints (slot 37), so wasActiveAt(founder, n) is true for every proposal created before the founder's first
    // status change.
    uint256[15] private __gap2;
    struct ActiveCheckpoint {
        uint64 nonce;
        bool active;
    }
    uint256 public statusNonce;
    mapping(address => ActiveCheckpoint[]) private activeCheckpoints;

    // Slots 38 and 39 of the real contract: the order of first activation. Founders are numbered 1..7 in the order listed in
    // the constructor; the board uses it to break ties between candidates with equal votes (the older validator wins).
    uint256 public activationCount;
    mapping(address => uint256) public activationSeq;

    // ------------------------------------------------------------------
    // No-argument constructor — the genesis timestamp and initial validator set are hardcoded
    // directly below.
    // FILL_IN: replace the placeholder timestamp (0) and every 0x000...000 address with the real, final founding validator
    // set before this file is deployed anywhere.
    // ------------------------------------------------------------------
    constructor() {
        uint256 genesisTimestamp = 0; // FILL_IN: the real genesis timestamp of the live network

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
                pendingSlashEpoch: 0,
                demotedAt: 0,
                isPaidEntrant: false // founders are always free, never paid entrants
            });
            activeIndex[v] = activeValidators.length + 1;
            activeValidators.push(v);
            everActivated[v] = true; // founders must be payable from the first distribution; see everActivated in the real contract
            activationSeq[v] = ++activationCount;
            activeCheckpoints[v].push(ActiveCheckpoint({nonce: 0, active: true})); // L04
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
