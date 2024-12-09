// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LSNFT.sol";
import "../src/Market.sol";
import "../src/Space.sol";

contract MarketScript is Script {

  function run() public {
    vm.startBroadcast();
    address owner = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // local
    // address owner = 0xD571Cb930A525c83D7D2B7442a34b09c5F1cCa3E; // test
    address feeTo = 0x77C6E6bCF894db0CF226BCE6c6e66498f1d41a77;
    
    LSNFT nft = new LSNFT(owner);
    console.log("create nft contract: ", address(nft));

    Market market = new Market(address(nft), payable(feeTo));
    console.log("create market contract: ", address(market));

    Space space = new Space(address(nft));
    console.log("create space contract: ", address(space));

    // nft.setAdmin(address(market));

    vm.stopBroadcast();
  }
}