// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./Whitelist.sol";
import "./Pausable.sol";
import "./ERC721Enumerable.sol";
import "./IManSuit.sol";
// import "./IArea.sol";
// import "./IExtractor.sol";
import "./ITraits.sol";
import "./PASTE.sol";


import "hardhat/console.sol";


contract ManSuit is IManSuit, ERC721Enumerable, Ownable, Pausable {
    
    // mint price
    uint256 public constant MINT_PRICE = 0.1 ether;
    uint256 public constant MINT_PRICE_PASTE = 2 ether;
    // number of tokens that can be minted by PASTE - 500 in production
    uint256 public PASTE_TOKENS = 102;
    // max number of token to be minted per trans - 3 or 5
    uint8 public MAX_PER_MINT = 3;   
    // number of tokens that can be claimed with ETH - 20% of MAX_TOKENS
    uint256 public ETH_TOKENS = 30;
    uint256 public MAX_TOKENS = 132; // PASTE_TOKENS + ETH_TOKENS;
    // number of tokens have been minted so far
    uint256 public minted;

    // reference to the area to call 
    address public area_address;
    // reference to extractor 
    address public extractor_address;
    // reference to bridge
    address public bridge_address;
    // reference to $PASTE for burning or minting
    PASTE public paste;
    // reference to Traits
    ITraits public traits;
    // reference to whitelist
    // Whitelist public whitelist;

    // mapping from tokenId to a struct containing the token's traits
    mapping(uint256 => HuManSuit) public tokenTraits;
    // mapping from tokenId to a struct containing the token's display traits
    mapping(uint256 => DHuManSuit) public tokenDTraits;
    // mapping from hashed(tokenTrait) to the tokenId it's associated with
    // used to ensure there are no duplicates
    mapping(uint256 => uint256) public existingCombinations;


    constructor(address _paste, address _area, address _extractor, address _traits,
    address _bridge) 
    ERC721("ManSuit Game Test", 'MANSUIT TEST') {
        paste = PASTE(_paste);
        traits = ITraits(_traits);
        area_address = _area;
        extractor_address = _extractor;
        bridge_address = _bridge;
        // whitelist = Whitelist(_whitelist);
    }

    function setAddresses(address _area, address _extractor, address _bridge) external onlyOwner {
        area_address = _area;
        extractor_address = _extractor;
        bridge_address = _bridge;
    }


    /** ---- MINT ---- */

    /** 
     * mint an NFT token - 100% human
     * The first 22.7% require eth to claim, the remaining cost $PASTE
     */
    function mint(uint256 amount) external payable whenNotPaused {
       require(tx.origin == _msgSender(), "Only EOA");
       require(minted + amount <= MAX_TOKENS, "All tokens minted");
       require(amount > 0 && amount <= MAX_PER_MINT, "Invalid mint amount");
       if (minted < ETH_TOKENS) {
            require(minted + amount <= ETH_TOKENS, "All tokens on-sale already sold");
            require(amount * MINT_PRICE == msg.value, "Invalid payment amount");
        } else {
            require(msg.value == 0);
        }

        uint256 totalPasteCost = 0;
        uint256 seed;
        for (uint i = 0; i < amount; i++) {
            minted++;
            seed = random(minted);
            generate(minted, seed);
            _safeMint(_msgSender(), minted);
            totalPasteCost += mintCost(minted);
            console.log("token ID ", minted, "is minted");
        }
        if (totalPasteCost > 0) paste.burn(_msgSender(), totalPasteCost);
        console.log("total ", totalPasteCost, " $PASTE is costed");
   }

    /** 
     * the first ETH_TOKENS are paid in ETH
     * the next 33.3% of PASTE_TOKENS are 20000 $BRAIN
     * the next 40% are 40000 $BRAIN
     * the final 20% are 80000 $BRAIN
     * @param tokenId the ID to check the cost of to mint
     * @return the cost of the given token ID
     */
    function mintCost(uint256 tokenId) public view returns (uint256) {
        if (tokenId <= ETH_TOKENS) return 0;
        if (tokenId <= ETH_TOKENS + PASTE_TOKENS * 2 / 6) return MINT_PRICE_PASTE;
        if (tokenId <= ETH_TOKENS + PASTE_TOKENS * 3 / 6) return MINT_PRICE_PASTE * 2;
        return MINT_PRICE_PASTE * 4;
    }

    /** ---- SETUP TRAITS ---- */

    // generate unique token trait for a token
    function generate(uint256 tokenId, uint256 seed) internal {
        // for now, keep token trait the same; later, can add more variety to it
        tokenTraits[tokenId] = HuManSuit({
            name: uint16(tokenId),
            status: 0,
            killCount: 0,
            infectedTime: 0
        });
        tokenDTraits[tokenId] = DHuManSuit({
            head: 0
        });
    }

    // function selectTrait(uint16 seed, uint8 traitType) internal view returns (uint8) {
    //     // uint8 trait = uint8(seed) % uint8(rarities[traitType].length);
    //     // if (seed >> 8 < rarities[traitType][trait]) return trait;
    //     // return aliases[traitType][trait];
    // }


    /**
     * generates a pseudorandom number
     * @param seed a value ensure different outcomes for different sources in the same block
     * @return a pseudorandom value
     */
    function random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp,
            seed
        )));
    }

    /** ---- ERC721 RELATED ---- */

    function transferFrom(address from, address to, uint256 tokenId) public virtual override (ERC721, IERC721) {
        // Hardcode the area, extractor, bridge's approval so that users don't have to waste gas approving to have NFTs transferred/staked to them
        if (_msgSender() != area_address && _msgSender() != extractor_address 
        && _msgSender() != bridge_address)
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    // /** ---- CHANGE TOKENTRAITS ---- */

    function addKillCount(uint256 tokenId) onlyFromShip external {
        tokenTraits[tokenId].killCount += 1;
    }

    function transformToManSuit(uint256 tokenId) onlyFromShip external {
        tokenTraits[tokenId] = HuManSuit({
            name: uint16(tokenId),
            status: 1, // set status to mansuit
            killCount: tokenTraits[tokenId].killCount,
            infectedTime: uint80(block.timestamp) // set infection time
        });
    }

    function restoreToHuman(uint256 tokenId) onlyFromShip external {
        tokenTraits[tokenId] = HuManSuit({
            name: uint16(tokenId),
            status: 0,  // set status to human
            killCount: tokenTraits[tokenId].killCount,
            infectedTime: 0 // reset infection time
        });
    }

    function madeToPie(uint256 tokenId) onlyFromShip external {
        tokenTraits[tokenId].status = 2;
    }

    function burnMeatPie(uint256 tokenId) onlyFromShip external {
        _burn(tokenId);
    }

    // use if instead of require to save gas? 
    modifier onlyFromShip {
        if (_msgSender() == area_address || _msgSender() == extractor_address
        || _msgSender() == bridge_address) 
        _;
    }

    /*
     * checks if a token is a human, mansuit, meatpie
     * @param tokenId the ID of the token to check
     * @return true or false - whether or not a token is 
     */
    // function isHuman(uint256 tokenId) external view returns (bool) {
    //     return tokenTraits[tokenId].status == 0 ? true : false;
    // }


    /** ---- ADMIN ---- */

    // function withdraw() external onlyOwner {
    //     payable(owner()).transfer(address(this).balance);
    // }

    /**
     * transfer proceed of NFT sale to Bridge contract
     * to be deleted if free mint
     */
    function transferToBridge() external onlyOwner {
        payable(bridge_address).transfer(address(this).balance);
    }

    // /**
    //  * updates the number of tokens for sale
    //  */
    function setEthTokens(uint256 _ethTokens) external onlyOwner {
        ETH_TOKENS = _ethTokens;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /** ---- RENDER ---- */


    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return traits.tokenURI(tokenId);
    }

    function getLocation(uint256 tokenId) external view returns (uint8 location) {
        address ownerAddress = ownerOf(tokenId);
        if (ownerAddress == area_address) location = 2;
        else if (ownerAddress == extractor_address) location = 1;
        else if (ownerAddress != address(0)) location = 0;
    }


    function getTokenTraits(uint256 tokenId) public view override returns (HuManSuit memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return tokenTraits[tokenId];
    }

    function getTokenDTraits(uint256 tokenId) public view override returns (DHuManSuit memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return tokenDTraits[tokenId];
    }

    // receive() external payable {}






}