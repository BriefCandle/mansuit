// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./Strings.sol";
import "./ITraits.sol";
import "./IManSuit.sol";
import "./Base64.sol";
import "hardhat/console.sol";

contract Traits is Ownable, ITraits {
    using Strings for uint256;
    using Base64 for bytes;

    // struct to store traits that are purely used for display purpose
    struct DTrait {
        string name;
        string svg;
    }

    string[5] _TraitTypes = [
        "Name", "Status", "Kill Count", "Infected Time", "Location"
    ];

    string[3] _DTraitTypes = [
        "Kill Count",
        "Location",
        "Head"
    ];

    // storage of each location name and SVG data
    mapping(uint8 => DTrait) public locationData;
    // storage of each kill count status and SVG data
    mapping(uint8 => DTrait) public killerData;
    // storage of each dtraits name and base64 SVG data
    mapping(uint8 => mapping(uint8 => DTrait)) public dTraitData;

    IManSuit public manSuit;
    // address public area_address;
    // address public extractor_address;

    constructor() {}

      /** ADMIN */

  function setManSuit(address _manSuit) external onlyOwner {
    manSuit = IManSuit(_manSuit);
    // area_address = _area;
    // extractor_address = _extractor;
  }

    /**
   * administrative to upload the names and images associated with each trait
   * @param traitType the trait type to upload the traits for (see traitTypes for a mapping)
   * @param dTraits the names and base64 encoded SVGs for each trait
   */
    function uploadDTraits(uint8 traitType, uint8[] calldata traitIds, DTrait[] calldata dTraits) external onlyOwner {
        require(traitIds.length == dTraits.length, "Mismatched inputs");
        for (uint i = 0; i < dTraits.length; i++) {
            dTraitData[traitType][traitIds[i]] = DTrait(
                dTraits[i].name,
                dTraits[i].svg
            );
        }
    }
    // locationIds: ['0', '1', '2']
    // locationTraits: [{name: 'corridor', svg: ''}, {name: 'extractor', svg: ''}, {name: 'area', svg: ''}]
    function uploadLocationData(uint8[] calldata locationIds, DTrait[] calldata locationTraits) external onlyOwner {
        require(locationIds.length == locationTraits.length, "Mismatched inputs");
        for (uint i = 0; i < locationTraits.length; i++) {
            locationData[locationIds[i]] = DTrait(
                locationTraits[i].name,
                locationTraits[i].svg
            );
        }
    }

    // killerIds: [0,1,2,3]
    // killerTraits: [{name: 'killer 1', svg: ''},{name: 'killer 2', svg: ''},{name: 'killer 3', svg: ''},{name: 'killer 4', svg: ''}]
    function uploadKillerData(uint8[] calldata killerIds, DTrait[] calldata killerTraits) external onlyOwner {
        require(killerIds.length == killerTraits.length, "Mismatched inputs");
        for (uint i = 0; i< killerTraits.length; i++) {
            killerData[killerIds[i]] = DTrait(
                killerTraits[i].name,
                killerTraits[i].svg
            );
        }
    }
    /** RENDER */
  
    // compile uri from mansuit's tokentraits
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        IManSuit.HuManSuit memory h = manSuit.getTokenTraits(tokenId);
        IManSuit.DHuManSuit memory dH = manSuit.getTokenDTraits(tokenId);
        string memory metadata = string(abi.encodePacked(
            // '{"name": "blah", "description":"blahblha", "image": "data:....", "attributes": [{"trait_type": "status", "value": "alive"}]}'
            '{"name": "',
            h.status == 0 ? 'human#':(h.status==1?'man-suit#':'meat-pie#'),
            tokenId.toString(),
            '", "description": "blahblah", "image": "data:image/svg+xml;base64,',
            bytes(drawSVG(h, dH, tokenId)).base64(),
            '", "attributes":',
            compileAttributes(h, dH, tokenId),
            "}"
        ));
        console.log(metadata);
        return string(abi.encodePacked(
            "data:application/json;base64,",
            bytes(metadata).base64()
        ));
    }

    // ATTENTION
    function compileAttributes(IManSuit.HuManSuit memory h, IManSuit.DHuManSuit memory dH, uint256 tokenId) public view returns (string memory) {
        string memory traits = string(abi.encodePacked(
            attributeForTypeAndValue("Name", uint256(h.name).toString()), ',',
            attributeForTypeAndValue("Status", convertStatus(h.status)), ',',
            attributeForTypeAndValue("Kill Count", uint256(h.killCount).toString()), ',',
            attributeForTypeAndValue("Infected Time", uint256(h.infectedTime).toString()), ',',
            attributeForTypeAndValue("Location", convertLocation(manSuit.getLocation(tokenId))), ',',
            // compile for display traits
            attributeForTypeAndValue("Head", dTraitData[0][dH.head].name)
            // to be added....

        ));
        return string(abi.encodePacked(
            '[',
            traits,
            ']'
        ));
    }

    /**
     * generates an attribute for the attributes array in the ERC721 metadata standard
     * @param traitType the trait type to reference as the metadata key
     * @param value the token's trait associated with the key
     * @return a JSON dictionary for the single attribute
     */
    function attributeForTypeAndValue(string memory traitType, string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            traitType,
            '","value":"',
            value,
            '"}'
        ));
    }

    /**
   * generates an entire SVG by composing multiple <image> elements of SVGs
   * @return a SVG 
   */
    // ATTENTION
    function drawSVG(IManSuit.HuManSuit memory h, IManSuit.DHuManSuit memory dH, uint256 tokenId) public view returns (string memory) {
        uint8 location = manSuit.getLocation(tokenId);
        string memory svgString = string(abi.encodePacked(
            // drawTrait(locationData[location])
            locationData[location].svg
        ));

        return string(abi.encodePacked(
            '<svg id="mansuit" width="100%" height="100%" version="1.1" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
            svgString,
            "</svg>"
        ));
    }

    /**
    * generates an <image> element using base64 encoded PNGs
    * @param trait the trait storing the PNG data
    * @return the <image> element
    */
    function drawTrait(DTrait memory trait) internal pure returns (string memory) {
        return string(abi.encodePacked(
            trait.svg
        ));
    }

    function convertStatus(uint status) internal pure returns (string memory) {
        return status==0?'human':(status==1?'man-suit':'meat-pie');
    }

    function convertLocation(uint location) internal pure returns (string memory) {
        return location==0?'corridor':(location==1?'extractor':'area');
    }





}