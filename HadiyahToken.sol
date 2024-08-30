// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1363/ERC1363.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV3Router {
    function factory() external pure returns (address);
    function WETH9() external pure returns (address);
}

contract HadiyahToken is ERC20Burnable, ERC20Capped, ERC20Pausable, ERC1363, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public burnRate;
    uint256 public taxRate;
    uint256 public marketingFeeRate;
    uint256 public liquidityFeeRate;
    uint256 public maxTxAmount;
    address public taxWallet;
    address public marketingWallet;
    address public liquidityWallet;

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV3Router public uniswapV3Router;

    event Tax(address indexed from, address indexed to, uint256 value);
    event MarketingFee(address indexed from, address indexed to, uint256 value);
    event LiquidityFee(address indexed from, address indexed to, uint256 value);

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 cap,
        uint256 initialSupply,
        uint256 _burnRate,
        uint256 _taxRate,
        uint256 _marketingFeeRate,
        uint256 _liquidityFeeRate,
        uint256 _maxTxAmount,
        address _taxWallet,
        address _marketingWallet,
        address _liquidityWallet,
        address _uniswapV2Router,
        address _uniswapV3Router
    ) 
        ERC20(name, symbol)
        ERC20Capped(cap * 10 ** uint256(decimals))
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);

        _mint(msg.sender, initialSupply * 10 ** uint256(decimals)); // Mint initial supply to the owner

        burnRate = _burnRate;
        taxRate = _taxRate;
        marketingFeeRate = _marketingFeeRate;
        liquidityFeeRate = _liquidityFeeRate;
        maxTxAmount = _maxTxAmount * 10 ** uint256(decimals);
        taxWallet = _taxWallet;
        marketingWallet = _marketingWallet;
        liquidityWallet = _liquidityWallet;

        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV3Router = IUniswapV3Router(_uniswapV3Router);
    }

    // Mint new tokens
    function mint(address to, uint256 amount) public {
        require(hasRole(MINTER_ROLE, msg.sender), "Must have minter role to mint");
        _mint(to, amount);
    }

    // Override _mint to enforce cap
    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Capped) {
        super._mint(to, amount);
    }

    // Override _beforeTokenTransfer to support pause functionality
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Pausable) {
        super._beforeTokenTransfer(from, to, amount);
    }

    // Override transfer function to include burn, tax, marketing fee, and liquidity fee
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount");

        uint256 burnAmount = (amount * burnRate) / 100;
        uint256 taxAmount = (amount * taxRate) / 100;
        uint256 marketingFeeAmount = (amount * marketingFeeRate) / 100;
        uint256 liquidityFeeAmount = (amount * liquidityFeeRate) / 100;
        uint256 transferAmount = amount - burnAmount - taxAmount - marketingFeeAmount - liquidityFeeAmount;

        super._transfer(sender, recipient, transferAmount);
        if (burnAmount > 0) {
            _burn(sender, burnAmount);
        }
        if (taxAmount > 0) {
            super._transfer(sender, taxWallet, taxAmount);
            emit Tax(sender, taxWallet, taxAmount);
        }
        if (marketingFeeAmount > 0) {
            super._transfer(sender, marketingWallet, marketingFeeAmount);
            emit MarketingFee(sender, marketingWallet, marketingFeeAmount);
        }
        if (liquidityFeeAmount > 0) {
            super._transfer(sender, liquidityWallet, liquidityFeeAmount);
            emit LiquidityFee(sender, liquidityWallet, liquidityFeeAmount);
        }
    }

    // Set burn rate
    function setBurnRate(uint256 _burnRate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        burnRate = _burnRate;
    }

    // Set tax rate
    function setTaxRate(uint256 _taxRate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        taxRate = _taxRate;
    }

    // Set marketing fee rate
    function setMarketingFeeRate(uint256 _marketingFeeRate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        marketingFeeRate = _marketingFeeRate;
    }

    // Set liquidity fee rate
    function setLiquidityFeeRate(uint256 _liquidityFeeRate) public onlyRole(DEFAULT_ADMIN_ROLE) {
        liquidityFeeRate = _liquidityFeeRate;
    }

    // Set max transaction amount
    function setMaxTxAmount(uint256 _maxTxAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTxAmount = _maxTxAmount * 10 ** uint256(decimals());
    }

    // Set tax wallet
    function setTaxWallet(address _taxWallet) public onlyRole(DEFAULT_ADMIN_ROLE) {
        taxWallet = _taxWallet;
    }

    // Set marketing wallet
    function setMarketingWallet(address _marketingWallet) public onlyRole(DEFAULT_ADMIN_ROLE) {
        marketingWallet = _marketingWallet;
    }

    // Set liquidity wallet
    function setLiquidityWallet(address _liquidityWallet) public onlyRole(DEFAULT_ADMIN_ROLE) {
        liquidityWallet = _liquidityWallet;
    }

    // Function to rescue tokens mistakenly sent to the contract
    function rescueTokens(address tokenAddress, uint256 tokens) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool success) {
        return IERC20(tokenAddress).transfer(msg.sender, tokens);
    }

    // Function to pause all token transfers
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    // Function to unpause all token transfers
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Support for ERC1363 functionality
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC1363) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
