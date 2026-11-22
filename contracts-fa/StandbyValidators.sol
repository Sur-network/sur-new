// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @dev تنها دو getter از ValidatorsRegistry که این قرارداد لازم دارد.
interface IStandbyRegistry {
    function ownerOfOperator(address operator) external view returns (address);
    function operatorOf(address owner) external view returns (address);
}

/// @title StandbyValidators
/// @notice قرارداد genesis در `SurAddresses.STANDBY_VALIDATORS` (0xcCcC...cCcC). یک فهرست آمادهٔ ولیدیتور فقط برای
///         **بازیابی اضطراری اجماع** است و برای هیچ کار دیگری نیست. Besu در حالت `contract` از یک قرارداد می‌پرسد
///         `getValidators()` تا بداند چه کسانی اجازهٔ تولید بلاک دارند. در حالت عادی آن قرارداد ValidatorsRegistry است. اگر بیش از
///         یک‌سوم ولیدیتورها بمیرند زنجیره می‌ایستد و هیچ تراکنشی نمی‌تواند آن را درست کند؛ تنها راه، یک مدخل تازه در
///         `transitions.qbft` ژنزیس است که انتخاب را به **همین قرارداد** برگرداند (گزارش پژوهش
///         testing-evidence/recovery-research-v26، آزمایش e5؛ گذار `blockheader` روی Shanghai/Cancun کار نمی‌کند). قرارداد مقصد
///         باید از قبل در state باشد، چون تغییر `alloc` پس از راه‌اندازی باعث می‌شود همهٔ نودها ژنزیس را رد کنند: به همین دلیل
///         از ابتدای genesis می‌آید.
///
///         روی زنجیرهٔ سالم **هیچ اثری** ندارد: تا وقتی اپراتورهای نود با تصمیم اجتماعی هماهنگ با ژنزیسی که به آن اشاره دارد
///         ریستارت نکنند، کسی آن را نمی‌خواند. پس حتی اگر هیأت بنیاد بدخواه باشد قدرتش کم است: تغییر فهرست به‌تنهایی چیزی را عوض
///         نمی‌کند.
///
///         نویسنده: **فقط FoundationDAO** (پیشنهاد `Execute` که `setStandby` را صدا می‌زند، ۳ از ۵). ValidatorsBoard نه، چون
///         اگر ولیدیتورها از کار بیفتند هیأتشان هم احتمالاً نمی‌تواند عمل کند؛ هیأت بنیاد به زنده‌بودن مجموعهٔ ولیدیتورها وابسته
///         نیست. هر تغییر کل فهرست را جایگزین می‌کند و همین‌جا سنجیده می‌شود: اندازه، آدرس‌های اکیداً صعودی (پس تکراری نیست؛ همان
///         قاعدهٔ payPage)، غیرصفر، و هر عضو باید **کلید اپراتور فعلی** (کلید نود) یک صندلی ثبت‌شده در ValidatorsRegistry باشد.
///
///         نگه‌داری: کلیدهای اپراتور عوض می‌شوند (setOperator، انتقال صندلی). `staleMembers()` و `isReady()` به داشبورد و ابزار
///         بازیابی می‌گویند فهرست هنوز معتبر است یا نه؛ بنیاد باید در همان اقدام حاکمیتی که عضوی را تغییر می‌دهد فهرست را تازه کند.
///
///         حساب QBFT: n عضو دست‌کم ceil(2n/3) عضو آنلاین لازم دارند؛ فهرست ۱تایی هیچ نود خاموشی را تحمل نمی‌کند و ۴تایی یکی را. برنامهٔ
///         بازیابی باید اعضایی را بگذارد که خوب اداره می‌شوند و در دسترس‌اند.
///
///         GENESIS: بدون constructor و بدون seed ذخیره. فقط بایت‌کد runtime در `alloc` می‌رود. فهرست **خالی** شروع می‌شود؛ پس بنیاد
///         باید بلافاصله بعد از راه‌اندازی آن را پر کند (چک‌لیست کیت راه‌اندازی)، یا GenesisBuilder می‌تواند seed کند.
contract StandbyValidators {
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;
    IStandbyRegistry public constant REGISTRY = IStandbyRegistry(SurAddresses.VALIDATORS_REGISTRY);

    /// @notice کوچک‌ترین فهرست معتبر. یک عضو عمداً مجاز است (تصمیم مالک ۲۰۲۶-۱۱-۲۲): در genesis فقط اولین ولیدیتور در فهرست است و یک نود در دسترس
    ///         در بحران بسیار محتمل‌تر از دو‌سوم یک فهرست بزرگ‌تر زنده است. یک عضو هیچ خطایی را تحمل نمی‌کند: بنیاد باید پس از آمدن ولیدیتورهای بیشتر
    ///         فهرست را به ۳ یا ۴ عضو برساند.
    uint256 public constant MIN_MEMBERS = 1;
    /// @notice سقف فهرست؛ getValidators() را برای Besu ارزان نگه می‌دارد.
    uint256 public constant MAX_MEMBERS = 100;

    address[] private _members;
    /// @notice تعداد دفعاتی که فهرست جایگزین شده (۰ = هرگز تنظیم نشده).
    uint256 public version;
    /// @notice زمان آخرین جایگزینی (۰ = هرگز تنظیم نشده).
    uint256 public updatedAt;

    event StandbyUpdated(uint256 indexed version, address[] members);

    /// @notice فهرستی که Besu می‌خواند. فقط خواندن storage است: هرگز revert نمی‌کند و به قرارداد دیگری وابسته نیست.
    function getValidators() external view returns (address[] memory) {
        return _members;
    }

    function memberCount() external view returns (uint256) {
        return _members.length;
    }

    /// @notice کل فهرست را جایگزین می‌کند. فقط FoundationDAO (از راه پیشنهاد Execute).
    function setStandby(address[] calldata members) external {
        require(msg.sender == FOUNDATION, "StandbyValidators: only FoundationDAO");
        uint256 n = members.length;
        require(n >= MIN_MEMBERS, "StandbyValidators: too few members");
        require(n <= MAX_MEMBERS, "StandbyValidators: too many members");
        address prev = address(0);
        for (uint256 i = 0; i < n; i++) {
            address m = members[i];
            require(m > prev, "StandbyValidators: members must be strictly ascending and non-zero");
            require(_isCurrentOperator(m), "StandbyValidators: not the current operator key of a registered seat");
            prev = m;
        }
        _members = members;
        version += 1;
        updatedAt = block.timestamp;
        emit StandbyUpdated(version, members);
    }

    /// @notice اعضایی که دیگر کلید اپراتور فعلی یک صندلی نیستند (فهرست باید تازه شود).
    function staleMembers() public view returns (address[] memory stale) {
        uint256 n = _members.length;
        address[] memory tmp = new address[](n);
        uint256 c;
        for (uint256 i = 0; i < n; i++) {
            if (!_isCurrentOperator(_members[i])) tmp[c++] = _members[i];
        }
        stale = new address[](c);
        for (uint256 j = 0; j < c; j++) stale[j] = tmp[j];
    }

    /// @notice وقتی فهرست همین حالا برای بازیابی قابل استفاده است: دست‌کم MIN_MEMBERS و بدون عضو کهنه.
    function isReady() external view returns (bool) {
        return _members.length >= MIN_MEMBERS && staleMembers().length == 0;
    }

    function _isCurrentOperator(address m) private view returns (bool) {
        address owner_ = REGISTRY.ownerOfOperator(m);
        return owner_ != address(0) && REGISTRY.operatorOf(owner_) == m;
    }
}
