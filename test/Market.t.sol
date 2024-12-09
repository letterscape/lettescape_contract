// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/Market.sol";
import "../src/LSNFT.sol";
import "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract MarketTest is Test{

  Market market;

  LSNFT nft;

  address feeTo;

  struct WNFT {
        bool isPaid;
        bool isListed;
        bool isExpired;
        uint16 interval; // 1 one hour, 2 two hour, ... , 24 one day
        address owner;
        uint256 deadline;
        uint256 tokenId;
        uint256 price;
        uint256 lastDealPrice;
    }

  function setUp() public {
    // transfer address must not be address(1) etc. It will cause precompile OOG
    feeTo = makeAddr("feeTo");
    nft = new LSNFT(address(this));
    market = new Market(address(nft), payable(feeTo));
    nft.setMarket(address(market));
  }

  function test_mint_success_without_tokenId() public {
    (address creator, uint256 tokenId) = mint(200, 1);
    address owner = nft.ownerOf(tokenId);
    assertEq(creator, owner);
  }

  function test_mint_success_with_tokenId() public {
    uint256 tokenId = 0xa0ee7a142d267c1f36714e4a8f75612f20a79720f8c4437e2db9944f00000001;
    uint256 price = 8888;
    uint16 interval = 24;
    string memory originURI = "http://localhost:3000/space/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/1";
    address creator = nft.getCreator(tokenId);
    console.log("now: ", block.timestamp);
    console.log("deadline: ", block.timestamp + uint256(interval) * 3600);
    vm.startPrank(creator);
    nft.bind(originURI, creator);
    market.mint(tokenId, price, interval, originURI);
    vm.stopPrank();
  }

  function test_nft_burn_success() public {
    (address creator, uint256 tokenId) = mint(200, 1);
    uint256 balance = nft.balanceOf(creator);

    assertEq(creator, nft.ownerOf(tokenId));

    vm.startPrank(address(market));
    nft.burn(tokenId);
    assertEq(balance - 1, nft.balanceOf(creator));
    vm.stopPrank();

  }

  function test_list_success() public {
    list();
  }

  function list() public returns (address creator, uint256 tokenId, uint256 price) {
    uint256 prvk;
    (creator, prvk) = makeAddrAndKey("creator1");
    price = 200;

    vm.startPrank(creator);

    tokenId = mint(creator, price, 3);
    bytes32 hashData = market.getSignHash(creator, address(nft), tokenId, price);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(prvk, hashData);
    bytes memory signature = abi.encodePacked(r, s, v);

    market.list(tokenId, price, signature);

    Market.WNFT memory wnft = market.getWNFT(tokenId);
    assertEq(creator, wnft.owner);
    assertEq(true, nft.isApprovedForAll(creator, address(market)));
    vm.stopPrank();
  }

  function test_buy_success() public {

    (address creator, uint256 tokenId, uint256 price) = list();

    address buyer = makeAddr("buyer1");
    vm.deal(buyer, 1000);
    vm.deal(address(market), 1 ether);
    vm.startPrank(buyer);
    uint256 holdFee = market.getHoldFee(tokenId, 3);
    console.log("holdFee: ", holdFee);
    console.log("gasleft: ", gasleft());
    market.buy{value: holdFee + price}(tokenId, price, 500);
    vm.stopPrank();

    console.log(feeTo.balance);
    assertTrue(creator.balance > 0);
  }

  function test_payHoldFee_success() public {
    (address creator, uint256 tokenId) = mint(500, 48);
    vm.deal(creator, 1000);
    vm.deal(address(market), 1 ether);

    uint256 fee = market.getHoldFee(tokenId, 3);
    console.log('fee: ', fee);
    uint256 holdFeeP = market.getHoldFee(tokenId, 1);
    uint256 holdFeeC = market.getHoldFee(tokenId, 2);
    console.log('holdFeeP: ', holdFeeP);
    console.log('holdFeeC: ', holdFeeC);
    market.payHoldFee{value: holdFeeP+holdFeeC}(tokenId);
  
  }

  function test_getHoldFee() public {
    (address creator, uint256 tokenId) = mint(500, 48);
    uint256 fee = market.getHoldFee(tokenId, 3);
    console.log('fee: ', fee);
  }

  function test_soldOut_success() public {
    ( , uint256 tokenId) = mint(200, 1);
    market.soldOut(tokenId);
    assertEq(false, market.isOnsale(tokenId));
  }

  function test_changePrice_success() public {

  }

  function test_isListed() public {
    ( , uint256 tokenId) = mint(200, 1);
    assertEq(false, market.isOnsale(tokenId));
    market.soldOut(tokenId);
    assertEq(false, market.isOnsale(tokenId));
  }

  function test_burn_with_ower() public {
    uint8 interval = 1;
    ( , uint256 tokenId) = mint(200, interval);
    market.burn(tokenId);
    assertEq(address(0), market.getWNFT(tokenId).owner);
  }

  function test_burn_without_owner_when_not_expired() public {
    uint8 interval = 1;
    ( , uint256 tokenId) = mint(200, interval);

    address somebody = makeAddr("somebody");
    vm.startPrank(somebody);

    vm.expectRevert("no permission to burn");
    market.burn(tokenId);

    vm.stopPrank();
  }

  function test_burn_without_owner_when_expired() public {
    uint8 interval = 1;
    ( , uint256 tokenId) = mint(200, interval);
    bool res = market.isExpired(tokenId);
    console.log("now:%s, deadline:%s", block.timestamp, market.getWNFT(tokenId).deadline);
    assertEq(res, false);

    skip(interval * 3600 + 2);
    res = market.isExpired(tokenId);
    console.log("now:%s, deadline:%s", block.timestamp, market.getWNFT(tokenId).deadline);
    assertEq(res, true);

    address somebody = makeAddr("somebody");
    vm.startPrank(somebody);

    market.burn(tokenId);
    assertEq(address(0), market.getWNFT(tokenId).owner);

    vm.stopPrank();
  }

  function test_isExpired() public {
    uint8 interval = 1;
    ( , uint256 tokenId) = mint(200, interval);
    bool res = market.isExpired(tokenId);
    console.log("now:%s, deadline:%s", block.timestamp, market.getWNFT(tokenId).deadline);
    assertEq(res, false);

    skip(interval * 3600 + 2);
    res = market.isExpired(tokenId);
    console.log("now:%s, deadline:%s", block.timestamp, market.getWNFT(tokenId).deadline);
    assertEq(res, true);
  }
  

  function test_createTokenId() public {
    address creator = makeAddr("creator");
    uint256 id = 1;
    uint256 tokenId = createTokenId(creator, 'www.letterscape.xyz', 'www.letterscape.xyz/1', id);
    console.log("tokenId: ", tokenId);
    assertEq(uint160(creator), tokenId >> 96);
    assertEq(id, tokenId & type(uint96).max);
  }

  function test_getFP() public {
    uint256 tokenId = 0xd571cb930a525c83d7d2b7442a34b09c5f1cca3ee66982e1f80ed25400000001;
    bytes12 fp = nft.getFP(tokenId);
    assertEq(0xe66982e1f80ed25400000001, uint96(fp));
  }

  function test_getOriginURI() public {
    address creator = makeAddr("creator");
    vm.startPrank(creator);
    uint256 tokenId = mint(creator, 100, 3);
    string memory originUri = nft.getOriginURI(tokenId);
    vm.assertNotEq(originUri, "");
    vm.stopPrank();
  }

  function test_getTokenURI_success() public {
    uint256 tokenId = 0xa0ee7a142d267c1f36714e4a8f75612f20a79720f8c4437e2db9944f00000001;
    uint256 price = 8888;
    uint16 interval = 24;
    string memory originURI = "http://localhost:3000/space/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/1";
    address creator = nft.getCreator(tokenId);
    string memory tokenURI = "QmZ3smj6KGukfYCi7KQTbeLSqWq2mUr2Na7BHGPFaGnFJK";
    console.log("now: ", block.timestamp);
    console.log("deadline: ", block.timestamp + uint256(interval) * 3600);
    
    vm.startPrank(creator);
    nft.bind(originURI, creator);
    market.mint(tokenId, price, interval, originURI);
    uint96 fp = uint96(nft.getFP(tokenId));
    nft.setTokenURI(tokenId, tokenURI);
    string memory res = nft.getTokenURI(fp);
    assertEq(tokenURI, res);
    vm.stopPrank();
  }

  function createTokenId(address creator, string memory website, string memory originURI, uint256 id) public pure returns (uint256) {
    require(id < type(uint8).max, "id too large");
    bytes4 fp = bytes4(keccak256(abi.encodePacked(website)));
    bytes4 fp2 = bytes4(keccak256(abi.encodePacked(originURI)));
    return (uint256(uint160(creator)) << 96) + uint256(bytes32(fp << 64)) + uint256(bytes32(fp2 << 32)) + id;
  }

  function mint(uint256 price, uint8 interval) public returns (address, uint256) {
    address creator = address(this);
    return (creator, mint(creator, price, interval));
  }

  function mint(address creator, uint256 price, uint8 interval) public returns (uint256) {
    uint256 tokenId = createTokenId(creator, 'www.letterscape.xyz', 'www.letterscape.xyz/1', 1);
    string memory originURI = "http://www.letterspace.xyz/abc";
    uint256 balance = nft.balanceOf(creator);
    nft.bind(originURI, creator);
    market.mint(tokenId, price, interval, originURI);
    Market.WNFT memory wnft = market.getWNFT(tokenId);
    printWNFT(wnft);
    assertEq(balance + 1, nft.balanceOf(creator));
    assertEq(nft.ownerOf(tokenId), wnft.owner);
    return tokenId;
  }

  function printWNFT(Market.WNFT memory wnft) public view {
    console.log("tokenId: %s,", wnft.tokenId);
    console.log("owner: %s,", wnft.owner);
    console.log("deadline: %s,", wnft.deadline);
    console.log("isPaid: %s,", wnft.isPaid);
    console.log("isListed: %s,", wnft.isListed);
    console.log("interval: %s,", wnft.interval);
    console.log("price: %s,", wnft.price);
    console.log("lastDealPrice: %s", wnft.lastDealPrice);
  }

  function test_genSign() public {
    address owner = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address nftAddr = 0x5fe2f174fe51474Cd198939C96e7dB65983EA307;
    // uint256 tokenId = createTokenId(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, "http://localhost:3000", "http://localhost:3000/space/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/1", 1);
    // console.log(tokenId);
    uint256 tokenId = 72791407931748004276589748829050622920751384330453328789245692068238198833164;
    uint256 price = 666;
    bytes32 hash = market.getSignHash(owner, nftAddr, tokenId, price);
    string memory num = "0x832a592cdd3abd88ee0acc5b0e1f3b47a7612437fa270e488c77dafc9c96504e200c65d3f7315f731c4548836925afaeed2ff0dc68a6ecdabf08a9a9153f7a5d1b";
    bytes memory sellerSign = hexStringToBytes(num);
    address signer = market.recover(hash, sellerSign);
    console.log(signer);
  }

  function toBytes() public pure returns (bytes memory) {
    bytes memory result = new bytes(65);
    string memory num = "0x35ea571b7f95a959d5b43cf0847197804012495eebf0b6f4a6a6d5786e17e0c65c88495623379b6861b13879360f5b793032def130eb07e040efb3143038cf591c";
    assembly {
        mstore(add(result, 65), num)
    }
    return result;
  }

  function test_assembly() public view {
    bytes32 pr;
    assembly {
      let ptr := mload(0x40)
      // mstore(ptr, hex"19_01")
      mstore(add(ptr, 0x02), 0)
      pr := ptr
    }
    console.logBytes32(pr);
  }

  function test_sign() public view {
    uint256 prv = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    address account = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    uint256 tokenId = createTokenId(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, "http://localhost:3000", "http://localhost:3000/space/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266/1", 1);
    uint256 price = 8888;
    bytes32 hashData = market.getSignHash(account, address(nft), tokenId, price);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(prv, hashData);
    bytes memory signature = abi.encodePacked(r, s, v);
    
    console.log(signature.length);
  }

  function hexStringToBytes(string memory num) public pure returns (bytes memory) {
    bytes memory hexBytes = bytes(num);
    
    // Ensure the string starts with '0x'
    require(hexBytes.length >= 2 && hexBytes[0] == '0' && hexBytes[1] == 'x', "Invalid hex string");
    
    uint length = hexBytes.length - 2; // Exclude "0x"
    require(length % 2 == 0, "Hex string must have an even number of characters");
    
    bytes memory result = new bytes(length / 2);
    
    for (uint i = 0; i < length / 2; i++) {
        result[i] = bytes1(_fromHexChar(uint8(hexBytes[2 + 2 * i])) * 16 + _fromHexChar(uint8(hexBytes[3 + 2 * i])));
    }
    
    return result;
  }

  // Helper function to convert a hex character to its value
  function _fromHexChar(uint8 c) internal pure returns (uint8) {
    if (bytes1(c) >= '0' && bytes1(c) <= '9') {
        return c - uint8(bytes1('0'));
    }
    if (bytes1(c) >= 'a' && bytes1(c) <= 'f') {
        return 10 + c - uint8(bytes1('a'));
    }
    if (bytes1(c) >= 'A' && bytes1(c) <= 'F') {
        return 10 + c - uint8(bytes1('A'));
    }
    revert("Invalid hex character");
  }

  function test_getCreator() public view {
    uint256 tokenId = 72791407931748004276589748829050622920751384330453328789245692068238198833164;
    address creator = nft.getCreator(tokenId);
    console.log(creator);
  }
}