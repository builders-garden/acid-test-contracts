// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

contract MockERC is ERC20 {    
    constructor(string memory name_, string memory symbol_) 
        ERC20(name_, symbol_)
    {}
}

/// @notice A simple aggregator mock that always returns 2692480000 as the price
contract MockAggregator {
    int256 public constant ANSWER = 138255741564;
    
    function latestRoundData() external view  returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, ANSWER, block.timestamp, block.timestamp, 0);
    }
}

// Attacker contract to test reentrancy protection on mint function.
contract ReentrantAttacker {
    AcidTest public acidTest;
    uint256 public attackCount;
    
    constructor(address payable _acidTest) {
        acidTest = AcidTest(_acidTest);
    }
    
    function attack(uint256 tokenId) external payable {
        acidTest.mint{value: msg.value}(address(this), tokenId, 1, false);
    }
    
    receive() external payable {
        if (attackCount < 5 && address(acidTest).balance >= msg.value) {
            attackCount++;
            acidTest.mint{value: msg.value}(address(this), 1, 1, false);
        }
    }
}

/// @notice Tests for the AcidTest contract.
contract AcidTestTest is Test {
    AcidTest public acidTest;
    MockERC public usdc;
    MockERC public weth;
    MockAggregator public aggregator;
    
    address public owner;
    address public receiver;
    address public user;
    address public metadataOperator;
    // Constants adjusted for decimals
    uint256 public constant INITIAL_USDC_BALANCE = 1000 * 1e6; // 1000 USDC with 18 decimals
    uint256 public constant INITIAL_WETH_BALANCE = 1000 * 1e18; // 1000 WETH with 18 decimals
    uint256 public constant INITIAL_ETH_BALANCE = 1000 * 1e18; // 1000 ETH
    uint256 public constant TOKEN_PRICE = 1e6; // $1
    address public constant AGGREGATOR_V3_BASE_MAINNET = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    function setUp() public {
        owner = vm.addr(117384701234701293471023647012845787238437949884);
        receiver = vm.addr(213287489179103947091823740712364078126304123697482);
        user = vm.addr(1928378213982739817298312548328934136841239840192374);
        metadataOperator = vm.addr(1234567890123456789012345678901234567890);
        // Deploy mocks
        usdc = new MockERC("USD Coin", "USDC");
        weth = new MockERC("Wrapped Ether", "WETH");

        if (block.chainid == 8453) {
            aggregator =  MockAggregator(AGGREGATOR_V3_BASE_MAINNET);
        } else {
            aggregator = new MockAggregator();
        }
        
        // Deploy the AcidTest contract
        vm.prank(owner);
        acidTest = new AcidTest(
            address(usdc),
            address(weth),
            owner,
            address(aggregator),
            "ipfs://QmTNgv3jx2HHfBjQX9RnKtxj2xv2xQDtbVXoRi5rJ3a46e",
            receiver,
            1000
        );
        
        vm.prank(owner);
        address[] memory operators = new address[](1);
        operators[0] = metadataOperator;
        bool[] memory isOperator = new bool[](1);
        isOperator[0] = true;
        acidTest.setOperators(operators, isOperator);
       


        vm.prank(owner);
        acidTest.create(
            uint32(block.timestamp),             // salesStartDate
            uint32(block.timestamp + 1 days),    // salesExpirationDate
            uint208(TOKEN_PRICE),                // usdPrice ($1)
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1",        // tokenUri
            receiver, 
            receiver, 
            1000
        );
        
        
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(acidTest)));
        
        // Fund the user with USDC, WETH, and ETH
        vm.deal(user, INITIAL_ETH_BALANCE);
        deal(address(usdc), user, INITIAL_USDC_BALANCE);
        deal(address(weth), user, INITIAL_WETH_BALANCE);


        assertEq(address(acidTest.usdc()), address(usdc));
        assertEq(address(acidTest.weth()), address(weth));
        assertEq(address(acidTest.aggregatorV3()), address(aggregator));
        assertEq(acidTest.owner(), owner);
        
    }

    function test_TokenCreation() public view {
        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        assertEq(info.salesStartDate, uint32(block.timestamp));
        assertEq(info.salesExpirationDate, uint32(block.timestamp + 1 days));
        assertEq(info.usdPrice, TOKEN_PRICE);
        assertEq(info.uri, "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1");
    }
 


    function test_TokenCreationFromNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        acidTest.create(
            uint32(block.timestamp),             // salesStartDate
            uint32(block.timestamp + 1 days),    // salesExpirationDate
            uint208(TOKEN_PRICE),                // usdPrice ($1 in 18 decimals)
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1",        // tokenUri
            receiver, 
            receiver, 
            1000
        );
    }

       
    function test_MintWithUSDC() public {
        uint256 amount = 1;
        uint256 payment = TOKEN_PRICE * amount;
         
        vm.startPrank(user);
        usdc.approve(address(acidTest), payment);
        acidTest.mint(user, 1, amount, false);
        vm.stopPrank();

        assertEq(acidTest.balanceOf(user, 1), amount);
        assertEq(usdc.balanceOf(receiver), payment);
        assertEq(usdc.balanceOf(user), INITIAL_USDC_BALANCE - payment);
    }

    
    function test_MintWithETH() public {
        uint256 amount = 1;
        (, int256 answer, , ,) = aggregator.latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        uint256 requiredEth = (uint256(TOKEN_PRICE) * amount * ethToOneDollar) / 1e6;
        
        // Calculate minimum required ETH (99% of required amount due to slippage)
        uint256 minRequiredEth = (requiredEth * 99) / 100;
        
        // Log the amount in USDC
        console.log("Amount in USDC:", TOKEN_PRICE * amount);

        vm.startPrank(user);
        // Send exactly the required amount
        acidTest.mint{value: requiredEth}(user, 1, amount, false);
        vm.stopPrank();

        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        
        // Add descriptive messages to assertions
        assertEq(acidTest.balanceOf(user, 1), amount, "User balance should match the minted amount");
        assertEq(address(info.receiverAddress).balance, requiredEth, "Receiver balance should match the required ETH");
        assertEq(user.balance, INITIAL_ETH_BALANCE - requiredEth * amount, "User's ETH balance should be reduced by the required ETH");

        console.logUint(requiredEth);
    }

    function test_RevertInsufficientETHPayment() public {
        uint256 amount = 1;
        (, int256 answer, , ,) = aggregator.latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        uint256 requiredEth = (TOKEN_PRICE * amount * ethToOneDollar) / 1e6;
        uint256 minRequiredEth = (requiredEth * 99) / 100; // 1% slippage allowance
        
        vm.startPrank(user);
        // Try to mint with insufficient ETH - send a small amount to trigger ETH path
        vm.expectRevert(abi.encodeWithSelector(AcidTest.CannotSendETHWithWETH.selector));
        acidTest.mint{value: minRequiredEth / 2}(user, 1, amount, true);  // isWeth is true

        vm.expectRevert(abi.encodeWithSelector(AcidTest.InsufficientPayment.selector, minRequiredEth, minRequiredEth / 2));
        acidTest.mint{value: minRequiredEth / 2}(user, 1, amount, false); // isWeth is false
        vm.stopPrank();
    }

 
    function test_MintWithETHRefund() public {
        uint256 amount = 1;
        (, int256 answer, , ,) = aggregator.latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        uint256 requiredEth = (TOKEN_PRICE * amount * ethToOneDollar) / 1e6;
        
        // Send extra ETH so that a refund is triggered.
        uint256 overpayment = requiredEth + 0.2 ether;
        
        vm.prank(user);
        acidTest.mint{value: overpayment}(user, 1, amount, false);
        
        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        // Verify token minting.
        assertEq(acidTest.balanceOf(user, 1), amount);
        // After refund, the contract should only have kept exactly the 'requiredEth'.
        assertEq(address(info.receiverAddress).balance, requiredEth);
        // (Note: Due to gas costs, checking the user's balance exactly is not reliable in tests.)
    }
  
    function test_MintWithWETH() public {
        uint256 amount = 3;
        (, int256 answer, , ,) = aggregator.latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        // Adjust for 18 decimals
        uint256 requiredWeth = (TOKEN_PRICE * amount * ethToOneDollar) / 1e6;
        
        vm.startPrank(user);
        weth.approve(address(acidTest), requiredWeth);
        acidTest.mint(user, 1, amount, true);
        vm.stopPrank();
        
        assertEq(acidTest.balanceOf(user, 1), amount);
        assertEq(weth.balanceOf(receiver), requiredWeth);
        assertEq(weth.balanceOf(user), INITIAL_WETH_BALANCE - requiredWeth);
    }


    function test_RevertWhenSaleNotStarted() public {
        // Create a new token (tokenId 2) with a future start date.
        vm.prank(owner);
        acidTest.create(
            uint32(block.timestamp + 1 hours),
            uint32(block.timestamp + 2 hours),
            uint208(TOKEN_PRICE),
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/2",
            receiver, 
            receiver, 
            1000
        );
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AcidTest.SalesNotActive.selector, 2));
        acidTest.mint(user, 2, 1, false);
    }
    
    
    function test_RevertWhenSaleExpired() public {
        // Warp time to after the expiration of token 1.
        vm.warp(block.timestamp + 2 days);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AcidTest.SalesNotActive.selector, 1));
        acidTest.mint(user, 1, 1, false);
    }

  
    function test_RevertWithInsufficientUSDC() public {
        console.log("usdc address ", address(usdc));
        console.log("user address ", user);
        vm.startPrank(user);
        // First approve spending
        usdc.approve(address(acidTest), type(uint256).max);
        // Then drain the balance
        usdc.transfer(address(0x1), usdc.balanceOf(user));
        
        vm.expectRevert(abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector,
            user,
            0,
            TOKEN_PRICE
        ));
        acidTest.mint(user, 1, 1, false);
        vm.stopPrank();
    }
    
    function test_MultipleTokenCreations() public {
        for (uint i=2; i < 11; i++) {
            vm.prank(owner);
            acidTest.create(
                uint32(block.timestamp),
                uint32(block.timestamp + 1 days),
                uint208(TOKEN_PRICE),   
                "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/n",
                receiver, 
                receiver, 
                1000
            );
        }
        for (uint i=2; i <11; i++){
            assertEq(acidTest.getTokenInfo(i).salesStartDate, uint32(block.timestamp));
            assertEq(acidTest.getTokenInfo(i).salesExpirationDate, uint32(block.timestamp + 1 days));
            assertEq(acidTest.getTokenInfo(i).usdPrice, TOKEN_PRICE);
            assertEq(acidTest.getTokenInfo(i).uri, "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/n");      
        }
    }

    function test_ModifyTokenInfo() public {
        uint32 newStartDate = uint32(block.timestamp + 1 days);
        uint32 newEndDate = uint32(block.timestamp + 2 days);
        uint208 newPrice = uint208(TOKEN_PRICE * 2); // Explicit casting
        string memory newUri = "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1/updated";
        address newReceiver = vm.addr(4);
        vm.prank(owner);
        acidTest.modifyTokenInfo(1, newStartDate, newEndDate, newPrice, newUri, newReceiver);
        
        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        assertEq(info.salesStartDate, newStartDate);
        assertEq(info.salesExpirationDate, newEndDate);
        assertEq(info.usdPrice, newPrice);
        assertEq(info.uri, newUri);
        assertEq(info.receiverAddress, newReceiver);
    }
    
   
    
    function test_RevertModifyTokenInfoNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        acidTest.modifyTokenInfo(1, 0, 0, 0, "", address(0x1));
    }


    function test_PreventReentrantMint() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(acidTest)));
        
        vm.expectRevert();
        attacker.attack{value: 1 ether}(1);
        
        assertEq(acidTest.balanceOf(address(attacker), 1), 0);
    }

    function test_GetTokenInfos() public {
        // Create multiple tokens directly in the test
        for (uint i = 1; i <= 5; i++) {
            vm.prank(owner);
            acidTest.create(
                uint32(block.timestamp),             // salesStartDate
                uint32(block.timestamp + 1 days),    // salesExpirationDate
                uint208(TOKEN_PRICE * i),            // usdPrice ($1, $2, $3, ...)
                string(abi.encodePacked("ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/", i)),// tokenUri
                receiver, 
                receiver, 
                1000
            );
        }

        // Retrieve token infos for token IDs 1 to 5
        AcidTest.TokenInfo[] memory tokenInfos = acidTest.getTokenInfos(2, 6);

        // Check the length of the returned array
        assertEq(tokenInfos.length, 5);

        // Verify the details of each token
        for (uint i = 1; i <= 5; i++) {
            // Print actual values for debugging
            console.log("Expected URI:", string(abi.encodePacked("ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/", i)));
            console.log("Actual URI:", tokenInfos[i - 1].uri);

            assertEq(tokenInfos[i - 1].salesStartDate, uint32(block.timestamp));
            assertEq(tokenInfos[i - 1].salesExpirationDate, uint32(block.timestamp + 1 days));
            assertEq(tokenInfos[i - 1].usdPrice, uint208(TOKEN_PRICE * i));
            assertEq(tokenInfos[i - 1].uri, string(abi.encodePacked("ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/", i)));
        }
    }

    function test_TransferOwnership() public {
        // Check initial owner
        assertEq(acidTest.owner(), owner);
        address newOwner = address(123);
        // Transfer ownership to newOwner
        vm.prank(owner);
        acidTest.transferOwnership(newOwner);

        // Check new owner
        assertEq(acidTest.owner(), newOwner);
    }

    function test_TransferOwnership_NotOwner() public {
        address newOwner = address(123);
        // Attempt to transfer ownership from a non-owner account
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        acidTest.transferOwnership(newOwner);
    }

    function test_SetContractURI() public {
        string memory newContractURI = "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/contract/1";
        vm.prank(metadataOperator);
        acidTest.setContractURI(newContractURI);
        assertEq(acidTest.contractURI(), newContractURI);
        newContractURI = "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/contract/2";
        vm.prank(owner);
        acidTest.setContractURI(newContractURI);
        assertEq(acidTest.contractURI(), newContractURI);
    }

    function test_SetContractURI_NotMetadataOperator() public {
        string memory newContractURI = "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/contract/1";
        vm.prank(user);
        vm.expectRevert();
        acidTest.setContractURI(newContractURI);
    }
    
    function test_SetOperators() public {
        
        address[] memory operators = new address[](1);
        operators[0] = metadataOperator;
        bool[] memory isOperator = new bool[](1);
        isOperator[0] = true;
        vm.prank(owner);
        acidTest.setOperators(operators, isOperator);

        // Call s_operators as a function with the metadataOperator as parameter
        vm.prank(owner);
        bool isOp = acidTest.s_operators(metadataOperator);
        assertEq(isOp, true); 

        isOperator[0] = false;
        vm.prank(owner);
        acidTest.setOperators(operators, isOperator);
        isOp = acidTest.s_operators(metadataOperator);
        assertEq(isOp, false);
    }   

    function test_SetOperators_NotOwner() public {
        vm.prank(metadataOperator);
        vm.expectRevert();
        acidTest.setOperators(new address[](0), new bool[](0));
    }   


    function test_royaltyInfo() public {
        (address receiver, uint256 royaltyAmount) = acidTest.royaltyInfo(1, 1e18);
        assertEq(receiver, receiver);
        assertEq(royaltyAmount, 1e18 / 10);
    }
    
    function test_tokenRoyalty() public {
        // Test for token 1 which was created in setUp with 1000 (10%) royalty fee
        uint256 salePrice = 1 ether;
        (address royaltyReceiver, uint256 royaltyAmount) = acidTest.royaltyInfo(1, salePrice);
        
        // Check receiver is correct (should be the 'receiver' address from setUp)
        assertEq(royaltyReceiver, receiver);
        
        // Check royalty amount is 10% of sale price (1000 = 10%)
        assertEq(royaltyAmount, salePrice / 10);
        
        // Test for a different sale price
        salePrice = 5 ether;
        (royaltyReceiver, royaltyAmount) = acidTest.royaltyInfo(1, salePrice);
        assertEq(royaltyAmount, salePrice / 10);
    }
    
    function test_setRoyalty() public {
        address newReceiver = address(0x99);
        vm.prank(owner);
        acidTest.setRoyalty(1, newReceiver, 1000);
        
        (address royaltyReceiver, uint256 royaltyAmount) = acidTest.royaltyInfo(1, 1e18);
        assertEq(royaltyReceiver, newReceiver);
        assertEq(royaltyAmount, 1e18 / 10);
    }   


    function test_mintUnexistentToken() public {
        vm.expectRevert();
        acidTest.mint(user, 1000, 1, false);
    }
}