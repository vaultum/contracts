// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccount} from "./interfaces/IAccount.sol";
import {UserOperation} from "./interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IModule} from "./modules/IModule.sol";
import {ModuleManager} from "./modules/ModuleManager.sol";
import {ValidatorManager} from "./validators/ValidatorManager.sol";
import {ISignatureValidator} from "./validators/ISignatureValidator.sol";

contract SmartAccount is IAccount, ModuleManager, ValidatorManager, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public owner;
    address public entryPoint;

    event Executed(address target, uint256 value, bytes data, bytes result);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event EntryPointSet(address indexed entryPoint);

    error BlockedByModule();

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    modifier onlyEntryPointOrOwner() { require(msg.sender == entryPoint || msg.sender == owner, "not allowed"); _; }
    modifier onlyEntryPoint() { require(msg.sender == entryPoint, "not entrypoint"); _; }
    modifier onlyModule() { require(isModule(msg.sender), "not module"); _; }

    constructor(address _owner) {
        require(_owner != address(0), "zero owner");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function setEntryPoint(address _entryPoint) external onlyOwner {
        require(_entryPoint != address(0), "zero entry");
        entryPoint = _entryPoint;
        emit EntryPointSet(_entryPoint);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setOwnerFromModule(address newOwner) external onlyModule {
        require(newOwner != address(0), "zero owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    // Module management
    function addModule(address module) external onlyOwner {
        _addModule(module);
    }

    function removeModule(address module) external onlyOwner {
        _removeModule(module);
    }

    // Validator management
    function addValidator(address validator) external onlyOwner {
        _addValidator(validator);
    }

    function removeValidator(address validator) external onlyOwner {
        _removeValidator(validator);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external payable onlyEntryPointOrOwner nonReentrant returns (bytes memory result)
    {
        require(target != address(0), "zero target");
        address[] memory list = getModules();
        for (uint256 i = 0; i < list.length; i++) {
            if (!IModule(list[i]).preExecute(msg.sender, target, value, data)) {
                revert BlockedByModule();
            }
        }
        (bool ok, bytes memory res) = target.call{value: value}(data);
        require(ok, "call failed");
        emit Executed(target, value, data, res);
        for (uint256 i2 = 0; i2 < list.length; i2++) {
            IModule(list[i2]).postExecute(msg.sender, target, value, data, res);
        }
        return res;
    }

    /// @notice ERC 4337 callback. Not view anymore, because it may pay missing funds to EntryPoint.
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        bool ok = false;

        // 1) try owner - use tryRecover to handle invalid signatures gracefully
        (address recovered, ECDSA.RecoverError err, ) = userOpHash.toEthSignedMessageHash().tryRecover(userOp.signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            ok = true;
        }

        // 2) try registered validators if not owner
        if (!ok) {
            address[] memory list = getValidators();
            for (uint256 i = 0; i < list.length; i++) {
                if (ISignatureValidator(list[i]).isValidUserOp(userOp.signature, userOpHash)) {
                    ok = true;
                    break;
                }
            }
        }

        // 3) pay missing funds to EntryPoint if needed
        if (missingFunds > 0) {
            // best effort, ignore return
            // solhint-disable-next-line avoid-low-level-calls
            (bool sent, ) = payable(msg.sender).call{value: missingFunds}("");
            sent; // silence warning
        }

        return ok ? 0 : 1;
    }

    receive() external payable {}
}