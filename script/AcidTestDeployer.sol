// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";

contract AcidTestDeployer is Script, ContractAddresses {
    
    function run() public {
        // Get owner and receiver addresses from environment variables
        address owner = vm.envAddress("OWNER_ADDRESS");
        address receiver = vm.envAddress("RECEIVER_ADDRESS");
        address royaltyRecipient = vm.envAddress("ROYALTY_RECIPIENT");
        uint96 royaltyFee = uint96(vm.envUint("ROYALTY_FEE"));
        string memory contractURI = vm.envString("CONTRACT_URI");
        
        vm.startBroadcast();

        new AcidTest(USDC_BASE_MAINNET, WETH_BASE_MAINNET, owner, AGGREGATOR_V3_BASE_MAINNET, contractURI, royaltyRecipient, royaltyFee);
    
        vm.stopBroadcast();
    }   
}