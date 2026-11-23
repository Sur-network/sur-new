// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Test-only mocks. Never part of the production contract set.

contract MockCounter {
    uint256 public n;
    address public lastCaller;
    function inc(uint256 x) external payable { n += x; lastCaller = msg.sender; }
    function fail() external pure { revert("MockCounter: boom"); }
}

contract MockSale {
    string public lastCall;
    address public lastAccount;
    address public lastAccount2;
    uint256 public lastNum;
    string public lastName;
    address public lastCaller;
    function _rec(string memory c, address a, address b, uint256 x) private { lastCall = c; lastAccount = a; lastAccount2 = b; lastNum = x; lastCaller = msg.sender; }
    function registerExchange(address a, string calldata name, uint256 q) external { _rec("registerExchange", a, address(0), q); lastName = name; }
    function setExchangeQuota(address a, uint256 q) external { _rec("setExchangeQuota", a, address(0), q); }
    function changeExchangeKey(address o, address n_) external { _rec("changeExchangeKey", o, n_, 0); }
    function resumeExchange(address a) external { _rec("resumeExchange", a, address(0), 0); }
    function removeExchange(address a) external { _rec("removeExchange", a, address(0), 0); }
    function setTotalCap(uint256 c) external { _rec("setTotalCap", address(0), address(0), c); }
    function sweepUnsold(address to) external { _rec("sweepUnsold", to, address(0), 0); }
    function pauseExchange(address a) external { _rec("pauseExchange", a, address(0), 0); }
}

contract MockIdentity {
    address public oracle;
    address public lastCaller;
    mapping(address => bool) public verified;
    function setIdentityOracle(address o) external { oracle = o; lastCaller = msg.sender; }
    function setVerified(address who, bool v) external { verified[who] = v; }
    function isFullyVerified(address who) external view returns (bool) { return verified[who]; }
}

contract MockLotteryRegistry {
    mapping(address => bool) public entered;
    uint256 public enteredCount;
    bool public failing;
    function setFailing(bool f) external { failing = f; }
    function enterAsLotteryWinner(address w) external {
        require(!failing, "MockRegistry: refuses");
        entered[w] = true;
        enteredCount++;
    }
}

contract MockDistributor {
    function receiveMembershipFee() external payable {}
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 x) external { balanceOf[to] += x; }
    function transfer(address to, uint256 x) external returns (bool) {
        require(balanceOf[msg.sender] >= x, "MockToken: balance");
        balanceOf[msg.sender] -= x; balanceOf[to] += x; return true;
    }
}

contract MockLottery {
    uint256 public price;
    uint256 public winners;
    uint256 public closeTime;
    address public lastCaller;
    function startLottery(uint256 p, uint256 w, uint256 c) external { price = p; winners = w; closeTime = c; lastCaller = msg.sender; }
}

interface IMockReg { function requestMembership(address operator) external payable; }
interface IMockDist { function claim() external; }

/// @dev Test-only owner with code: can enter the Registry (also from its constructor, where code.length is still 0), has a switchable receive(),
///      and can try to re-enter claim() while it is being paid.
contract MockSeatOwner {
    bool public rejectPayments;
    bool public attack;
    address public dist;
    bool public reenterSucceeded;
    bytes public reenterReason;
    uint256 public received;

    constructor(address reg, address operator) payable {
        if (reg != address(0)) IMockReg(reg).requestMembership{value: msg.value}(operator);
    }
    function enter(address reg, address operator) external payable { IMockReg(reg).requestMembership{value: msg.value}(operator); }
    function setReject(bool r) external { rejectPayments = r; }
    function setAttack(bool a, address d) external { attack = a; dist = d; }
    function callClaim(address d) external { IMockDist(d).claim(); }
    function sellSeat(address nft, uint256 id, address to) external {
        (bool ok, bytes memory r) = nft.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), to, id));
        if (!ok) { assembly { revert(add(r, 32), mload(r)) } }
    }
    receive() external payable {
        require(!rejectPayments, "MockSeatOwner: rejects payments");
        received += msg.value;
        if (attack) {
            try IMockDist(dist).claim() { reenterSucceeded = true; } catch (bytes memory r) { reenterReason = r; }
        }
    }
}

/// @dev Test-only stand-in for ValidatorsBoard in the reward-rate tests: board authority and the composition version are set by hand
///      (the real board rotates every month, which is irrelevant to the rate rules and would need a vote round per month in a 6-month test).
contract MockBoard {
    uint256 public boardVersion; // (starts at 0: no storage initialisers run when only the runtime code is installed)
    mapping(address => bool) public auth;
    function setAuth(address a, bool v) external { auth[a] = v; }
    function bumpVersion() external { boardVersion++; }
    function hasBoardAuthority(address a) external view returns (bool) { return auth[a]; }
    function isBoardMember(address a) external view returns (bool) { return auth[a]; }
    function syncVoter(address) external {}
}

/// @dev Test-only Registry for the genesis-freeze tests of BlockRewardDistributor: everybody is an active validator, and the genesis
///      time (normally seeded by the Registry genesis helper) is set by hand, including 0 (= never seeded).
contract MockRateRegistry {
    uint256 public genesisTime; // (no storage initialisers: the tests install the runtime code only)
    function setGenesisTime(uint256 g) external { genesisTime = g; }
    function statusNonce() external pure returns (uint256) { return 1; }
    function isValidator(address) external pure returns (bool) { return true; }
    function wasActiveAt(address, uint256) external pure returns (bool) { return true; }
    function everActivated(address) external pure returns (bool) { return true; }
    function getActiveValidatorCount() external pure returns (uint256) { return 1; }
    function membershipEpoch(address) external pure returns (uint256) { return 0; }
}
