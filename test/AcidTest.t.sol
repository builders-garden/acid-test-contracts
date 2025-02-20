// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AcidTest} from "../src/AcidTest.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockERC is ERC20 {    
    constructor(string memory name_, string memory symbol_) 
        ERC20(name_, symbol_)
    {}
}

/// @notice A simple aggregator mock that always returns 2692480000 as the price
contract MockAggregator {
    int256 public constant ANSWER = 2692480000;

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

    // Constants adjusted for decimals
    uint256 public constant INITIAL_USDC_BALANCE = 1000 * 1e6; // 1000 USDC with 18 decimals
    uint256 public constant INITIAL_WETH_BALANCE = 1000 * 1e18; // 1000 WETH with 18 decimals
    uint256 public constant INITIAL_ETH_BALANCE = 1000 * 1e18; // 1000 ETH
    uint256 public constant TOKEN_PRICE = 1e6; // $1

    function setUp() public {
        owner = vm.addr(1);
        receiver = vm.addr(2);
        user = vm.addr(3);
        
        // Deploy mocks
        usdc = new MockERC("USD Coin", "USDC");
        weth = new MockERC("Wrapped Ether", "WETH");
        aggregator = new MockAggregator();
        
        // Deploy the AcidTest contract
        vm.prank(owner);
        acidTest = new AcidTest(
            address(usdc),
            address(weth),
            owner,
            address(aggregator),
            receiver
        );
        
        // Create a token on sale (tokenId will be 1)
        vm.prank(owner);
        acidTest.create(
            uint24(block.timestamp),             // salesStartDate
            uint24(block.timestamp + 1 days),    // salesExpirationDate
            uint208(TOKEN_PRICE),                // usdPrice ($1)
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1"        // tokenUri
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
        assertEq(acidTest.receiverAddress(), receiver);
    }

    function test_TokenCreation() public view {
        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        assertEq(info.salesStartDate, uint24(block.timestamp));
        assertEq(info.salesExpirationDate, uint24(block.timestamp + 1 days));
        assertEq(info.usdPrice, TOKEN_PRICE);
        assertEq(info.uri, "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1");
    }
 


    function test_TokenCreationFromNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        acidTest.create(
            uint24(block.timestamp),             // salesStartDate
            uint24(block.timestamp + 1 days),    // salesExpirationDate
            uint208(TOKEN_PRICE),                // usdPrice ($1 in 18 decimals)
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1"        // tokenUri
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
        // Calculate required ETH amount with better precision
        uint256 requiredEth = (uint256(TOKEN_PRICE) * amount * 1e26) / uint256(answer) / 1e6;
        
        // Calculate minimum required ETH (99% of required amount due to slippage)
        uint256 minRequiredEth = (requiredEth * 99) / 100;
        
        vm.startPrank(user);
        // Send exactly the required amount
        acidTest.mint{value: requiredEth}(user, 1, amount, false);
        vm.stopPrank();

        assertEq(acidTest.balanceOf(user, 1), amount);
        assertEq(address(acidTest.receiverAddress()).balance, requiredEth);
        assertEq(user.balance, INITIAL_ETH_BALANCE - requiredEth * amount);
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
        
        // Verify token minting.
        assertEq(acidTest.balanceOf(user, 1), amount);
        // After refund, the contract should only have kept exactly the 'requiredEth'.
        assertEq(address(acidTest.receiverAddress()).balance, requiredEth);
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
            uint24(block.timestamp + 1 hours),
            uint24(block.timestamp + 2 hours),
            uint208(TOKEN_PRICE),
            "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/2"
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
                uint24(block.timestamp),
                uint24(block.timestamp + 1 days),
                uint208(TOKEN_PRICE),   
                "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/n"
            );
        }
        for (uint i=2; i <11; i++){
            assertEq(acidTest.getTokenInfo(i).salesStartDate, uint24(block.timestamp));
            assertEq(acidTest.getTokenInfo(i).salesExpirationDate, uint24(block.timestamp + 1 days));
            assertEq(acidTest.getTokenInfo(i).usdPrice, TOKEN_PRICE);
            assertEq(acidTest.getTokenInfo(i).uri, "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/n");      
        }
    }

    function test_ModifyTokenInfo() public {
        uint24 newStartDate = uint24(block.timestamp + 1 days);
        uint24 newEndDate = uint24(block.timestamp + 2 days);
        uint208 newPrice = uint208(TOKEN_PRICE * 2); // Explicit casting
        string memory newUri = "ipfs://QmS4ghgMgPXDqF3aSaW34D2WQJQf6XeT3b3Y5eF2F2F/token/1/updated";

        vm.prank(owner);
        acidTest.modifyTokenInfo(1, newStartDate, newEndDate, newPrice, newUri);
        
        AcidTest.TokenInfo memory info = acidTest.getTokenInfo(1);
        assertEq(info.salesStartDate, newStartDate);
        assertEq(info.salesExpirationDate, newEndDate);
        assertEq(info.usdPrice, newPrice);
        assertEq(info.uri, newUri);
    }
    
    function test_SetReceiverAddress() public {
        address newReceiver = vm.addr(4);
        
        vm.prank(owner);
        acidTest.setReceiverAddress(newReceiver);
        assertEq(acidTest.receiverAddress(), newReceiver);
    }
    
    function test_RevertModifyTokenInfoNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        acidTest.modifyTokenInfo(1, 0, 0, 0, "");
    }
    
    function test_RevertSetReceiverAddressNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        acidTest.setReceiverAddress(address(0x1));
    }


    function test_PreventReentrantMint() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(acidTest)));
        
        vm.expectRevert();
        attacker.attack{value: 1 ether}(1);
        
        assertEq(acidTest.balanceOf(address(attacker), 1), 0);
    }
}