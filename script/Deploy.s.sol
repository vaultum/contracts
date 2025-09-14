// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/SmartAccount.sol";
import "../src/modules/ModuleManager.sol";
import "../src/validators/SessionKeyValidator.sol";
import "../src/modules/SessionKeyModule.sol";
import "../src/modules/SpendingLimitModule.sol";

contract DeployScript is Script {
    // Sepolia Entry Point (same for most testnets)
    address constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy validators
        SessionKeyValidator sessionKeyValidator = new SessionKeyValidator(deployer);
        console.log("SessionKeyValidator:", address(sessionKeyValidator));
        
        // Deploy modules
        SessionKeyModule sessionKeyModule = new SessionKeyModule(address(sessionKeyValidator), deployer);
        console.log("SessionKeyModule:", address(sessionKeyModule));
        
        SpendingLimitModule spendingLimitModule = new SpendingLimitModule(deployer);
        console.log("SpendingLimitModule:", address(spendingLimitModule));
        
        // Deploy factory (if needed)
        // SmartAccountFactory factory = new SmartAccountFactory(ENTRY_POINT);
        // console.log("Factory:", address(factory));
        
        // Deploy a test account
        SmartAccount account = new SmartAccount(deployer);
        console.log("Test SmartAccount:", address(account));
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "entryPoint": "', vm.toString(ENTRY_POINT), '",\n',
            '  "sessionKeyValidator": "', vm.toString(address(sessionKeyValidator)), '",\n',
            '  "sessionKeyModule": "', vm.toString(address(sessionKeyModule)), '",\n',
            '  "spendingLimitModule": "', vm.toString(address(spendingLimitModule)), '",\n',
            '  "testAccount": "', vm.toString(address(account)), '"\n',
            "}"
        ));
        
        vm.writeFile("deployments/latest.json", deploymentInfo);
        console.log("\nDeployment saved to deployments/latest.json");
    }
}
