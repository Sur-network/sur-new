// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @dev تنها سه getter از ValidatorsRegistry که این قرارداد لازم دارد.
interface IStandbyRegistry {
    function ownerOfOperator(address operator) external view returns (address);
    function operatorOf(address owner) external view returns (address);
    /// @dev اول status (enum Status: 0 None, 1 Probation, 2 Active, 3 Demoted, 4 Exiting, 5 RemovedInRecovery, 6 SelfSuspended)
    function getValidatorInfo(address who) external view returns (uint8 status, uint256 lockedStake, uint256 periodStartedAt, uint256 demotedAt, uint256 pendingSlashEpoch, bool isPaidEntrant);
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
///         قاعدهٔ payPage)، غیرصفر، و هر عضو باید **کلید اپراتور فعلی** (کلید نود) یک صندلی ثبت‌شده در ValidatorsRegistry باشد که مالکش هنوز آن‌جا «زنده» است
///         (وضعیت Probation، Active، Demoted یا SelfSuspended؛ نه None، Exiting، RemovedInRecovery). Registry عمداً هرگز کلید اپراتور را
///         آزاد نمی‌کند؛ پس نگاشت کلید-به-مالک پس از خروج، برداشت و حذف در بازیابی می‌ماند و این قرارداد خودش وضعیت مالک را می‌سنجد.
///
///         نگه‌داری: کلید اپراتور با «صندلی» می‌ماند. فروش صندلی (انتقال NFT) یا مهاجرت صندلی پس از گم‌شدن کلید مالک پیوند کلید را به
///         مالک تازه می‌برد (ownerOfOperator اکنون مالک تازه را نشان می‌دهد، با همان وضعیت)، پس چنین عضوی معتبر می‌ماند و فهرست
///         به تازه‌سازی نیاز ندارد. عضو فقط وقتی کهنه می‌شود که مالکش کلید را عوض کند (setOperator؛ برای صندلی Active،
///         proposeOperator که Verifier تأییدش می‌کند) یا مالک برود (خروج، برداشت یا حذف در بازیابی). `staleMembers()` و `isReady()`
///         به داشبورد و ابزار بازیابی می‌گویند فهرست هنوز معتبر است یا نه؛ بنیاد باید در همان اقدام حاکمیتی که عضوی را تغییر می‌دهد
///         فهرست را تازه کند.
///
///         حساب QBFT: n عضو دست‌کم ceil(2n/3) عضو آنلاین لازم دارند؛ فهرست ۱تایی هیچ نود خاموشی را تحمل نمی‌کند و ۴تایی یکی را. برنامهٔ
///         بازیابی باید اعضایی را بگذارد که خوب اداره می‌شوند و در دسترس‌اند.
///
///         GENESIS: بدون constructor. بایت‌کد runtime در `alloc` می‌رود، همراه seed ذخیره‌ای که
///         genesis-seed-helpers/StandbyValidators_GenesisSeed.sol می‌نویسد: فهرست دقیقاً **یک** عضو دارد، کلید اپراتور اولین ولیدیتور
///         (version برابر ۱، updatedAt برابر زمان genesis). بنیاد وقتی ولیدیتورهای بیشتری آمدند آن را به ۳ یا ۴ عضو می‌رساند.
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

    /// @notice اعضایی که دیگر کلید اپراتور فعلیِ یک صندلی «زنده» نیستند (مالکِ خارج‌شده، برداشت‌کرده یا حذف‌شده در بازیابی، یا کلید
    ///         عوض‌شده: فهرست باید تازه شود).
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
        if (owner_ == address(0) || REGISTRY.operatorOf(owner_) != m) return false;
        (uint8 status, , , , , ) = REGISTRY.getValidatorInfo(owner_);
        // زنده = Probation(1)، Active(2)، Demoted(3) یا SelfSuspended(6)؛ نه None(0، مثلاً پس از برداشت وثیقه)، Exiting(4)، RemovedInRecovery(5)
        return status == 1 || status == 2 || status == 3 || status == 6;
    }
}
