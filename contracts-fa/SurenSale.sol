// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IFoundationCeo {
    function ceo() external view returns (address);
}

/// @title SurenSale
/// @notice قرارداد فروش سورن بنیاد سور (v2.5): دوره‌ی قیمت ثابت ۹۰ روزه، سپس یک دوره‌ی گذار ۴۵ روزه
///         مبتنی بر حجم؛ «تنها» کانال فروش صرافی‌های دارای مجوز است.
///         به offchain-services/sur-suren-sale-spec.md مراجعه کن.
///
///         فروش چگونه کار می‌کند: مشتری تومان را به یک صرافی دارای مجوز می‌پردازد و آن صرافی
///         `sellTo(customer, tomanAmount, minSurenOut, reference)` را صدا می‌زند. قرارداد قیمت را
///         «خودش» از `block.timestamp` و پارامترهای خودش حساب می‌کند — صرافی فقط می‌تواند یک فروش را،
///         تا سقف سهمیه‌ی خودش، به قیمت رسمی همان لحظه ادعا کند؛ هرگز نمی‌تواند قیمت را پایین بیاورد.
///         `minSurenOut` وقتی قیمت بالا می‌رود از مشتری (و صرافی) محافظت می‌کند.
///
///         بدون oracle: `paymentOracle` / `reportPayment` سابق در v2.2 حذف شده است.
///
///         قرارداد genesis «نیست»: هر وقت بنیاد آماده باشد با یک تراکنش معمولی مستقر می‌شود؛ فقط به
///         آدرس ثابت FoundationDAO وابسته است (برای مدیرعامل و تصمیم‌های هیأت). بنیاد آدرس را با
///         پیشنهاد SetSaleContract به FoundationDAO اعلام می‌کند.
///
///         امنیت: بنیاد باید این قرارداد را دوره‌ای شارژ کند، نه یک‌جا، تا زیان ناشی از هک کلید یک
///         صرافی همیشه به سهمیه‌ی همان صرافی محدود بماند.
///
///         🔶 مفروضاتی که مشخصات هنوز درباره‌شان باز است (عمداً دیده می‌مانند): تمدیدها فقط پیش از پایان
///         دوره‌ی مربوط ممکن‌اند؛ تمدید دوره‌ی گذار همان قاعده‌ی حجم روزانه را ادامه می‌دهد؛ تسویه‌ی
///         تومانی بین صرافی و بنیاد خارج از زنجیره است.
contract SurenSale {
    // ------------------------------------------------------------------
    // آدرس ثابت (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // برنامه‌ی زمانی
    // ------------------------------------------------------------------
    /// @notice قیمت هر سورن به تومان برای ماه‌های ۱ تا ۳ دوره‌ی ثابت (هر ۳۰ روز ۵ تومان اضافه می‌شود).
    uint256[3] public monthlyPriceToman = [uint256(100), 105, 110];

    uint256 public constant BASE_FIXED_DURATION = 90 days;
    uint256 public constant SECONDS_PER_MONTH = 30 days;
    uint256 public constant TRANSITION_DURATION = 45 days;
    uint256 public constant TRANSITION_PRICE_STEP_BPS = 50; // ±۰٫۵٪ در روز
    uint256 public constant TRANSITION_HIGH_VOLUME_BPS = 12000; // ۱۲۰٪ میانگین متحرک ۷روزه
    uint256 public constant TRANSITION_LOW_VOLUME_BPS = 8000; // ۸۰٪ میانگین متحرک ۷روزه
    uint256 public constant TRANSITION_FLOOR_TOMAN = 90;
    uint256 public constant TRANSITION_CEILING_TOMAN = 150;
    uint256 public constant MOVING_AVERAGE_WINDOW_DAYS = 7;
    /// @notice دقت داخلی قیمت: قیمت‌ها به‌صورت میلی‌تومان (تومان × ۱۰۰۰) ذخیره می‌شوند.
    uint256 public constant PRICE_PRECISION = 1000;
    uint256 private constant BPS_DENOMINATOR = 10000;
    /// @notice محافظ اشتباه تایپی برای یک فراخوان تمدید (تعداد کل تمدیدها نامحدود است).
    uint256 public constant MAX_EXTENSION_DAYS_PER_CALL = 3650;
    /// @notice سپرده‌ی gas که هنگام ثبت‌نام به حساب یک صرافی فرستاده می‌شود (تصمیم ۲۰۲۶-۱۱-۱۹: ۱۰۰ سورن).
    uint256 public constant GAS_DEPOSIT = 100 ether;

    uint256 public immutable saleStartTime;

    /// @dev بخش‌های قیمتیِ اضافه‌شده با تمدید مدیرعامل در دوره‌ی ثابت، به‌ترتیب و پیوسته:
    ///      بخش i بازه‌ی [پایان قبلی، end) را با قیمت `priceMilli` پوشش می‌دهد.
    struct Segment {
        uint256 end;
        uint256 priceMilli;
    }
    Segment[] private _segments;
    /// @notice پایان دوره‌ی قیمت ثابت، شامل همه‌ی تمدیدها.
    uint256 public fixedEnd;
    /// @notice روزهای اضافه‌ای که مدیرعامل به دوره‌ی گذار افزوده است.
    uint256 public transitionExtraDays;

    // state دوره‌ی گذار
    uint256 public transitionPriceMilliToman;
    uint256 public lastPricedTransitionDay;
    mapping(uint256 => uint256) public transitionDailyVolumeSuren;

    /// @notice توسط FoundationDAO تنظیم می‌شود (پیشنهاد EndSale): فروش متوقف می‌شود و باقی‌مانده قابل جمع‌آوری است.
    bool public saleEnded;

    // ------------------------------------------------------------------
    // صرافی‌ها
    // ------------------------------------------------------------------
    enum ExchangeStatus { None, Active, Paused, Removed }

    struct Exchange {
        ExchangeStatus status;
        uint256 id; // همراه صرافی در تغییر کلیدها می‌ماند؛ کلید مجموعه‌ی مرجع‌های هر صرافی است
        string name;
        uint256 quota; // کل سورنی که این صرافی اجازه‌ی فروشش را دارد (شامل آنچه قبلاً فروخته)
        uint256 sold; // سورن
        uint256 tomanReceived;
        uint256 salesCount;
        uint256 lastSaleAt;
    }

    mapping(address => Exchange) private _ex;
    address[] private _exchangeList;
    uint256 public exchangeCount; // شناسه‌هایی که تا الان داده شده‌اند
    mapping(uint256 => mapping(bytes32 => bool)) private _usedReference; // شناسه‌ی صرافی => مرجع

    /// @notice کل سورنی که همه‌ی صرافی‌ها روی هم اجازه‌ی فروشش را دارند. تا وقتی هیأت آن را تنظیم نکند ۰ است،
    ///         پس پیش از تصمیم بنیاد درباره‌ی سقف هیچ فروشی انجام نمی‌شود.
    uint256 public totalCap;
    uint256 public totalSurenSold;
    uint256 public totalTomanReceived;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event Funded(address indexed from, uint256 amount);
    event ExchangeRegistered(address indexed account, uint256 indexed id, string name, uint256 quota, uint256 gasDeposit);
    event ExchangeQuotaChanged(address indexed account, uint256 newQuota);
    event ExchangeKeyChanged(address indexed oldAccount, address indexed newAccount, uint256 indexed id);
    event ExchangePaused(address indexed account);
    event ExchangeResumed(address indexed account);
    event ExchangeRemoved(address indexed account);
    event TotalCapChanged(uint256 newCap);
    event SaleExecuted(
        address indexed exchange,
        address indexed customer,
        uint256 tomanAmount,
        uint256 surenAmount,
        uint256 priceMilliToman,
        bytes32 orderRef
    );
    event FixedPeriodExtended(uint256 extraDays, uint256 newEnd, uint256 priceToman);
    event TransitionExtended(uint256 extraDays, uint256 newEnd);
    event SaleEnded();
    event UnsoldSurenSweeped(address indexed to, uint256 amount);
    event TransitionPriceUpdated(
        uint256 indexed dayIndex,
        uint256 dayVolumeSuren,
        uint256 movingAverageSuren,
        uint256 newPriceMilliToman,
        uint256 newPriceToman
    );

    modifier onlyFoundation() {
        require(msg.sender == FOUNDATION, "SurenSale: caller is not the Foundation");
        _;
    }

    modifier onlyCeo() {
        address c = IFoundationCeo(FOUNDATION).ceo();
        require(c != address(0) && msg.sender == c, "SurenSale: caller is not the CEO");
        _;
    }

    constructor() {
        saleStartTime = block.timestamp;
        fixedEnd = block.timestamp + BASE_FIXED_DURATION;
    }

    /// @notice شارژ. بنیاد سورن را از خزانه‌ی خودش می‌پردازد (پیشنهاد Spend).
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // ==================================================================
    //  دوره‌ها و قیمت
    // ==================================================================
    enum Period { FixedPrice, Transition, Ended }

    function transitionStartTime() public view returns (uint256) { return fixedEnd; }

    function transitionEndTime() public view returns (uint256) {
        return fixedEnd + TRANSITION_DURATION + transitionExtraDays * 1 days;
    }

    function isFixedActive() public view returns (bool) {
        return !saleEnded && block.timestamp < fixedEnd;
    }

    function isTransitionActive() public view returns (bool) {
        return !saleEnded && block.timestamp >= fixedEnd && block.timestamp < transitionEndTime();
    }

    function isSaleActive() public view returns (bool) {
        return isFixedActive() || isTransitionActive();
    }

    function currentPeriod() public view returns (Period) {
        if (isFixedActive()) return Period.FixedPrice;
        if (isTransitionActive()) return Period.Transition;
        return Period.Ended;
    }

    /// @notice آخرین قیمت دوره‌ی ثابت (قیمت شروع گذار) به میلی‌تومان.
    function lastFixedPriceMilli() public view returns (uint256) {
        if (_segments.length > 0) return _segments[_segments.length - 1].priceMilli;
        return monthlyPriceToman[2] * PRICE_PRECISION;
    }

    /// @notice قیمت رسمی به میلی‌تومان (تومان × ۱۰۰۰) — مقدار دقیقی که در تسویه استفاده می‌شود.
    function currentPriceMilliToman() public view returns (uint256) {
        uint256 t = block.timestamp;
        if (t < fixedEnd) return _fixedPriceAt(t);
        return transitionPriceMilliToman == 0 ? _clampToBand(lastFixedPriceMilli()) : transitionPriceMilliToman;
    }

    /// @notice قیمت گردشده فقط برای نمایش؛ هرگز در محاسبات از آن استفاده نکن.
    function currentPriceToman() public view returns (uint256) {
        return currentPriceMilliToman() / PRICE_PRECISION;
    }

    function _fixedPriceAt(uint256 t) private view returns (uint256) {
        uint256 baseEnd = saleStartTime + BASE_FIXED_DURATION;
        if (t < baseEnd) {
            uint256 month = (t - saleStartTime) / SECONDS_PER_MONTH;
            if (month > 2) month = 2;
            return monthlyPriceToman[month] * PRICE_PRECISION;
        }
        for (uint256 i = 0; i < _segments.length; i++) {
            if (t < _segments[i].end) return _segments[i].priceMilli;
        }
        return lastFixedPriceMilli();
    }

    function segmentCount() external view returns (uint256) { return _segments.length; }

    function segmentAt(uint256 i) external view returns (uint256 end, uint256 priceMilli) {
        return (_segments[i].end, _segments[i].priceMilli);
    }

    // ------------------------------------------------------------------
    // مدیرعامل: تمدیدها (در مجموع نامحدود؛ قیمت یک دوره‌ی ثابتِ تمدیدشده را مدیرعامل تعیین می‌کند و ثابت می‌ماند)
    // ------------------------------------------------------------------
    /// @param extraDays تعداد روزهای افزوده‌شده به دوره‌ی قیمت ثابت
    /// @param priceToman قیمت (تومان صحیح) دقیقاً برای همین روزهای افزوده‌شده
    function extendFixedPeriod(uint256 extraDays, uint256 priceToman) external onlyCeo {
        require(!saleEnded && block.timestamp < fixedEnd, "SurenSale: fixed period already over");
        require(extraDays > 0 && extraDays <= MAX_EXTENSION_DAYS_PER_CALL, "SurenSale: bad extension length");
        require(priceToman > 0, "SurenSale: zero price");
        fixedEnd += extraDays * 1 days;
        _segments.push(Segment(fixedEnd, priceToman * PRICE_PRECISION));
        emit FixedPeriodExtended(extraDays, fixedEnd, priceToman);
    }

    function extendTransition(uint256 extraDays) external onlyCeo {
        require(!saleEnded && block.timestamp < transitionEndTime(), "SurenSale: transition already over");
        require(extraDays > 0 && extraDays <= MAX_EXTENSION_DAYS_PER_CALL, "SurenSale: bad extension length");
        transitionExtraDays += extraDays;
        emit TransitionExtended(extraDays, transitionEndTime());
    }

    // ------------------------------------------------------------------
    // قیمت گذار: بدون نیاز به مجوز، جبران محدود (در آغاز هر فروش هم اجرا می‌شود)
    // ------------------------------------------------------------------
    function currentTransitionDay() public view returns (uint256) {
        return (block.timestamp - fixedEnd) / 1 days;
    }

    /// @dev بازهٔ ۹۰ تا ۱۵۰ تومان در دوره‌ی گذار «مطلق» است: قیمتی که هر فروشِ دوره‌ی گذار به کار می‌برد همیشه درون
    ///      [TRANSITION_FLOOR_TOMAN, TRANSITION_CEILING_TOMAN] است. قیمت تمدیدِ CEO برای دوره‌ی ثابت آزاد می‌ماند (تصمیم)، پس آخرین
    ///      قیمت ثابت می‌تواند بیرون از بازه باشد؛ در این حالت دوره‌ی گذار از نزدیک‌ترین سرِ بازه شروع می‌شود.
    function _clampToBand(uint256 priceMilli) private pure returns (uint256) {
        uint256 floorMilli = TRANSITION_FLOOR_TOMAN * PRICE_PRECISION;
        uint256 ceilingMilli = TRANSITION_CEILING_TOMAN * PRICE_PRECISION;
        if (priceMilli < floorMilli) return floorMilli;
        if (priceMilli > ceilingMilli) return ceilingMilli;
        return priceMilli;
    }

    function advanceTransitionPrice() public {
        if (block.timestamp < fixedEnd) return;
        if (transitionPriceMilliToman == 0) {
            transitionPriceMilliToman = _clampToBand(lastFixedPriceMilli()); // با آخرین قیمت دوره‌ی ثابت، گیرکرده در بازه، مقداردهی اولیه شده
        }
        uint256 maxDay = (TRANSITION_DURATION + transitionExtraDays * 1 days) / 1 days;
        uint256 today = currentTransitionDay();
        if (today > maxDay) today = maxDay;

        while (lastPricedTransitionDay < today) {
            uint256 dayIndex = lastPricedTransitionDay;
            uint256 dayVolume = transitionDailyVolumeSuren[dayIndex];
            uint256 avg = _movingAverage(dayIndex);
            if (avg > 0) {
                uint256 step = (transitionPriceMilliToman * TRANSITION_PRICE_STEP_BPS) / BPS_DENOMINATOR;
                if (dayVolume > (avg * TRANSITION_HIGH_VOLUME_BPS) / BPS_DENOMINATOR) {
                    transitionPriceMilliToman = transitionPriceMilliToman + step;
                } else if (dayVolume < (avg * TRANSITION_LOW_VOLUME_BPS) / BPS_DENOMINATOR) {
                    transitionPriceMilliToman = transitionPriceMilliToman > step ? transitionPriceMilliToman - step : 0;
                }
            }
            transitionPriceMilliToman = _clampToBand(transitionPriceMilliToman); // بعد از «هر» روز، هرچه شده باشد (روز ۰ و روزهای خنثی هم)
            emit TransitionPriceUpdated(dayIndex, dayVolume, avg, transitionPriceMilliToman, transitionPriceMilliToman / PRICE_PRECISION);
            lastPricedTransitionDay++;
        }
    }

    function _movingAverage(uint256 uptoExclusiveDay) private view returns (uint256) {
        if (uptoExclusiveDay == 0) return 0;
        uint256 windowStart = uptoExclusiveDay > MOVING_AVERAGE_WINDOW_DAYS ? uptoExclusiveDay - MOVING_AVERAGE_WINDOW_DAYS : 0;
        uint256 count = uptoExclusiveDay - windowStart;
        uint256 sum;
        for (uint256 d = windowStart; d < uptoExclusiveDay; d++) sum += transitionDailyVolumeSuren[d];
        return sum / count;
    }

    // ==================================================================
    //  صرافی‌ها — با FoundationDAO مدیریت می‌شوند (پیشنهادهای تایپ‌شده، ۳ از ۵)
    // ==================================================================
    function registerExchange(address account, string calldata name, uint256 quota) external onlyFoundation {
        require(account != address(0), "SurenSale: zero account");
        require(_ex[account].status == ExchangeStatus.None, "SurenSale: account already used");
        require(bytes(name).length > 0, "SurenSale: empty name");
        require(address(this).balance >= GAS_DEPOSIT, "SurenSale: balance below gas deposit");
        uint256 id = ++exchangeCount;
        Exchange storage e = _ex[account];
        e.status = ExchangeStatus.Active;
        e.id = id;
        e.name = name;
        e.quota = quota;
        _exchangeList.push(account);
        emit ExchangeRegistered(account, id, name, quota, GAS_DEPOSIT);
        // سپرده از موجودی قرارداد خارج می‌شود و بیرون از سهمیه است
        (bool ok, ) = account.call{value: GAS_DEPOSIT}("");
        require(ok, "SurenSale: gas deposit failed");
    }

    function setExchangeQuota(address account, uint256 newQuota) external onlyFoundation {
        Exchange storage e = _ex[account];
        require(e.status == ExchangeStatus.Active || e.status == ExchangeStatus.Paused, "SurenSale: no such exchange");
        require(newQuota >= e.sold, "SurenSale: quota below what is already sold");
        e.quota = newQuota;
        emit ExchangeQuotaChanged(account, newQuota);
    }

    /// @notice یک صرافی (سهمیه‌ی باقی‌مانده، آمار، مرجع‌های مصرف‌شده، وضعیت) را به حساب جدید منتقل می‌کند.
    function changeExchangeKey(address oldAccount, address newAccount) external onlyFoundation {
        Exchange storage o = _ex[oldAccount];
        require(o.status == ExchangeStatus.Active || o.status == ExchangeStatus.Paused, "SurenSale: no such exchange");
        require(newAccount != address(0) && _ex[newAccount].status == ExchangeStatus.None, "SurenSale: new account already used");
        _ex[newAccount] = o;
        delete _ex[oldAccount];
        _ex[oldAccount].status = ExchangeStatus.Removed;
        for (uint256 i = 0; i < _exchangeList.length; i++) {
            if (_exchangeList[i] == oldAccount) { _exchangeList[i] = newAccount; break; }
        }
        emit ExchangeKeyChanged(oldAccount, newAccount, _ex[newAccount].id);
    }

    /// @notice توقف فوری یک صرافی (FoundationDAO.pauseExchange: مدیرعامل یا هر عضو اصلی هیأت به‌تنهایی).
    function pauseExchange(address account) external onlyFoundation {
        require(_ex[account].status == ExchangeStatus.Active, "SurenSale: exchange not active");
        _ex[account].status = ExchangeStatus.Paused;
        emit ExchangePaused(account);
    }

    function resumeExchange(address account) external onlyFoundation {
        require(_ex[account].status == ExchangeStatus.Paused, "SurenSale: exchange not paused");
        _ex[account].status = ExchangeStatus.Active;
        emit ExchangeResumed(account);
    }

    function removeExchange(address account) external onlyFoundation {
        ExchangeStatus s = _ex[account].status;
        require(s == ExchangeStatus.Active || s == ExchangeStatus.Paused, "SurenSale: no such exchange");
        _ex[account].status = ExchangeStatus.Removed;
        emit ExchangeRemoved(account);
    }

    function setTotalCap(uint256 cap) external onlyFoundation {
        totalCap = cap;
        emit TotalCapChanged(cap);
    }

    // ==================================================================
    //  تنها تابعی که سورن را به مشتریان منتقل می‌کند
    // ==================================================================
    /// @param customer سورن را مستقیماً دریافت می‌کند
    /// @param tomanAmount تومانی که صرافی از مشتری گرفته (تومان صحیح)
    /// @param minSurenOut حداقل سورنی که مشتری باید بگیرد؛ کمتر => revert
    /// @param orderRef شناسه‌ی سفارش، یکتا در هر صرافی
    function sellTo(address customer, uint256 tomanAmount, uint256 minSurenOut, bytes32 orderRef) external {
        Exchange storage e = _ex[msg.sender];
        require(e.status == ExchangeStatus.Active, "SurenSale: caller is not an active exchange");
        require(isSaleActive(), "SurenSale: sale is not active");
        require(customer != address(0), "SurenSale: zero customer");
        require(tomanAmount > 0, "SurenSale: zero amount");
        require(!_usedReference[e.id][orderRef], "SurenSale: reference already used");

        if (isTransitionActive()) advanceTransitionPrice();

        uint256 priceMilli = currentPriceMilliToman();
        uint256 surenAmount = (tomanAmount * 1 ether * PRICE_PRECISION) / priceMilli;
        require(surenAmount > 0 && surenAmount >= minSurenOut, "SurenSale: below minSurenOut");
        require(e.sold + surenAmount <= e.quota, "SurenSale: exchange quota exceeded");
        require(totalSurenSold + surenAmount <= totalCap, "SurenSale: total cap exceeded");
        require(surenAmount <= address(this).balance, "SurenSale: insufficient Suren balance");

        _usedReference[e.id][orderRef] = true;
        e.sold += surenAmount;
        e.tomanReceived += tomanAmount;
        e.salesCount += 1;
        e.lastSaleAt = block.timestamp;
        totalSurenSold += surenAmount;
        totalTomanReceived += tomanAmount;
        if (isTransitionActive()) transitionDailyVolumeSuren[currentTransitionDay()] += surenAmount;

        emit SaleExecuted(msg.sender, customer, tomanAmount, surenAmount, priceMilli, orderRef);
        (bool ok, ) = customer.call{value: surenAmount}("");
        require(ok, "SurenSale: transfer to customer failed");
    }

    // ==================================================================
    //  پایان فروش و جمع‌آوری آنچه فروخته نشده
    // ==================================================================
    /// @notice تصمیم هیأت (پیشنهاد EndSale): همه‌ی فروش‌ها را یک‌جا متوقف می‌کند.
    function endSale() external onlyFoundation {
        require(!saleEnded, "SurenSale: already ended");
        saleEnded = true;
        emit SaleEnded();
    }

    /// @notice وقتی فروش رسماً تمام شده باشد true است: بنیاد آن را پایان داده، یا هر دو دوره سپری شده‌اند.
    function isSaleOver() public view returns (bool) {
        return saleEnded || block.timestamp >= transitionEndTime();
    }

    function sweepUnsold(address to) external onlyFoundation {
        require(isSaleOver(), "SurenSale: sale not officially over");
        require(to != address(0), "SurenSale: zero destination");
        uint256 amount = address(this).balance;
        require(amount > 0, "SurenSale: nothing to sweep");
        emit UnsoldSurenSweeped(to, amount);
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "SurenSale: sweep failed");
    }

    // ==================================================================
    //  viewها برای داشبورد عمومی
    // ==================================================================
    function getExchange(address account) external view returns (
        ExchangeStatus status,
        string memory name,
        uint256 quota,
        uint256 quotaLeft,
        uint256 sold,
        uint256 tomanReceived,
        uint256 salesCount,
        uint256 lastSaleAt
    ) {
        Exchange storage e = _ex[account];
        uint256 left = e.quota > e.sold ? e.quota - e.sold : 0;
        return (e.status, e.name, e.quota, left, e.sold, e.tomanReceived, e.salesCount, e.lastSaleAt);
    }

    function exchangeQuotaLeft(address account) external view returns (uint256) {
        Exchange storage e = _ex[account];
        return e.quota > e.sold ? e.quota - e.sold : 0;
    }

    function getExchanges() external view returns (address[] memory) { return _exchangeList; }

    function getBalance() external view returns (uint256) { return address(this).balance; }

    function timeRemaining() external view returns (uint256) {
        if (saleEnded || block.timestamp >= fixedEnd) return 0;
        return fixedEnd - block.timestamp;
    }

    function transitionTimeRemaining() external view returns (uint256) {
        uint256 end = transitionEndTime();
        if (saleEnded || block.timestamp < fixedEnd || block.timestamp >= end) return 0;
        return end - block.timestamp;
    }
}
