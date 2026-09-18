// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title SurenSale
/// @notice قرارداد فروش دوره‌ی قیمت ثابت (۶ ماهه) سورن توسط بنیاد سور.
///
///         چون تومان یک ارز فیات است (نه دارایی on-chain)، پرداخت واقعی همیشه آف‌چین اتفاق
///         می‌افتد (درگاه پرداخت بانکی). یک سرویس آف‌چین جدا («PaymentReporter» — دقیقاً همان
///         الگوی `verifier`/`distributionOracle`) پرداخت‌های تأییدشده را با کلید `paymentOracle`
///         به این قرارداد گزارش می‌دهد؛ خودِ قرارداد قیمت را **مستقل و از روی `block.timestamp`**
///         محاسبه می‌کند — یعنی حتی اگر کلید `paymentOracle` کاملاً هک شود، مهاجم فقط می‌تواند
///         *ادعای پرداخت* کند (و موجودی فعلی قرارداد را خالی کند)، هرگز نمی‌تواند خودِ قیمت را
///         دستکاری کند.
///
///         ⚠️ توصیه‌ی امنیتی حیاتی: بنیاد نباید کل ۲۰ میلیون سورن را یک‌جا به این قرارداد واریز
///         کند — باید دوره‌ای (مثلاً ماهانه) فقط بخشی از موجودی را منتقل کند، تا سقف زیانِ
///         احتمالیِ یک کلید `paymentOracle` هک‌شده محدود بماند.
///
///         این قرارداد یکی از شش قرارداد ساختاری genesis نیست — هر زمانی که بنیاد آماده بود،
///         با یک تراکنش معمولی دیپلوی می‌شود (نه در `alloc` genesis).
///
///         ✅ دوره‌ی گذار (تازه اضافه شد — به sur-tokenomics.md بخش ۳ مراجعه کنید): بلافاصله
///         پس از پایان دوره‌ی ۶ماهه‌ی قیمت ثابت، یک دوره‌ی گذار ۴۵روزه شروع می‌شود که در آن
///         بنیاد (همچنان تنها فروشنده، از همون موجودی باقی‌مانده) با قیمتی که روزانه بر اساس
///         تقاضای واقعی تنظیم می‌شود می‌فروشد — ±۰.۵٪ در روز، بسته به این‌که حجم فروش آن روز
///         بالا یا پایین بازه‌ی [۸۰٪، ۱۲۰٪] میانگین متحرک ۷روزه بوده، با کف ۹۰ تومان و سقف
///         ۱۵۰ تومان. به advanceTransitionPrice() پایین مراجعه کنید برای مکانیزم دقیق و
///         این‌که چرا یک تابع «جبرانی» بدون‌مجوز و با حلقه‌ی محدود است، نه چیزی که نیاز به
///         ربات keeper یا فراخوانی روزانه‌ی اوراکل داشته باشد.
contract SurenSale {
    // ------------------------------------------------------------------
    // آدرس ثابت متقابل بین قراردادها (به SurAddresses.sol مراجعه کن)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // جدول قیمت فروش — ۶ ماه، پله‌ی ۳٪ رشد مرکب ماهانه (تصمیم قطعی پروژه؛ جدول از پیش محاسبه و
    // هاردکد شده، نه محاسبه‌ی توان on-chain — چون فقط ۶ نقطه‌ی ثابت داریم، سادگی و گس کمتر
    // بهتر از یک فرمول توان عمومی است).
    // ------------------------------------------------------------------

    /// @notice قیمت هر سورن به تومان، به‌ازای هر ماه (ماه ۱ تا ۶). مقادیر از پیش محاسبه‌شده با
    ///         ۱۰۰ تومان پایه و ۳٪ رشد مرکب ماهانه، رندشده به نزدیک‌ترین تومان.
    uint256[6] public monthlyPriceToman = [uint256(100), 103, 106, 109, 113, 116];

    uint256 public constant SALE_DURATION = 180 days; // ~۶ ماه
    uint256 public constant SECONDS_PER_MONTH = 30 days;

    /// @notice لحظه‌ی شروع دوره‌ی فروش — در سازنده تنظیم می‌شود، تغییرناپذیر.
    uint256 public immutable saleStartTime;

    // ------------------------------------------------------------------
    // ✅ دوره‌ی گذار (تازه) — sur-tokenomics.md بخش ۳: پس از پایان دوره‌ی ۶ماهه‌ی قیمت ثابت،
    // به‌جای پرش ناگهانی به «هرچه بازار آزاد بگوید»، یک پنجره‌ی ۴۵روزه با قیمت‌گذاری متقارن و
    // واکنش‌به‌حجم اجرا می‌شود. بنیاد همچنان تنها فروشنده است، از همون موجودی باقی‌مانده —
    // هیچ فروشنده‌ی تازه‌ای اضافه نمی‌شود.
    // ------------------------------------------------------------------

    uint256 public constant TRANSITION_DURATION = 45 days;
    uint256 public constant TRANSITION_PRICE_STEP_BPS = 50; // ±۰.۵٪ در هر تعدیل
    uint256 public constant TRANSITION_HIGH_VOLUME_BPS = 12000; // ۱۲۰٪ میانگین متحرک ۷روزه
    uint256 public constant TRANSITION_LOW_VOLUME_BPS = 8000; // ۸۰٪ میانگین متحرک ۷روزه
    uint256 public constant TRANSITION_FLOOR_TOMAN = 90;
    uint256 public constant TRANSITION_CEILING_TOMAN = 150;
    uint256 public constant MOVING_AVERAGE_WINDOW_DAYS = 7;

    /// @notice قیمت فعلی دوره‌ی گذار، به تومان. تا وقتی دوره‌ی گذار واقعاً شروع و اولین‌بار
    ///         لمس شود صفر است (بعد با آخرین قیمت دوره‌ی ثابت، monthlyPriceToman[5]، مقداردهی
    ///         می‌شود).
    uint256 public transitionPriceToman;

    /// @notice چند روز از دوره‌ی گذار قبلاً حجمشان در یک تعدیل قیمت لحاظ شده. شاخص روزها
    ///         صفرمبنا و از transitionStartTime() شمرده می‌شود.
    uint256 public lastPricedTransitionDay;

    /// @notice حجم واقعی سورن فروخته‌شده (از طریق reportPayment) در هر روز دوره‌ی گذار.
    mapping(uint256 => uint256) public transitionDailyVolumeSuren;

    event TransitionPriceUpdated(
        uint256 indexed dayIndex,
        uint256 dayVolumeSuren,
        uint256 movingAverageSuren,
        uint256 newPriceToman
    );

    // ------------------------------------------------------------------
    // کلید عملیاتی — گزارش‌دهنده‌ی پرداخت‌های تأییدشده. چرخشش از طریق فراخوانی عمومی
    // `FoundationDAO.proposeExecute` (نوع پیشنهاد اکثریت ساده، نه دوسوم) ممکن است — چون سقف
    // زیان این کلید با تأمین مالی دوره‌ای (نه یک‌جا) محدود نگه داشته می‌شود؛ اگر بعداً مبالغ
    // تأمین‌شده در هر دوره بزرگ‌تر شد، این تصمیم باید بازبینی شود (احتمالاً نصاب دوسوم مناسب‌تر
    // خواهد بود).
    // ------------------------------------------------------------------
    /// @dev ✅ پرشده: آدرس اولیه‌ی paymentOracle، خوانده‌شده از SurAddresses.sol (منبع واحد
    ///      صحت برای هر چهار آدرس اوراکل — دلیلش را در آن فایل ببین). مستقیم هاردکد شده،
    ///      مطابق همون الگوی سه اوراکل دیگر، نه به‌عنوان آرگومان constructor — این یه تصمیم
    ///      عمدی پروژه بود، با وجود این‌که این قرارداد genesis-injected نیست و واقعاً یک
    ///      constructor اجراشونده دارد.
    address public paymentOracle = SurAddresses.PAYMENT_ORACLE;

    modifier onlyFoundation() {
        require(msg.sender == FOUNDATION, "SurenSale: caller is not the Foundation");
        _;
    }

    modifier onlyPaymentOracle() {
        require(msg.sender == paymentOracle, "SurenSale: caller is not the payment oracle");
        _;
    }

    // ------------------------------------------------------------------
    // Idempotency — هر پرداخت با یک شناسه‌ی یکتا (مثلاً کد پیگیری درگاه پرداخت) فقط یک‌بار
    // قابل‌پردازش است.
    // ------------------------------------------------------------------
    mapping(string => bool) public processedPayments;

    uint256 public totalSurenSold;
    uint256 public totalTomanReceived;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event PaymentOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event Funded(address indexed from, uint256 amount);
    event PaymentReported(
        address indexed buyer,
        uint256 tomanAmount,
        uint256 surenAmount,
        uint256 priceTomanPerSuren,
        string paymentReference
    );
    event UnsoldSurenSweeped(address indexed to, uint256 amount);

    // ------------------------------------------------------------------
    // سازنده — اجرای واقعی روی زنجیره (این قرارداد genesis-injected نیست). دیگر paymentOracle
    // را به‌عنوان آرگومان نمی‌گیرد — طبق تصمیم پروژه، بالا هاردکد شده است.
    // ------------------------------------------------------------------
    constructor() {
        saleStartTime = block.timestamp;
    }

    // ------------------------------------------------------------------
    // تأمین مالی — بنیاد به‌صورت دوره‌ای بخشی از موجودی‌اش را اینجا واریز می‌کند
    // (`FoundationDAO.proposeSendETH` با نصاب دوسوم — چون این خرج واقعی سورن بنیاد است).
    // ------------------------------------------------------------------
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // قیمت فعلی — دوره‌ی ثابت: مستقیم از block.timestamp. دوره‌ی گذار: متغیر حالتی که
    // advanceTransitionPrice() تنظیم می‌کند، با آخرین قیمت ثابت مقداردهی اولیه شده.
    // ------------------------------------------------------------------
    function currentPriceToman() public view returns (uint256) {
        if (isSaleActive()) {
            uint256 elapsed = block.timestamp - saleStartTime;
            uint256 monthIndex = elapsed / SECONDS_PER_MONTH;
            if (monthIndex > 5) monthIndex = 5;
            return monthlyPriceToman[monthIndex];
        }
        // دوره‌ی گذار (یا بعد از پایانش — قرارداد دیگر نقش قیمت‌گذاری ندارد، ولی به‌جای
        // revert کردن، همچنان آخرین قیمت شناخته‌شده را برمی‌گرداند — برای هر داشبورد آف‌چینی
        // که این مقدار را می‌خواند، یک قیمت قدیمی‌ولی‌مشخص امن‌تر از خطاست).
        return transitionPriceToman == 0 ? monthlyPriceToman[5] : transitionPriceToman;
    }

    function isSaleActive() public view returns (bool) {
        return block.timestamp < saleStartTime + SALE_DURATION;
    }

    /// @notice لحظه‌ی شروع دوره‌ی گذار — بلافاصله بعد از پایان دوره‌ی قیمت ثابت. خودش یک
    ///         متغیر ذخیره‌شده نیست (تابعی خالص از saleStartTime است)، مطابق همون الگوی
    ///         saleStartTime + SALE_DURATION موجود.
    function transitionStartTime() public view returns (uint256) {
        return saleStartTime + SALE_DURATION;
    }

    function isTransitionActive() public view returns (bool) {
        uint256 start = transitionStartTime();
        return block.timestamp >= start && block.timestamp < start + TRANSITION_DURATION;
    }

    /// @notice شاخص روز دوره‌ی گذار (صفرمبنا) برای «همین الان» — روز ۰ اولین روز دوره‌ی
    ///         گذار است. فقط وقتی isTransitionActive() درست باشد معنا دارد.
    function currentTransitionDay() public view returns (uint256) {
        return (block.timestamp - transitionStartTime()) / 1 days;
    }

    /// @notice بدون‌مجوز — هرکسی (نه فقط paymentOracle) می‌تواند این را فراخوانی کند تا همه‌ی
    ///         روزهای کاملاً تمام‌شده‌ی دوره‌ی گذار که هنوز قیمت‌گذاری نشده‌اند را، یک تعدیل
    ///         به‌ازای هر روز و به‌ترتیب، در قیمت لحاظ کند. همچنین به‌طور خودکار در ابتدای هر
    ///         reportPayment() طی دوره‌ی گذار فراخوانی می‌شود، تا قیمتی که به خریدار اعلام
    ///         می‌شود همیشه با «امروز» به‌روز باشد، حتی اگر کسی مستقیم این را صدا نزده باشد.
    ///         حلقه‌ی محدود: حداکثر TRANSITION_DURATION/1 days (۴۵) تکرار در کل عمر دوره‌ی
    ///         گذار، و معمولاً خیلی کمتر در هر فراخوانی چون بیشتر فراخوان‌ها (reportPayment)
    ///         حداقل روزانه این را فعال می‌کنند.
    function advanceTransitionPrice() public {
        if (block.timestamp < transitionStartTime()) return; // دوره‌ی ثابت هنوز جریان دارد

        if (transitionPriceToman == 0) {
            transitionPriceToman = monthlyPriceToman[5]; // با آخرین قیمت دوره‌ی ثابت مقداردهی اولیه
        }

        uint256 maxDay = TRANSITION_DURATION / 1 days;
        uint256 today = currentTransitionDay();
        if (today > maxDay) today = maxDay; // بعد از پایان پنجره، دیگر قیمت‌گذاری ادامه پیدا نکند

        while (lastPricedTransitionDay < today) {
            uint256 dayIndex = lastPricedTransitionDay;
            uint256 dayVolume = transitionDailyVolumeSuren[dayIndex];
            uint256 avg = _transitionMovingAverage(dayIndex);

            if (avg > 0) {
                uint256 highThreshold = (avg * TRANSITION_HIGH_VOLUME_BPS) / BPS_DENOMINATOR_LOCAL;
                uint256 lowThreshold = (avg * TRANSITION_LOW_VOLUME_BPS) / BPS_DENOMINATOR_LOCAL;

                if (dayVolume > highThreshold) {
                    uint256 step = (transitionPriceToman * TRANSITION_PRICE_STEP_BPS) / BPS_DENOMINATOR_LOCAL;
                    uint256 raised = transitionPriceToman + step;
                    transitionPriceToman = raised > TRANSITION_CEILING_TOMAN ? TRANSITION_CEILING_TOMAN : raised;
                } else if (dayVolume < lowThreshold) {
                    uint256 step = (transitionPriceToman * TRANSITION_PRICE_STEP_BPS) / BPS_DENOMINATOR_LOCAL;
                    uint256 lowered = transitionPriceToman > step ? transitionPriceToman - step : 0;
                    transitionPriceToman = lowered < TRANSITION_FLOOR_TOMAN ? TRANSITION_FLOOR_TOMAN : lowered;
                }
                // در غیر این صورت: داخل بازه‌ی [۸۰٪، ۱۲۰٪] میانگین متحرک — امروز بدون تغییر.
            }
            // avg == 0 (هنوز داده‌ی روز قبلی نیست، مثلاً روز ۰) — بدون تغییر؛ نمی‌توان با
            // میانگین متحرکی که هنوز وجود ندارد مقایسه کرد.

            emit TransitionPriceUpdated(dayIndex, dayVolume, avg, transitionPriceToman);
            lastPricedTransitionDay++;
        }
    }

    /// @dev میانگین حجم روزانه طی حداکثر ۷ روز دوره‌ی گذار درست پیش از `uptoExclusiveDay`
    ///      (یعنی روزهای [uptoExclusiveDay-7, uptoExclusiveDay)). اگر `uptoExclusiveDay` صفر
    ///      باشد صفر برمی‌گرداند (هنوز هیچ روز قبلی وجود ندارد).
    function _transitionMovingAverage(uint256 uptoExclusiveDay) private view returns (uint256) {
        if (uptoExclusiveDay == 0) return 0;
        uint256 windowStart = uptoExclusiveDay > MOVING_AVERAGE_WINDOW_DAYS
            ? uptoExclusiveDay - MOVING_AVERAGE_WINDOW_DAYS
            : 0;
        uint256 count = uptoExclusiveDay - windowStart;
        uint256 sum;
        for (uint256 d = windowStart; d < uptoExclusiveDay; d++) {
            sum += transitionDailyVolumeSuren[d];
        }
        return sum / count;
    }

    uint256 private constant BPS_DENOMINATOR_LOCAL = 10000;

    // ------------------------------------------------------------------
    // گزارش پرداخت — تنها نقطه‌ی ورودی که سورن واقعی جابه‌جا می‌کند.
    // ------------------------------------------------------------------

    /// @notice گزارش یک پرداخت تومانی تأییدشده (آف‌چین) و ارسال خودکار سورن معادل به خریدار.
    /// @param buyer آدرس اتریومی خریدار (از طرف کاربر، همراه با پرداختش اعلام می‌شود)
    /// @param tomanAmount مبلغ پرداختی، به تومان (عدد صحیح، بدون اعشار)
    /// @param paymentReference شناسه‌ی یکتای این پرداخت (مثلاً کد پیگیری درگاه) — برای جلوگیری
    ///        از پردازش دوباره‌ی همان پرداخت
    function reportPayment(
        address buyer,
        uint256 tomanAmount,
        string calldata paymentReference
    ) external onlyPaymentOracle {
        require(isSaleActive() || isTransitionActive(), "SurenSale: sale and transition periods have both ended");
        require(buyer != address(0), "SurenSale: zero buyer address");
        require(tomanAmount > 0, "SurenSale: zero amount");
        require(!processedPayments[paymentReference], "SurenSale: payment already processed");

        processedPayments[paymentReference] = true;

        // طی دوره‌ی گذار، پیش از اعلام قیمت به این پرداخت، اول قیمت را با «امروز» به‌روز کن
        // (همه‌ی روزهای کاملاً تمام‌شده از آخرین به‌روزرسانی را لحاظ کن) — به
        // advanceTransitionPrice() مراجعه کن که چرا فراخوانی بی‌قیدوشرط و مکررش امن است.
        if (isTransitionActive()) {
            advanceTransitionPrice();
        }

        uint256 price = currentPriceToman();
        uint256 surenAmount = (tomanAmount * 1 ether) / price;

        require(surenAmount <= address(this).balance, "SurenSale: insufficient Suren balance");

        totalSurenSold += surenAmount;
        totalTomanReceived += tomanAmount;

        if (isTransitionActive()) {
            transitionDailyVolumeSuren[currentTransitionDay()] += surenAmount;
        }

        (bool success, ) = buyer.call{value: surenAmount}("");
        require(success, "SurenSale: transfer to buyer failed");

        emit PaymentReported(buyer, tomanAmount, surenAmount, price, paymentReference);
    }

    // ------------------------------------------------------------------
    // مدیریت کلید عملیاتی — فقط بنیاد (از طریق FoundationDAO.proposeExecute، اکثریت ساده)
    // ------------------------------------------------------------------
    function setPaymentOracle(address newOracle) external onlyFoundation {
        require(newOracle != address(0), "SurenSale: zero oracle address");
        emit PaymentOracleUpdated(paymentOracle, newOracle);
        paymentOracle = newOracle;
    }

    // ------------------------------------------------------------------
    // جمع‌آوری باقی‌مانده‌ی نفروخته — فقط بعد از پایان رسمی دوره‌ی فروش، فقط توسط بنیاد.
    // ------------------------------------------------------------------
    function sweepUnsold(address to) external onlyFoundation {
        require(!isSaleActive() && !isTransitionActive(), "SurenSale: sale or transition period still active");
        require(to != address(0), "SurenSale: zero destination address");

        uint256 amount = address(this).balance;
        require(amount > 0, "SurenSale: nothing to sweep");

        emit UnsoldSurenSweeped(to, amount);
        (bool success, ) = to.call{value: amount}("");
        require(success, "SurenSale: sweep transfer failed");
    }

    // ------------------------------------------------------------------
    // توابع کمکی view — برای داشبورد فروش عمومی
    // ------------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function currentMonthIndex() external view returns (uint256) {
        uint256 elapsed = block.timestamp - saleStartTime;
        uint256 monthIndex = elapsed / SECONDS_PER_MONTH;
        return monthIndex > 5 ? 5 : monthIndex;
    }

    function timeRemaining() external view returns (uint256) {
        uint256 endTime = saleStartTime + SALE_DURATION;
        if (block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }

    /// @notice ثانیه‌های باقی‌مانده تا پایان دوره‌ی گذار؛ اگر هنوز شروع نشده یا قبلاً تمام
    ///         شده صفر برمی‌گرداند. برای داشبورد فروش عمومی، مشابه timeRemaining() بالا.
    function transitionTimeRemaining() external view returns (uint256) {
        uint256 start = transitionStartTime();
        uint256 endTime = start + TRANSITION_DURATION;
        if (block.timestamp < start || block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }
}
