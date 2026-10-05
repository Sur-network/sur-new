// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title IdentityRegistry
/// @notice Sur's sixth structural contract (fixed address `0x6666...6666`): the single source of truth for identity across
///         all network users, not only validators. It follows the SIP001/SIP002 model (identity verification for individual
///         and legal-entity users, and use of that verification by dApps) with two design choices:
///
///         1. **No notary office.** Verification is fully online: an eKYC check (face matching, liveness detection and
///            document authenticity, performed by a licensed provider) plus a signature of a challenge with the user's own
///            Sur key.
///
///         2. **No sensitive raw data on-chain.** No storage on a public blockchain is confidential (`eth_getStorageAt` is
///            always available), and for low-entropy data such as a 10-digit national ID even hashing gives no protection
///            without a secret salt. Raw data therefore never enters this contract: only verification flags (bool) and a
///            commitment (kept solely to prove non-tampering in a possible legal dispute, never used to answer a query) are
///            stored. The "matching" operation (SIP002 section 6) must be an off-chain API call, never an on-chain
///            transaction, because the transaction's own input (the value being compared) is visible in public calldata.
///            Details are in `sur-identity-registry-spec.md`.
///
///         A migrated address is burned: `hasIdentity` and `getVerificationStatus` report nothing for it, and neither the
///         owner nor the oracle can register or verify it again.
contract IdentityRegistry {
    // ------------------------------------------------------------------
    // Fixed cross-contract address (see SurAddresses.sol)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // Self-attested identity (SIP001's first layer)
    // ------------------------------------------------------------------
    enum PersonType { Individual, Legal }

    struct Identity {
        bool registered;
        PersonType personType;
        string name;
        bool phoneVerified;      // the actual phone number is never stored here — only this flag
        bool telegramVerified;   // the actual Telegram ID is never stored here — only this flag
        bool kycVerified;        // result of the full eKYC check (photo + national ID + face match)
        bytes32 kycCommitment;   // kept only to prove non-tampering in disputes, never for matching
        address migratedTo;      // non-zero: this address is burned and its identity was migrated to that address (spec section 3.4)
    }

    mapping(address => Identity) public identities;

    // ------------------------------------------------------------------
    // Operational key — controlled by the Foundation (not the validators' board), because
    // identity verification is the Foundation's responsibility, per SIP001's original design
    // ("the Sur Foundation is responsible for recording verified information about individuals
    // and legal entities").
    // ------------------------------------------------------------------

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

    modifier notMigrated(address who) {
        require(identities[who].migratedTo == address(0), "IdentityRegistry: address was migrated (burned)");
        _;
    }

    modifier onlyIdentityOracle() {
        require(msg.sender == identityOracle, "IdentityRegistry: caller is not the identity oracle");
        _;
    }

    // ------------------------------------------------------------------
    // GENESIS FILL-IN: this contract has no constructor because it is injected into the genesis `alloc`. The genesis tool
    // simulates its deployment on a temporary local chain and copies the resulting storage into the final genesis file; the
    // initial value below is a documentation and tooling marker.
    // ------------------------------------------------------------------

    /// @dev Initial identityOracle address, read from SurAddresses.sol (the single source for all oracle addresses).
    address public identityOracle = SurAddresses.IDENTITY_ORACLE;

    // ------------------------------------------------------------------
    // Self-attestation — any address, not just validators
    // ------------------------------------------------------------------

    /// @notice Registers/updates self-attested identity (name and person type only). Callable
    ///         by any address, at any time; calling it again never resets any verification flag.
    function registerIdentity(PersonType personType, string calldata name) external {
        require(bytes(name).length > 0, "IdentityRegistry: empty name");

        Identity storage id_ = identities[msg.sender];
        require(id_.migratedTo == address(0), "IdentityRegistry: address was migrated (burned)");
        id_.registered = true;
        id_.personType = personType;
        id_.name = name;

        emit IdentityRegistered(msg.sender, personType, name);
    }

    /// @notice Tier-zero check (open access, no dApp registration required), equivalent to SIP002 section 6-1: "has this
    ///         address registered an identity at all?", revealing nothing else. A migrated address (`migratedTo != 0`)
    ///         returns false.
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
        if (id_.migratedTo != address(0)) return (false, false, false, false);
        return (id_.registered, id_.phoneVerified, id_.telegramVerified, id_.kycVerified);
    }

    // ------------------------------------------------------------------
    // Verification — identityOracle only (off-chain Identity Service; see
    // sur-identity-registry-spec.md for details)
    // ------------------------------------------------------------------

    function setPhoneVerified(address who, bool verified) external onlyIdentityOracle notMigrated(who) {
        identities[who].phoneVerified = verified;
        emit PhoneVerificationUpdated(who, verified);
    }

    function setTelegramVerified(address who, bool verified) external onlyIdentityOracle notMigrated(who) {
        identities[who].telegramVerified = verified;
        emit TelegramVerificationUpdated(who, verified);
    }

    /// @notice Records the result of a full eKYC check (personal photo + national ID card +
    ///         birth-certificate-level details + face match). `commitment` is a salted hash of
    ///         the full verified data set — kept **only** to prove non-tampering in a possible
    ///         future legal dispute; no on-chain function ever uses it to answer a "matching"
    ///         query (that operation always goes through the off-chain Identity Service API —
    ///         see section 5 of `sur-identity-registry-spec.md`).
    function setKycVerified(address who, bool verified, bytes32 commitment) external onlyIdentityOracle notMigrated(who) {
        Identity storage id_ = identities[who];
        id_.kycVerified = verified;
        id_.kycCommitment = verified ? commitment : bytes32(0);
        emit KycVerificationUpdated(who, verified, id_.kycCommitment);
    }

    // ------------------------------------------------------------------
    // Identity recovery: the online replacement for SIP001 sections 7/8 (lost key / burned address). A call must always
    // follow an independent off-chain verification (spec section 3.4): for phone/Telegram-only users, repeating the OTP
    // flow is enough; for KYC-verified users, the eKYC provider must confirm that the new selfie matches the previously
    // stored biometric data for the same national ID. This is a recovery, not a fresh registration.
    // ------------------------------------------------------------------

    /// @notice Migrates the full identity status from an old (lost or compromised) address to a new one. The old address
    ///         is burned: `hasIdentity` and `getVerificationStatus` report nothing for it and it can no longer be registered
    ///         or verified, but its record, and its liability for past actions, is not erased. The new address must be a
    ///         different address that has not itself been migrated.
    function migrateIdentity(address oldAddr, address newAddr) external onlyIdentityOracle {
        require(newAddr != address(0), "IdentityRegistry: zero new address");
        require(newAddr != oldAddr, "IdentityRegistry: new address equals old address");
        require(identities[newAddr].migratedTo == address(0), "IdentityRegistry: new address was itself migrated");
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
