// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

// to be called by the NFT contract, i.e., ManSuit.sol, a function to display metadata on opensea
// first, it reads token traits from ManSuit.sol
// then, it compiles and returns a base64 encoded metadata 
interface ITraits {
  function tokenURI(uint256 tokenId) external view returns (string memory);
}

