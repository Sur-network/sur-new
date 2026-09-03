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
    // Current price — computed purely from block.timestamp, entirely independent of any report.
    // ------------------------------------------------------------------
    function currentPriceToman() public view returns (uint256) {
        uint256 elapsed = block.timestamp - saleStartTime;
        uint256 monthIndex = elapsed / SECONDS_PER_MONTH;
        if (monthIndex > 5) monthIndex = 5; // after the sale period ends, keep returning the last price
        return monthlyPriceToman[monthIndex];
    }

    function isSaleActive() public view returns (bool) {
        return block.timestamp < saleStartTime + SALE_DURATION;
    }

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
        require(!isSaleActive(), "SurenSale: sale period still active");
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
}
