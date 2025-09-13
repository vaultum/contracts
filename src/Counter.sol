// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Counter {
    uint256 public value;

    function inc(uint256 by) external {
        value += by;
    }
    
    // Allow receiving ETH for testing
    receive() external payable {}
}
