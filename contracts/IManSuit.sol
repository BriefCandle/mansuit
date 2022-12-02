// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./IERC721.sol";

interface IManSuit {
    // struct to store each HuManSuit's traits
    struct HuManSuit {
        uint16 name;  // human/manSuit/meatPie + #id, updated when status changed
        uint8 status; // 0 for human, 1 for manSuit, 2 for meatPie
        uint16 killCount; // amount of manSuit killed by this NFT, updated when termination succeeds
        uint80 infectedTime; // if infected for more than 48 hours, unrestorable, updated when infected
        // wait to add other trait_type & trait_value
    }
    // struct to store each HuManSuit's traits for display
    struct DHuManSuit {
        uint8 head;
    }
    function getTokenTraits(uint256 tokenId) external view returns (HuManSuit memory);
    function getTokenDTraits(uint256 tokenId) external view returns (DHuManSuit memory);
    function getLocation(uint256 tokenId) external view returns (uint8);   
      // function infection(uint256 tokenId) external;
    // function restoration(uint256 tokenId, address account) external;
    // function makingPie(uint256 tokenId1, uint256 tokenId2) external;
    // function makingPaste(uint256 tokenId) external;

}