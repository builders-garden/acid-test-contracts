// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.28;

import {ERC1155} from "openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC2981} from "openzeppelin/contracts/token/common/ERC2981.sol";

/// @title AcidTest - An ERC1155 NFT contract with multiple payment options and royalty support
/// @notice This contract implements an ERC1155 token with USDC, ETH, and WETH payment options
/// @dev Inherits from ERC1155, Ownable, ReentrancyGuard, and ERC2981 for royalty support
contract AcidTest is ERC1155, Ownable, ReentrancyGuard, ERC2981 {

    // ======================= Errors =======================
    error SalesNotActive(uint256 tokenId);
    error NotEnoughUSD();
    error InsufficientPayment(uint256 required, uint256 sent);
    error CannotSendETHWithWETH();
    error NotOperatorOrOwner();

    // ======================= Events =======================
    event TokenCreated(uint256 tokenId, TokenInfo tokenInfo);
    event TokenInfoUpdated(uint256 tokenId, TokenInfo tokenInfo);
    event TokenURIUpdated(uint256 tokenId, string tokenURI);
    event ContractURIUpdated(string newContractURI);
    event OperatorsStateChanged(address[] operators, bool[] isOperator);    
  
    // ======================= State Variables =======================
    IERC20 public immutable usdc;
    IERC20 public immutable weth;
    uint public idCounter;
    mapping (uint id=>TokenInfo) public s_tokenInfo;
    mapping (address operator=> bool) public s_operators;
    string public contractURIMetadata;
    AggregatorV3Interface public aggregatorV3; 
    string public constant name = "ACID TEST";
    // ======================= Structs =======================
    struct TokenInfo {
        uint32 salesStartDate;
        uint32 salesExpirationDate;
        uint256 usdPrice;
        string uri;
        address receiverAddress;
    }

    // ======================= Modifiers =======================
    /// @notice Restricts function access to metadata operators or the owner
    /// @dev Reverts if the caller is neither an operator nor the owner
    modifier onlyMetadataOperatorOrOwner() {
        if (!s_operators[msg.sender] && msg.sender != owner()) revert NotOperatorOrOwner();
        _;
    }

    // ======================= Constructor =======================
    /// @notice Initializes the AcidTest contract
    /// @dev Sets up payment tokens, price feed, and royalty defaults
    /// @param _usdc The USDC token address
    /// @param _weth The WETH token address
    /// @param _owner The initial owner of the contract
    /// @param _aggregatorV3 The price feed address for ETH/USD
    /// @param _contractURI The contract metadata URI
    /// @param _royaltyRecipient The default recipient for royalties
    /// @param _royaltyFee The default royalty fee (in basis points)
    constructor(
        address _usdc,
        address _weth, 
        address _owner, 
        address _aggregatorV3,
        string memory _contractURI,
        address _royaltyRecipient,
        uint96 _royaltyFee
    )
        ERC1155("AcidTest")
        Ownable(_owner)
    {
        usdc = IERC20(_usdc);   
        weth = IERC20(_weth);
        aggregatorV3 = AggregatorV3Interface(_aggregatorV3);
        contractURIMetadata = _contractURI;
        _setDefaultRoyalty(_royaltyRecipient, _royaltyFee);
    }    
    
    /// @notice Allows the contract to receive ETH
    /// @dev Required for ETH payments and refunds
    receive() external payable {}

    // ======================= View Functions =======================
    /// @notice Gets the contract-level metadata URI for marketplaces
    /// @dev Used by marketplaces like OpenSea for collection metadata
    /// @return The contract metadata URI
    function contractURI() public view returns (string memory) {
        return contractURIMetadata;
    }

    /// @notice Gets the metadata URI for a token
    /// @dev Overrides the ERC1155 uri function
    /// @param tokenId The ID of the token to query
    /// @return The metadata URI for the specified token
    function uri(uint256 tokenId) public view override returns (string memory) {
        return s_tokenInfo[tokenId].uri;
    }

    /// @notice Gets the detailed information for a token
    /// @dev Returns the full TokenInfo struct
    /// @param tokenId The ID of the token to query
    /// @return The TokenInfo struct for the specified token
    function getTokenInfo(uint256 tokenId) public view returns (TokenInfo memory) {
        return s_tokenInfo[tokenId];
    }

    /// @notice Gets information for a range of tokens
    /// @dev Useful for paginated queries of token information
    /// @param startIndex The first token ID to include
    /// @param endIndex The last token ID to include
    /// @return An array of TokenInfo structs for the specified range
    function getTokenInfos(uint128 startIndex, uint128 endIndex) public view returns (TokenInfo[] memory) {
        TokenInfo[] memory tokenInfos = new TokenInfo[](endIndex - startIndex + 1);
        if (endIndex > idCounter) endIndex = uint128(idCounter);
        for (uint128 i = startIndex; i <= endIndex; i++) {
            tokenInfos[i - startIndex] = s_tokenInfo[i];
        }
        return tokenInfos;
    }

    /// @notice Checks if this contract implements an interface
    /// @dev Handles the diamond inheritance problem between ERC1155 and ERC2981
    /// @param interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC2981) returns (bool) {
        return ERC1155.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // ======================= User Functions =======================
    /// @notice Mints new tokens with payment in USDC, ETH, or WETH
    /// @dev Includes reentrancy protection and validates sales period
    /// @param to The recipient address for the minted tokens
    /// @param tokenId The ID of the token to mint
    /// @param amount The number of tokens to mint
    /// @param isWeth Whether to use WETH for payment (true) or ETH/USDC (false)
    function mint(
        address to,
        uint256 tokenId,
        uint256 amount, 
        bool isWeth
    ) external payable nonReentrant {
        TokenInfo memory tokenInfo = s_tokenInfo[tokenId];

        address receiverAddress = tokenInfo.receiverAddress;
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

    // ======================= Admin Functions =======================
    /// @notice Creates a new token type
    /// @dev Only the contract owner can create new tokens
    /// @param salesStartDate The timestamp when sales for this token begin
    /// @param salesExpirationDate The timestamp when sales for this token end
    /// @param usdPrice The price in USD (with 6 decimals)
    /// @param tokenUri The metadata URI for this token
    /// @param receiverAddress The address that receives payments for this token
    /// @param royaltyRecipient The address that receives royalties for this token
    /// @param royaltyFee The royalty fee in basis points (e.g., 1000 = 10%)
    function create(
        uint32 salesStartDate,
        uint32 salesExpirationDate, 
        uint256 usdPrice,
        string memory tokenUri,
        address receiverAddress,
        address royaltyRecipient,
        uint96 royaltyFee
    ) public onlyOwner {
        ++idCounter;
        s_tokenInfo[idCounter] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri,
            receiverAddress: receiverAddress
        });

        _setTokenRoyalty(idCounter, royaltyRecipient, royaltyFee);

        emit TokenCreated(idCounter, s_tokenInfo[idCounter]);
    }

    /// @notice Sets the contract-level metadata URI
    /// @dev Only metadata operators or the owner can call this function
    /// @param _contractURI The new contract URI to set
    function setContractURI(string memory _contractURI) external onlyMetadataOperatorOrOwner() {
        contractURIMetadata = _contractURI;
        emit ContractURIUpdated(_contractURI);
    }
    
    /// @notice Modifies the information of an existing token
    /// @dev Only the contract owner can modify token info
    /// @param tokenId The ID of the token to modify
    /// @param salesStartDate The new timestamp when sales for this token begin
    /// @param salesExpirationDate The new timestamp when sales for this token end
    /// @param usdPrice The new price in USD (with 6 decimals)
    /// @param tokenUri The new metadata URI for this token
    /// @param receiverAddress The new address that receives payments for this token
    function modifyTokenInfo(uint256 tokenId,
        uint32 salesStartDate,
        uint32 salesExpirationDate,
        uint256 usdPrice,
        string memory tokenUri,
        address receiverAddress
    ) public onlyOwner {
        s_tokenInfo[tokenId] = TokenInfo({
            salesStartDate: salesStartDate,
            salesExpirationDate: salesExpirationDate,
            usdPrice: usdPrice,
            uri: tokenUri,
            receiverAddress: receiverAddress
        }); 
        
        emit TokenInfoUpdated(tokenId, s_tokenInfo[tokenId]);
    }
    
    /// @notice Updates only the metadata URI of a token
    /// @dev Can be called by metadata operators or the owner
    /// @param tokenId The ID of the token to update
    /// @param tokenUri The new URI to set for the token
    function modifyTokenURI(uint256 tokenId, string memory tokenUri) public onlyMetadataOperatorOrOwner {
        s_tokenInfo[tokenId].uri = tokenUri;
        emit TokenURIUpdated(tokenId, tokenUri);
    }

    /// @notice Sets operators who can manage token metadata
    /// @dev Only the contract owner can set operators
    /// @param operators Array of operator addresses to set
    /// @param isOperator Array of boolean values indicating if each address is an operator
    function setOperators(address[] memory operators, bool[] memory isOperator) public onlyOwner {
        if (operators.length != isOperator.length) revert("Length mismatch");
        for (uint i = 0; i < operators.length; i++) {
            s_operators[operators[i]] = isOperator[i];
        }

        emit OperatorsStateChanged(operators, isOperator);  
    }

    function setRoyalty(uint256 tokenId, address royaltyRecipient, uint96 royaltyFee) public onlyOwner {
        _setTokenRoyalty(tokenId, royaltyRecipient, royaltyFee);
    }
}       