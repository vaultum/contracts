// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserOperation} from "../../src/interfaces/IEntryPoint.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";

contract EntryPointMock {
    uint256 public lastValidationData;
    uint256 public fundsReceived;

    function callValidate(IAccount acc, UserOperation calldata op, bytes32 opHash) external returns (uint256) {
        lastValidationData = acc.validateUserOp(op, opHash, 0);
        return lastValidationData;
    }

    function callValidateWithFunds(IAccount acc, UserOperation calldata op, bytes32 opHash, uint256 missingFunds)
        external
        payable
        returns (uint256)
    {
        uint256 beforeBal = address(this).balance;
        lastValidationData = acc.validateUserOp(op, opHash, missingFunds);
        uint256 afterBal = address(this).balance;
        fundsReceived += (afterBal - beforeBal);
        return lastValidationData;
    }

    receive() external payable {}
}