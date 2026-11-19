// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

interface IFoundationCeo {
    function ceo() external view returns (address);
}

/// @title SurenSale
/// @notice The Sur Foundation's Suren sale contract (v2.5): fixed-price period of 90 days, then a
///         45-day volume-driven transition period; the ONLY sales channel is licensed exchanges.
///         See offchain-services/sur-suren-sale-spec.md.
///
///         HOW A SALE WORKS: the customer pays Toman to a licensed exchange, which calls
///         `sellTo(customer, tomanAmount, minSurenOut, reference)`. The contract computes the price
///         ITSELF from `block.timestamp` and its own parameters — an exchange can only claim a sale,
///         up to its own quota, at the official price of that moment; it can never lower the price.
///         `minSurenOut` protects the customer (and the exchange) when the price rises.
///
///         NO ORACLE: the former `paymentOracle` / `reportPayment` of v2.2 is gone.
///
///         NOT a genesis contract: deployed with an ordinary transaction whenever the foundation is
///         ready; it only depends on the fixed address of FoundationDAO (for the CEO and for board
///         decisions). The foundation tells FoundationDAO the address with the SetSaleContract proposal.
///
///         SECURITY: the foundation should fund this contract periodically, not all at once, so the
///         loss from a hacked exchange key stays bounded by that exchange's quota.
///
///         🔶 Assumptions where the spec is still open (kept visible): extensions are only possible
///         before the relevant period ends; an extension of the transition period continues the same
///         daily volume rule; the Toman settlement between exchange and foundation is off-chain.
contract SurenSale {
    // ------------------------------------------------------------------
    // Fixed address (see SurAddresses.sol)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // Schedule
    // ------------------------------------------------------------------
    /// @notice Price per Suren in Toman for months 1..3 of the fixed period (+5 Toman every 30 days).
    uint256[3] public monthlyPriceToman = [uint256(100), 105, 110];

    uint256 public constant BASE_FIXED_DURATION = 90 days;
    uint256 public constant SECONDS_PER_MONTH = 30 days;
    uint256 public constant TRANSITION_DURATION = 45 days;
    uint256 public constant TRANSITION_PRICE_STEP_BPS = 50; // ±0.5% per day
    uint256 public constant TRANSITION_HIGH_VOLUME_BPS = 12000; // 120% of the 7-day moving average
    uint256 public constant TRANSITION_LOW_VOLUME_BPS = 8000; // 80% of the 7-day moving average
    uint256 public constant TRANSITION_FLOOR_TOMAN = 90;
    uint256 public constant TRANSITION_CEILING_TOMAN = 150;
    uint256 public constant MOVING_AVERAGE_WINDOW_DAYS = 7;
    /// @notice Internal price precision: prices are stored as milli-Toman (Toman * 1000).
    uint256 public constant PRICE_PRECISION = 1000;
    uint256 private constant BPS_DENOMINATOR = 10000;
    /// @notice Typo guard for one extension call (the total number of extensions is unlimited).
    uint256 public constant MAX_EXTENSION_DAYS_PER_CALL = 3650;
    /// @notice Gas deposit sent to an exchange account at registration (decision 2026-11-19: 100 Suren).
    uint256 public constant GAS_DEPOSIT = 100 ether;

    uint256 public immutable saleStartTime;

    /// @dev Price segments added by CEO extensions of the fixed period, in order and contiguous:
    ///      segment i covers [previous end, end) at `priceMilli`.
    struct Segment {
        uint256 end;
        uint256 priceMilli;
    }
    Segment[] private _segments;
    /// @notice End of the fixed-price period including every extension.
    uint256 public fixedEnd;
    /// @notice Extra days added to the transition period by the CEO.
    uint256 public transitionExtraDays;

    // transition-period state
    uint256 public transitionPriceMilliToman;
    uint256 public lastPricedTransitionDay;
    mapping(uint256 => uint256) public transitionDailyVolumeSuren;

    /// @notice Set by FoundationDAO (EndSale proposal): sales stop and the rest can be swept.
    bool public saleEnded;

    // ------------------------------------------------------------------
    // Exchanges
    // ------------------------------------------------------------------
    enum ExchangeStatus { None, Active, Paused, Removed }

    struct Exchange {
        ExchangeStatus status;
        uint256 id; // follows the exchange through key changes; keys the per-exchange reference set
        string name;
        uint256 quota; // total Suren this exchange may sell (including what it already sold)
        uint256 sold; // Suren
        uint256 tomanReceived;
        uint256 salesCount;
        uint256 lastSaleAt;
    }

    mapping(address => Exchange) private _ex;
    address[] private _exchangeList;
    uint256 public exchangeCount; // ids handed out so far
    mapping(uint256 => mapping(bytes32 => bool)) private _usedReference; // exchange id => reference

    /// @notice Total Suren all exchanges together may sell. 0 until the board sets it, so nothing
    ///         sells before the foundation has decided the cap.
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

    /// @notice Funding. The foundation pays Suren from its treasury (a Spend proposal).
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // ==================================================================
    //  Periods and price
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

    /// @notice Last price of the fixed period (the transition's starting price), in milli-Toman.
    function lastFixedPriceMilli() public view returns (uint256) {
        if (_segments.length > 0) return _segments[_segments.length - 1].priceMilli;
        return monthlyPriceToman[2] * PRICE_PRECISION;
    }

    /// @notice Official price in milli-Toman (Toman * 1000) — the exact value used for settlement.
    function currentPriceMilliToman() public view returns (uint256) {
        uint256 t = block.timestamp;
        if (t < fixedEnd) return _fixedPriceAt(t);
        return transitionPriceMilliToman == 0 ? lastFixedPriceMilli() : transitionPriceMilliToman;
    }

    /// @notice Rounded price for display only; never use it for calculations.
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
    // CEO: extensions (unlimited in total; the price of an extended fixed period is set by the CEO and stays fixed)
    // ------------------------------------------------------------------
    /// @param extraDays days added to the fixed-price period
    /// @param priceToman price (whole Toman) for exactly these added days
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
    // Transition price: permissionless, bounded catch-up (also run at the start of every sale)
    // ------------------------------------------------------------------
    function currentTransitionDay() public view returns (uint256) {
        return (block.timestamp - fixedEnd) / 1 days;
    }

    function advanceTransitionPrice() public {
        if (block.timestamp < fixedEnd) return;
        if (transitionPriceMilliToman == 0) {
            transitionPriceMilliToman = lastFixedPriceMilli(); // seeded with the last fixed-period price
        }
        uint256 maxDay = (TRANSITION_DURATION + transitionExtraDays * 1 days) / 1 days;
        uint256 today = currentTransitionDay();
        if (today > maxDay) today = maxDay;

        uint256 floorMilli = TRANSITION_FLOOR_TOMAN * PRICE_PRECISION;
        uint256 ceilingMilli = TRANSITION_CEILING_TOMAN * PRICE_PRECISION;

        while (lastPricedTransitionDay < today) {
            uint256 dayIndex = lastPricedTransitionDay;
            uint256 dayVolume = transitionDailyVolumeSuren[dayIndex];
            uint256 avg = _movingAverage(dayIndex);
            if (avg > 0) {
                uint256 step = (transitionPriceMilliToman * TRANSITION_PRICE_STEP_BPS) / BPS_DENOMINATOR;
                if (dayVolume > (avg * TRANSITION_HIGH_VOLUME_BPS) / BPS_DENOMINATOR) {
                    uint256 raised = transitionPriceMilliToman + step;
                    transitionPriceMilliToman = raised > ceilingMilli ? ceilingMilli : raised;
                } else if (dayVolume < (avg * TRANSITION_LOW_VOLUME_BPS) / BPS_DENOMINATOR) {
                    uint256 lowered = transitionPriceMilliToman > step ? transitionPriceMilliToman - step : 0;
                    transitionPriceMilliToman = lowered < floorMilli ? floorMilli : lowered;
                }
            }
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
    //  Exchanges — managed by FoundationDAO (typed proposals, 3 of 5)
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
        // the deposit leaves the contract balance and is outside the quota
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

    /// @notice Moves an exchange (remaining quota, statistics, used references, status) to a new account.
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

    /// @notice Immediate stop of one exchange (FoundationDAO.pauseExchange: CEO or any principal board member alone).
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
    //  The only function that moves Suren to customers
    // ==================================================================
    /// @param customer receives the Suren directly
    /// @param tomanAmount Toman the exchange received from the customer (whole Toman)
    /// @param minSurenOut minimum Suren the customer must get; fewer => revert
    /// @param orderRef order id, unique per exchange
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
    //  End of the sale and sweeping what was not sold
    // ==================================================================
    /// @notice Board decision (EndSale proposal): stops all sales at once.
    function endSale() external onlyFoundation {
        require(!saleEnded, "SurenSale: already ended");
        saleEnded = true;
        emit SaleEnded();
    }

    /// @notice True when the sale is officially over: ended by the foundation, or both periods ran out.
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
    //  Views for the public dashboard
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
