// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface ISurDocSignIdentity {
    function hasIdentity(address who) external view returns (bool);
    function isFullyVerified(address who) external view returns (bool);
}

interface ISurDocSignFoundation {
    function ceo() external view returns (address);
    function chair() external view returns (address);
    function treasurer() external view returns (address);
}

/// @title SurDocSign
/// @notice On-chain registry for document timestamps and signatures. Only a hash goes on-chain, never the document.
///
///         THREE LEVELS (all in one contract):
///           1. Timestamp: `register(docHash, ...)`. Proves only that the hash existed at block time, not authorship.
///           2. Signature: `sign(...)` with `envelopeId = 0`. Any address signs any hash. The same document can carry ANY
///              NUMBER of independent signatures: every distinct signer adds one (`signerCount`, `hasSigned`, one event each).
///           3. Multi-party envelope: `createEnvelope(...)` fixes a sorted list of required signers (and optionally the three
///              Foundation roles); `sign(...)` with that `envelopeId` fills one slot; when all slots are filled the envelope is complete.
///         One document can be signed outside any envelope AND inside any number of envelopes.
///
///         ONE SIGNATURE per (docHash, envelopeId, signer). Signing twice in the same context reverts, which is also the replay guard.
///
///         IDENTITY LEVEL is read from IdentityRegistry at signing time and stored with the signature record: 0 = any address,
///         1 = `hasIdentity`, 2 = `isFullyVerified`. An envelope can demand a minimum level. A later identity migration does not change
///         records already written; a migrated (burned) address has level 0 afterwards.
///
///         FOUNDATION ROLES (ceo / chair / treasurer of FoundationDAO) are the only legal-entity signers. An envelope with
///         `foundationCountersign` has three extra slots, one per role; the signer must hold that role at signing time. One address fills
///         at most one slot of an envelope, so an envelope whose role holders collide (one address with two roles) cannot complete until the
///         roles change; the creator can cancel it.
///
///         TWO WAYS TO SUBMIT: directly (msg.sender is the actor, pays gas) or with an EIP-712 signature (`...WithSig`; anyone submits,
///         the actor is recovered from the signature). The relayer service uses the second form and cannot forge anything.
///
///         NOT A GENESIS CONTRACT: ordinary deployment after genesis, no owner, no upgrade, no parameter that can be changed. A bug is fixed
///         by deploying a new version at a new address; readers keep reading the old one. Externally owned accounts only (ecrecover);
///         smart-contract wallets (ERC-1271) are not supported. Holds no funds: not payable, no receive.
contract SurDocSign {
    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------
    address public constant IDENTITY = SurAddresses.IDENTITY_REGISTRY;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @dev `role` values: 0 = ordinary party; 1..3 = Foundation roles.
    uint8 public constant ROLE_PARTY = 0;
    uint8 public constant ROLE_CEO = 1;
    uint8 public constant ROLE_CHAIR = 2;
    uint8 public constant ROLE_TREASURER = 3;

    /// @dev Hash algorithm ids. 0 = SHA-256 over the raw file bytes; 1 = keccak256 over UTF-8 text. The id is part of what is signed.
    uint8 public constant ALG_SHA256 = 0;
    uint8 public constant ALG_KECCAK256 = 1;

    /// @dev Total slots of one envelope (named signers + Foundation roles). 🔶 proposed value.
    uint256 public constant MAX_SLOTS = 20;
    /// @dev Allowed envelope deadline window, relative to creation. 🔶 proposed values.
    uint64 public constant MIN_ENVELOPE_SECONDS = 1 hours;
    uint64 public constant MAX_ENVELOPE_SECONDS = 365 days;

    uint8 public constant STATE_NONE = 0;
    uint8 public constant STATE_ACTIVE = 1;
    uint8 public constant STATE_COMPLETE = 2;
    uint8 public constant STATE_CANCELLED = 3;
    uint8 public constant STATE_EXPIRED = 4;

    // EIP-712
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant SIGN_TYPEHASH = keccak256(
        "DocumentSignature(bytes32 docHash,uint8 alg,bytes32 metaHash,bytes32 envelopeId,uint8 role,uint64 deadline)"
    );
    bytes32 public constant CREATE_TYPEHASH = keccak256(
        "EnvelopeCreate(bytes32 docHash,uint8 alg,bytes32 metaHash,bytes32 signersHash,bool foundationCountersign,uint8 minLevel,uint64 deadline,bytes32 salt,uint64 sigDeadline)"
    );
    bytes32 public constant CANCEL_TYPEHASH = keccak256("EnvelopeCancel(bytes32 envelopeId,uint64 sigDeadline)");

    /// @dev secp256k1 curve order / 2: signatures with a larger `s` are rejected (malleability).
    uint256 private constant HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    struct Doc {
        uint64 firstSeen;        // block time of the first registration or signature (0 = never seen)
        address firstRegistrant; // who touched the hash first (not an authorship claim)
        uint32 signerCount;      // DISTINCT addresses that signed this hash anywhere (standalone or in any envelope)
    }

    struct SigRecord {
        uint64 signedAt; // 0 = no signature
        uint8 level;     // identity level at signing time
        uint8 role;      // 0 party; 1..3 Foundation role the signer filled
    }

    struct Envelope {
        bytes32 docHash;
        bytes32 metaHash;
        address creator;
        uint64 deadline;
        uint8 alg;
        uint8 minLevel;
        uint8 required;  // total slots
        uint8 filled;    // slots filled so far
        bool foundation; // true: three Foundation role slots are part of `required`
        bool cancelled;
        uint64 createdAt;
        uint64 completedAt;
    }

    mapping(bytes32 => Doc) private _docs;
    /// @notice First time `signer` signed `docHash` in any context (0 = never). `hasSigned` is `> 0`.
    mapping(bytes32 => mapping(address => uint64)) public firstSignedAt;
    mapping(bytes32 => mapping(bytes32 => mapping(address => SigRecord))) private _sigs; // docHash => envelopeId => signer
    mapping(bytes32 => Envelope) private _envelopes;
    mapping(bytes32 => mapping(address => bool)) public isNamedSigner; // envelopeId => address => named in the list
    mapping(bytes32 => uint8) public roleFilledMask;                   // envelopeId => bit (role - 1)

    // ------------------------------------------------------------------
    // Parameters (structs keep the stack small)
    // ------------------------------------------------------------------
    struct EnvelopeParams {
        bytes32 docHash;
        uint8 alg;
        bytes32 metaHash;
        address[] signers;          // strictly ascending, non-zero; may be empty only with foundationCountersign
        bool foundationCountersign;
        uint8 minLevel;             // 0..2
        uint64 deadline;            // absolute time by which all slots must be filled
        bytes32 salt;               // makes the envelope id unique for otherwise identical parameters
    }

    struct SignParams {
        bytes32 docHash;
        uint8 alg;
        bytes32 metaHash;
        bytes32 envelopeId;         // 0 = signature outside any envelope
        uint8 role;                 // 0 party; 1..3 Foundation role
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event DocumentRegistered(bytes32 indexed docHash, address indexed registrant, uint8 alg, bytes32 metaHash, bool first);
    event EnvelopeCreated(
        bytes32 indexed envelopeId,
        address indexed creator,
        bytes32 indexed docHash,
        uint8 alg,
        bytes32 metaHash,
        address[] signers,
        bool foundationCountersign,
        uint8 minLevel,
        uint64 deadline
    );
    event DocumentSigned(
        bytes32 indexed docHash,
        bytes32 indexed envelopeId,
        address indexed signer,
        uint8 role,
        uint8 level,
        uint64 time,
        address submitter
    );
    event EnvelopeCompleted(bytes32 indexed envelopeId, bytes32 indexed docHash, uint64 time);
    event EnvelopeCancelled(bytes32 indexed envelopeId, address indexed creator);

    constructor() {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    // ------------------------------------------------------------------
    // 1. Timestamp
    // ------------------------------------------------------------------

    /// @notice Timestamp a hash. No identity is claimed; anyone (including the relayer) may call it. The first call stores `firstSeen` and
    ///         `firstRegistrant`; later calls only emit an event.
    function register(bytes32 docHash, uint8 alg, bytes32 metaHash) external {
        require(docHash != bytes32(0), "SurDocSign: empty hash");
        require(alg <= ALG_KECCAK256, "SurDocSign: unknown algorithm");
        bool first = _touch(docHash, msg.sender);
        emit DocumentRegistered(docHash, msg.sender, alg, metaHash, first);
    }

    // ------------------------------------------------------------------
    // 2 and 3. Signatures
    // ------------------------------------------------------------------

    /// @notice Sign as `msg.sender`. `p.envelopeId == 0`: a signature outside any envelope (any number of different signers may do this on
    ///         the same hash). Otherwise fills one slot of that envelope.
    function sign(SignParams calldata p) external {
        _sign(msg.sender, p);
    }

    /// @notice Sign on behalf of `signer` using their EIP-712 signature (`DocumentSignature`); anyone may submit.
    function signWithSig(SignParams calldata p, address signer, uint64 sigDeadline, bytes calldata sig) external {
        require(block.timestamp <= sigDeadline, "SurDocSign: signature expired");
        bytes32 structHash = keccak256(
            abi.encode(SIGN_TYPEHASH, p.docHash, p.alg, p.metaHash, p.envelopeId, p.role, sigDeadline)
        );
        require(_recover(_digest(structHash), sig) == signer, "SurDocSign: bad signature");
        _sign(signer, p);
    }

    function _sign(address signer, SignParams calldata p) private {
        require(signer != address(0), "SurDocSign: zero signer");
        require(p.docHash != bytes32(0), "SurDocSign: empty hash");
        require(p.alg <= ALG_KECCAK256, "SurDocSign: unknown algorithm");
        require(p.role <= ROLE_TREASURER, "SurDocSign: unknown role");
        require(_sigs[p.docHash][p.envelopeId][signer].signedAt == 0, "SurDocSign: already signed");

        uint8 level = _level(signer);
        uint64 nowT = uint64(block.timestamp);
        Envelope storage e = _envelopes[p.envelopeId];

        if (p.envelopeId == bytes32(0)) {
            require(p.role == ROLE_PARTY, "SurDocSign: role needs an envelope");
        } else {
            require(e.createdAt != 0, "SurDocSign: unknown envelope");
            require(e.docHash == p.docHash && e.alg == p.alg && e.metaHash == p.metaHash, "SurDocSign: envelope mismatch");
            require(!e.cancelled, "SurDocSign: envelope cancelled");
            require(e.completedAt == 0, "SurDocSign: envelope complete");
            require(nowT <= e.deadline, "SurDocSign: envelope expired");
            require(level >= e.minLevel, "SurDocSign: identity level too low");
            if (p.role == ROLE_PARTY) {
                require(isNamedSigner[p.envelopeId][signer], "SurDocSign: not a listed signer");
            } else {
                require(e.foundation, "SurDocSign: envelope has no Foundation slots");
                uint8 bit = uint8(1) << (p.role - 1);
                require(roleFilledMask[p.envelopeId] & bit == 0, "SurDocSign: role already signed");
                require(_roleHolder(p.role) == signer, "SurDocSign: not the role holder");
                roleFilledMask[p.envelopeId] |= bit;
            }
        }

        _touch(p.docHash, signer);
        _sigs[p.docHash][p.envelopeId][signer] = SigRecord({signedAt: nowT, level: level, role: p.role});
        if (firstSignedAt[p.docHash][signer] == 0) {
            firstSignedAt[p.docHash][signer] = nowT;
            _docs[p.docHash].signerCount += 1;
        }
        emit DocumentSigned(p.docHash, p.envelopeId, signer, p.role, level, nowT, msg.sender);

        if (p.envelopeId != bytes32(0)) {
            e.filled += 1;
            if (e.filled == e.required) {
                e.completedAt = nowT;
                emit EnvelopeCompleted(p.envelopeId, p.docHash, nowT);
            }
        }
    }

    // ------------------------------------------------------------------
    // Envelopes
    // ------------------------------------------------------------------

    /// @notice Create an envelope as `msg.sender`. Returns the envelope id (also computable beforehand with `previewEnvelopeId`).
    function createEnvelope(EnvelopeParams calldata p) external returns (bytes32) {
        return _create(msg.sender, p);
    }

    /// @notice Create an envelope on behalf of `creator` using their EIP-712 signature (`EnvelopeCreate`).
    function createEnvelopeWithSig(EnvelopeParams calldata p, address creator, uint64 sigDeadline, bytes calldata sig)
        external
        returns (bytes32)
    {
        require(block.timestamp <= sigDeadline, "SurDocSign: signature expired");
        bytes32 signersHash = keccak256(abi.encodePacked(p.signers));
        // two chunks of static 32-byte words: identical to one abi.encode, keeps the stack small
        bytes32 structHash = keccak256(
            bytes.concat(
                abi.encode(CREATE_TYPEHASH, p.docHash, p.alg, p.metaHash, signersHash),
                abi.encode(p.foundationCountersign, p.minLevel, p.deadline, p.salt, sigDeadline)
            )
        );
        require(_recover(_digest(structHash), sig) == creator, "SurDocSign: bad signature");
        return _create(creator, p);
    }

    function _create(address creator, EnvelopeParams calldata p) private returns (bytes32 id) {
        require(creator != address(0), "SurDocSign: zero creator");
        require(p.docHash != bytes32(0), "SurDocSign: empty hash");
        require(p.alg <= ALG_KECCAK256, "SurDocSign: unknown algorithm");
        require(p.minLevel <= 2, "SurDocSign: bad level");
        uint256 slots = p.signers.length + (p.foundationCountersign ? 3 : 0);
        require(slots >= 1, "SurDocSign: no signers");
        require(slots <= MAX_SLOTS, "SurDocSign: too many signers");
        require(
            p.deadline >= block.timestamp + MIN_ENVELOPE_SECONDS && p.deadline <= block.timestamp + MAX_ENVELOPE_SECONDS,
            "SurDocSign: deadline out of range"
        );

        id = _envelopeId(creator, p);
        require(_envelopes[id].createdAt == 0, "SurDocSign: envelope exists");

        _storeSigners(id, p);

        _envelopes[id] = Envelope({
            docHash: p.docHash,
            metaHash: p.metaHash,
            creator: creator,
            deadline: p.deadline,
            alg: p.alg,
            minLevel: p.minLevel,
            required: uint8(slots),
            filled: 0,
            foundation: p.foundationCountersign,
            cancelled: false,
            createdAt: uint64(block.timestamp),
            completedAt: 0
        });
        _touch(p.docHash, creator);
        _emitCreated(id, creator, p);
    }

    /// @dev Validates and stores the named signers of a new envelope (kept apart from `_create` to limit the stack).
    function _storeSigners(bytes32 id, EnvelopeParams calldata p) private {
        address prev = address(0);
        address ceo_;
        address chair_;
        address treasurer_;
        if (p.foundationCountersign) {
            ceo_ = _roleHolder(ROLE_CEO);
            chair_ = _roleHolder(ROLE_CHAIR);
            treasurer_ = _roleHolder(ROLE_TREASURER);
        }
        for (uint256 i = 0; i < p.signers.length; i++) {
            address s = p.signers[i];
            require(s > prev, "SurDocSign: signers must be ascending and non-zero");
            prev = s;
            // a named signer who also holds a role could fill only one of the two slots, so the envelope could never complete
            require(
                !p.foundationCountersign || (s != ceo_ && s != chair_ && s != treasurer_),
                "SurDocSign: signer holds a Foundation role"
            );
            isNamedSigner[id][s] = true;
        }
    }

    function _emitCreated(bytes32 id, address creator, EnvelopeParams calldata p) private {
        emit EnvelopeCreated(id, creator, p.docHash, p.alg, p.metaHash, p.signers, p.foundationCountersign, p.minLevel, p.deadline);
    }

    /// @notice Cancel an incomplete envelope as its creator. Signatures already written stay on record.
    function cancelEnvelope(bytes32 envelopeId) external {
        _cancel(msg.sender, envelopeId);
    }

    function cancelEnvelopeWithSig(bytes32 envelopeId, address creator, uint64 sigDeadline, bytes calldata sig) external {
        require(block.timestamp <= sigDeadline, "SurDocSign: signature expired");
        bytes32 structHash = keccak256(abi.encode(CANCEL_TYPEHASH, envelopeId, sigDeadline));
        require(_recover(_digest(structHash), sig) == creator, "SurDocSign: bad signature");
        _cancel(creator, envelopeId);
    }

    function _cancel(address creator, bytes32 envelopeId) private {
        Envelope storage e = _envelopes[envelopeId];
        require(e.createdAt != 0, "SurDocSign: unknown envelope");
        require(e.creator == creator, "SurDocSign: not the creator");
        require(!e.cancelled, "SurDocSign: already cancelled");
        require(e.completedAt == 0, "SurDocSign: envelope complete");
        e.cancelled = true;
        emit EnvelopeCancelled(envelopeId, creator);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function docInfo(bytes32 docHash) external view returns (uint64 firstSeen, address firstRegistrant, uint32 signers) {
        Doc storage d = _docs[docHash];
        return (d.firstSeen, d.firstRegistrant, d.signerCount);
    }

    /// @notice Number of DISTINCT addresses that signed `docHash` (outside or inside any envelope).
    function signerCount(bytes32 docHash) external view returns (uint32) {
        return _docs[docHash].signerCount;
    }

    /// @notice Whether `signer` signed `docHash` in any context.
    function hasSigned(bytes32 docHash, address signer) external view returns (bool) {
        return firstSignedAt[docHash][signer] != 0;
    }

    /// @notice One signature record. `envelopeId = 0` for a signature outside any envelope. `signedAt == 0` means none.
    function signatureOf(bytes32 docHash, bytes32 envelopeId, address signer)
        external
        view
        returns (uint64 signedAt, uint8 level, uint8 role)
    {
        SigRecord storage r = _sigs[docHash][envelopeId][signer];
        return (r.signedAt, r.level, r.role);
    }

    function envelopeInfo(bytes32 envelopeId) external view returns (Envelope memory) {
        return _envelopes[envelopeId];
    }

    function isComplete(bytes32 envelopeId) external view returns (bool) {
        return _envelopes[envelopeId].completedAt != 0;
    }

    /// @notice 0 none, 1 active, 2 complete, 3 cancelled, 4 expired (deadline passed, not complete, not cancelled).
    function envelopeState(bytes32 envelopeId) public view returns (uint8) {
        Envelope storage e = _envelopes[envelopeId];
        if (e.createdAt == 0) return STATE_NONE;
        if (e.completedAt != 0) return STATE_COMPLETE;
        if (e.cancelled) return STATE_CANCELLED;
        if (block.timestamp > e.deadline) return STATE_EXPIRED;
        return STATE_ACTIVE;
    }

    /// @notice Whether the Foundation slot of `role` (1..3) is filled in this envelope.
    function roleFilled(bytes32 envelopeId, uint8 role) external view returns (bool) {
        require(role >= ROLE_CEO && role <= ROLE_TREASURER, "SurDocSign: unknown role");
        return roleFilledMask[envelopeId] & (uint8(1) << (role - 1)) != 0;
    }

    /// @notice The id `createEnvelope` / `createEnvelopeWithSig` will give these parameters when `creator` creates them on this chain.
    function previewEnvelopeId(address creator, EnvelopeParams calldata p) external view returns (bytes32) {
        return _envelopeId(creator, p);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _CACHED_CHAIN_ID ? _CACHED_DOMAIN_SEPARATOR : _buildDomainSeparator();
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /// @dev Records the first sight of a hash. Returns true if it was the first.
    function _touch(bytes32 docHash, address who) private returns (bool first) {
        Doc storage d = _docs[docHash];
        if (d.firstSeen == 0) {
            d.firstSeen = uint64(block.timestamp);
            d.firstRegistrant = who;
            return true;
        }
        return false;
    }

    function _envelopeId(address creator, EnvelopeParams calldata p) private view returns (bytes32) {
        bytes32 signersHash = keccak256(abi.encodePacked(p.signers));
        return keccak256(
            bytes.concat(
                abi.encode(address(this), block.chainid, creator, p.docHash, p.alg),
                abi.encode(p.metaHash, signersHash, p.foundationCountersign, p.minLevel, p.deadline, p.salt)
            )
        );
    }

    /// @dev Identity level; any failure of the registry reads as 0 (understates, never overstates).
    function _level(address who) private view returns (uint8) {
        (bool ok, bool v) = _staticBool(IDENTITY, abi.encodeWithSelector(ISurDocSignIdentity.isFullyVerified.selector, who));
        if (ok && v) return 2;
        (ok, v) = _staticBool(IDENTITY, abi.encodeWithSelector(ISurDocSignIdentity.hasIdentity.selector, who));
        if (ok && v) return 1;
        return 0;
    }

    function _staticBool(address target, bytes memory data) private view returns (bool ok, bool value) {
        (bool success, bytes memory ret) = target.staticcall(data);
        if (!success || ret.length < 32) return (false, false);
        return (true, abi.decode(ret, (uint256)) != 0);
    }

    /// @dev Current holder of a Foundation role; address(0) if FoundationDAO cannot answer.
    function _roleHolder(uint8 role) private view returns (address) {
        bytes4 sel = role == ROLE_CEO
            ? ISurDocSignFoundation.ceo.selector
            : role == ROLE_CHAIR ? ISurDocSignFoundation.chair.selector : ISurDocSignFoundation.treasurer.selector;
        (bool success, bytes memory ret) = FOUNDATION.staticcall(abi.encodeWithSelector(sel));
        if (!success || ret.length < 32) return address(0);
        return abi.decode(ret, (address));
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("SurDocSign"), keccak256("1"), block.chainid, address(this))
        );
    }

    function _digest(bytes32 structHash) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
    }

    /// @dev ecrecover with v normalized to 27/28 (0/1 accepted) and low-s enforced. Reverts on any malformed signature.
    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        require(sig.length == 65, "SurDocSign: bad signature length");
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "SurDocSign: bad signature v");
        require(uint256(s) <= HALF_N, "SurDocSign: high-s signature");
        address a = ecrecover(digest, v, r, s);
        require(a != address(0), "SurDocSign: bad signature");
        return a;
    }
}
