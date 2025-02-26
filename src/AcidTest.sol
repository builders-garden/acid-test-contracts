// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.28;

import {ERC1155} from "openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AcidTest is ERC1155, Ownable, ReentrancyGuard {

    error SalesNotActive(uint256 tokenId);
    error NotEnoughUSD();
    error InsufficientPayment(uint256 required, uint256 sent);
    error CannotSendETHWithWETH();
    error InvalidReceiverAddress();


    event TokenCreated(uint256 tokenId, TokenInfo tokenInfo);
    event TokenModified(uint256 tokenId, TokenInfo tokenInfo);
    event TokenMinted(address to, uint256 tokenId, uint256 amount, bool isWeth);


    IERC20 public immutable usdc;
    IERC20 public immutable weth;
    uint internal idCounter;
    address public receiverAddress;
    mapping (uint id=>TokenInfo) public s_tokenInfo;
   
 
    AggregatorV3Interface public aggregatorV3;


    struct TokenInfo {
        uint32 salesStartDate;
        uint32 salesExpirationDate;
        uint208 usdPrice;
        string uri;
    }

    /////////////////////////////////////////////////
    /////////////////// CONSTRUCTOR /////////////////
    /////////////////////////////////////////////////

    constructor(address _usdc,
        address _weth, 
        address _owner, 
        address _aggregatorV3, 
        address _receiverAddress
    )
        ERC1155("AcidTest")
        Ownable(_owner)
    {
        usdc = IERC20(_usdc);   
        weth = IERC20(_weth);
        aggregatorV3 = AggregatorV3Interface(_aggregatorV3);
        receiverAddress = _receiverAddress;
    }    
    
    receive() external payable{}

    /////////////////////////////////////////////////
    ///////////////// ADMIN FUNCTIONS //////////////
    ////////////////////////////////////////////////

    function create(
        uint32 salesStartDate,
        uint32 salesExpirationDate, 
        uint208 usdPrice,
        string memory tokenUri
    ) public onlyOwner{
        ++idCounter;
        s_tokenInfo[idCounter] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri
        });

        emit TokenCreated(idCounter, s_tokenInfo[idCounter]);
    }

    
    function modifyTokenInfo(uint256 tokenId,
        uint32 salesStartDate,
        uint32 salesExpirationDate,
        uint208 usdPrice,
        string memory tokenUri
    ) public onlyOwner{
        s_tokenInfo[tokenId] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri   
        }); 

        emit TokenModified(tokenId, s_tokenInfo[tokenId]);
    }
    
    function setReceiverAddress(address _receiverAddress) public onlyOwner{
        if (_receiverAddress == address(0)) revert InvalidReceiverAddress();
        receiverAddress = _receiverAddress;
    }

    
    /////////////////////////////////////////////////
    ///////////////// USER FUNCTIONS ////////////////
    /////////////////////////////////////////////////

    function mint(
        address to,
        uint256 tokenId,
        uint256 amount, 
        bool isWeth
    ) external payable nonReentrant {
        TokenInfo memory tokenInfo = s_tokenInfo[tokenId];


        if(block.timestamp < tokenInfo.salesStartDate || block.timestamp >= tokenInfo.salesExpirationDate) 
            revert SalesNotActive(tokenId);
        
        // Calculate ETH amount once for both paths
        (, int answer,,,) = aggregatorV3.latestRoundData();
        uint256 ethToOneDollar = 1e26 / uint256(answer);
        uint256 requiredEth = (uint256(tokenInfo.usdPrice) * amount * ethToOneDollar) / 1e6;
        
        // Handle payment validation
        if (isWeth) {
            if (msg.value > 0) revert CannotSendETHWithWETH();
        } else if (msg.value > 0) {
            uint256 minRequiredEth = (requiredEth * 99) / 100;
            if (msg.value < minRequiredEth) revert InsufficientPayment(minRequiredEth, msg.value);
        }

        _mint(to, tokenId, amount, "");

        if (isWeth) {
            // WETH payment path
            weth.transferFrom(msg.sender, receiverAddress, requiredEth);
        } else if (msg.value > 0) {
            // Native ETH payment path
            uint256 excess = msg.value - requiredEth;
            if (excess > 0) {
                (bool refundSuccess, ) = msg.sender.call{value: excess}("");
                require(refundSuccess, "Refund failed");
            }
            
            // Transfer the required ETH to receiver
            (bool transferSuccess, ) = receiverAddress.call{value: requiredEth}("");
            require(transferSuccess, "Transfer to receiver failed");
        } else {
            // USDC payment path
            usdc.transferFrom(msg.sender, receiverAddress, tokenInfo.usdPrice * amount);
        }
    }
    
    /////////////////////////////////////////////////   
    ///////////////// VIEW FUNCTIONS ////////////////
    /////////////////////////////////////////////////

    function uri(uint256 tokenId) public view override returns (string memory) {
        return s_tokenInfo[tokenId].uri;
    }

    function getTokenInfo(uint256 tokenId) public view returns (TokenInfo memory) {
        return s_tokenInfo[tokenId];
    }
}       