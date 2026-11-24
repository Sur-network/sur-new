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
/// @notice دفتر روی زنجیره برای ثبت‌زمان و امضای اسناد. فقط هش روی زنجیره می‌رود، نه خود سند.
///
///         سه سطح (همه در یک قرارداد):
///           ۱. ثبت‌زمان: `register(docHash, ...)`. فقط ثابت می‌کند این هش در زمان بلوک وجود داشته، نه نویسنده را.
///           ۲. امضا: `sign(...)` با `envelopeId = 0`. هر آدرس هر هشی را امضا می‌کند. یک سند می‌تواند هر تعداد امضای
///              مستقل داشته باشد: هر امضاکنندهٔ متمایز یک امضا اضافه می‌کند (`signerCount`، `hasSigned`، یک رویداد برای هر امضا).
///           ۳. جریان چندطرفه (envelope): `createEnvelope(...)` فهرست مرتب‌شدهٔ امضاکنندگان لازم (و در صورت لزوم سه نقش بنیاد)
///              را ثابت می‌کند؛ `sign(...)` با همان `envelopeId` یک جایگاه را پر می‌کند؛ با پرشدن همهٔ جایگاه‌ها جریان کامل است.
///         یک سند هم بیرون از هر جریان و هم داخل هر تعداد جریان امضا می‌شود.
///
///         یک امضا برای هر (docHash, envelopeId, signer). امضای دوباره در همان بستر revert می‌کند و همین ضد بازپخش هم هست.
///
///         سطح هویت هنگام امضا از IdentityRegistry خوانده و با رکورد امضا نگه‌داری می‌شود: ۰ = هر آدرس،
///         ۱ = `hasIdentity`، ۲ = `isFullyVerified`. جریان می‌تواند حداقل سطح بخواهد. مهاجرت هویت پس از آن رکوردهای نوشته‌شده را
///         تغییر نمی‌دهد؛ آدرس مهاجرت‌شده (سوخته) پس از آن سطح ۰ دارد.
///
///         نقش‌های بنیاد (ceo / chair / treasurer در FoundationDAO) تنها امضاکنندگان شخص حقوقی‌اند. جریانِ دارای
///         `foundationCountersign` سه جایگاه اضافه دارد، یکی برای هر نقش؛ امضاکننده باید هنگام امضا همان نقش را داشته باشد.
///         یک آدرس در هر جریان حداکثر یک جایگاه را پر می‌کند؛ پس جریانی که دارندگان نقش‌هایش یکی باشند (یک آدرس با دو نقش)
///         تا تغییر نقش‌ها کامل نمی‌شود؛ سازنده می‌تواند آن را لغو کند.
///
///         دو راه ارسال: مستقیم (`msg.sender` فاعل است و گس می‌دهد) یا با امضای EIP-712 (`...WithSig`؛ هر کس می‌فرستد و
///         فاعل از امضا بازیابی می‌شود). سرویس relayer از شکل دوم استفاده می‌کند و نمی‌تواند چیزی را جعل کند.
///
///         قرارداد genesis نیست: استقرار معمولی پس از genesis، بدون مالک، بدون ارتقا و بدون پارامتر قابل‌تغییر. اشکال با استقرار
///         نسخهٔ تازه در آدرس تازه رفع می‌شود و خوانندگان نسخهٔ قدیم را همچنان می‌خوانند. فقط حساب‌های EOA (ecrecover)؛
///         کیف‌پول قراردادی (ERC-1271) پشتیبانی نمی‌شود. هیچ پولی نگه نمی‌دارد: payable نیست و receive ندارد.
contract SurDocSign {
    // ------------------------------------------------------------------
    // ثابت‌ها
    // ------------------------------------------------------------------
    address public constant IDENTITY = SurAddresses.IDENTITY_REGISTRY;
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    /// @dev مقدارهای `role`: ۰ = طرف عادی؛ ۱ تا ۳ = نقش‌های بنیاد.
    uint8 public constant ROLE_PARTY = 0;
    uint8 public constant ROLE_CEO = 1;
    uint8 public constant ROLE_CHAIR = 2;
    uint8 public constant ROLE_TREASURER = 3;

    /// @dev شناسهٔ الگوریتم هش. ۰ = SHA-256 روی بایت‌های خام فایل؛ ۱ = keccak256 روی متن UTF-8. شناسه جزو چیزی است که امضا می‌شود.
    uint8 public constant ALG_SHA256 = 0;
    uint8 public constant ALG_KECCAK256 = 1;

    /// @dev مجموع جایگاه‌های یک جریان (امضاکنندگان نام‌برده + نقش‌های بنیاد). 🔶 مقدار پیشنهادی.
    uint256 public constant MAX_SLOTS = 20;
    /// @dev بازهٔ مجاز مهلت جریان نسبت به لحظهٔ ساخت. 🔶 مقدارهای پیشنهادی.
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

    /// @dev نصفِ مرتبهٔ منحنی secp256k1: امضای با `s` بزرگ‌تر رد می‌شود (جلوگیری از تغییر شکل امضا).
    uint256 private constant HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    // ------------------------------------------------------------------
    // حالت (storage)
    // ------------------------------------------------------------------
    struct Doc {
        uint64 firstSeen;        // زمان بلوکِ اولین ثبت یا امضا (۰ = هرگز دیده نشده)
        address firstRegistrant; // نخستین کسی که به این هش دست زد (ادعای نویسندگی نیست)
        uint32 signerCount;      // آدرس‌های متمایزی که این هش را در هر بستری (بیرون یا داخل هر جریان) امضا کرده‌اند
    }

    struct SigRecord {
        uint64 signedAt; // ۰ = امضایی نیست
        uint8 level;     // سطح هویت هنگام امضا
        uint8 role;      // ۰ طرف عادی؛ ۱ تا ۳ نقش بنیادی که امضاکننده پر کرده
    }

    struct Envelope {
        bytes32 docHash;
        bytes32 metaHash;
        address creator;
        uint64 deadline;
        uint8 alg;
        uint8 minLevel;
        uint8 required;  // مجموع جایگاه‌ها
        uint8 filled;    // جایگاه‌های پرشده تا اینجا
        bool foundation; // درست: سه جایگاه نقش بنیاد جزو `required` است
        bool cancelled;
        uint64 createdAt;
        uint64 completedAt;
    }

    mapping(bytes32 => Doc) private _docs;
    /// @notice اولین زمانی که `signer` در هر بستری `docHash` را امضا کرده (۰ = هرگز). `hasSigned` یعنی `> 0`.
    mapping(bytes32 => mapping(address => uint64)) public firstSignedAt;
    mapping(bytes32 => mapping(bytes32 => mapping(address => SigRecord))) private _sigs; // docHash => envelopeId => signer
    mapping(bytes32 => Envelope) private _envelopes;
    mapping(bytes32 => mapping(address => bool)) public isNamedSigner; // envelopeId => آدرس => در فهرست نام برده شده
    mapping(bytes32 => uint8) public roleFilledMask;                   // envelopeId => بیت (role - 1)

    // ------------------------------------------------------------------
    // پارامترها (ساختارها پشته را کوچک نگه می‌دارند)
    // ------------------------------------------------------------------
    struct EnvelopeParams {
        bytes32 docHash;
        uint8 alg;
        bytes32 metaHash;
        address[] signers;          // اکیداً صعودی و ناصفر؛ فقط با foundationCountersign می‌تواند خالی باشد
        bool foundationCountersign;
        uint8 minLevel;             // ۰ تا ۲
        uint64 deadline;            // زمان مطلقی که تا آن همهٔ جایگاه‌ها باید پر شوند
        bytes32 salt;               // برای پارامترهای یکسان شناسهٔ جریان را یکتا می‌کند
    }

    struct SignParams {
        bytes32 docHash;
        uint8 alg;
        bytes32 metaHash;
        bytes32 envelopeId;         // ۰ = امضا بیرون از هر جریان
        uint8 role;                 // ۰ طرف عادی؛ ۱ تا ۳ نقش بنیاد
    }

    // ------------------------------------------------------------------
    // رویدادها
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
    // ۱. ثبت‌زمان
    // ------------------------------------------------------------------

    /// @notice ثبت‌زمان یک هش. هویتی ادعا نمی‌شود؛ هر کس (از جمله relayer) می‌تواند صدا بزند. فراخوانی اول `firstSeen` و
    ///         `firstRegistrant` را می‌نویسد؛ فراخوانی‌های بعدی فقط رویداد می‌دهند.
    function register(bytes32 docHash, uint8 alg, bytes32 metaHash) external {
        require(docHash != bytes32(0), "SurDocSign: empty hash");
        require(alg <= ALG_KECCAK256, "SurDocSign: unknown algorithm");
        bool first = _touch(docHash, msg.sender);
        emit DocumentRegistered(docHash, msg.sender, alg, metaHash, first);
    }

    // ------------------------------------------------------------------
    // ۲ و ۳. امضاها
    // ------------------------------------------------------------------

    /// @notice امضا به نام `msg.sender`. `p.envelopeId == 0`: امضا بیرون از هر جریان (هر تعداد امضاکنندهٔ متفاوت می‌توانند روی
    ///         همان هش این کار را بکنند). در غیر این صورت یک جایگاه آن جریان را پر می‌کند.
    function sign(SignParams calldata p) external {
        _sign(msg.sender, p);
    }

    /// @notice امضا به نام `signer` با امضای EIP-712 او (`DocumentSignature`)؛ هر کس می‌تواند بفرستد.
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
    // جریان‌ها (envelope)
    // ------------------------------------------------------------------

    /// @notice ساخت جریان به نام `msg.sender`. شناسهٔ جریان را برمی‌گرداند (از پیش هم با `previewEnvelopeId` قابل‌محاسبه است).
    function createEnvelope(EnvelopeParams calldata p) external returns (bytes32) {
        return _create(msg.sender, p);
    }

    /// @notice ساخت جریان به نام `creator` با امضای EIP-712 او (`EnvelopeCreate`).
    function createEnvelopeWithSig(EnvelopeParams calldata p, address creator, uint64 sigDeadline, bytes calldata sig)
        external
        returns (bytes32)
    {
        require(block.timestamp <= sigDeadline, "SurDocSign: signature expired");
        bytes32 signersHash = keccak256(abi.encodePacked(p.signers));
        // دو تکه از کلمه‌های ۳۲بایتیِ ایستا: برابر یک abi.encode است و پشته را کوچک نگه می‌دارد
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

    /// @dev امضاکنندگان نام‌بردهٔ یک جریان تازه را بررسی و ذخیره می‌کند (جدا از `_create` برای کوچک‌ماندن پشته).
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
            // امضاکنندهٔ نام‌برده‌ای که نقش هم دارد فقط یکی از دو جایگاه را پر می‌کند، پس جریان هرگز کامل نمی‌شد
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

    /// @notice لغو جریان ناتمام توسط سازنده‌اش. امضاهای نوشته‌شده در رکورد می‌مانند.
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
    // نماها (view)
    // ------------------------------------------------------------------

    function docInfo(bytes32 docHash) external view returns (uint64 firstSeen, address firstRegistrant, uint32 signers) {
        Doc storage d = _docs[docHash];
        return (d.firstSeen, d.firstRegistrant, d.signerCount);
    }

    /// @notice تعداد آدرس‌های متمایزی که `docHash` را امضا کرده‌اند (بیرون یا داخل هر جریان).
    function signerCount(bytes32 docHash) external view returns (uint32) {
        return _docs[docHash].signerCount;
    }

    /// @notice آیا `signer` در هر بستری `docHash` را امضا کرده است.
    function hasSigned(bytes32 docHash, address signer) external view returns (bool) {
        return firstSignedAt[docHash][signer] != 0;
    }

    /// @notice یک رکورد امضا. برای امضای بیرون از جریان `envelopeId = 0`. `signedAt == 0` یعنی امضایی نیست.
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

    /// @notice ۰ ناموجود، ۱ فعال، ۲ کامل، ۳ لغوشده، ۴ منقضی (مهلت گذشته، نه کامل، نه لغوشده).
    function envelopeState(bytes32 envelopeId) public view returns (uint8) {
        Envelope storage e = _envelopes[envelopeId];
        if (e.createdAt == 0) return STATE_NONE;
        if (e.completedAt != 0) return STATE_COMPLETE;
        if (e.cancelled) return STATE_CANCELLED;
        if (block.timestamp > e.deadline) return STATE_EXPIRED;
        return STATE_ACTIVE;
    }

    /// @notice آیا جایگاه نقش `role` (۱ تا ۳) بنیاد در این جریان پر شده است.
    function roleFilled(bytes32 envelopeId, uint8 role) external view returns (bool) {
        require(role >= ROLE_CEO && role <= ROLE_TREASURER, "SurDocSign: unknown role");
        return roleFilledMask[envelopeId] & (uint8(1) << (role - 1)) != 0;
    }

    /// @notice شناسه‌ای که `createEnvelope` / `createEnvelopeWithSig` وقتی `creator` این پارامترها را روی این زنجیره بسازد می‌دهد.
    function previewEnvelopeId(address creator, EnvelopeParams calldata p) external view returns (bytes32) {
        return _envelopeId(creator, p);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _CACHED_CHAIN_ID ? _CACHED_DOMAIN_SEPARATOR : _buildDomainSeparator();
    }

    // ------------------------------------------------------------------
    // درونی
    // ------------------------------------------------------------------

    /// @dev اولین دیدن یک هش را ثبت می‌کند. اگر اولین بود درست برمی‌گرداند.
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

    /// @dev سطح هویت؛ هر شکست رجیستری ۰ خوانده می‌شود (کمتر نشان می‌دهد، هرگز بیشتر).
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

    /// @dev دارندهٔ فعلی یک نقش بنیاد؛ اگر FoundationDAO نتواند جواب بدهد address(0).
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

    /// @dev ecrecover با `v` یکسان‌شده به ۲۷/۲۸ (۰/۱ پذیرفته می‌شود) و low-s اجباری. هر امضای ناقص revert می‌کند.
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
