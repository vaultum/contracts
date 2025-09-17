// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/SmartAccount.sol";
import "../src/modules/SocialRecoveryModule.sol";
import "../src/modules/SessionKeyModule.sol";
import "../src/modules/SpendingLimitModule.sol";
import "../src/validators/SessionKeyValidator.sol";

contract DeployTestnet is Script {
    // Sepolia Entry Point (ERC-4337 v0.6)
    address constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("Deploying Vaultum to Testnet");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("EntryPoint:", ENTRY_POINT);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Smart Account
        console.log("Deploying SmartAccount...");
        SmartAccount account = new SmartAccount(deployer);
        account.setEntryPoint(ENTRY_POINT);
        console.log("[OK] SmartAccount:", address(account));
        
        // 2. Deploy Social Recovery Module
        console.log("\nDeploying SocialRecoveryModule...");
        SocialRecoveryModule recoveryModule = new SocialRecoveryModule(address(account));
        console.log("[OK] SocialRecoveryModule:", address(recoveryModule));
        
        // 3. Deploy Session Key Validator
        console.log("\nDeploying SessionKeyValidator...");
        SessionKeyValidator sessionValidator = new SessionKeyValidator(address(account));
        console.log("[OK] SessionKeyValidator:", address(sessionValidator));
        
        // 4. Deploy Session Key Module
        console.log("\nDeploying SessionKeyModule...");
        SessionKeyModule sessionModule = new SessionKeyModule(address(account), address(sessionValidator));
        console.log("[OK] SessionKeyModule:", address(sessionModule));
        
        // 5. Deploy Spending Limit Module
        console.log("\nDeploying SpendingLimitModule...");
        SpendingLimitModule spendingModule = new SpendingLimitModule(address(account));
        console.log("[OK] SpendingLimitModule:", address(spendingModule));
        
        // 6. Configure the Smart Account
        console.log("\n========================================");
        console.log("Configuring SmartAccount...");
        console.log("========================================");
        
        // Add modules
        account.addModule(address(recoveryModule));
        console.log("[OK] Added SocialRecoveryModule");
        
        account.addModule(address(sessionModule));
        console.log("[OK] Added SessionKeyModule");
        
        account.addModule(address(spendingModule));
        console.log("[OK] Added SpendingLimitModule");
        
        // Add validator
        account.addValidator(address(sessionValidator));
        console.log("[OK] Added SessionKeyValidator");
        
        // Authorize recovery module
        account.setRecoveryModule(address(recoveryModule), true);
        console.log("[OK] Authorized SocialRecoveryModule");
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n========================================");
        console.log(">>> Deployment Complete! <<<");
        console.log("========================================");
        console.log("Network: ", getNetworkName());
        console.log("");
        console.log("Core Contracts:");
        console.log("  SmartAccount:          ", address(account));
        console.log("  EntryPoint:            ", ENTRY_POINT);
        console.log("");
        console.log("Modules:");
        console.log("  SocialRecoveryModule:  ", address(recoveryModule));
        console.log("  SessionKeyModule:      ", address(sessionModule));  
        console.log("  SpendingLimitModule:   ", address(spendingModule));
        console.log("");
        console.log("Validators:");
        console.log("  SessionKeyValidator:   ", address(sessionValidator));
        console.log("========================================");
        
        // Save deployment info
        saveDeployment(
            address(account),
            address(recoveryModule),
            address(sessionModule),
            address(spendingModule),
            address(sessionValidator)
        );
    }
    
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 84532) return "Base Sepolia";
        if (chainId == 80001) return "Polygon Mumbai";
        if (chainId == 421614) return "Arbitrum Sepolia";
        if (chainId == 10200) return "Gnosis Chiado";
        return vm.toString(chainId);
    }
    
    function saveDeployment(
        address account,
        address recoveryModule,
        address sessionModule,
        address spendingModule,
        address sessionValidator
    ) internal {
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "network": "', getNetworkName(), '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployer": "', vm.toString(vm.addr(vm.envUint("PRIVATE_KEY"))), '",\n',
            '  "entryPoint": "', vm.toString(ENTRY_POINT), '",\n',
            '  "contracts": {\n',
            '    "SmartAccount": "', vm.toString(account), '",\n',
            '    "SocialRecoveryModule": "', vm.toString(recoveryModule), '",\n',
            '    "SessionKeyModule": "', vm.toString(sessionModule), '",\n',
            '    "SpendingLimitModule": "', vm.toString(spendingModule), '",\n',
            '    "SessionKeyValidator": "', vm.toString(sessionValidator), '"\n',
            '  }\n',
            '}'
        ));
        
        string memory filename = string(abi.encodePacked(
            "deployments/",
            getNetworkName(),
            "-",
            vm.toString(block.timestamp),
            ".json"
        ));
        
        vm.writeFile(filename, json);
        vm.writeFile("deployments/latest.json", json);
        
        console.log("");
        console.log("[FILE] Deployment saved to:");
        console.log("   ", filename);
        console.log("   deployments/latest.json");
    }
}
