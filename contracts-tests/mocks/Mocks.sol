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
