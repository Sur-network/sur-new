// SPDX-License-Identifier: MIT
// Throw-away stand-in for the ValidatorsRegistry: Besu QBFT contract mode only calls getValidators() (selector 0xb7ab4db5).
// The validator list is written straight into genesis storage by lab.mjs (slot 0 = length, elements at keccak256(0)+i).
pragma solidity 0.8.26;
contract ToyValidators {
    address[] public v;
    function getValidators() external view returns (address[] memory) { return v; }
}
