// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BigfootToken is ERC20, Ownable {
    uint256 public constant MINIMUM_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant MAX_SUPPLY = 200_000_000 * 10**18;
    uint256 public constant MAX_MINT_AMOUNT = 1_000_000 * 10**18;

    constructor() ERC20("BigfootToken", "BFT") Ownable(msg.sender) {
        require(totalSupply() == 0, "Initial supply must be zero");
        _mint(msg.sender, MINIMUM_SUPPLY);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= MAX_MINT_AMOUNT, "Exceeds maximum mint amount");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");

        _mint(to, amount);
    }
}