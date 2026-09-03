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
    // کلید عملیاتی — گزارش‌دهنده‌ی پرداخت‌های تأییدشده. چرخشش از طریق فراخوانی عمومی
    // `FoundationDAO.proposeExecute` (نوع پیشنهاد اکثریت ساده، نه دوسوم) ممکن است — چون سقف
    // زیان این کلید با تأمین مالی دوره‌ای (نه یک‌جا) محدود نگه داشته می‌شود؛ اگر بعداً مبالغ
    // تأمین‌شده در هر دوره بزرگ‌تر شد، این تصمیم باید بازبینی شود (احتمالاً نصاب دوسوم مناسب‌تر
    // خواهد بود).
    // ------------------------------------------------------------------
    /// @dev ✅ پرشده: آدرس اولیه‌ی paymentOracle (چک‌سام‌شده طبق EIP-55). مستقیم هاردکد شده،
    ///      مطابق همون الگوی سه اوراکل دیگر، نه به‌عنوان آرگومان constructor — این یه تصمیم
    ///      عمدی پروژه بود، با وجود این‌که این قرارداد genesis-injected نیست و واقعاً یک
    ///      constructor اجراشونده دارد.
    address public paymentOracle = 0xc1fF1F40F665404fbf7DaAD26153357C544C35A0;

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
    // قیمت فعلی — کاملاً مستقل از هر گزارشی، فقط از block.timestamp محاسبه می‌شود.
    // ------------------------------------------------------------------
    function currentPriceToman() public view returns (uint256) {
        uint256 elapsed = block.timestamp - saleStartTime;
        uint256 monthIndex = elapsed / SECONDS_PER_MONTH;
        if (monthIndex > 5) monthIndex = 5; // بعد از پایان دوره، همچنان آخرین قیمت را برمی‌گرداند
        return monthlyPriceToman[monthIndex];
    }

    function isSaleActive() public view returns (bool) {
        return block.timestamp < saleStartTime + SALE_DURATION;
    }

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
        require(isSaleActive(), "SurenSale: sale period has ended");
        require(buyer != address(0), "SurenSale: zero buyer address");
        require(tomanAmount > 0, "SurenSale: zero amount");
        require(!processedPayments[paymentReference], "SurenSale: payment already processed");

        processedPayments[paymentReference] = true;

        uint256 price = currentPriceToman();
        uint256 surenAmount = (tomanAmount * 1 ether) / price;

        require(surenAmount <= address(this).balance, "SurenSale: insufficient Suren balance");

        totalSurenSold += surenAmount;
        totalTomanReceived += tomanAmount;

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
        require(!isSaleActive(), "SurenSale: sale period still active");
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
}
