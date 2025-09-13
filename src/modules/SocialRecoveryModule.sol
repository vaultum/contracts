// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IModule} from "./IModule.sol";

interface ISmartAccountOwner {
    function setOwnerFromModule(address newOwner) external;
}

contract SocialRecoveryModule is IModule {
    address public immutable account;

    mapping(address => bool) public guardian;
    uint256 public threshold;
    uint64 public timelock; // seconds

    address public pendingOwner;
    uint64 public proposedAt;
    uint256 public approvals; // bitmap style in later sprints, simple counter for now
    mapping(address => bool) public approved; // per proposal approvals

    event GuardianSet(address indexed g, bool isGuardian);
    event ThresholdSet(uint256 n);
    event TimelockSet(uint64 seconds_);
    event RecoveryProposed(address indexed newOwner, uint64 at);
    event Approved(address indexed g, address indexed newOwner, uint256 approvals);
    event Executed(address indexed newOwner);

    modifier onlyAccount() { require(msg.sender == account, "not account"); _; }
    modifier onlyGuardian() { require(guardian[msg.sender], "not guardian"); _; }

    constructor(address _account, address[] memory initialGuardians, uint256 _threshold, uint64 _timelock) {
        require(_account != address(0), "zero account");
        account = _account;
        require(_threshold > 0, "zero threshold");
        threshold = _threshold;
        timelock = _timelock;
        for (uint256 i = 0; i < initialGuardians.length; i++) {
            guardian[initialGuardians[i]] = true;
            emit GuardianSet(initialGuardians[i], true);
        }
        emit ThresholdSet(_threshold);
        emit TimelockSet(_timelock);
    }

    function setGuardian(address g, bool isG) external onlyAccount {
        guardian[g] = isG;
        emit GuardianSet(g, isG);
    }

    function setThreshold(uint256 n) external onlyAccount {
        require(n > 0, "zero n");
        threshold = n;
        emit ThresholdSet(n);
    }

    function setTimelock(uint64 seconds_) external onlyAccount {
        timelock = seconds_;
        emit TimelockSet(seconds_);
    }

    function propose(address newOwner) external onlyGuardian {
        require(newOwner != address(0), "zero owner");
        // reset state for new proposal
        pendingOwner = newOwner;
        proposedAt = uint64(block.timestamp);
        approvals = 0;
        // reset approvals mapping lazily in later sprints, for now each change invalidates old approvals
        emit RecoveryProposed(newOwner, proposedAt);
        // implicit self approval
        _approveInternal(msg.sender);
    }

    function approve() external onlyGuardian {
        require(pendingOwner != address(0), "no proposal");
        _approveInternal(msg.sender);
    }

    function _approveInternal(address g) internal {
        if (!approved[g]) {
            approved[g] = true;
            approvals += 1;
            emit Approved(g, pendingOwner, approvals);
        }
    }

    function execute() external onlyGuardian returns (bool) {
        require(pendingOwner != address(0), "no proposal");
        require(approvals >= threshold, "not enough approvals");
        require(block.timestamp >= proposedAt + timelock, "timelock");
        ISmartAccountOwner(account).setOwnerFromModule(pendingOwner);
        emit Executed(pendingOwner);
        // clear proposal
        pendingOwner = address(0);
        proposedAt = 0;
        approvals = 0;
        return true;
    }

    // module hook no-op
    function preExecute(address, address, uint256, bytes calldata) external override returns (bool) { return true; }
    function postExecute(address, address, uint256, bytes calldata, bytes calldata) external override returns (bool) { return true; }
}
