// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ServiceStaking
/// @notice یک دفتر عمومی و قابل‌استفاده‌ی مجدد برای «استیک برای دسترسی به سرویس» — به
///         sur-tokenomics.md بخش ۱۰ برای جدول کامل تصمیمی که این قرارداد پیاده می‌کند مراجعه
///         کنید. این یک اسکلت پیش‌نویس اول است (مثل SurZether.sol)، نه یک قرارداد سخت‌شده و
///         آدیت‌شده — صراحتاً علامت‌گذاری شده که هنوز پیش از هر دیپلوی واقعی نیاز به بازبینی
///         طراحی دارد.
///
///         هدف: چند دپ/سرویس برنامه‌ریزی‌شده (نام‌گذاری، ثبت‌زمان، صدور مدرک، رجیستری
///         کسب‌وکار، سقف بالاتر Zether، یک لایه‌ی اعتبار) هرکدام نیاز دارند کاربر یا صادرکننده
///         مقداری سورن قفل کند برای دسترسی — ولی با قوانین متفاوت برای هر سرویس:
///           - نام‌گذاری: اجباری، تا هروقت نام نگه داشته شود، آزادسازی فوری در خروج.
///           - ثبت‌زمان: امتیازی اختیاری (سقف روزانه‌ی بالاتر)، آزادسازی فوری در خروج.
///           - صدور مدرک: اجباری (روی صادرکننده، نه دریافت‌کننده‌ی مدرک)، ۹۰ روز cooldown
///             خروج (برای بازبینی مدارک قبلاً صادرشده).
///           - رجیستری کسب‌وکار: اجباری (روی ثبت‌کننده)، ۹۰ روز cooldown خروج (همان استدلال،
///             پنجره‌ی بازبینی برای ثبت‌های قبلی).
///           - سقف بالاتر تراکنش محرمانه‌ی Zether: امتیازی اختیاری، ۷ روز cooldown خروج
///             (کوتاه‌تر از دوتای بالا چون این درباره‌ی سقف تراکنش است، نه ثبت هویت/رجیستری
///             که نیاز به پنجره‌ی بازبینی دارد).
///           - لایه‌ی اعتبار/رپوتیشن: خودِ مبلغ استیک‌شده امتیاز است (نه یه دروازه‌ی دودویی)،
///             با یک قفل اجباری حداقل ۹۰ روزه پیش از این‌که اصلاً بشود درخواست برداشت داد —
///             تا امتیاز نشان‌دهنده‌ی تعهد پایدار باشد، نه استیک-و-برداشت همان‌روز برای
///             بالابردن موقتی‌اش.
///
///         انتخاب طراحی، یک قرارداد عمومی، نه شش قرارداد اختصاصی: هر سرویس بالا به همان
///         پرایمیتیو تقلیل پیدا می‌کند («N سورن برای سرویس X قفل کن، بعد از cooldown Y آزادش
///         کن»)، فقط با مقادیر cooldown متفاوت و یک قانون خاص حداقل‌قفل برای رپوتیشن. به‌جای
///         پیاده‌سازی دوباره‌ی این الگوی قفل/آزادسازی شش‌بار (یا کپی‌پیست الگویی که در مدیریت
///         وثیقه‌ی ValidatorsRegistry از قبل اثبات شده)، این قرارداد یک‌بار و با پارامتر گرفتن
///         از یک enum به اسم ServiceId پیاده‌اش می‌کند. هر قرارداد مصرف‌کننده (یک
///         NamingService، CredentialRegistry، و غیره‌ی آینده) باید پیش از اعطای سرویس خودش،
///         `hasMinimumStake()` یا `stakeOf()` را به‌عنوان یک چک view فراخوانی کند — این
///         قرارداد نمی‌داند و اجرا نمی‌کند کدام سرویس‌ها «اجباری»اند؛ آن اجرا در منطق خودِ هر
///         قرارداد مصرف‌کننده زندگی می‌کند.
///
///         🔶 سؤالات طراحی باز (هنوز تصمیم گرفته نشده، به‌جای حدس‌زدن اینجا فهرست شده‌اند):
///           - مبلغ دقیق حداقل استیک برای هر سرویس (این قرارداد فقط cooldown و مدت حداقل‌قفل
///             رپوتیشن را اجرا می‌کند، نه اندازه‌ی حداقل استیک؛ آن یک تصمیم اقتصادی جداگانه و
///             هنوز باز است، احتمالاً برای هر سرویس متفاوت و شاید نیازمند حکمرانی به‌جای
///             هاردکدشدن اینجا).
///           - آیا withdrawalCooldown هر سرویس باید بعداً قابل‌حکمرانی شود (فعلاً در سازنده
///             هاردکد شده، مطابق الگوی کلی پروژه: «با یک پیش‌فرض هاردکدشده‌ی معقول شروع کن،
///             اگر لازم به تغییر بود با رأی کامل ولیدیتورها بازبینی کن» — مثلاً slashBps در
///             ValidatorsRegistry).
///           - آیا این قرارداد باید خودش genesis-injected باشد (هفتمین آدرس ساختاری) یا مثل
///             SurenSale معمولی دیپلوی شود. این پیش‌نویس الگوی SurenSale (دیپلوی معمولی،
///             سازنده‌ی واقعی، بدون ردیف alloc در genesis) را فرض می‌کند چون یک امکانات
///             اختیاری اکوسیستم است، نه زیرساخت اصلی شبکه.
contract ServiceStaking {
    enum ServiceId {
        Naming,           // اجباری، بدون مدت ثابت، آزادسازی فوری
        Timestamping,     // امتیازی اختیاری، آزادسازی فوری
        CredentialIssuer, // اجباری (روی صادرکننده)، ۹۰ روز cooldown خروج
        BusinessRegistry, // اجباری (روی ثبت‌کننده)، ۹۰ روز cooldown خروج
        ZetherLimit,      // امتیازی اختیاری، ۷ روز cooldown خروج
        Reputation        // مبلغ استیک = امتیاز؛ ۹۰ روز حداقل‌قفل اجباری پیش از هر درخواست برداشت
    }

    struct Stake {
        uint256 amount;
        uint256 stakedAt;              // زمان اولین استیک؛ فقط برای حداقل‌قفل رپوتیشن استفاده می‌شود
        uint256 withdrawalRequestedAt; // ۰ یعنی درخواست معلقی نیست؛ فقط وقتی cooldown > 0 استفاده می‌شود
    }

    /// @notice ثانیه‌هایی که باید بین درخواست برداشت و برداشت واقعی بگذرد، برای هر سرویس.
    ///         صفر یعنی «نیازی به مرحله‌ی درخواست نیست، withdraw() بلافاصله کار می‌کند.»
    mapping(ServiceId => uint256) public withdrawalCooldown;

    /// @notice کاربر => سرویس => اطلاعات استیک فعلی‌اش.
    mapping(address => mapping(ServiceId => Stake)) public stakes;

    event Staked(address indexed user, ServiceId indexed service, uint256 amount, uint256 newTotal);
    event WithdrawalRequested(address indexed user, ServiceId indexed service, uint256 availableAt);
    event Withdrawn(address indexed user, ServiceId indexed service, uint256 amount);

    constructor() {
        withdrawalCooldown[ServiceId.Naming] = 0;
        withdrawalCooldown[ServiceId.Timestamping] = 0;
        withdrawalCooldown[ServiceId.CredentialIssuer] = 90 days;
        withdrawalCooldown[ServiceId.BusinessRegistry] = 90 days;
        withdrawalCooldown[ServiceId.ZetherLimit] = 7 days;
        withdrawalCooldown[ServiceId.Reputation] = 0; // بدون cooldown بعد از درخواست؛ قانون ۹۰
        // روزه‌ی رپوتیشن یک حداقل‌قفل پیش از این‌که اصلاً درخواست مجاز باشد است (پایین را
        // ببین)، مکانیزمی متفاوت از cooldown «الان درخواست بده، صبر کن، بعد بردار» بقیه‌ی
        // سرویس‌ها.
    }

    /// @notice قفل‌کردن مقدار بیشتری سورن برای یک سرویس مشخص. تکرارپذیر؛ استیک‌های اضافه
    ///         صرفاً به مبلغ موجود اضافه می‌شوند. استیک‌کردن بیشتر همچنین هر درخواست برداشت
    ///         معلق برای همان سرویس را لغو می‌کند (نمی‌شود هم‌زمان «استیک اضافه می‌کنم» و
    ///         «دارم خارج می‌شوم» بود).
    function stake(ServiceId service) external payable {
        require(msg.value > 0, "ServiceStaking: zero stake amount");

        Stake storage s = stakes[msg.sender][service];
        // ✅ اصلاح‌شده (اکسپلویت بحرانی پیداشده در بازبینی): قبلاً `stakedAt` فقط در **اولین**
        // استیک (وقتی s.amount صفر بود) تنظیم می‌شد — یعنی یه top-up بعد از این‌که قفل ۹۰روزه‌ی
        // اصلی Reputation از قبل تموم شده بود، ساعت رو ریست نمی‌کرد؛ پس یه کاربر می‌تونست یه
        // مقدار ناچیز استیک کنه، ۹۰ روز صبر کنه، بعد با یه مبلغ بزرگ top-up کنه و بلافاصله کل
        // مبلغ رو برداره، چون چک قفل فقط تایم‌استمپ همون استیک اولیه‌ی ناچیز رو می‌دید. اصلاح:
        // برای Reputation به‌طور خاص، **هر** فراخوان stake() (چه top-up چه اولین‌بار) `stakedAt`
        // رو به همین لحظه ریست می‌کنه، یعنی قفل ۹۰روزه برای کل موجودی تازه از نو شروع می‌شه —
        // چون کل فلسفه‌ی طراحی Reputation اینه که «وزن/قفل باید مقدار *فعلی* استیک‌شده رو منعکس
        // کنه»، پس یه top-up نباید یه قفل از قبل منقضی‌شده‌ی مال یه استیک قبلی خیلی کوچیک‌تر رو
        // به ارث ببره. سایر سرویس‌ها اصلاً از stakedAt برای هیچی استفاده نمی‌کنن (cooldownشون
        // از withdrawalRequestedAt محاسبه می‌شه)، پس این تغییر براشون بی‌اثره.
        if (service == ServiceId.Reputation) {
            s.stakedAt = block.timestamp;
        } else if (s.amount == 0) {
            s.stakedAt = block.timestamp;
        }
        s.amount += msg.value;
        s.withdrawalRequestedAt = 0;

        emit Staked(msg.sender, service, msg.value, s.amount);
    }

    /// @notice پیش از withdraw() برای هر سرویسی با cooldown غیرصفر (صدور مدرک، رجیستری
    ///         کسب‌وکار، سقف Zether) لازم است. برای سرویس‌های با cooldown صفر (نام‌گذاری،
    ///         ثبت‌زمان) لازم نیست، و اصلاً revert می‌شود؛ آن‌ها مستقیم withdraw می‌کنند.
    ///         برای رپوتیشن، این تابع اضافه‌بر آن، حداقل‌قفل ۹۰روزه را هم اجرا می‌کند.
    function requestWithdrawal(ServiceId service) external {
        Stake storage s = stakes[msg.sender][service];
        require(s.amount > 0, "ServiceStaking: no stake to withdraw");
        require(withdrawalCooldown[service] > 0, "ServiceStaking: this service has no cooldown, call withdraw() directly");

        s.withdrawalRequestedAt = block.timestamp;
        emit WithdrawalRequested(msg.sender, service, block.timestamp + withdrawalCooldown[service]);
    }

    /// @notice کل استیک فراخوان را برای یک سرویس برمی‌گرداند. رفتار بسته به cooldown سرویس
    ///         فرق دارد:
    ///           - cooldown صفر (نام‌گذاری، ثبت‌زمان، رپوتیشن): بلافاصله کار می‌کند، بدون نیاز
    ///             به فراخوانی قبلی requestWithdrawal() — به‌جز رپوتیشن، که همچنان حداقل‌قفل
    ///             ۹۰روزه‌ی خودش را از زمان اولین استیک اجرا می‌کند، مستقل از مکانیزم cooldown
    ///             (که صفر است).
    ///           - cooldown غیرصفر (صدور مدرک، رجیستری کسب‌وکار، سقف Zether): نیازمند
    ///             فراخوانی قبلی requestWithdrawal() و گذشتن cooldown آن است.
    function withdraw(ServiceId service) external {
        Stake storage s = stakes[msg.sender][service];
        require(s.amount > 0, "ServiceStaking: no stake");

        uint256 cooldown = withdrawalCooldown[service];
        if (cooldown > 0) {
            require(s.withdrawalRequestedAt > 0, "ServiceStaking: call requestWithdrawal first");
            require(block.timestamp >= s.withdrawalRequestedAt + cooldown, "ServiceStaking: cooldown not elapsed");
        }

        if (service == ServiceId.Reputation) {
            require(block.timestamp >= s.stakedAt + 90 days, "ServiceStaking: reputation stake still in its 90-day minimum lock");
        }

        uint256 amount = s.amount;
        s.amount = 0;
        s.stakedAt = 0;
        s.withdrawalRequestedAt = 0;

        emit Withdrawn(msg.sender, service, amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ServiceStaking: transfer failed");
    }

    // ------------------------------------------------------------------
    // توابع کمکی view — برای قراردادهای مصرف‌کننده (NamingService، CredentialRegistry، و
    // غیره) و داشبوردهای آف‌چین.
    // ------------------------------------------------------------------

    function stakeOf(address user, ServiceId service) external view returns (uint256) {
        return stakes[user][service].amount;
    }

    /// @notice چک راحت برای دروازه‌ی «آیا این آدرس مجاز به استفاده از سرویس من است»ِ خودِ
    ///         قرارداد مصرف‌کننده — مثلاً `require(serviceStaking.hasMinimumStake(msg.sender,
    ///         ServiceId.BusinessRegistry, MIN_REGISTRANT_STAKE), ...)`. این قرارداد تعریف
    ///         نمی‌کند `minAmount` برای هیچ سرویسی چقدر باید باشد؛ آن تصمیم خودِ هر قرارداد
    ///         مصرف‌کننده است (به سؤالات طراحی باز در کامنت هدر مراجعه کنید).
    function hasMinimumStake(address user, ServiceId service, uint256 minAmount) external view returns (bool) {
        return stakes[user][service].amount >= minAmount;
    }
}
