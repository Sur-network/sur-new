// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title IdentityRegistry
/// @notice ششمین قرارداد ساختاری سور (آدرس ثابت `0x6666...6666`) — مرجع واحد هویت برای **کل
///         کاربران شبکه**، نه فقط ولیدیتورها. الهام‌گرفته از استاندارد قدیمی پروژه SIP001/SIP002
///         («روش احراز هویت کاربران حقیقی و حقوقی» و «استفاده از خدمات احراز هویت توسط دپ‌ها»)،
///         با دو اصلاح آگاهانه نسبت به نسخه‌ی اصلی:
///
///         ۱. **بدون دفترخانه‌ی اسناد رسمی.** SIP001 نیاز به گواهی امضای حضوری در دفترخانه
///            داشت. اینجا جایگزینش شده با یک فرآیند کاملاً آنلاین: تأیید eKYC (تطبیق چهره +
///            liveness detection + بررسی اصالت مدرک، توسط یک سرویس‌دهنده‌ی مجاز) + امضای
///            دیجیتال چالش با همان کلید سوری کاربر (این بخش دوم دقیقاً همان ایده‌ی SIP001 است،
///            بدون تغییر).
///
///         ۲. **بدون داده‌ی خام حساس on-chain.** SIP001 پیشنهاد می‌داد کد ملی/نام/شناسنامه در
///            یک «قرارداد هوشمند محرمانه» ذخیره شود. این از نظر فنی ممکن نیست: هیچ storage
///            روی یک بلاک‌چین عمومی واقعاً محرمانه نمی‌ماند (`eth_getStorageAt` همیشه در
///            دسترس است)، و برای داده‌ی کم‌آنتروپی مثل کد ملی (۱۰ رقم)، حتی هش‌کردن هم بدون یک
///            salt مخفی محافظت واقعی نمی‌دهد. راه‌حل: داده‌ی خام هرگز وارد این قرارداد نمی‌شود؛
///            فقط یک وضعیت وریفای (bool) و یک commitment (برای اثبات عدم‌دستکاری در دعاوی
///            حقوقی آینده، نه برای پاسخ به کوئری) on-chain می‌مانند. خودِ عملیات «تطبیق»
///            (بخش ۶ SIP002) باید یک فراخوانی API آف‌چین باشد، نه یک تراکنش on-chain — چون
///            حتی اگر قرارداد پاسخ را فاش نکند، **پارامتر ورودی خودِ تراکنش** (مقداری که
///            دارد با آن مقایسه می‌شود) در calldata عمومی و همیشه قابل‌مشاهده است. جزئیات
///            کامل در `sur-identity-registry-spec.md`.
contract IdentityRegistry {
    // ------------------------------------------------------------------
    // آدرس ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // هویت خوداظهاری (لایه‌ی اول SIP001) — بدون تغییر نسبت به طراحی قبلی خودمان، فقط
    // منتقل‌شده از ValidatorsRegistry.
    // ------------------------------------------------------------------
    enum PersonType { Individual, Legal }

    struct Identity {
        bool registered;
        PersonType personType;
        string name;
        bool phoneVerified;      // موبایل واقعی هرگز اینجا ذخیره نمی‌شود — فقط این فلگ
        bool telegramVerified;   // آیدی تلگرام واقعی هرگز اینجا ذخیره نمی‌شود — فقط این فلگ
        bool kycVerified;        // تازه — نتیجه‌ی eKYC کامل (تصویر+کارت‌ملی+تطبیق چهره)
        bytes32 kycCommitment;   // تازه — فقط برای اثبات عدم‌دستکاری در دعاوی، نه matching
        address migratedTo;      // تازه — غیرصفر یعنی این آدرس «سوخته» و هویتش به آدرس جدید منتقل شده (بخش ۳.۴ سند فنی؛ معادل بخش ۷/۸ SIP001)
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

    modifier onlyIdentityOracle() {
        require(msg.sender == identityOracle, "IdentityRegistry: caller is not the identity oracle");
        _;
    }

    // ------------------------------------------------------------------
    // 🔶 پرکردنِ genesis — این قرارداد constructor ندارد چون مستقیم در alloc بلاک genesis
    // تزریق می‌شود (constructorش هرگز روی زنجیره‌ی واقعی اجرا نمی‌شود). ابزار genesis آف‌چین
    // باید دیپلوی این قرارداد را (با آرگومان واقعی، روی یک زنجیره‌ی محلی موقت) شبیه‌سازی کند
    // و storage نتیجه را در فایل نهایی genesis کپی کند — این سورس دقیقاً همین‌طور که هست
    // دیپلوی نشود با این فرض که مقدار placeholder پایین روی زنجیره اثر دارد؛ این مقدار فقط
    // یک علامت مستندسازی/ابزاری است.
    // ------------------------------------------------------------------

    /// @dev 🔶 FILL_IN: آدرس اولیه‌ی identityOracle (باید غیرصفر باشد).
    address public identityOracle = address(0);

    // ------------------------------------------------------------------
    // خوداظهاری — هر آدرسی، نه فقط ولیدیتورها
    // ------------------------------------------------------------------

    /// @notice ثبت/به‌روزرسانی هویت خوداظهاری (فقط نام و نوع شخصیت). قابل‌فراخوانی توسط هر
    ///         آدرسی، هر زمان؛ فراخوانی دوباره هیچ‌کدام از فلگ‌های وریفای را ریست نمی‌کند.
    function registerIdentity(PersonType personType, string calldata name) external {
        require(bytes(name).length > 0, "IdentityRegistry: empty name");

        Identity storage id_ = identities[msg.sender];
        id_.registered = true;
        id_.personType = personType;
        id_.name = name;

        emit IdentityRegistered(msg.sender, personType, name);
    }

    /// @notice چک سطح صفر (دسترسی آزاد، بدون نیاز به ثبت‌نام دپ) — دقیقاً معادل بخش ۶-۱ SIP002:
    ///         «آیا این آدرس اصلاً هویتش را ثبت کرده؟» بدون افشای هیچ داده‌ی دیگری. آدرس‌های
    ///         مهاجرت‌کرده (`migratedTo != 0`) دیگر `true` برنمی‌گردانند — طبق بخش ۳.۴ سند فنی.
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
        return (id_.registered, id_.phoneVerified, id_.telegramVerified, id_.kycVerified);
    }

    // ------------------------------------------------------------------
    // وریفای — فقط identityOracle (سرویس آف‌چین Identity Service، جزئیات در
    // sur-identity-registry-spec.md)
    // ------------------------------------------------------------------

    function setPhoneVerified(address who, bool verified) external onlyIdentityOracle {
        identities[who].phoneVerified = verified;
        emit PhoneVerificationUpdated(who, verified);
    }

    function setTelegramVerified(address who, bool verified) external onlyIdentityOracle {
        identities[who].telegramVerified = verified;
        emit TelegramVerificationUpdated(who, verified);
    }

    /// @notice ثبت نتیجه‌ی eKYC کامل (تصویر شخص + کارت ملی + مشخصات شناسنامه‌ای + تطبیق چهره).
    ///         `commitment` یک هش نمکین (salted hash) از داده‌ی کامل تأییدشده است — **فقط**
    ///         برای اثبات عدم‌دستکاری در دعاوی حقوقی احتمالی آینده نگه‌داری می‌شود؛ هیچ تابع
    ///         on-chain‌ای هرگز از آن برای پاسخ به کوئری «تطبیق» استفاده نمی‌کند (آن عملیات
    ///         همیشه از طریق API آف‌چین Identity Service انجام می‌شود — بخش ۵،
    ///         sur-identity-registry-spec.md).
    function setKycVerified(address who, bool verified, bytes32 commitment) external onlyIdentityOracle {
        Identity storage id_ = identities[who];
        id_.kycVerified = verified;
        id_.kycCommitment = verified ? commitment : bytes32(0);
        emit KycVerificationUpdated(who, verified, id_.kycCommitment);
    }

    // ------------------------------------------------------------------
    // بازیابی هویت — جایگزین آنلاین بخش ۷/۸ SIP001 (گم‌شدن کلید / سوزاندن آدرس). فراخوانی این
    // تابع همیشه باید بعد از یک فرآیند احراز آف‌چین مستقل باشد (بخش ۳.۴ سند فنی): برای
    // کاربران فقط-موبایل/تلگرام، تکرار OTP کافی است؛ برای کاربران KYC‌شده، باید سرویس‌دهنده‌ی
    // eKYC تأیید کند سلفی جدید با بیومتریک قبلی همان کد ملی تطبیق دارد — نه یک ثبت‌نام تازه.
    // ------------------------------------------------------------------

    /// @notice انتقال کامل وضعیت هویت از یک آدرس قدیمی (گم‌شده/لو‌رفته) به یک آدرس جدید.
    ///         آدرس قدیمی برای همیشه «سوخته» می‌شود (`hasIdentity` برایش دیگر true برنمی‌گرداند)
    ///         ولی رکوردش (و مسئولیتش برای اقدامات قبلی) پاک نمی‌شود — فقط دیگر قابل‌استفاده نیست.
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
    // چرخش کلید — فقط بنیاد (نه هیأت‌مدیره‌ی ولیدیتورها)
    // ------------------------------------------------------------------
    function setIdentityOracle(address newOracle) external onlyFoundation {
        require(newOracle != address(0), "IdentityRegistry: zero oracle address");
        emit IdentityOracleUpdated(identityOracle, newOracle);
        identityOracle = newOracle;
    }
}
