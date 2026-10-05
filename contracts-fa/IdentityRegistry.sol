// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title IdentityRegistry
/// @notice قرارداد ساختاری ششم سور (آدرس ثابت `0x6666...6666`): منبع واحد حقیقت برای هویت در میان همهٔ کاربران شبکه، نه فقط
///         ولیدیتورها. از مدل SIP001/SIP002 پیروی می‌کند (احراز هویت برای کاربران حقیقی و حقوقی و استفادهٔ dAppها از آن) با دو
///         انتخاب طراحی:
///
///         ۱. **بدون دفتر اسناد رسمی.** احراز هویت کاملاً آنلاین است: بررسی eKYC (تطبیق چهره، تشخیص زنده‌بودن و اصالت سند، توسط
///            ارائه‌دهندهٔ دارای مجوز) به‌علاوهٔ امضای یک challenge با کلید Sur خود کاربر.
///
///         ۲. **بدون داده‌ی خام حساس روی زنجیره.** هیچ storage روی بلاک‌چین عمومی محرمانه نیست (`eth_getStorageAt` همیشه
///            هست) و برای دادهٔ کم‌آنتروپی مثل کد ملی ۱۰رقمی حتی هش هم بدون salt محرمانه حفاظتی نمی‌دهد. پس داده‌ی خام
///            هرگز وارد این قرارداد نمی‌شود: فقط پرچم‌های احراز (bool) و یک commitment نگه داشته می‌شود (که صرفاً برای اثبات
///            دست‌نخوردگی در یک اختلاف حقوقی احتمالی است و هرگز برای پاسخ به پرس‌وجو به کار نمی‌رود). عمل «تطبیق» (بخش ۶
///            SIP002) باید فراخوان API آف‌چین باشد، نه تراکنش روی زنجیره، چون ورودیِ خودِ تراکنش (مقداری که مقایسه می‌شود) در
///            calldata عمومی دیده می‌شود. جزئیات در `sur-identity-registry-spec.md` است.
///
///         آدرس منتقل‌شده سوخته است: `hasIdentity` و `getVerificationStatus` برایش چیزی گزارش نمی‌کنند و نه مالک و نه oracle
///         دیگر نمی‌توانند آن را ثبت یا احراز کنند.
contract IdentityRegistry {
    // ------------------------------------------------------------------
    // آدرس ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // هویت خوداظهار (لایهٔ اول SIP001)
    // ------------------------------------------------------------------
    enum PersonType { Individual, Legal }

    struct Identity {
        bool registered;
        PersonType personType;
        string name;
        bool phoneVerified;  // موبایل واقعی هرگز اینجا ذخیره نمی‌شود — فقط این فلگ
        bool telegramVerified;  // آیدی تلگرام واقعی هرگز اینجا ذخیره نمی‌شود — فقط این فلگ
        bool kycVerified;  // نتیجهٔ بررسی کامل eKYC (عکس + کد ملی + تطبیق چهره)
        bytes32 kycCommitment;  // فقط برای اثبات دست‌نخوردگی در اختلاف‌ها نگه داشته می‌شود، هرگز برای تطبیق
        address migratedTo;  // ناصفر: این آدرس سوخته است و هویتش به آن آدرس منتقل شده (بخش ۳.۴ مشخصات)
    }

    mapping(address => Identity) public identities;

    // ------------------------------------------------------------------
    // کلید عملیاتی — کنترل بنیاد (نه هیأت‌مدیره‌ی ولیدیتورها)، چون احراز هویت طبق طراحی
    // اصلی SIP001 («بنیاد سور موظف است اطلاعات اشخاص حقیقی و حقوقی احراز هویت‌شده را ثبت
    // کند») مسئولیت بنیاد است.
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
    // GENESIS FILL-IN: این قرارداد constructor ندارد چون در `alloc` بلاک genesis تزریق می‌شود. ابزار genesis استقرارش را روی یک
    // زنجیرهٔ محلی موقت شبیه‌سازی می‌کند و storage حاصل را در فایل نهایی genesis می‌گذارد؛ مقدار اولیهٔ زیر نشانگر مستندات و ابزار است.
    // ------------------------------------------------------------------

    /// @dev آدرس اولیهٔ identityOracle که از SurAddresses.sol خوانده می‌شود (منبع واحد همهٔ آدرس‌های oracle).
    address public identityOracle = SurAddresses.IDENTITY_ORACLE;

    // ------------------------------------------------------------------
    // خوداظهاری — هر آدرسی، نه فقط ولیدیتورها
    // ------------------------------------------------------------------

    /// @notice ثبت/به‌روزرسانی هویت خوداظهاری (فقط نام و نوع شخصیت). قابل‌فراخوانی توسط هر
    ///         آدرسی، هر زمان؛ فراخوانی دوباره هیچ‌کدام از فلگ‌های وریفای را ریست نمی‌کند.
    function registerIdentity(PersonType personType, string calldata name) external {
        require(bytes(name).length > 0, "IdentityRegistry: empty name");

        Identity storage id_ = identities[msg.sender];
        require(id_.migratedTo == address(0), "IdentityRegistry: address was migrated (burned)");
        id_.registered = true;
        id_.personType = personType;
        id_.name = name;

        emit IdentityRegistered(msg.sender, personType, name);
    }

    /// @notice بررسی سطح صفر (دسترسی آزاد، بدون ثبت‌نام dApp)، معادل بخش ۶-۱ SIP002: «آیا این آدرس اصلاً هویتی ثبت کرده؟»،
    ///         بدون افشای چیز دیگر. آدرس منتقل‌شده (`migratedTo != 0`) false برمی‌گرداند.
    function hasIdentity(address who) external view returns (bool) {
        Identity storage id_ = identities[who];
        return id_.registered && id_.migratedTo == address(0);
    }

    /// @notice چک عمومی وضعیت وریفای — همه‌اش بولی، هیچ داده‌ی خامی نیست، پس افشای آزادش
    ///         مشکلی ندارد (دقیقاً مثل بخش ۶-۱ SIP002).
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
    // احراز — فقط identityOracle (سرویس هویت آف‌چین؛ جزئیات در
    // sur-identity-registry-spec.md)
    // ------------------------------------------------------------------

    function setPhoneVerified(address who, bool verified) external onlyIdentityOracle notMigrated(who) {
        identities[who].phoneVerified = verified;
        emit PhoneVerificationUpdated(who, verified);
    }

    function setTelegramVerified(address who, bool verified) external onlyIdentityOracle notMigrated(who) {
        identities[who].telegramVerified = verified;
        emit TelegramVerificationUpdated(who, verified);
    }

    /// @notice نتیجهٔ بررسی کامل eKYC را ثبت می‌کند (عکس شخصی + کارت ملی + جزئیات در سطح شناسنامه + تطبیق چهره).
    ///         `commitment` هش دارای salt کل مجموعه‌دادهٔ احرازشده است — **فقط** برای اثبات دست‌نخوردگی در یک اختلاف حقوقی
    ///         احتمالی نگه داشته می‌شود؛ هیچ تابع روی زنجیره‌ای هرگز آن را برای پاسخ به پرس‌وجوی «تطبیق» به کار نمی‌برد (آن
    ///         عمل همیشه از API سرویس هویت آف‌چین می‌گذرد — بخش ۵ `sur-identity-registry-spec.md` را ببینید).
    function setKycVerified(address who, bool verified, bytes32 commitment) external onlyIdentityOracle notMigrated(who) {
        Identity storage id_ = identities[who];
        id_.kycVerified = verified;
        id_.kycCommitment = verified ? commitment : bytes32(0);
        emit KycVerificationUpdated(who, verified, id_.kycCommitment);
    }

    // ------------------------------------------------------------------
    // بازیابی هویت: جایگزین آنلاین بخش‌های ۷ و ۸ SIP001 (کلید گم‌شده / آدرس سوخته). هر فراخوان باید همیشه پس از یک
    // راستی‌آزمایی آف‌چین مستقل باشد (بخش ۳.۴ مشخصات): برای کاربران فقط‌ تلفن/تلگرام تکرار فرایند OTP کافی است؛ برای
    // کاربران KYC‌شده ارائه‌دهندهٔ eKYC باید تأیید کند سلفی جدید با داده‌های بیومتریک پیشتر ذخیره‌شده برای همان کد ملی
    // می‌خواند. این یک بازیابی است، نه ثبت‌نام تازه.
    // ------------------------------------------------------------------

    /// @notice کل وضعیت هویت را از یک آدرس قدیمی (گم‌شده یا لورفته) به آدرس جدید منتقل می‌کند. آدرس قدیمی سوخته می‌شود:
    ///         `hasIdentity` و `getVerificationStatus` برایش چیزی گزارش نمی‌کنند و دیگر نمی‌شود آن را ثبت یا احراز کرد، ولی
    ///         رکورد و مسئولیتش برای کارهای گذشته پاک نمی‌شود. آدرس جدید باید آدرسی متفاوت باشد که خودش منتقل نشده باشد.
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
    // چرخش کلید — فقط بنیاد (نه هیأت‌مدیره‌ی ولیدیتورها)
    // ------------------------------------------------------------------
    function setIdentityOracle(address newOracle) external onlyFoundation {
        require(newOracle != address(0), "IdentityRegistry: zero oracle address");
        emit IdentityOracleUpdated(identityOracle, newOracle);
        identityOracle = newOracle;
    }
}
