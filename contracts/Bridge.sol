//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
import "./ManSuit.sol";
import "./IBridge.sol";

/**
 * @dev Brief Explanation
 *
 * Only NFTs with ManSuit or Human status can participate in the final fight as only 
 * their stakings are counted as votes. Whoever obtains more votes wins.
 *
 * If man-suits win, all staked humans are reduced to meat-pie. Owner can claim 45%
 * of the total proceed of NFT sale. Each staked man-suits can claim a portion of the 
 * remaining 55%.
 *
 * If humans win, all staked man-suits are reduced to meat-pie. Owner can claim 15%
 * of the total proceed of NFT sale. Staked human cannot claim ETH right away. They 
 * need to decide new contract addresses, to which the ownership of the Bridge, ManSuit,
 * and PASTE contracts will be transferred.
 * 
 * There are still many moving pieces. For example, it is not hardcoded that the proceed
 * of NFT sale will be transferred from ManSuit contract to Bridge contract. However, 
 * no withdraw function is setup in the ManSuit contract, preventing owner from taking
 * the proceed. Owner is therefore incentivized to transfer the proceed to Bridge 
 * contract so that he can claim 15% - 45% of profit. For the same reason, the owner 
 * will not postpone JDay indefinitely because completing the Bridge process is his
 * only way to withdraw the proceed.
 * 
 * Take another example. The contract ownership transfer is not hardcoded either. 
 * However, it is the owner's belief that the triumph of humans represents the establishment
 * of a community valuing long-term benefit. It is rewarding to grant such a collective
 * consensus with ownership as well as exciting to see the formation of a DAO.
 */

contract Bridge is IBridge, Ownable, IERC721Receiver {
    struct Stake {
        uint16 tokenId;
        address owner;
    }


    mapping(uint256 => Stake) public stakedHuman;
    uint256[] public stakedHumanIds;
    mapping(uint256 => Stake) public stakedManSuit;
    uint256[] public stakedManSuitIds;

    // timestamp where the final battle will end
    uint256 public JDAY;
    // waiting period for setResult() after JDAY passes? 
    // result of the final battle: 1 for human; 2 for mansuit; no tie
    uint8 public result;

    uint256 public MANSUIT_CLAIM_PERCENT = 55; // to be deleted if free mint
    uint256 public HUMAN_OWN_PERCENT = 85; // to be deleted if free mint
    // amount to claim per winning mansuit
    uint256 public claimAmountPerManSuit; // to be deleted if free mint
    uint256 public claimAmountByOwner; // to be deleted if free mint
    uint8 public ownerHasClaimed; // to be deleted if free mint

    ManSuit public manSuit;

    constructor() {}


    function stakeManyToBridge(address account, uint16[] calldata tokenIds) external override {
        require(account == _msgSender(), "only sender are owner");
        require(JDAY >= uint256(block.timestamp), "battle has ended or JDAY not set");
        require(result == 0, "result is set"); // NOT redundant?
        for (uint i = 0; i < tokenIds.length; i++) {
            require(manSuit.ownerOf(tokenIds[i]) == _msgSender(), "only owner");
            manSuit.transferFrom(_msgSender(), address(this), tokenIds[i]);

            if (isHuman(tokenIds[i])) _moveHumanToBridge(account, tokenIds[i]);
            else if (isManSuit(tokenIds[i])) _moveManSuitToBridge(account, tokenIds[i]);
            // if isMeatPie, it will be transferred to area with no hope of getting back
        }
    }

    function _moveHumanToBridge(address account, uint256 tokenId) internal {
        stakedHuman[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId)
        });
        stakedHumanIds.push(tokenId);
        emit StakeHuman(account, tokenId);
    }

    function _moveManSuitToBridge(address account, uint256 tokenId) internal {
        stakedManSuit[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId)
        });
        stakedManSuitIds.push(tokenId);
        emit StakeManSuit(account, tokenId);
    }

    function unstakeHumanFromBridge(address account, uint16[] calldata tokenIds) external override {
        require(account == _msgSender(), "only sender are owner");
        require(result != 0, "Result not set yet");
        for (uint i = 0; i < tokenIds.length; i++) {
            uint16 tokenId = tokenIds[i];
            Stake memory stake = stakedHuman[tokenId]; 
            require(stake.owner == _msgSender(), "only owner or owner exists");
            delete stakedHuman[tokenId];
            _arrayRemoveValue(tokenId, stakedHumanIds);
            if (result == 2) manSuit.madeToPie(tokenId);
            manSuit.safeTransferFrom(address(this), _msgSender(), tokenId, ""); 
        }
    }

    function unstakeManSuitFromBridge(address account, uint16[] calldata tokenIds) external override{
        require(account == _msgSender(), "only sender are owner");
        require(result != 0, 'Result not set yet');
        uint256 owed; // to be deleted if free mint
        for (uint i = 0; i < tokenIds.length; i++) {
            uint16 tokenId = tokenIds[i];
            Stake memory stake = stakedManSuit[tokenId]; 
            require(stake.owner == _msgSender(), "only owner or owner exists");
            delete stakedManSuit[tokenId];
            _arrayRemoveValue(tokenId, stakedManSuitIds);
            if (result == 1) manSuit.madeToPie(tokenId);
            else owed += claimAmountPerManSuit;  // to be deleted if free mint
            manSuit.safeTransferFrom(address(this), _msgSender(), tokenId, ""); 
        }
        if (owed == 0) return; // to be deleted if free mint
        payable(_msgSender()).transfer(owed); // to be deleted if free mint
    }

    // --- ARRAY_MANIPULATION --- //
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

    // --- VIEW --- //
    function getStakedHumanIds() external view override returns(uint256[] memory) {
        return stakedHumanIds;
    }

    function getStakedManSuitIds() external view override returns(uint256[] memory) {
        return stakedManSuitIds;
    }

    function isHuman(uint256 tokenId) internal view returns (bool human) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        human = status == 0 ? true : false;
    }

    function isManSuit(uint256 tokenId) internal view returns (bool ms) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        ms = status == 1 ? true : false;
    }

    // function isMeatPie(uint256 tokenId) internal view returns (bool ms) {
    //     ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
    //     ms = status == 2 ? true : false;
    // }

    // --- ADMIN --- //
    function setManSuit(address _manSuit) external onlyOwner {
        manSuit = ManSuit(_manSuit);
    }

    function setJDay(uint256 inSeconds) external onlyOwner {
        require(result == 0, "result has been set");
        JDAY = uint256(block.timestamp) + inSeconds;
        emit SetJDay(JDAY);
    }

    // can only be called once
    function setResult() external onlyOwner { 
        require(result == 0, "result has been set");
        require(JDAY != 0 && JDAY < uint256(block.timestamp), "battle has NOT ended or begun");
        uint256 balance = address(this).balance; // to be deleted if free mint
        if (stakedHumanIds.length >= stakedManSuitIds.length) {
            claimAmountByOwner = balance * (100 - HUMAN_OWN_PERCENT) / 100; // to be deleted if free mint
            result = 1;
        }
        else {
            claimAmountByOwner = balance * (100 - MANSUIT_CLAIM_PERCENT) / 100; // to be deleted if free mint
            claimAmountPerManSuit = balance * MANSUIT_CLAIM_PERCENT / 100 
            / stakedManSuitIds.length; // to be deleted if free mint
            result = 2;
        }
        emit SetResult(result);
    }

    // to be deleted if free mint
    /**
     * owner can only claim an allowed percentage of balance
     */
    function withdraw() external onlyOwner {
        require(ownerHasClaimed == 0, "owner has claimed");
        ownerHasClaimed = 1;
        payable(owner()).transfer(claimAmountByOwner);
    }

    // to be deleted if free mint
    receive() external payable {}

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
      require(from == address(0x0), "Cannot send tokens");
      return IERC721Receiver.onERC721Received.selector;
    }

}