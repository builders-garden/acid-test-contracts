// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";

contract AcidTestTest is Script, ContractAddresses {
    
    function run() public {
        
        uint256 deployerPrivateKey; /*= vm.envUint("PRIVATE_KEY");*/
        /* TODO: add a more secure way to get the private key */ 
        vm.startBroadcast();
        
        bool isTestnet = false;
        
    
        new AcidTest(USDC_BASE_MAINNET, WETH_BASE_MAINNET, msg.sender, AGGREGATOR_V3_BASE_MAINNET, msg.sender);
        
        vm.stopBroadcast();
    }   
}