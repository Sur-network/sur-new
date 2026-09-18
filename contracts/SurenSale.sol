// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SurAddresses.sol";

/// @title SurenSale
/// @notice The Sur Foundation's fixed-price (6-month) Suren sale contract.
///
///         Because Toman is a fiat currency (not an on-chain asset), the actual payment always
///         happens off-chain (a bank payment gateway). A separate off-chain service
///         ("PaymentReporter" — exactly the same trust pattern as `verifier`/
///         `distributionOracle`) reports confirmed payments to this contract using the
///         `paymentOracle` key; the contract itself computes the price **independently, from
///         `block.timestamp`** — meaning that even if the `paymentOracle` key were fully
///         compromised, an attacker could only *falsely claim a payment* (draining the
///         contract's current balance), never manipulate the price itself.
///
///         WARNING — critical security recommendation: the Foundation should not deposit the
///         entire 20 million Suren into this contract at once — it should transfer only a
///         portion of the balance periodically (e.g. monthly), so that the maximum possible
///         loss from a compromised `paymentOracle` key stays bounded.
///
///         This contract is not one of the six genesis structural contracts — whenever the
///         Foundation is ready, it is deployed via a normal transaction (not in the genesis
///         `alloc`).
///
///         ✅ TRANSITION PERIOD (added — see sur-tokenomics.md section 3): immediately after
///         the 6-month fixed-price period ends, a 45-day transition period begins, during which
///         the Foundation (still the only seller, from the same remaining balance) sells at a
///         price that adjusts daily based on realized demand — ±0.5% per day depending on
///         whether that day's volume was above/below [80%, 120%] of the trailing 7-day moving
///         average, floored at 90 Toman and capped at 150 Toman. See advanceTransitionPrice()
///         below for the exact mechanism and why it is a permissionless, bounded-loop "catch-up"
///         function rather than something requiring a keeper bot or daily oracle call.
contract SurenSale {
    // ------------------------------------------------------------------
    // Fixed cross-contract address (see SurAddresses.sol)
    // ------------------------------------------------------------------
    address public constant FOUNDATION = SurAddresses.FOUNDATION_DAO;

    // ------------------------------------------------------------------
    // Sale schedule — 6 months, 3% monthly compound step (final project decision; the schedule
    // is precomputed and hardcoded rather than computed as an on-chain power function — since
    // there are only 6 fixed points, this is simpler and cheaper in gas than a general
    // exponentiation formula).
    // ------------------------------------------------------------------

    /// @notice Price of one Suren in Toman, per month (month 1 through 6). Precomputed with a
    ///         100 Toman base and 3% monthly compound growth, rounded to the nearest Toman.
    uint256[6] public monthlyPriceToman = [uint256(100), 103, 106, 109, 113, 116];

    uint256 public constant SALE_DURATION = 180 days; // ~6 months
    uint256 public constant SECONDS_PER_MONTH = 30 days;

    /// @notice The moment the sale period starts — set in the constructor, immutable thereafter.
    uint256 public immutable saleStartTime;

    // ------------------------------------------------------------------
    // ✅ Transition period (new) — sur-tokenomics.md section 3: after the 6-month fixed-price
    // period ends, instead of jumping straight to "whatever the free market says", a 45-day
    // window with symmetric, volume-reactive pricing runs first. The Foundation is still the
    // only seller here, from the same remaining genesis balance — no new seller is added.
    // ------------------------------------------------------------------

    uint256 public constant TRANSITION_DURATION = 45 days;
    uint256 public constant TRANSITION_PRICE_STEP_BPS = 50; // ±0.5% per adjustment
    uint256 public constant TRANSITION_HIGH_VOLUME_BPS = 12000; // 120% of the 7-day moving average
    uint256 public constant TRANSITION_LOW_VOLUME_BPS = 8000; // 80% of the 7-day moving average
    uint256 public constant TRANSITION_FLOOR_TOMAN = 90;
    uint256 public constant TRANSITION_CEILING_TOMAN = 150;
    uint256 public constant MOVING_AVERAGE_WINDOW_DAYS = 7;

    /// @notice Current transition-period price, in Toman. Zero until the transition period
    ///         actually starts and is first touched (seeded from the last fixed-period price,
    ///         monthlyPriceToman[5]).
    uint256 public transitionPriceToman;

    /// @notice How many transition-days have already had their volume folded into a price
    ///         adjustment. Day indices are 0-based, counted from transitionStartTime().
    uint256 public lastPricedTransitionDay;

    /// @notice Suren volume actually sold (via reportPayment) on each transition-day.
    mapping(uint256 => uint256) public transitionDailyVolumeSuren;

    event TransitionPriceUpdated(
        uint256 indexed dayIndex,
        uint256 dayVolumeSuren,
        uint256 movingAverageSuren,
        uint256 newPriceToman
    );

    // ------------------------------------------------------------------
    // Operational key — reports confirmed payments. Rotatable via the public
    // `FoundationDAO.proposeExecute` call (a simple-majority proposal type, not two-thirds) —
    // because the maximum possible loss from this key is kept bounded by periodic (not
    // lump-sum) funding; if the amounts funded per period grow larger later on, this decision
    // should be revisited (a two-thirds quorum would likely become more appropriate).
    // ------------------------------------------------------------------
    /// @dev ✅ FILLED: initial paymentOracle address, read from SurAddresses.sol (single
    ///      source of truth for all four oracle addresses — see that file for rationale).
    ///      Hardcoded directly, matching the pattern of the other three oracles, rather than
    ///      taken as a constructor argument — this was a deliberate project decision even
    ///      though this contract is not genesis-injected and does have a real, executing
    ///      constructor.
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
    // Idempotency — each payment, identified by a unique reference (e.g. the payment gateway's
    // tracking code), can only be processed once.
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
    // Constructor — actually executes on-chain (this contract is not genesis-injected). No
    // longer takes paymentOracle as an argument — it is hardcoded above, by project decision.
    // ------------------------------------------------------------------
    constructor() {
        saleStartTime = block.timestamp;
    }

    // ------------------------------------------------------------------
    // Funding — the Foundation periodically deposits a portion of its balance here
    // (`FoundationDAO.proposeSendETH`, two-thirds quorum — since this is a real expenditure of
    // the Foundation's Suren).
    // ------------------------------------------------------------------
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    // ------------------------------------------------------------------
    // Current price — fixed period: computed purely from block.timestamp. Transition period:
    // the state variable set by advanceTransitionPrice(), seeded from the last fixed price.
    // ------------------------------------------------------------------
    function currentPriceToman() public view returns (uint256) {
        if (isSaleActive()) {
            uint256 elapsed = block.timestamp - saleStartTime;
            uint256 monthIndex = elapsed / SECONDS_PER_MONTH;
            if (monthIndex > 5) monthIndex = 5;
            return monthlyPriceToman[monthIndex];
        }
        // Transition period (or after it ends — the contract has no further pricing role past
        // this point, but keeps returning its last known price rather than reverting, since a
        // stale-but-defined price is safer for any off-chain dashboard reading it than a revert).
        return transitionPriceToman == 0 ? monthlyPriceToman[5] : transitionPriceToman;
    }

    function isSaleActive() public view returns (bool) {
        return block.timestamp < saleStartTime + SALE_DURATION;
    }

    /// @notice The moment the transition period begins — immediately when the fixed-price
    ///         period ends. Not itself a stored variable (it's a pure function of
    ///         saleStartTime), matching the existing pattern for saleStartTime + SALE_DURATION.
    function transitionStartTime() public view returns (uint256) {
        return saleStartTime + SALE_DURATION;
    }

    function isTransitionActive() public view returns (bool) {
        uint256 start = transitionStartTime();
        return block.timestamp >= start && block.timestamp < start + TRANSITION_DURATION;
    }

    /// @notice 0-based transition-day index for "right now" — day 0 is the first day of the
    ///         transition period. Only meaningful while isTransitionActive() is true.
    function currentTransitionDay() public view returns (uint256) {
        return (block.timestamp - transitionStartTime()) / 1 days;
    }

    /// @notice Permissionless — anyone (not just the paymentOracle) can call this to fold all
    ///         fully-completed-but-not-yet-priced transition-days into the price, one
    ///         adjustment per day, in order. It is also called automatically at the start of
    ///         every reportPayment() during the transition period, so the price a buyer is
    ///         quoted is always caught up to "today" even if nobody has called this directly.
    ///         Bounded loop: at most TRANSITION_DURATION/1 days (45) iterations total across the
    ///         whole transition period's lifetime, and typically far fewer per call since most
    ///         callers (reportPayment) trigger this at least daily.
    function advanceTransitionPrice() public {
        if (block.timestamp < transitionStartTime()) return; // fixed period still running

        if (transitionPriceToman == 0) {
            transitionPriceToman = monthlyPriceToman[5]; // seed with the last fixed-period price
        }

        uint256 maxDay = TRANSITION_DURATION / 1 days;
        uint256 today = currentTransitionDay();
        if (today > maxDay) today = maxDay; // don't keep pricing forever past the window's end

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
                // else: within [80%, 120%] of the moving average — no change this day.
            }
            // avg == 0 (no prior-day data yet, e.g. day 0) — no change; can't compare to a
            // moving average that doesn't exist yet.

            emit TransitionPriceUpdated(dayIndex, dayVolume, avg, transitionPriceToman);
            lastPricedTransitionDay++;
        }
    }

    /// @dev Average daily volume over the up-to-7 transition-days strictly before
    ///      `uptoExclusiveDay` (i.e. days [uptoExclusiveDay-7, uptoExclusiveDay)). Returns 0 if
    ///      `uptoExclusiveDay` is 0 (no prior days exist yet).
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
    // Payment reporting — the only entry point that actually moves real Suren.
    // ------------------------------------------------------------------

    /// @notice Reports a confirmed (off-chain) Toman payment and automatically sends the
    ///         equivalent Suren to the buyer.
    /// @param buyer The buyer's Ethereum-style address (supplied by the user together with their payment)
    /// @param tomanAmount The amount paid, in Toman (whole integer, no decimals)
    /// @param paymentReference A unique identifier for this payment (e.g. the gateway's tracking
    ///        code) — used to prevent the same payment from being processed twice
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

        // During the transition period, catch the price up to "today" (folding in every fully
        // completed day since the last update) BEFORE quoting it to this payment — see
        // advanceTransitionPrice() for why this is safe to call unconditionally and often.
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
    // Operational key management — Foundation only (via FoundationDAO.proposeExecute, simple majority)
    // ------------------------------------------------------------------
    function setPaymentOracle(address newOracle) external onlyFoundation {
        require(newOracle != address(0), "SurenSale: zero oracle address");
        emit PaymentOracleUpdated(paymentOracle, newOracle);
        paymentOracle = newOracle;
    }

    // ------------------------------------------------------------------
    // Sweeping unsold balance — only after the sale period has formally ended, only by the Foundation.
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
    // View helpers — for the public sale dashboard
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

    /// @notice Seconds remaining in the transition period, 0 if it hasn't started yet or has
    ///         already ended. For the public sale dashboard, mirroring timeRemaining() above.
    function transitionTimeRemaining() external view returns (uint256) {
        uint256 start = transitionStartTime();
        uint256 endTime = start + TRANSITION_DURATION;
        if (block.timestamp < start || block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }
}
