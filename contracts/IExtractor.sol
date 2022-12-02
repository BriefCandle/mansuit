// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IExtractor {
    event AddHumanToExtractor(address owner, uint256 tokenId);
    event HumanTransformed(address owner, uint256 tokenId);
    event HumanRestored(address owner, uint256 tokenId);
    event PieMakingAllowed();
    event MeatPieMade(address owner, uint256 tokenId);

    function addHumanToExtractor(address account, uint16[] calldata tokenIds) external;
    function transformHuman(address account, uint16[] calldata tokenIds) external returns (uint256 award);
    function restoreToHuman(uint256 tokenId) external;
    function makingPaste(uint256 tokenId) external;
    function getStakedHumanIds() external view returns(uint256[] memory);
}