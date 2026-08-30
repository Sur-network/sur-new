// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SurAddresses
/// @notice آدرس‌های ثابت و genesis-محور شش قرارداد ساختاری شبکه‌ی سور.
///         هر شش قرارداد مستقیماً در بخش `alloc` بلاک genesis دیپلوی می‌شوند (بایت‌کد + storage
///         مستقیم تزریق می‌شود، نه از طریق یک تراکنش دیپلوی معمولی — برای دستورالعمل دقیق به
///         "sur-contracts-deploy-notes.md" مراجعه کن). چون آدرس هر یک از این قراردادها از قبل
///         و پیش از شبیه‌سازی هر constructor‌ای مشخص است، هر قرارداد می‌تواند آدرس بقیه را
///         به‌صورت ثابت (constant) در سورس خودش هاردکد کند — بدون نیاز به یک مرحله‌ی اجرایی
///         "wire()" بعد از دیپلوی (روش قبلی پروژه، که الان کنار گذاشته شده).
///
///         این مقادیر بعد از تولید genesis نباید تغییر کنند — چون به‌صورت ثابت داخل بایت‌کد
///         تمام قراردادهای دیگر جاسازی شده‌اند، نه در یک state قابل‌تغییر.
library SurAddresses {
    /// @dev FoundationDAO — حکمرانی بنیاد سور (۱۵ عضو)
    address internal constant FOUNDATION_DAO = 0x1111111111111111111111111111111111111111;

    /// @dev BlockRewardDistributor — دریافت‌کننده‌ی بلاک‌ریوارد و فی به‌عنوان miningbeneficiary،
    ///      پرداخت‌کننده‌ی دوره‌ای به ولیدیتورها + ValidatorsTreasury
    address internal constant BLOCK_REWARD_DISTRIBUTOR = 0x2222222222222222222222222222222222222222;

    /// @dev ValidatorsRegistry — مرجع اجماع (getValidators()) و مرجع صلاحیت پرداخت
    ///      (isValidator()). این همان آدرسی است که باید به‌عنوان qbft.validatorcontractaddress
    ///      در genesis.json هم تنظیم شود.
    address internal constant VALIDATORS_REGISTRY = 0x3333333333333333333333333333333333333333;

    /// @dev ValidatorsBoard — هیأت کوچک منتخب/قابل‌عزل با اختیارات تفویضی محدود
    address internal constant VALIDATORS_BOARD = 0x4444444444444444444444444444444444444444;

    /// @dev ValidatorsTreasury — نگه‌دارنده و خرج‌کننده‌ی سهم ۵۰٪ ریوارد ولیدیتورها
    address internal constant VALIDATORS_TREASURY = 0x5555555555555555555555555555555555555555;

    /// @dev IdentityRegistry — ششمین قرارداد ساختاری (در یک بازنگری بعدی اضافه شد). مرجع واحد
    ///      هویت خوداظهاری (نام/نوع شخصیت) و وضعیت وریفای (موبایل/تلگرام/KYC کامل) برای
    ///      **کل کاربران شبکه**، نه فقط ولیدیتورها — به همین دلیل از ValidatorsRegistry
    ///      مستقل نگه داشته شده است.
    address internal constant IDENTITY_REGISTRY = 0x6666666666666666666666666666666666666666;
}
