// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/SmartAccount.sol";
import "../src/validators/SessionKeyValidator.sol";
import "../src/modules/SessionKeyModule.sol";
import "../src/modules/SpendingLimitModule.sol";
import "../src/modules/SocialRecoveryModule.sol";

contract DeployAnvilScript is Script {
    // For local testing, use a dummy entry point
    address constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function run() external returns (
        address sessionKeyValidator,
        address sessionKeyModule,
        address spendingLimitModule,
        address socialRecoveryModule,
        address smartAccount
    ) {
        // Get deployer from environment or use default Anvil account
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerKey);
        
        console.log("=====================================");
        console.log("DEPLOYING TO ANVIL");
        console.log("=====================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        
        vm.startBroadcast(deployerKey);
        
        // Deploy validators
        sessionKeyValidator = address(new SessionKeyValidator(deployer));
        console.log("SessionKeyValidator:", sessionKeyValidator);
        
        // Deploy modules
        sessionKeyModule = address(new SessionKeyModule(sessionKeyValidator, deployer));
        console.log("SessionKeyModule:", sessionKeyModule);
        
        spendingLimitModule = address(new SpendingLimitModule(deployer));
        console.log("SpendingLimitModule:", spendingLimitModule);
        
        socialRecoveryModule = address(new SocialRecoveryModule(deployer));
        console.log("SocialRecoveryModule:", socialRecoveryModule);
        
        // Deploy test account
        smartAccount = address(new SmartAccount(deployer));
        console.log("SmartAccount:", smartAccount);
        
        vm.stopBroadcast();
        
        console.log("=====================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("=====================================");
        
        return (sessionKeyValidator, sessionKeyModule, spendingLimitModule, socialRecoveryModule, smartAccount);
    }
}
