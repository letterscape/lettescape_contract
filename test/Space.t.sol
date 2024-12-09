// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/LSNFT.sol";
import "../src/Space.sol";

contract SpaceTest is Test {

  Space space;

  LSNFT nft;

  function setUp() public {
    nft = new LSNFT(address(this));
    space = new Space(address(nft));
  }

  function test_create_success() public {
    address author = makeAddr("author1");
    string memory originURI = "http://localhost:3000/space/fc7b1b2437b947f1a56f1f399fbf6753";
    vm.startPrank(author);
    space.create("fc7b1b2437b947f1a56f1f399fbf6753", "Evolving Influencers", "QmYHAvydF2Xo7XrkQGpRYhbfm4JUmWPKyeDgJwpdjAfewT", originURI);
    vm.stopPrank();

    bool isBind = nft.checkBinding(originURI, author);
    vm.assertEq(true, isBind);
  }
}