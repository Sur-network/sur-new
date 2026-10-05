// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ServiceStaking
/// @notice دفتر عمومی و قابل‌استفادهٔ مجدد «استیک برای دسترسی به سرویس» — جدول تصمیم کامل را در sur-tokenomics.md
///         بخش ۱۰ ببینید. وضعیت: اسکلت پیش‌نویس، نه قرارداد سخت‌شده یا ممیزی‌شده؛ پیش از هر استقرار واقعی بازبینی طراحی می‌خواهد.
///
///         هدف: چند dApp / سرویس برنامه‌ریزی‌شده (نام‌گذاری، مهرزمانی، صدور مدرک، ثبت کسب‌وکار، سقف‌های بالاتر Zether، لایهٔ
///         اعتبار) هر کدام می‌خواهند کاربر یا صادرکننده مقداری سورن را برای دسترسی قفل کند — ولی با قواعد متفاوت برای هر سرویس:
///           - نام‌گذاری: اجباری، تا وقتی نام نگه داشته می‌شود، آزادسازی فوری هنگام خروج.
///           - مهرزمانی: مزیت اختیاری (سهمیهٔ روزانهٔ بالاتر)، آزادسازی فوری هنگام خروج.
///           - صدور مدرک: اجباری (روی صادرکننده، نه دریافت‌کنندهٔ مدرک)، دورهٔ انتظار ۹۰روزه هنگام خروج (برای فرصت بازبینی
///             مدارک صادرشده).
///           - ثبت کسب‌وکار: اجباری (روی ثبت‌کننده)، دورهٔ انتظار ۹۰روزه هنگام خروج (با همان استدلال — پنجرهٔ بازبینی برای
///             ورودی‌های انجام‌شده).
///           - سقف بالاتر تراکنش محرمانهٔ Zether: مزیت اختیاری، دورهٔ انتظار ۷روزه هنگام خروج (کوتاه‌تر از دو مورد بالا چون
///             دربارهٔ سقف تراکنش است، نه ورودی‌های هویتی/ثبتی که پنجرهٔ بازبینی می‌خواهند).
///           - لایهٔ اعتبار: خودِ مقدار استیک همان امتیاز است (نه یک دروازهٔ دودویی) — با حداقل قفل اجباری ۹۰روزه پیش از آنکه
///             حتی بشود درخواست برداشت داد، تا امتیاز تعهد پایدار را نشان دهد، نه استیک‌گذاری و برداشت هم‌روزی برای باد‌کردن
///             موقت آن.
///
///         انتخاب طراحی — یک قرارداد عمومی، نه شش قرارداد جدا: هر سرویس بالا به همان ابتدایی‌ترین عمل برمی‌گردد («N سورن را
///         برای سرویس X قفل کن، پس از دورهٔ Y آزاد کن»)، فقط با مقادیر دورهٔ متفاوت و یک قاعدهٔ حداقل‌قفل ویژه برای Reputation.
///         به‌جای پیاده‌سازی شش‌باره (یا کپی الگوی اثبات‌شده در مدیریت وثیقهٔ ValidatorsRegistry)، این قرارداد آن را یک‌بار و
///         پارامتری با enum ServiceId پیاده می‌کند. هر قرارداد مصرف‌کننده (NamingService، CredentialRegistry و غیره در آینده) باید
///         پیش از دادن سرویس خودش `hasMinimumStake()` یا `stakeOf()` را به‌صورت view چک کند — این قرارداد نمی‌داند و اعمال نمی‌کند
///         کدام سرویس‌ها «اجباری»اند؛ آن اعمال در منطق خود هر قرارداد مصرف‌کننده است.
///
///         پرسش‌های باز طراحی:
///           - مقدار دقیق حداقل استیک برای هر سرویس (این قرارداد فقط دوره‌های انتظار و مدت حداقل‌قفل Reputation را اعمال می‌کند،
///             نه اندازهٔ حداقل استیک؛ آن‌ها تصمیم اقتصادی جدا و هنوز باز است، احتمالاً برای هر سرویس متفاوت و شاید نیازمند
///             حکمرانی به‌جای هاردکد در اینجا).
///           - آیا withdrawalCooldown هر سرویس باید بعداً حکمرانی‌پذیر شود (فعلاً در constructor هاردکد است، مطابق الگوی کلی
///             این پروژه: «با یک پیش‌فرض معقول هاردکد عرضه کن و اگر لازم شد با رأی کامل ولیدیتورها بازبینی کن» — مثلاً slashBps در
///             ValidatorsRegistry را ببینید).
///           - آیا خود این قرارداد باید در genesis تزریق شود (آدرس ساختاری هفتم) یا مثل SurenSale عادی مستقر شود. این پیش‌نویس
///             الگوی SurenSale را فرض می‌کند (استقرار عادی، constructor واقعی، بدون ورودی `alloc` در genesis)، چون یک راحتی
///             اختیاری اکوسیستم است، نه زیرساخت هستهٔ شبکه.
///
///         تضمین لحظه‌ای: برای سرویسی با دورهٔ انتظار صفر (نام‌گذاری، مهرزمانی) می‌شود استیک را در یک تراکنش اضافه و برداشت کرد، پس
///         `hasMinimumStake` فقط ثابت می‌کند فراخواننده همین لحظه آن استیک را نگه داشته است. قرارداد مصرف‌کننده‌ای که تضمین پیوسته
///         می‌خواهد باید سرویسی با دورهٔ انتظار ناصفر به کار ببرد یا قاعدهٔ نگه‌داشتن خودش را اضافه کند. استیکی که درخواست برداشتش
///         ثبت شده در `hasMinimumStake` شمرده نمی‌شود.
contract ServiceStaking {
    enum ServiceId {
        Naming,  // اجباری، بدون مدت ثابت، آزادسازی فوری
        Timestamping,  // امتیازی اختیاری، آزادسازی فوری
        CredentialIssuer,  // اجباری (روی صادرکننده)، ۹۰ روز cooldown خروج
        BusinessRegistry,  // اجباری (روی ثبت‌کننده)، ۹۰ روز cooldown خروج
        ZetherLimit,  // امتیازی اختیاری، ۷ روز cooldown خروج
        Reputation  // مبلغ استیک = امتیاز؛ ۹۰ روز حداقل‌قفل اجباری پیش از هر درخواست برداشت
    }

    struct Stake {
        uint256 amount;
        uint256 stakedAt;  // زمان اولین استیک؛ فقط برای حداقل‌قفل رپوتیشن استفاده می‌شود
        uint256 withdrawalRequestedAt;  // ۰ یعنی درخواست معلقی نیست؛ فقط وقتی cooldown > 0 استفاده می‌شود
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
        withdrawalCooldown[ServiceId.Reputation] = 0;  // بدون cooldown بعد از درخواست؛ قانون ۹۰
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
        // Reputation: هر فراخوان stake() (اولین یا افزایشی) قفل ۹۰روزه را برای کل موجودی تازه از نو شروع می‌کند، چون وزن و قفل
        // مقدار استیکِ فعلی را منعکس می‌کنند؛ افزایش نباید قفل منقضی‌شدهٔ یک استیک کوچک‌تر قبلی را به ارث ببرد. سرویس‌های
        // دیگر از stakedAt استفاده نمی‌کنند (دورهٔ انتظارشان از withdrawalRequestedAt می‌شمارد).
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

    /// @notice بررسی راحت برای دروازهٔ «آیا این آدرس مجاز به استفاده از سرویس من است» در قرارداد مصرف‌کننده (تا وقتی درخواست
    ///         برداشت در انتظار است false) — مثلاً `require(serviceStaking.hasMinimumStake(msg.sender,
    ///         ServiceId.BusinessRegistry, MIN_REGISTRANT_STAKE), ...)`. این قرارداد تعیین نمی‌کند `minAmount` برای هر سرویس
    ///         چقدر باشد — آن تصمیم خودِ هر قرارداد مصرف‌کننده است (پرسش‌های باز در کامنت سرآیند را ببینید).
    function hasMinimumStake(address user, ServiceId service, uint256 minAmount) external view returns (bool) {
        Stake storage s = stakes[user][service];
        if (s.withdrawalRequestedAt != 0) return false;  // استیکی که در حال برداشت است دیگر شمرده نمی‌شود
        return s.amount >= minAmount;
    }
}
