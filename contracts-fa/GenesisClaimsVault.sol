// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title GenesisClaimsVault
/// @notice مطالبات genesis ردیف‌های ۲ و ۳ (۱۱٬۹۸۴٬۰۰۰ + ۲۱٬۳۲۷٬۰۰۰ سورن) را به‌جای اعتبار دادن مستقیم به کیف‌پول‌ها
///         نگه می‌دارد و در ۲۴ قسط مساوی ماهانه آزاد می‌کند (بخش ۱۰ سند مرجع، تصمیم‌ها ✅):
///           * برای هر آدرس یک طلب جمع‌شده ثبت می‌شود؛ ۱۰۰ سورن از هر طلب از ابتدا در کیف‌پول خودِ طلبکار است (برای گس)
///             و از طلب کسر می‌شود: صندوق برای آن آدرس (طلب − ۱۰۰) را نگه می‌دارد؛
///           * مبلغ نگه‌داشته‌شده در ۲۴ قسط مساوی، در ابتدای هر ماه میلادی (UTC) آزاد می‌شود؛ قسط اول در ابتدای
///             نخستین ماه میلادیِ بعد از زمان genesis آزاد می‌شود؛
///           * قسطِ برداشت‌نشده هرگز منقضی نمی‌شود؛ انباشته می‌شود و مالک هر مقدار را که آزاد شده برداشت می‌کند؛
///           * فهرست آدرس‌ها پیش از genesis ثابت می‌شود؛ آدرس قابل تغییر نیست؛ سورنِ مطالبه‌نشده همین‌جا می‌ماند؛
///           * طلب بنیان‌گذاران مشروط به ماندن در ولیدیتوری نیست و هرگز slash نمی‌شود؛
///           * 🔶 باقی‌ماندهٔ تقسیم بر ۲۴ در قسط آخر قرار می‌گیرد (پیش‌فرض این کد).
///         موجودی صندوق در `alloc` ی genesis باید برابر مجموع (طلب − ۱۰۰) همهٔ آدرس‌ها باشد.
///
///         GENESIS: constructor ندارد و راهی برای افزودن طلب در آینده وجود ندارد. طلب‌ها و `genesisTimestamp` را
///         genesis-seed-helpers/GenesisClaimsVault_GenesisSeed.sol می‌نویسد (از این قرارداد ارث می‌برد؛ شبیه‌سازی و استخراج).
///         انتقال ساده رد می‌شود: صندوق فقط از طریق `alloc` ی genesis پر می‌شود.
contract GenesisClaimsVault {
    uint256 public constant INSTALLMENTS = 24;
    /// @notice بخشی از هر طلب که در genesis از قبل در کیف‌پول طلبکار است (پول گس).
    uint256 public constant WALLET_PART = 100 ether;

    /// @notice باید برابر `timestamp` فایل genesis.json باشد.
    uint256 public genesisTimestamp;
    /// @notice مجموع سورنی که در genesis برای همهٔ طلبکارها نگه داشته می‌شود (مجموع طلب − ۱۰۰).
    uint256 public totalHeld;

    struct Claim {
        uint256 held;       // طلب − ۱۰۰ سورن: مبلغی که این صندوق آزاد می‌کند
        uint256 withdrawn;
    }

    mapping(address => Claim) private _claims;

    event Withdrawn(address indexed claimant, uint256 amount);

    // ------------------------------------------------------------------
    // توابع خواندنی
    // ------------------------------------------------------------------
    /// @notice شناسهٔ ماه میلادی (UTC): سال × ۱۲ + (ماه − ۱). همان الگوریتم ValidatorsBoard.monthIdOf.
    function monthIdOf(uint256 timestamp) public pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    /// @notice تعداد اقساط آزادشده تا اکنون (۰ تا ۲۴): در ماه genesis برابر ۰ و از روز اول ماه بعد برابر ۱.
    function monthsReleased() public view returns (uint256) {
        uint256 first = monthIdOf(genesisTimestamp) + 1;
        uint256 current = monthIdOf(block.timestamp);
        if (current < first) return 0;
        uint256 n = current - first + 1;
        return n > INSTALLMENTS ? INSTALLMENTS : n;
    }

    /// @notice قسط ماهانهٔ معمولی (قسط آخر باقی‌ماندهٔ گرد کردن را هم در بر می‌گیرد).
    function installmentAmount(address claimant) external view returns (uint256) {
        return _claims[claimant].held / INSTALLMENTS;
    }

    /// @notice مقدار آزادشده تا اکنون (چه برداشت شده باشد چه نه).
    function releasedOf(address claimant) public view returns (uint256) {
        Claim storage c = _claims[claimant];
        uint256 n = monthsReleased();
        if (n >= INSTALLMENTS) return c.held;
        return (c.held / INSTALLMENTS) * n;
    }

    function withdrawableOf(address claimant) public view returns (uint256) {
        return releasedOf(claimant) - _claims[claimant].withdrawn;
    }

    /// @return held مبلغی که این صندوق برای طلبکار آزاد می‌کند (طلب − ۱۰۰ سورن)
    /// @return walletPart ۱۰۰ سورنی که در genesis مستقیماً در کیف‌پول گذاشته شد
    /// @return released مقدار آزادشده تا اکنون
    /// @return withdrawn مقداری که قبلاً پرداخت شده
    function claimInfo(address claimant) external view returns (uint256 held, uint256 walletPart, uint256 released, uint256 withdrawn) {
        Claim storage c = _claims[claimant];
        return (c.held, c.held == 0 ? 0 : WALLET_PART, releasedOf(claimant), c.withdrawn);
    }

    // ------------------------------------------------------------------
    // برداشت — فقط طلبکار ثبت‌شده، و هرچه آزاد شده و هنوز برداشت نشده
    // ------------------------------------------------------------------
    function withdraw() external {
        Claim storage c = _claims[msg.sender];
        require(c.held != 0, "GenesisClaimsVault: no claim for this address");
        uint256 amount = withdrawableOf(msg.sender);
        require(amount > 0, "GenesisClaimsVault: nothing released yet");
        c.withdrawn += amount;
        emit Withdrawn(msg.sender, amount);
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "GenesisClaimsVault: transfer failed");
    }

    receive() external payable {
        revert("GenesisClaimsVault: funded only through the genesis alloc");
    }

    // ------------------------------------------------------------------
    // seed کردن genesis (فقط GenesisClaimsVault_GenesisSeed استفاده می‌کند)
    // ------------------------------------------------------------------
    function _seed(address[] memory claimants, uint256[] memory claims, uint256 genesisTimestamp_) internal {
        require(claimants.length == claims.length, "seed: length mismatch");
        genesisTimestamp = genesisTimestamp_;
        for (uint256 i = 0; i < claimants.length; i++) {
            address a = claimants[i];
            require(a != address(0) && _claims[a].held == 0, "seed: bad or duplicate claimant");
            require(claims[i] > WALLET_PART, "seed: claim must exceed the 100 Suren wallet part");
            uint256 held = claims[i] - WALLET_PART;
            _claims[a].held = held;
            totalHeld += held;
        }
    }
}
