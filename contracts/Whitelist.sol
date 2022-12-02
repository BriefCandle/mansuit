//SPDX-License-Identifier: Unlicensed

// import "./Ownable.sol";

pragma solidity ^0.8.0;

contract Whitelist {

    address public owner;
    uint256 public maxAmount;
    uint256 public currentAmount;
    mapping(address => bool) whitelistedAddresses;

    constructor(uint256 _maxAmount) {
        owner = msg.sender;
        maxAmount = _maxAmount;
    }

    function addAddressToWhitelist(address _address) external onlyOwner {
        require(!whitelistedAddresses[_address], "already whitelisted");
        require(currentAmount < maxAmount,"max reached");

        whitelistedAddresses[_address] = true;
        currentAmount += 1;
    }

    function removeAddressFromWhitelist(address _address) external onlyOwner{
        require(whitelistedAddresses[_address], " not whitelisted");
        whitelistedAddresses[_address] = false;
        currentAmount -= 1;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    // function isWhitelisted(address _address) external view returns (bool) {
    //     return whitelistedAddresses[_address];
    // }

    // function getCurrentAmount() public view returns (uint256) {
    //     return currentAmount;
    // }

}
