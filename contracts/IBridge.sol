// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IBridge {
    event StakeHuman(address owner, uint256 tokenId);
    event StakeManSuit(address owner, uint256 tokenId);
    event SetJDay(uint256 jDay);
    event SetResult(uint8 result);

    function stakeManyToBridge(address account, uint16[] calldata tokenIds) external;
    function unstakeHumanFromBridge(address account, uint16[] calldata tokenIds) external;
    function unstakeManSuitFromBridge(address account, uint16[] calldata tokenIds) external;
    function getStakedHumanIds() external view returns(uint256[] memory);
    function getStakedManSuitIds() external view returns(uint256[] memory);
}