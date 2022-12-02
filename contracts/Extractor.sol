// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
import "./IExtractor.sol";
import "./ManSuit.sol";
import "./Area.sol";
import "hardhat/console.sol";


contract Extractor is IExtractor, Ownable, IERC721Receiver {
    
    struct Stake {
        uint16 tokenId;
        uint80 value;
        address owner;
    }

    // maps human tokenId to Extractor
    mapping(uint256 => Stake) public stakedHuman;
    uint256[] public stakedHumanIds;
    // paste rewarded when human becomes mansuit
    uint256 public constant PASTE_IN_HUMAN = 1 ether;
    // the required locked-up time for mansuit and human to be 
    uint256 public constant LOCK_TIME = 2 * 60 * 60; // 2 hours

    // max duration to be restored after infected, about 2 days
    uint256 public MAX_DURATION_RESTORE = 172800;
    // $PASTE cost to restore from mansuit to human
    uint256 public RESTORATION_COST = 1.5 ether;
    // $PASTE reward for burning meatpie
    uint256 public MEATPIE_REWARD = 2 ether;
    bool public allowPieToPaste;


    // reference to the Human NFT contract; initialized in onlyOwner function
    ManSuit manSuit;
    // reference to Paste
    PASTE paste;


    constructor(address _paste) {
        paste = PASTE(_paste);
    }

    // --- STAKE ---
    function addHumanToExtractor(address account, uint16[] calldata tokenIds) external { 
        require(account == _msgSender(), "only sender are owner");
        for (uint i = 0; i < tokenIds.length; i++) {
            uint16 tokenId = tokenIds[i];
            require(isHuman(tokenId), "staked NFT not human");
            require(manSuit.ownerOf(tokenId) == _msgSender(), "only owner");
            manSuit.transferFrom(_msgSender(), address(this), tokenIds[i]);
            stakedHuman[tokenId] = Stake({
                owner: msg.sender,
                tokenId: uint16(tokenId),
                value: uint80(block.timestamp)
            });
            stakedHumanIds.push(tokenId); 
            console.log(tokenId, " from ", _msgSender(), " is staked in extractor.");
            emit AddHumanToExtractor(_msgSender(), tokenId);
        }
    }

    // --- MATURITY --- 
    function checkHumanMaturity(uint16 tokenId) public view returns (uint256 timeRemain) { 
        Stake memory stake = stakedHuman[tokenId]; 
        uint256 timePass = block.timestamp - stake.value;
        timeRemain = LOCK_TIME > timePass ? LOCK_TIME - timePass : 0;
    }

    // --- CLAIM/UNSTAKE/TRANSFORM ---
    function transformHuman(address account, uint16[] calldata tokenIds) external override returns (uint256 award) {
        require(account == _msgSender(), "caller");
        for (uint i = 0; i < tokenIds.length; i++) {
            uint16 tokenId = tokenIds[i];
            Stake memory stake = stakedHuman[tokenId]; 
            require (stake.owner == _msgSender(), "not authorized");  
            require (checkHumanMaturity(tokenId) == 0, "not enough time");
                delete stakedHuman[tokenId];
                _arrayRemoveValue(tokenId, stakedHumanIds);
                manSuit.transformToManSuit(tokenId);
                manSuit.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back mansuit
                award += PASTE_IN_HUMAN;
                console.log(tokenId, " is transformed to mansuit, and belongs to ", _msgSender());
                emit HumanTransformed(_msgSender(), tokenId);
            
        }
        if (award != 0) paste.mint(_msgSender(), award); 
        console.log("total ", award, " $PASTE is awarded to _msgSender()");
    }

    
    // --- RESTORE ---
    // change it to tokenIds to save gas?
    function restoreToHuman(uint256 tokenId) external override {
        require(_msgSender() == manSuit.ownerOf(tokenId), "caller needs to be owner");
        require(isManSuit(tokenId), "nft needs to be mansuit!");
        (, , , uint80 infectedTime) = manSuit.tokenTraits(tokenId);
        require(block.timestamp - infectedTime <= MAX_DURATION_RESTORE, "too late to be restored");
        paste.burn(_msgSender(), RESTORATION_COST); // later add a function to calculate restoration cost per minted token amount
        manSuit.restoreToHuman(tokenId);
        console.log(_msgSender(), tokenId, " is restored back to human with burned", RESTORATION_COST);
        emit HumanRestored(_msgSender(), tokenId);
    }

    // --- BURN MEAT PIE & MAKE PASTE ---
    function makingPaste(uint256 tokenId) external override {
        require(allowPieToPaste, "require approval from ship AI");
        require(_msgSender() == manSuit.ownerOf(tokenId), "caller needs to be owner");
        require(isMeatPie(tokenId), "nft needs to be meatpie!");
        manSuit.burnMeatPie(tokenId); 
        paste.mint(_msgSender(), MEATPIE_REWARD);
    }

    function allowMakingPaste() external onlyOwner {
        allowPieToPaste = true;
        emit PieMakingAllowed();
    }


    /*
     * checks if a token is a human alive
     * @param tokenId the ID of the token to check
     * @return sheep - whether or not a token is a Sheep
     */
    function isHuman(uint256 tokenId) internal view returns (bool human) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        human = status == 0 ? true : false;
    }

    function isManSuit(uint256 tokenId) internal view returns (bool ms) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        ms = status == 1 ? true : false;
    }

    function isMeatPie(uint256 tokenId) internal view returns (bool ms) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        ms = status == 2 ? true : false;
    }

    function getStakedHumanIds() external view returns(uint256[] memory) {
        return stakedHumanIds;
    }


    /**
     * remove an array element by index without preserving order
     * basically, move the last element to the deleted spot and remove the last element.
     */
    function _arrayRemoveIndex(uint index, uint256[] storage _idArray) private {
        require(index < _idArray.length);
        _idArray[index] = _idArray[_idArray.length-1];
        _idArray.pop();
    }

    // remove an array element by value, which is token id
    function _arrayRemoveValue(uint value, uint256[] storage _idArray) private {
        for (uint i = 0; i < _idArray.length; i++) {
            if (_idArray[i] == value) {
                _arrayRemoveIndex(i, _idArray);
                return;
            }
        }
        revert("no id");
    }


    // --- ADMIN //
    function setManSuit(address _manSuit) external onlyOwner {
        manSuit = ManSuit(_manSuit);
    }

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
      require(from == address(0x0), "Cannot send tokens to extractor directly");
      return IERC721Receiver.onERC721Received.selector;
    }




}