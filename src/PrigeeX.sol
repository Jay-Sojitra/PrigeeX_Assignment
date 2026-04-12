// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PrigeeX Token (PGX)
 * @notice ERC-20 token with configurable supply and owner-controlled mint/burn
 */
contract PrigeeX is ERC20, Ownable {
    /**
     * @notice Deploys the PrigeeX token with an initial supply
     * @param initialSupply The amount of tokens to mint to the deployer (in wei units)
     */
    constructor(uint256 initialSupply) ERC20("PrigeeX", "PGX") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Mints new tokens to a specified address
     * @param to The address to receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from a specified address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
