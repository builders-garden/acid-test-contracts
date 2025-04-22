// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

contract AcidTestDeployer is Script, ContractAddresses {
    
    function run() public {
        // Get owner and receiver addresses from environment variables
        address owner = vm.envAddress("OWNER_ADDRESS");
        address royaltyRecipient = vm.envAddress("ROYALTY_RECIPIENT");
        uint96 royaltyFee = uint96(vm.envUint("ROYALTY_FEE"));
        string memory contractURI = vm.envString("CONTRACT_URI");
        
        vm.startBroadcast();

        // Deploy the contract
        AcidTest acidTest = new AcidTest(
            USDC_BASE_MAINNET, 
            WETH_BASE_MAINNET, 
            owner, 
            AGGREGATOR_V3_BASE_MAINNET, 
            "https://tan-petite-thrush-593.mypinata.cloud/ipfs/bafkreifj2bpdihl6td4a5eqvopslzuko3v3zy22i6dusgkmm5no4pgifui", 
            royaltyRecipient, 
            royaltyFee
        );
        
        uint256 usdPrice = 1; // 100 USDC with 6 decimals

        // Create NFT with price of 100 USDC
        acidTest.create(
            uint32(block.timestamp),             // salesStartDate
            uint32(block.timestamp + 30 days),   // salesExpirationDate
            usdPrice,                            // usdPrice (100 USDC)
            "https://tan-petite-thrush-593.mypinata.cloud/ipfs/bafkreicj2av7epp5nxvuilkjzftm5guwvus2jfhtpnvtr6s7qboonivzzq",        // tokenUri
            royaltyRecipient,                    // receiverAddress
            royaltyRecipient,                    // royaltyRecipient
            royaltyFee                           // royaltyFee
        );

        // Calculate ETH amount needed - matching test calculation
        uint256 amount = 1;
        (, int256 answer, , ,) = AggregatorV3Interface(AGGREGATOR_V3_BASE_MAINNET).latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        uint256 requiredEth = (usdPrice * amount * ethToOneDollar) / 1e6;
        
        // Mint token ID 1 with ETH - sending exact amount like in test
        acidTest.mint{value: requiredEth}(
            owner,      // mint to owner
            1,          // tokenId
            amount,     // amount
            false       // not using WETH
        );

        vm.stopBroadcast();
        
        console.log("AcidTest deployed to:", address(acidTest));
        console.log("NFT created with ID: 1");
        console.log("NFT minted to:", owner);
        console.log("ETH spent:", requiredEth);
    }   
}