// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title IdentityRegistry
/// @notice Sur's sixth structural contract (fixed address `0x6666...6666`) — the single source
///         of truth for identity across **all network users**, not just validators. Inspired by
///         the project's earlier standards SIP001/SIP002 ("Identity verification method for
///         individual and legal-entity users" and "Use of identity verification services by
///         dApps"), with two deliberate changes from the original:
///
///         1. **No notary office.** SIP001 required an in-person notarized signature. Here it is
///            replaced with a fully online process: eKYC verification (face matching + liveness
///            detection + document authenticity check, performed by a licensed provider) +
///            digitally signing a challenge with the user's own Sur key (this second step is
///            exactly SIP001's original idea, unchanged).
///
///         2. **No sensitive raw data on-chain.** SIP001 proposed storing national ID / name /
///            birth-certificate data in a "confidential smart contract." This is not technically
///            possible: no storage on a public blockchain is ever truly confidential
///            (`eth_getStorageAt` is always available), and for low-entropy data such as a
///            10-digit national ID, even hashing provides no real protection without a secret
///            salt. Solution: raw data never enters this contract; only a verification status
///            (bool) and a commitment (kept solely to prove non-tampering in a possible future
///            legal dispute, never used to answer a query) live on-chain. The "matching"
///            operation itself (SIP002 section 6) must be an off-chain API call, never an
///            on-chain transaction — because even if the contract never reveals the answer, the
///            **transaction's own input parameter** (the value being compared against) is
///            always visible in public calldata. Full details in
///            `sur-identity-registry-spec.md`.
contract IdentityRegistry {
    // ------------------------------------------------------------------
    // Fixed cross-contract address (see SurAddresses.sol)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // Self-attested identity (SIP001's first layer) — unchanged from our earlier design, just
    // relocated out of ValidatorsRegistry.
    // ------------------------------------------------------------------
    enum PersonType { Individual, Legal }

    struct Identity {
        bool registered;
        PersonType personType;
        string name;
        bool phoneVerified;      // the actual phone number is never stored here — only this flag
        bool telegramVerified;   // the actual Telegram ID is never stored here — only this flag
        bool kycVerified;        // new — result of full eKYC (photo + national ID + face match)
        bytes32 kycCommitment;   // new — kept only to prove non-tampering in disputes, never for matching
        address migratedTo;      // new — non-zero means this address is "burned" and its identity has been migrated to a new address (see spec section 3.4; equivalent to SIP001 sections 7/8)
    }

    mapping(address => Identity) public identities;

    // ------------------------------------------------------------------
    // Operational key — controlled by the Foundation (not the validators' board), because
    // identity verification is the Foundation's responsibility, per SIP001's original design
    // ("the Sur Foundation is responsible for recording verified information about individuals
    // and legal entities").
    // ------------------------------------------------------------------
    address public identityOracle;

    event IdentityRegistered(address indexed who, PersonType personType, string name);
    event PhoneVerificationUpdated(address indexed who, bool verified);
    event TelegramVerificationUpdated(address indexed who, bool verified);
    event KycVerificationUpdated(address indexed who, bool verified, bytes32 commitment);
    event IdentityMigrated(address indexed oldAddress, address indexed newAddress);
    event IdentityOracleUpdated(address indexed oldOracle, address indexed newOracle);

    modifier onlyFoundation() {
        require(msg.sender == FOUNDATION, "IdentityRegistry: caller is not the Foundation");
        _;
    }

    modifier onlyIdentityOracle() {
        require(msg.sender == identityOracle, "IdentityRegistry: caller is not the identity oracle");
        _;
    }

    constructor(address _identityOracle) {
        require(_identityOracle != address(0), "IdentityRegistry: zero oracle address");
        identityOracle = _identityOracle;
    }

    // ------------------------------------------------------------------
    // Self-attestation — any address, not just validators
    // ------------------------------------------------------------------

    /// @notice Registers/updates self-attested identity (name and person type only). Callable
    ///         by any address, at any time; calling it again never resets any verification flag.
    function registerIdentity(PersonType personType, string calldata name) external {
        require(bytes(name).length > 0, "IdentityRegistry: empty name");

        Identity storage id_ = identities[msg.sender];
        id_.registered = true;
        id_.personType = personType;
        id_.name = name;

        emit IdentityRegistered(msg.sender, personType, name);
    }

    /// @notice Tier-zero check (open access, no dApp registration required) — exactly equivalent
    ///         to SIP002 section 6-1: "has this address registered an identity at all?", without
    ///         revealing any other data. Migrated addresses (`migratedTo != 0`) no longer return
    ///         `true` — see spec section 3.4.
    function hasIdentity(address who) external view returns (bool) {
        Identity storage id_ = identities[who];
        return id_.registered && id_.migratedTo == address(0);
    }

    /// @notice Public verification-status check — everything here is boolean, no raw data, so
    ///         freely disclosing it is not a problem (exactly like SIP002 section 6-1).
    function getVerificationStatus(address who)
        external
        view
        returns (bool registered, bool phoneVerified, bool telegramVerified, bool kycVerified)
    {
        Identity storage id_ = identities[who];
        return (id_.registered, id_.phoneVerified, id_.telegramVerified, id_.kycVerified);
    }

    // ------------------------------------------------------------------
    // Verification — identityOracle only (off-chain Identity Service; see
    // sur-identity-registry-spec.md for details)
    // ------------------------------------------------------------------

    function setPhoneVerified(address who, bool verified) external onlyIdentityOracle {
        identities[who].phoneVerified = verified;
        emit PhoneVerificationUpdated(who, verified);
    }

    function setTelegramVerified(address who, bool verified) external onlyIdentityOracle {
        identities[who].telegramVerified = verified;
        emit TelegramVerificationUpdated(who, verified);
    }

    /// @notice Records the result of a full eKYC check (personal photo + national ID card +
    ///         birth-certificate-level details + face match). `commitment` is a salted hash of
    ///         the full verified data set — kept **only** to prove non-tampering in a possible
    ///         future legal dispute; no on-chain function ever uses it to answer a "matching"
    ///         query (that operation always goes through the off-chain Identity Service API —
    ///         see section 5 of `sur-identity-registry-spec.md`).
    function setKycVerified(address who, bool verified, bytes32 commitment) external onlyIdentityOracle {
        Identity storage id_ = identities[who];
        id_.kycVerified = verified;
        id_.kycCommitment = verified ? commitment : bytes32(0);
        emit KycVerificationUpdated(who, verified, id_.kycCommitment);
    }

    // ------------------------------------------------------------------
    // Identity recovery — the online replacement for SIP001 sections 7/8 (lost key / burned
    // address). Calling this function must always follow an independent off-chain verification
    // process (see spec section 3.4): for phone/Telegram-only users, repeating the OTP flow is
    // enough; for KYC-verified users, the eKYC provider must confirm the new selfie matches the
    // previously stored biometric data for the same national ID — this is a recovery, not a
    // fresh registration.
    // ------------------------------------------------------------------

    /// @notice Migrates the full identity status from an old (lost/compromised) address to a new
    ///         one. The old address is permanently "burned" (`hasIdentity` no longer returns true
    ///         for it), but its record — and its liability for past actions — is not erased, it
    ///         simply can no longer be used.
    function migrateIdentity(address oldAddr, address newAddr) external onlyIdentityOracle {
        require(newAddr != address(0), "IdentityRegistry: zero new address");
        Identity storage oldId = identities[oldAddr];
        require(oldId.registered, "IdentityRegistry: old address has no identity");
        require(oldId.migratedTo == address(0), "IdentityRegistry: old address already migrated");

        Identity storage newId = identities[newAddr];
        newId.registered = true;
        newId.personType = oldId.personType;
        newId.name = oldId.name;
        newId.phoneVerified = oldId.phoneVerified;
        newId.telegramVerified = oldId.telegramVerified;
        newId.kycVerified = oldId.kycVerified;
        newId.kycCommitment = oldId.kycCommitment;

        oldId.migratedTo = newAddr;

        emit IdentityMigrated(oldAddr, newAddr);
    }

    // ------------------------------------------------------------------
    // Key rotation — Foundation only (not the validators' board)
    // ------------------------------------------------------------------
    function setIdentityOracle(address newOracle) external onlyFoundation {
        require(newOracle != address(0), "IdentityRegistry: zero oracle address");
        emit IdentityOracleUpdated(identityOracle, newOracle);
        identityOracle = newOracle;
    }
}
