// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/Test.sol";

contract LSNFT is ERC721URIStorage, Ownable {

    mapping(uint256 => string) private originURIs;

    mapping(address => bool) private admins;

    mapping(address => bool) private markets;

    // fp => tokenId
    mapping(uint96 => uint256) private fingerPrints;

    // originURI => creator
    mapping(string => address) private binding;

    event Log1(address indexed, address indexed);

    uint256[] private tokenIds;

    constructor(address owner) ERC721("LetterSpace", "LS") Ownable(owner) {

    }

    modifier onlyAdmin() {
       require(admins[_msgSender()] == true, "no admin permission");
       _;
    }

    modifier onlyMarket() {
       require(markets[_msgSender()] == true, "no market permission");
       _;
    }

    function setAdmin(address admin) public onlyOwner {
        emit Log1(msg.sender, admin);
        admins[admin] = true;
    }

    function delAdmin(address admin) public onlyOwner {
        delete admins[admin];
    }

    function isAdmin(address addr) public view returns (bool) {
        return admins[addr];
    }

    function setMarket(address market) public onlyOwner {
        emit Log1(msg.sender, market);
        markets[market] = true;
    }

    function delMarket(address market) public onlyOwner {
        delete markets[market];
    }

    function isMarket(address addr) public view returns (bool) {
        return markets[addr];
    }

    function mint(address to, uint256 tokenId, string memory originURI) external {

        uint96 fp = uint96(getFP(tokenId));
        require(fingerPrints[fp] == 0, "existed resource");

        // check if the token derives from its creator
        require(checkBinding(originURI, getCreator(tokenId)), "invaild token creator");

        _mint(to, tokenId);

        fingerPrints[fp] = tokenId;
        if (to == getCreator(tokenId)) {
            originURIs[tokenId] = originURI;
        }
        tokenIds.push(tokenId);
    }

    function burn(uint256 tokenId) external onlyMarket {
        uint96 fp = uint96(getFP(tokenId));
        fingerPrints[fp] = 0;
        _setTokenURI(tokenId, "");
        _burn(tokenId);
    }

    function setApprovalForAll(address owner, address operator, bool approved) public onlyMarket {
        _setApprovalForAll(owner, operator, approved);
    }

    function setTokenURI(uint256 tokenId, string memory tokenURI) public {
        require(msg.sender == ownerOf(tokenId) || markets[msg.sender] == true || admins[msg.sender] == true, "no permission to set tokenURI");
        _setTokenURI(tokenId, tokenURI);
    }

    function getCreator(uint256 tokenId) public pure returns (address) {
        return address(uint160(tokenId >> 96));
    }

    function getFP(uint256 tokenId) public pure returns (bytes12) {
        return bytes12(bytes32(tokenId << 160));
    }

    function getOriginURI(uint256 tokenId) public view returns (string memory) {
        return originURIs[tokenId];
    }

    function getTokenIds() public view returns (uint256[] memory) {
        return tokenIds;
    }

    function getTokenURI(uint256 fp) public view returns (string memory) {
        uint256 tokenId = tokenOf(fp);
        if (tokenId == 0) {
            return "";
        }
        return tokenURI(tokenId);
    }

    function tokenOf(uint256 fp) public view returns (uint256) {
        return fingerPrints[uint96(fp)];
    }

    // creators bind their contents to their address
    // once the content of creator has been binded, all of the tokens minted from the content should derive from the creator of the content 
    function bind(string memory originURI, address creator) public {
        if(binding[originURI] == address(0)){
            binding[originURI] = creator;
        }
    }

    function checkBinding(string memory originURI, address creator) public view returns (bool) {
        return creator == binding[originURI];
    }
}