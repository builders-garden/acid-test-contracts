// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";

contract AcidTestTest is Script, ContractAddresses {
    
    function run() public {
        
        address receiverAddress = vm.envAddress("RECEIVER_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        uint256 deployerPrivateKey; /*= vm.envUint("PRIVATE_KEY");*/
        /* TODO: add a more secure way to get the private key */ 
        vm.startBroadcast(deployerPrivateKey);
        
        bool isTestnet = vm.envBool("TESTNET");
        
        if (isTestnet) {
            new AcidTest(USDC_BASE_SEPOLIA, WETH_BASE_SEPOLIA, owner, AGGREGATOR_V3_BASE_SEPOLIA, receiverAddress);
        } else {
            new AcidTest(USDC_BASE_MAINNET, WETH_BASE_MAINNET, owner, AGGREGATOR_V3_BASE_MAINNET, receiverAddress);
        }
        
        vm.stopBroadcast();
    }   
}