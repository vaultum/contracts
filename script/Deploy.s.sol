// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {SocialRecoveryModule} from "../src/modules/SocialRecoveryModule.sol";
import {SessionKeyModule} from "../src/modules/SessionKeyModule.sol";
import {SessionKeyValidator} from "../src/validators/SessionKeyValidator.sol";
import {SpendingLimitModule} from "../src/modules/SpendingLimitModule.sol";

/**
 * @title Deploy
 * @notice Professional deployment script for Vaultum smart contracts
 * @dev Uses environment variables for configuration, supports simulation and broadcast
 */
contract Deploy is Script {
    // Deployment artifacts
    SmartAccount public account;
    SocialRecoveryModule public recoveryModule;
    SessionKeyModule public sessionModule;
    SessionKeyValidator public sessionValidator;
    SpendingLimitModule public spendingModule;
    
    function run() external {
        // Load configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address entryPoint = vm.envOr("ENTRYPOINT", address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789));
        
        // Derive deployer address
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("========================================");
        console2.log("Deploying Vaultum Smart Account System");
        console2.log("========================================");
        console2.log("Deployer:", deployer);
        console2.log("EntryPoint:", entryPoint);
        console2.log("Chain ID:", block.chainid);
        console2.log("");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy SmartAccount
        console2.log("Deploying SmartAccount...");
        account = new SmartAccount(deployer);
        account.setEntryPoint(entryPoint);
        console2.log("  SmartAccount:", address(account));
        
        // 2. Deploy SocialRecoveryModule
        console2.log("Deploying SocialRecoveryModule...");
        recoveryModule = new SocialRecoveryModule(address(account));
        console2.log("  SocialRecoveryModule:", address(recoveryModule));
        
        // 3. Deploy SessionKeyValidator
        console2.log("Deploying SessionKeyValidator...");
        sessionValidator = new SessionKeyValidator(address(account));
        console2.log("  SessionKeyValidator:", address(sessionValidator));
        
        // 4. Deploy SessionKeyModule
        console2.log("Deploying SessionKeyModule...");
        sessionModule = new SessionKeyModule(address(account), address(sessionValidator));
        console2.log("  SessionKeyModule:", address(sessionModule));
        
        // 5. Deploy SpendingLimitModule
        console2.log("Deploying SpendingLimitModule...");
        spendingModule = new SpendingLimitModule(address(account));
        console2.log("  SpendingLimitModule:", address(spendingModule));
        
        // 6. Configure SmartAccount
        console2.log("\nConfiguring SmartAccount...");
        
        // Add modules
        account.addModule(address(recoveryModule));
        console2.log("  Added SocialRecoveryModule");
        
        account.addModule(address(sessionModule));
        console2.log("  Added SessionKeyModule");
        
        account.addModule(address(spendingModule));
        console2.log("  Added SpendingLimitModule");
        
        // Add validator
        account.addValidator(address(sessionValidator));
        console2.log("  Added SessionKeyValidator");
        
        // Authorize recovery module
        account.setRecoveryModule(address(recoveryModule), true);
        console2.log("  Authorized SocialRecoveryModule for recovery");
        
        vm.stopBroadcast();
        
        // Print deployment summary
        _printSummary();
        
        // Save deployment artifacts
        _saveDeployment();
    }
    
    function _printSummary() internal view {
        console2.log("\n========================================");
        console2.log("Deployment Complete!");
        console2.log("========================================");
        console2.log("SmartAccount:", address(account));
        console2.log("SocialRecoveryModule:", address(recoveryModule));
        console2.log("SessionKeyModule:", address(sessionModule));
        console2.log("SessionKeyValidator:", address(sessionValidator));
        console2.log("SpendingLimitModule:", address(spendingModule));
        console2.log("========================================");
    }
    
    function _saveDeployment() internal {
        string memory chainName = _getChainName();
        string memory timestamp = vm.toString(block.timestamp);
        
        // Create deployment JSON
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "chain": "', chainName, '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployer": "', vm.toString(vm.addr(vm.envUint("PRIVATE_KEY"))), '",\n',
            '  "timestamp": ', timestamp, ',\n',
            '  "contracts": {\n',
            '    "SmartAccount": "', vm.toString(address(account)), '",\n',
            '    "SocialRecoveryModule": "', vm.toString(address(recoveryModule)), '",\n',
            '    "SessionKeyModule": "', vm.toString(address(sessionModule)), '",\n',
            '    "SessionKeyValidator": "', vm.toString(address(sessionValidator)), '",\n',
            '    "SpendingLimitModule": "', vm.toString(address(spendingModule)), '"\n',
            '  },\n',
            '  "entryPoint": "', vm.toString(vm.envOr("ENTRYPOINT", address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789))), '"\n',
            '}'
        ));
        
        // Save to deployments directory
        string memory filename = string(abi.encodePacked("deployments/", chainName, "-", timestamp, ".json"));
        vm.writeFile(filename, json);
        vm.writeFile("deployments/latest.json", json);
        
        console2.log("\nDeployment saved to:", filename);
    }
    
    function _getChainName() internal view returns (string memory) {
        if (block.chainid == 1) return "mainnet";
        if (block.chainid == 11155111) return "sepolia";
        if (block.chainid == 31337) return "anvil";
        return vm.toString(block.chainid);
    }
}