// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.28;

import {ERC1155} from "openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {IEthWrapper} from "./interfaces/IEthWrapper.sol";
import {IPyth} from "./interfaces/IPyth.sol";
import {PythStructs} from "./interfaces/PythStructs.sol";

contract AcidTest is ERC1155, Ownable, ReentrancyGuard{

    error SalesNotActive(uint256 tokenId);
    error NotEnoughUSD();

    IERC20 public immutable usdc;
    uint internal idCounter;
    address public receiverAddress;
    mapping (uint id=>TokenInfo) public s_tokenInfo;
    IPyth public pyth;
    uint internal eth_usdc_price;   
    bytes32 internal priceFeedId;

    struct TokenInfo {
        uint24 salesStartDate;
        uint24 salesExpirationDate;
        uint208 usdPrice;
        string uri;
    }

    /////////////////////////////////////////////////
    /////////////////// CONSTRUCTOR /////////////////
    /////////////////////////////////////////////////

    constructor(address _usdc, address _owner, address _pyth, address _receiverAddress, bytes32 _priceFeedId)
        ERC1155("AcidTest")
        Ownable(_owner)
    {
        usdc = IERC20(_usdc);   
        pyth = IPyth(_pyth);
        priceFeedId = _priceFeedId;
        receiverAddress = _receiverAddress;
    }    
    
    receive() external payable{}

    /////////////////////////////////////////////////
    ///////////////// ADMIN FUNCTIONS //////////////
    ////////////////////////////////////////////////

    function create(uint24 salesStartDate, uint24 salesExpirationDate, uint208 usdPrice, string memory tokenUri) public onlyOwner{
        ++idCounter;
        s_tokenInfo[idCounter] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri
        });
    }

    
    function modifyTokenInfo(uint256 tokenId, uint24 salesStartDate, uint24 salesExpirationDate, uint208 usdPrice, string memory tokenUri) public onlyOwner{
        s_tokenInfo[tokenId] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri   
        });
    }
    
    function setReceiverAddress(address _receiverAddress) public onlyOwner{
        receiverAddress = _receiverAddress;
    }

    
    /////////////////////////////////////////////////
    ///////////////// USER FUNCTIONS ////////////////
    /////////////////////////////////////////////////

function mint(address to, uint256 tokenId, uint256 amount, bytes[] calldata priceUpdate) external nonReentrant payable {
    TokenInfo memory tokenInfo = s_tokenInfo[tokenId];

    if(
        block.timestamp < tokenInfo.salesStartDate || 
        block.timestamp >= tokenInfo.salesExpirationDate
    ) revert SalesNotActive(tokenId);
    
    if (msg.value > 0 && priceUpdate.length > 0) {
        uint fee = pyth.getUpdateFee(priceUpdate);
        require(msg.value > fee, "Insufficient ETH for price feed update fee");
        
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);

        PythStructs.Price memory ethPrice = pyth.getPriceNoOlderThan(priceFeedId, 60);
        uint256 ethPriceUint = uint256(int256(ethPrice.price));
        
        // Calculate exact ETH required
        uint256 requiredWei = (tokenInfo.usdPrice * amount * 1e18) / ethPriceUint;
        require(msg.value >= requiredWei + fee, "Insufficient ETH provided based on price update");
        
        // Transfer exact amount to receiver
        (bool success,) = receiverAddress.call{value: requiredWei}("");
        require(success, "ETH transfer failed");
        
        // Refund excess ETH if any
        if (msg.value > requiredWei + fee) {
            uint256 excess = msg.value - (requiredWei + fee);
            (bool refunded,) = msg.sender.call{value: excess}("");
            require(refunded, "ETH refund failed");
        }
    } else {
        usdc.transferFrom(msg.sender, receiverAddress, tokenInfo.usdPrice * amount);
    }
    
    _mint(to, tokenId, amount, "");
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
