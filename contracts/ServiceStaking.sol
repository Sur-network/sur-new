// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ServiceStaking
/// @notice A generic, reusable "stake for service access" ledger — see sur-tokenomics.md
///         section 10 for the full decision table this implements. This is a first-draft
///         skeleton (like SurZether.sol), not a hardened, audited contract — it is explicitly
///         flagged as still needing design review before any real deployment.
///
///         PURPOSE: several planned dapps/services (naming, timestamping, credential issuance,
///         business registry, Zether higher limits, a reputation layer) each need users or
///         issuers to lock some Suren for access — but with DIFFERENT rules per service:
///           - Naming: MANDATORY, held for as long as the name is kept, instant release on exit.
///           - Timestamping: OPTIONAL perk (higher daily quota), instant release on exit.
///           - Credential issuance: MANDATORY (on the issuer, not the credential recipient),
///             90-day cooldown on exit (to allow review of credentials already issued).
///           - Business registry: MANDATORY (on the registrant), 90-day cooldown on exit (same
///             reasoning — review window for entries already made).
///           - Zether confidential-tx higher limit: OPTIONAL perk, 7-day cooldown on exit
///             (shorter than the above two because this is about transaction limits, not
///             identity/registry entries that need a review window).
///           - Reputation/credit layer: the stake AMOUNT ITSELF is the score (not a binary
///             gate) — with a minimum 90-day mandatory lock before ANY withdrawal can even be
///             requested, so the score reflects sustained commitment, not a same-day stake-and-
///             unstake to temporarily inflate it.
///
///         DESIGN CHOICE — one generic contract, not six bespoke ones: every service above
///         reduces to the same primitive ("lock N Suren for service X, release after cooldown
///         Y"), just with different cooldown values and one special-cased minimum-lock rule for
///         Reputation. Rather than reimplementing this lock/release pattern six times (or
///         copy-pasting the pattern already proven in ValidatorsRegistry's collateral handling),
///         this contract implements it once, parameterized by a ServiceId enum. Each consuming
///         contract (a future NamingService, CredentialRegistry, etc.) is expected to call
///         `hasMinimumStake()` or `stakeOf()` as a view check before granting its own service —
///         this contract does not know or enforce which services are "mandatory"; that
///         enforcement lives in each consuming contract's own logic.
///
///         🔶 OPEN DESIGN QUESTIONS (not yet decided, listed here rather than guessed at):
///           - Exact minimum stake AMOUNTS per service (this contract only enforces cooldowns
///             and the Reputation minimum-lock DURATION — not minimum stake sizes; those are a
///             separate, still-open economic decision, likely to differ per service and
///             possibly to need governance rather than being hardcoded here).
///           - Whether withdrawalCooldown per service should become governable later (currently
///             hardcoded in the constructor, matching this project's general pattern of
///             "ship with a reasonable hardcoded default, revisit via full validator vote if it
///             turns out to need changing" — see e.g. slashBps in ValidatorsRegistry).
///           - Whether this contract itself should be genesis-injected (a seventh structural
///             address) or deployed normally like SurenSale. This draft assumes the SurenSale
///             pattern (normal deploy, real constructor, no genesis `alloc` entry) since it is
///             an optional ecosystem convenience, not core network infrastructure.
contract ServiceStaking {
    enum ServiceId {
        Naming,           // mandatory, no fixed term, instant withdrawal
        Timestamping,     // optional perk, instant withdrawal
        CredentialIssuer, // mandatory (on issuer), 90-day withdrawal cooldown
        BusinessRegistry, // mandatory (on registrant), 90-day withdrawal cooldown
        ZetherLimit,      // optional perk, 7-day withdrawal cooldown
        Reputation        // stake amount = score; 90-day MINIMUM LOCK before any withdrawal request
    }

    struct Stake {
        uint256 amount;
        uint256 stakedAt;              // first-staked timestamp — used only by Reputation's minimum lock
        uint256 withdrawalRequestedAt; // 0 = no pending request; only used when cooldown > 0
    }

    /// @notice Seconds that must elapse between requesting withdrawal and actually withdrawing,
    ///         per service. Zero means "no request step needed — withdraw() works immediately."
    mapping(ServiceId => uint256) public withdrawalCooldown;

    /// @notice user => service => their current stake info.
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
        withdrawalCooldown[ServiceId.Reputation] = 0; // no cooldown AFTER request — the 90-day
        // rule for Reputation is a minimum lock BEFORE a request is even allowed (see
        // requestWithdrawal/withdraw below), which is a different mechanism than the other
        // services' "request now, wait, then withdraw" cooldown.
    }

    /// @notice Lock more Suren for a given service. Repeatable — additional stakes simply add
    ///         to the existing amount. Staking more also cancels any pending withdrawal request
    ///         for that service (you can't be simultaneously "adding stake" and "exiting").
    function stake(ServiceId service) external payable {
        require(msg.value > 0, "ServiceStaking: zero stake amount");

        Stake storage s = stakes[msg.sender][service];
        if (s.amount == 0) {
            s.stakedAt = block.timestamp;
        }
        s.amount += msg.value;
        s.withdrawalRequestedAt = 0;

        emit Staked(msg.sender, service, msg.value, s.amount);
    }

    /// @notice Required before withdraw() for any service with a non-zero cooldown
    ///         (CredentialIssuer, BusinessRegistry, ZetherLimit). Not needed — and reverts —
    ///         for zero-cooldown services (Naming, Timestamping), which withdraw directly.
    ///         For Reputation, this additionally enforces the 90-day minimum lock.
    function requestWithdrawal(ServiceId service) external {
        Stake storage s = stakes[msg.sender][service];
        require(s.amount > 0, "ServiceStaking: no stake to withdraw");
        require(withdrawalCooldown[service] > 0, "ServiceStaking: this service has no cooldown, call withdraw() directly");

        s.withdrawalRequestedAt = block.timestamp;
        emit WithdrawalRequested(msg.sender, service, block.timestamp + withdrawalCooldown[service]);
    }

    /// @notice Withdraws the caller's full stake for a service. Behavior depends on the
    ///         service's cooldown:
    ///           - Zero cooldown (Naming, Timestamping, Reputation): works immediately, no
    ///             prior requestWithdrawal() call needed — EXCEPT Reputation, which still
    ///             enforces its own 90-day minimum lock from the original stake time,
    ///             independent of the (zero) cooldown mechanism.
    ///           - Non-zero cooldown (CredentialIssuer, BusinessRegistry, ZetherLimit):
    ///             requires a prior requestWithdrawal() call and that its cooldown has elapsed.
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
    // View helpers — for consuming contracts (NamingService, CredentialRegistry, etc.) and
    // off-chain dashboards.
    // ------------------------------------------------------------------

    function stakeOf(address user, ServiceId service) external view returns (uint256) {
        return stakes[user][service].amount;
    }

    /// @notice Convenience check for a consuming contract's own "is this address allowed to
    ///         use my service" gate — e.g. `require(serviceStaking.hasMinimumStake(msg.sender,
    ///         ServiceId.BusinessRegistry, MIN_REGISTRANT_STAKE), ...)`. This contract does not
    ///         define what `minAmount` should be for any service — that is each consuming
    ///         contract's own decision (see the open design questions in the header comment).
    function hasMinimumStake(address user, ServiceId service, uint256 minAmount) external view returns (bool) {
        return stakes[user][service].amount >= minAmount;
    }
}
