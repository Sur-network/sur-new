// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title GenesisClaimsVault
/// @notice Holds the genesis claims of tiers 2 and 3 (11,984,000 + 21,327,000 Suren) instead of crediting wallets, and releases
///         them in 24 equal monthly instalments (reference doc section 10, decisions ✅):
///           * one merged claim per address; 100 Suren of each claim are already in the claimant's own wallet (for gas)
///             and are deducted from the claim: the vault holds (claim - 100) for that address;
///           * the held amount is released in 24 equal instalments at the START of each calendar month (UTC); the first
///             instalment is released at the start of the first calendar month AFTER the genesis timestamp;
///           * an unwithdrawn instalment never expires; it accumulates and the owner withdraws whatever is released;
///           * the address list is fixed before genesis; an address cannot be changed; unclaimed Suren stay here;
///           * founders' claims are not conditional on staying a validator and can never be slashed;
///           * 🔶 the rounding remainder of the division by 24 goes into the LAST instalment (default of this code).
///         The vault balance in the genesis `alloc` must equal the sum of (claim - 100) over all addresses.
///
///         GENESIS: no constructor and no way to add claims later. The claims and `genesisTimestamp` are written by
///         genesis-seed-helpers/GenesisClaimsVault_GenesisSeed.sol (inherits this contract; simulate-and-extract).
///         Plain transfers are refused: the vault is funded only through the genesis `alloc`.
contract GenesisClaimsVault {
    uint256 public constant INSTALLMENTS = 24;
    /// @notice Part of every claim already sitting in the claimant's wallet at genesis (gas money).
    uint256 public constant WALLET_PART = 100 ether;

    /// @notice Must equal genesis.json `timestamp`.
    uint256 public genesisTimestamp;
    /// @notice Total Suren held for all claimants at genesis (sum of claim - 100).
    uint256 public totalHeld;

    struct Claim {
        uint256 held;       // claim - 100 Suren: the amount this vault releases
        uint256 withdrawn;
    }

    mapping(address => Claim) private _claims;

    event Withdrawn(address indexed claimant, uint256 amount);

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    /// @notice Calendar month identifier (UTC): year * 12 + (month - 1). Same algorithm as ValidatorsBoard.monthIdOf.
    function monthIdOf(uint256 timestamp) public pure returns (uint256) {
        uint256 z = timestamp / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 year = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) year += 1;
        return year * 12 + (month - 1);
    }

    /// @notice Number of instalments released so far (0..24): 0 during the genesis month, 1 from the first day of the next month.
    function monthsReleased() public view returns (uint256) {
        uint256 first = monthIdOf(genesisTimestamp) + 1;
        uint256 current = monthIdOf(block.timestamp);
        if (current < first) return 0;
        uint256 n = current - first + 1;
        return n > INSTALLMENTS ? INSTALLMENTS : n;
    }

    /// @notice The regular monthly instalment (the last one also carries the rounding remainder).
    function installmentAmount(address claimant) external view returns (uint256) {
        return _claims[claimant].held / INSTALLMENTS;
    }

    /// @notice Released so far (withdrawn or not).
    function releasedOf(address claimant) public view returns (uint256) {
        Claim storage c = _claims[claimant];
        uint256 n = monthsReleased();
        if (n >= INSTALLMENTS) return c.held;
        return (c.held / INSTALLMENTS) * n;
    }

    function withdrawableOf(address claimant) public view returns (uint256) {
        return releasedOf(claimant) - _claims[claimant].withdrawn;
    }

    /// @return held the amount this vault releases for the claimant (claim - 100 Suren)
    /// @return walletPart the 100 Suren that were placed directly in the wallet at genesis
    /// @return released released so far
    /// @return withdrawn already paid out
    function claimInfo(address claimant) external view returns (uint256 held, uint256 walletPart, uint256 released, uint256 withdrawn) {
        Claim storage c = _claims[claimant];
        return (c.held, c.held == 0 ? 0 : WALLET_PART, releasedOf(claimant), c.withdrawn);
    }

    // ------------------------------------------------------------------
    // Withdrawal — only the registered claimant, everything released and not yet withdrawn
    // ------------------------------------------------------------------
    function withdraw() external {
        Claim storage c = _claims[msg.sender];
        require(c.held != 0, "GenesisClaimsVault: no claim for this address");
        uint256 amount = withdrawableOf(msg.sender);
        require(amount > 0, "GenesisClaimsVault: nothing released yet");
        c.withdrawn += amount;
        emit Withdrawn(msg.sender, amount);
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "GenesisClaimsVault: transfer failed");
    }

    receive() external payable {
        revert("GenesisClaimsVault: funded only through the genesis alloc");
    }

    // ------------------------------------------------------------------
    // Genesis seeding (used only by GenesisClaimsVault_GenesisSeed)
    // ------------------------------------------------------------------
    function _seed(address[] memory claimants, uint256[] memory claims, uint256 genesisTimestamp_) internal {
        require(claimants.length == claims.length, "seed: length mismatch");
        genesisTimestamp = genesisTimestamp_;
        for (uint256 i = 0; i < claimants.length; i++) {
            address a = claimants[i];
            require(a != address(0) && _claims[a].held == 0, "seed: bad or duplicate claimant");
            require(claims[i] > WALLET_PART, "seed: claim must exceed the 100 Suren wallet part");
            uint256 held = claims[i] - WALLET_PART;
            _claims[a].held = held;
            totalHeld += held;
        }
    }
}
