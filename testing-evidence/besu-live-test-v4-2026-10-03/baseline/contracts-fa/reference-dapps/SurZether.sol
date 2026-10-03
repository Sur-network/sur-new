// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================================
// ⚠️⚠️⚠️  قرارداد مرجع/پیشنهادی — آماده‌ی دیپلوی روی شبکه‌ی واقعی نیست  ⚠️⚠️⚠️
//
// این یک دپ مرجع است، نه یکی از شش قرارداد ساختاری genesis سور. genesis-injected نیست،
// constructor معمولی دارد، و مثل هر دپ دیگری دیپلوی می‌شود — توسط بنیاد یا هر توسعه‌دهنده‌ی
// مستقل دیگری، هر زمان.
//
// دلیل کامل طراحی، برنامه‌ی اجرای فازبندی‌شده، و ریسک‌های شناخته‌شده در
// sur-zether-confidential-transfers-proposal.md مستند شده — اول آن سند را بخوانید.
//
// چه‌چیزی از این فایل مستقیماً امن است که استفاده شود:
//   - چیدمان ذخیره‌سازی موجودی رمزشده (struct Ciphertext / Account).
//   - محاسبات همومورفیک منحنی بیضوی (_ecAdd / _ecMul)، که precompile های استاندارد
//     ecAdd (آدرس 0x06) / ecMul (آدرس 0x07) اتریوم را صدا می‌زنند — precompile هایی که روی
//     هر کلاینت استاندارد EVM، از جمله Besu، بدون هیچ تغییری وجود دارند.
//   - جریان کلی قرارداد (register → fund → transfer → burn).
//
// چه‌چیزی **امن نیست** که مستقیم استفاده شود — باید قبل از هر دیپلوی واقعی جایگزین شود:
//   - `IZetherVerifier` یک interface **نمادین/تصویری** است. شکل کلی چیزی را نشان می‌دهد که
//     یک verifier اثبات دانش-صفر Zether باید بررسی کند، ولی پارامترهای دقیقش با هیچ
//     پیاده‌سازی رسمی و منتشرشده‌ی خاصی تأیید نشده‌اند. قرارداد verifier واقعی که این
//     interface را پیاده می‌کند (بررسی Σ-Bullets / Bulletproofs) **باید از یک پیاده‌سازی
//     رسمی، منتشرشده، و بازبینی‌شده‌ی Zether فورک شود** — هرگز از صفر و بدون بازبینی رسمی
//     رمزنگاری نوشته نشود. یک باگ ظریف در این لایه می‌تواند به جعل موجودی یا سرقت وجوه
//     منجر شود. نقطه‌ی شروع پیشنهادی (هنوز برای کاربرد سور به‌طور مستقل audit نشده — ارزیابی
//     کامل در sur-zether-confidential-transfers-proposal.md، بخش ۲):
//     https://github.com/Consensys/anonymous-zether
//     (کتابخانه‌ی سمت کلاینت متناظر: https://github.com/kaleido-io/anonymous-zether-client).
//     ⚠️ با github.com/ZetherOrg/go-zether اشتباه گرفته نشود — یک بلاک‌چین PoW کاملاً بی‌ربط
//     است که تصادفاً از اسم «Zether» استفاده کرده.
//   - این فایل هرگز audit، تست روی یک شبکه‌ی واقعی، یا بازبینی توسط متخصص رمزنگاری نشده
//     است. آن را دیپلوی نکنید — نه روی mainnet سور، نه testnet، نه هیچ‌جای دیگری که ارزش
//     واقعی جابه‌جا کند — پیش از تکمیل برنامه‌ی فازبندی‌شده در سند پیشنهاد (انتخاب پیاده‌سازی
//     مرجع → بررسی سازگاری منحنی/precompile → بازبینی امنیتی مستقل → دیپلوی به‌عنوان یک دپ
//     مرجع معمولی).
// ============================================================================

/// @notice interface نمادین برای یک verifier اثبات دانش-صفر به سبک Zether.
/// @dev شکل پارامترهای اینجا یک تقریب معقول از چیزی است که یک اثبات انتقال/سوزاندن
///      Σ-Bullets باید بررسی کند (موجودی رمزشده‌ی فعلی فرستنده، کلید عمومی هر دو طرف،
///      دلتاهای رمزشده‌ی انتقال، و بایت‌های اثبات) — ولی تضمینی وجود ندارد که دقیقاً با
///      هیچ پیاده‌سازی واقعی خاصی بایت‌به‌بایت مطابقت داشته باشد. هرکس یک verifier واقعی و
///      آدیت‌شده‌ی Zether را فورک می‌کند **باید** این interface (و محل فراخوانی‌اش در
///      SurZether پایین) را دقیقاً با ساختار اثبات واقعی آن پیاده‌سازی تطبیق دهد.
interface IZetherVerifier {
    /// @dev بررسی می‌کند یک انتقال محرمانه درست ساخته شده: موجودی فرستنده بعد از کسر مبلغ
    ///      رمزشده هنوز منفی نمی‌شود، همان مبلغ به گیرنده اضافه می‌شود، و هیچ ارزشی خلق/نابود
    ///      نشده — همه‌ی این‌ها بدون افشای خودِ مبلغ. پارامترها در قالب struct (نه آرایه‌های
    ///      تخت uint256) گروه‌بندی شده‌اند، دقیقاً برای این‌که مصرف پشته‌ی EVM به اندازه‌ی
    ///      کافی کم بماند تا بدون `viaIR` کامپایل شود — دلیلش را در sur-contracts-deploy-notes.md
    ///      ببینید.
    function verifyTransfer(
        SurZetherTypes.Ciphertext memory senderBalance,
        SurZetherTypes.PubKey memory senderPubKey,
        SurZetherTypes.PubKey memory receiverPubKey,
        SurZetherTypes.Ciphertext memory deltaFrom,
        SurZetherTypes.Ciphertext memory deltaTo,
        bytes memory proof
    ) external view returns (bool);

    /// @dev بررسی می‌کند سوزاندن (موجودی محرمانه -> سورن معمولی) دقیقاً به مبلغ `amount`
    ///      در برابر موجودی رمزشده‌ی فعلی حساب معتبر است، بدون افشای چیزی درباره‌ی موجودی
    ///      حساب فراتر از این‌که `amount` را پوشش می‌دهد.
    function verifyBurn(
        SurZetherTypes.PubKey memory pubKey,
        SurZetherTypes.Ciphertext memory balance,
        uint256 amount,
        bytes memory proof
    ) external view returns (bool);
}

/// @dev تعریف struct های مشترک، در یک library جدا نگه داشته شده تا هم `SurZether` هم هر
///      پیاده‌سازی `IZetherVerifier` دقیقاً از همان انواع استفاده کنند.
library SurZetherTypes {
    struct Ciphertext {
        uint256 cx;
        uint256 cy;
        uint256 dx;
        uint256 dy;
    }

    struct PubKey {
        uint256 x;
        uint256 y;
    }
}

contract SurZether {
    // ------------------------------------------------------------------
    // ثابت‌های منحنی BN254 (alt_bn128) — این همان منحنی‌ای است که precompile های استاندارد
    // ecAdd/ecMul اتریوم (آدرس‌های 0x06 / 0x07) روی آن کار می‌کنند. بخش ۵ سند پیشنهاد را
    // برای سؤال باز «آیا سیستم اثبات پیاده‌سازی مرجع انتخاب‌شده با همین منحنی سازگار است یا
    // نیاز به تطبیق دارد» ببینید.
    // ------------------------------------------------------------------
    uint256 internal constant GX = 1;
    uint256 internal constant GY = 2;
    uint256 internal constant FIELD_MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct Account {
        uint256 pubKeyX;
        uint256 pubKeyY;
        bool registered;
    }

    /// @dev حساب‌ها با هش کلید عمومی Zether کلیدگذاری می‌شوند — عمداً **نه** با آدرس
    ///      اتریوم، چون یک آدرس اتریوم ممکن است چند حساب محرمانه‌ی مستقل بخواهد، و کلید
    ///      عمومی Zether یک جفت‌کلید منحنی بیضوی کاملاً جداست که کلاینت مدیریت می‌کند
    ///      (بخش ۶ سند پیشنهاد را ببینید).
    mapping(bytes32 => Account) public accounts;
    mapping(bytes32 => SurZetherTypes.Ciphertext) public balances;

    IZetherVerifier public immutable verifier;

    event Registered(bytes32 indexed accountKey);
    event Funded(bytes32 indexed accountKey, uint256 amount);
    event Transferred(bytes32 indexed fromKey, bytes32 indexed toKey);
    event Burned(bytes32 indexed accountKey, uint256 amount);

    constructor(address _verifier) {
        require(_verifier != address(0), "SurZether: zero verifier address");
        verifier = IZetherVerifier(_verifier);
    }

    // ------------------------------------------------------------------
    // ثبت‌نام — یک کلید عمومی Zether (یک نقطه‌ی منحنی بیضوی، مدیریت‌شده سمت کلاینت) را به
    // یک حساب محرمانه‌ی روی زنجیره متصل می‌کند. هرکسی می‌تواند هر تعداد حساب ثبت کند.
    // ------------------------------------------------------------------
    function register(uint256 pubKeyX, uint256 pubKeyY) external {
        bytes32 key = _accountKey(pubKeyX, pubKeyY);
        require(!accounts[key].registered, "SurZether: already registered");
        accounts[key] = Account({pubKeyX: pubKeyX, pubKeyY: pubKeyY, registered: true});
        emit Registered(key);
    }

    // ------------------------------------------------------------------
    // واریز — سورن معمولی (عمومی) را به یک ورودی موجودی رمزشده‌ی اولیه تبدیل می‌کند.
    // ⚠️ مبلغ واریزی عمداً **عمومی** است — این دقیقاً همان طراحی اصلی Zether است. محرمانگی
    // فقط برای فراخوانی‌های `transfer` بعدی اعمال می‌شود؛ خودِ واریز به‌اندازه‌ی هر تراکنش
    // معمولی دیگر قابل‌مشاهده است.
    // ------------------------------------------------------------------
    function fund(bytes32 accountKey) external payable {
        require(accounts[accountKey].registered, "SurZether: account not registered");
        require(msg.value > 0, "SurZether: zero-value funding");

        (uint256 mx, uint256 my) = _ecMul(GX, GY, msg.value);
        SurZetherTypes.Ciphertext storage bal = balances[accountKey];
        (bal.dx, bal.dy) = _ecAdd(bal.dx, bal.dy, mx, my);
        // بخش C دست‌نخورده می‌ماند: یک سهم «متن ساده» یعنی یک رمزنگاری ElGamal با ضریب
        // تصادفی r = ۰، یعنی C = ۰*G = نقطه‌ی بی‌نهایت، که ecAdd آن را بدون تغییر به بخش C
        // موجود اضافه می‌کند.

        emit Funded(accountKey, msg.value);
    }

    // ------------------------------------------------------------------
    // انتقال محرمانه — عملیات اصلی. هشدار بالای فایل را ببینید: بررسی `proof` کاملاً به
    // `verifier` واگذار شده، که باید قبل از هر استفاده‌ی واقعی با ارزش، یک verifier واقعی و
    // آدیت‌شده‌ی Zether باشد.
    // ------------------------------------------------------------------
    function transfer(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom, // رمزنگاری -مبلغ، با کلید فرستنده
        SurZetherTypes.Ciphertext calldata deltaTo,   // رمزنگاری +مبلغ، با کلید گیرنده
        bytes calldata proof
    ) external {
        require(accounts[fromKey].registered, "SurZether: sender not registered");
        require(accounts[toKey].registered, "SurZether: receiver not registered");
        require(fromKey != toKey, "SurZether: self-transfer not allowed");

        bool ok = _checkTransferProof(fromKey, toKey, deltaFrom, deltaTo, proof);
        require(ok, "SurZether: invalid transfer proof");

        _applyTransfer(fromKey, toKey, deltaFrom, deltaTo);

        emit Transferred(fromKey, toKey);
    }

    /// @dev فقط برای پایین‌نگه‌داشتن مصرف پشته‌ی EVM (کامپایل بدون `viaIR`) از `transfer`
    ///      جدا شده — رفتار بدون تغییر است.
    function _checkTransferProof(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom,
        SurZetherTypes.Ciphertext calldata deltaTo,
        bytes calldata proof
    ) private view returns (bool) {
        Account storage sender = accounts[fromKey];
        Account storage receiver = accounts[toKey];

        return verifier.verifyTransfer(
            balances[fromKey],
            SurZetherTypes.PubKey({x: sender.pubKeyX, y: sender.pubKeyY}),
            SurZetherTypes.PubKey({x: receiver.pubKeyX, y: receiver.pubKeyY}),
            deltaFrom,
            deltaTo,
            proof
        );
    }

    /// @dev به همان دلیل `_checkTransferProof` از `transfer` جدا شده.
    function _applyTransfer(
        bytes32 fromKey,
        bytes32 toKey,
        SurZetherTypes.Ciphertext calldata deltaFrom,
        SurZetherTypes.Ciphertext calldata deltaTo
    ) private {
        SurZetherTypes.Ciphertext storage senderBalance = balances[fromKey];
        (senderBalance.cx, senderBalance.cy) =
            _ecAdd(senderBalance.cx, senderBalance.cy, deltaFrom.cx, deltaFrom.cy);
        (senderBalance.dx, senderBalance.dy) =
            _ecAdd(senderBalance.dx, senderBalance.dy, deltaFrom.dx, deltaFrom.dy);

        SurZetherTypes.Ciphertext storage receiverBalance = balances[toKey];
        (receiverBalance.cx, receiverBalance.cy) =
            _ecAdd(receiverBalance.cx, receiverBalance.cy, deltaTo.cx, deltaTo.cy);
        (receiverBalance.dx, receiverBalance.dy) =
            _ecAdd(receiverBalance.dx, receiverBalance.dy, deltaTo.dx, deltaTo.dy);
    }

    // ------------------------------------------------------------------
    // سوزاندن — یک موجودی رمزشده را به سورن معمولی و قابل‌برداشت تبدیل می‌کند. مبلغ
    // برداشت‌شده در این مرحله عمومی می‌شود (ذاتی هر خروج از سیستم محرمانه)، ولی موجودی
    // باقی‌مانده‌ی حساب همچنان پنهان می‌ماند.
    // ------------------------------------------------------------------
    function burn(bytes32 accountKey, uint256 amount, bytes calldata proof) external {
        require(accounts[accountKey].registered, "SurZether: account not registered");
        require(amount > 0, "SurZether: zero-value burn");
        require(address(this).balance >= amount, "SurZether: insufficient contract balance");

        bool ok = _checkBurnProof(accountKey, amount, proof);
        require(ok, "SurZether: invalid burn proof");

        SurZetherTypes.Ciphertext storage bal = balances[accountKey];
        (uint256 mx, uint256 my) = _ecMul(GX, GY, amount);
        (bal.dx, bal.dy) = _ecAdd(bal.dx, bal.dy, mx, _negateY(my));

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "SurZether: Suren withdrawal failed");

        emit Burned(accountKey, amount);
    }

    /// @dev به همان دلیل `_checkTransferProof` از `burn` جدا شده.
    function _checkBurnProof(bytes32 accountKey, uint256 amount, bytes calldata proof)
        private
        view
        returns (bool)
    {
        Account storage acc = accounts[accountKey];
        return verifier.verifyBurn(
            SurZetherTypes.PubKey({x: acc.pubKeyX, y: acc.pubKeyY}),
            balances[accountKey],
            amount,
            proof
        );
    }

    // ------------------------------------------------------------------
    // توابع کمکی داخلی — محاسبات منحنی بیضوی و کلیدگذاری حساب.
    // ------------------------------------------------------------------

    function _accountKey(uint256 x, uint256 y) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(x, y));
    }

    function _negateY(uint256 y) internal pure returns (uint256) {
        return FIELD_MODULUS - (y % FIELD_MODULUS);
    }

    /// @dev precompile استاندارد ecAdd اتریوم (آدرس 0x06) را صدا می‌زند — روی هر کلاینت
    ///      استاندارد EVM، از جمله Besu، بدون هیچ تغییری وجود دارد.
    function _ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        internal
        view
        returns (uint256 x3, uint256 y3)
    {
        bool success;
        assembly {
            let input := mload(0x40)
            mstore(input, x1)
            mstore(add(input, 0x20), y1)
            mstore(add(input, 0x40), x2)
            mstore(add(input, 0x60), y2)
            success := staticcall(gas(), 0x06, input, 0x80, input, 0x40)
            x3 := mload(input)
            y3 := mload(add(input, 0x20))
        }
        require(success, "SurZether: ecAdd precompile call failed");
    }

    /// @dev precompile استاندارد ecMul اتریوم (آدرس 0x07) را صدا می‌زند — روی هر کلاینت
    ///      استاندارد EVM، از جمله Besu، بدون هیچ تغییری وجود دارد.
    function _ecMul(uint256 x1, uint256 y1, uint256 scalar)
        internal
        view
        returns (uint256 x2, uint256 y2)
    {
        bool success;
        assembly {
            let input := mload(0x40)
            mstore(input, x1)
            mstore(add(input, 0x20), y1)
            mstore(add(input, 0x40), scalar)
            success := staticcall(gas(), 0x07, input, 0x60, input, 0x40)
            x2 := mload(input)
            y2 := mload(add(input, 0x20))
        }
        require(success, "SurZether: ecMul precompile call failed");
    }
}
