// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IArea {
  function stakeNFTs(address account, uint256 tokenId) external;
  function claimManyFromDistrict(uint16[] calldata tokenIds, bool unstake) external;
  // function addManyToBarnAndPack(address account, uint16[] calldata tokenIds) external;
  // function randomWolfOwner(uint256 seed) external view returns (address);
}