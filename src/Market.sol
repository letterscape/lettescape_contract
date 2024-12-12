// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./LSNFT.sol";

contract Market is ReentrancyGuard, Nonces, EIP712("LSMarket", "1") {

    bytes32 public constant WNFT_TYPEHASH = keccak256(
        "WNFT(address owner,address nft,uint256 tokenId,uint256 price,uint256 nonce)"
    );

    uint256 public constant PERCENT = 100;

    uint256 public constant MILLI = 1000;

    // mint fee 3%
    uint256 public constant MINT_FEE = 3;

    // value-add tax
    uint256 public constant VAT_C = 12;
    uint256 public constant VAT_P = 1;

    // 1% per day
    // hold fee to creator
    uint256 public constant HOLD_FEE_C = 1;
    // hold fee to project
    uint256 public constant HOLD_FEE_P = 1;

    // interval: one hour as a unit
    uint256 public constant MIN_INTERVAL = 24;

    address public nft;

    address payable public feeTo;

    //tokenId => WNFT
    mapping(uint256 => WNFT) private wnfts;

    uint256[50] _placeholder1;

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

    uint256[50] _placeholder2;

    event NFTExpired(uint256 indexed tokenId, address indexed owner, uint256 price, uint256 deadline);

    constructor(address _nft, address payable _feeTo) {
        nft = _nft;
        feeTo = _feeTo;
    }

    // high 160 bits of tokenId is creator address
    // minter is not equal to creator
    //todo The period between first mint and first trading that creator should not pay the hold fee and mint fee
    //todo Add a changeInterval function which effects in the next interval
    function mint(uint256 tokenId, uint256 price, uint16 interval, string memory originURI) public payable {
        LSNFT(nft).mint(msg.sender, tokenId, originURI);
        WNFT memory wnft = WNFT({
            isPaid: false,
            isListed: false,
            isExpired: false,
            interval: interval,
            owner: msg.sender,
            deadline: block.timestamp + uint256(interval) * 3600,
            tokenId: tokenId,
            price: price,
            lastDealPrice: 0
        });
        wnfts[tokenId] = wnft;

        // creators don't need to pay mint fee
        if (msg.sender == LSNFT(nft).getCreator(tokenId)) return;
        
        uint256 mintFee = getMintFee(price);

        require(msg.value >= mintFee, "mint fee not enough");
        feeTo.transfer(mintFee);
    }

    // offline sign approve
    function list(uint256 tokenId, uint256 price, bytes memory sellerSign) public {
        require(price > 0, "invalid price");
        require(!isExpired(tokenId), "nft is expired");
        require(!isOnsale(tokenId), "nft is on sale");
        address owner = LSNFT(nft).ownerOf(tokenId);
        bytes32 hash = getSignHash(owner, nft, tokenId, price);
        address signer = recover(hash, sellerSign);
        require(signer == owner, "invalid signer");

        WNFT storage wnft = wnfts[tokenId];

        wnft.isListed = true;

        if (!LSNFT(nft).isApprovedForAll(owner, address(this))) {
            LSNFT(nft).setApprovalForAll(owner, address(this), true);
        }
    }

    // function list(uint256 tokenId, uint256 price) public {
    //     require(price > 0, "invalid price");
    //     require(!isExpired(tokenId), "nft is expired");
    //     require(!isOnsale(tokenId), "nft is on sale");
    //     address owner = LSNFT(nft).ownerOf(tokenId);

    //     WNFT storage wnft = wnfts[tokenId];

    //     wnft.isListed = true;

    //     // LSNFT(nft).approve(to, tokenId);
    // }

    function buy(uint256 tokenId, uint256 buyPrice, uint256 sellPrice) public payable nonReentrant {
        WNFT storage wnft = wnfts[tokenId];
        address oldOwner = wnft.owner;
        address buyer = msg.sender;

        require(oldOwner != address(0), "invalid tokenId");
        require(oldOwner != buyer, "buyer is same with seller");
        require(sellPrice > 0, "invalid sellPrice");
        require(!isExpired(tokenId), "nft is expired");

        uint256 oldPrice = wnft.price;
        require(buyPrice >= oldPrice, "invalid buyPrice");

        uint256 amt = msg.value;
        (uint256 holdFeeP, uint256 timeDelay) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_P);
        uint256 holdFeeC = getHoldFee(tokenId, 2);
    
        require(amt == buyPrice + holdFeeP + holdFeeC, "Incorrect amount");

        // transfer nft to buyer
        LSNFT(nft).safeTransferFrom(wnft.owner, msg.sender, tokenId, "");
        wnft.owner = msg.sender;

        // reset approve
        if (!LSNFT(nft).isApprovedForAll(buyer, address(this))) {
            LSNFT(nft).setApprovalForAll(buyer, address(this), true);
        }

        // 每次交易后，重置deadline，重置后会延长nft的过期时间
        wnft.deadline = block.timestamp + timeDelay;
        // 交易后需支付hold fee，防止通过不断地平价交易延长deadline来逃避hold fee
        wnft.isPaid = true;

        uint256 vat_p = 0;
        uint256 vat_c = 0;
        uint256 margin = buyPrice - wnft.lastDealPrice;

        if (wnft.lastDealPrice > 0 && margin >= 0) {
            vat_c = (margin) * VAT_C / PERCENT;
            vat_p = (margin) * VAT_P / PERCENT;
            if (vat_c == 0) vat_c = 1;
            if (vat_p == 0) vat_p = 1;
            payable(LSNFT(nft).getCreator(tokenId)).transfer(holdFeeC + vat_c);
        }

        wnft.price = sellPrice;
        wnft.lastDealPrice = buyPrice;

        // reset tokenURI when the owner changed
        LSNFT(nft).setTokenURI(tokenId, "");

        uint256 oldOwnerProfit = oldPrice - vat_c - vat_p;
        if (oldOwnerProfit > 0) {
            payable(oldOwner).transfer(oldPrice - vat_c - vat_p);
        }
        feeTo.transfer(holdFeeP + vat_p);
    }

    // only the owner can burn anytime
    function burn(uint256 tokenId) public nonReentrant {
        address owner = LSNFT(nft).ownerOf(tokenId);
        require((owner == msg.sender || isExpired(tokenId)), "no permission to burn");

        delete wnfts[tokenId];
        LSNFT(nft).burn(tokenId);
    }

    // polling
    function payHoldFee(uint256 tokenId) public payable nonReentrant {
        require(!isExpired(tokenId), "nft is expired");

        uint256 payFee = msg.value;
        WNFT storage wnft = wnfts[tokenId];
        (uint256 holdFeeP, uint256 timeDelay) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_P);
        uint256 holdFeeC = getHoldFee(tokenId, 2);
        require(payFee ==  holdFeeP + holdFeeC, "Incorrect fee amount");

        wnft.deadline += timeDelay;
        wnft.isPaid = true;

        if (holdFeeP > 0) {
            feeTo.transfer(holdFeeP);
        }

        if (holdFeeC > 0) {
            address creator = LSNFT(nft).getCreator(tokenId);
            payable(creator).transfer(holdFeeC);
        }
    }

    function getHoldFee(uint256 price, uint16 interval, uint256 rate) internal pure returns (uint256, uint256) {
        uint256 interval_256 = uint256(interval);
        uint256 shouldPayAmt = (price * interval_256 * rate) / (PERCENT * MIN_INTERVAL);
        uint256 timeDelay = interval_256 * 3600;
        if (shouldPayAmt == 0) shouldPayAmt = 1;
        return (shouldPayAmt, timeDelay);
    }

    // choice: 1 get holdFeeP, 2 get holdFeeC, 3 get holdFeeP + holdFeeC
    function getHoldFee(uint256 tokenId, uint8 choice) public view returns (uint256) {
        WNFT memory wnft = wnfts[tokenId];
        uint256 fee;
        if (choice == 1) {
            (fee, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_P);
            if (fee == 0) fee = 1;
        } else if (choice == 2) {
            if (wnft.lastDealPrice > 0) {
                (fee, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_C);
                if (fee == 0) fee = 1;  
            }
        } else {
            if (wnft.lastDealPrice > 0) {
                (uint256 holdFeeC, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_C); 
                if (holdFeeC == 0) holdFeeC = 1;
                fee += holdFeeC;
            }
            (uint256 holdFeeP, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_P);
            if (holdFeeP == 0) holdFeeP = 1;
            fee += holdFeeP;
        }
        return fee;
    }

    // cannot use tokenId to get mintfee, because there is no wnft when mint a nft
    function getMintFee(uint256 price) public pure returns (uint256 mintFee) {
        mintFee = price * MINT_FEE / PERCENT;
        if (mintFee == 0) {
            mintFee = 1;
        }
    }

    function soldOut(uint256 tokenId) public {
        require(!isExpired(tokenId), "nft is expired");
        WNFT storage wnft = wnfts[tokenId];
        require(wnft.owner == msg.sender);
        wnft.isListed = false;
    }

    function changePrice(uint256 tokenId, uint256 newPrice) private nonReentrant {
        require(!isExpired(tokenId), "nft is expired");
        WNFT storage wnft = wnfts[tokenId];
        require(wnft.owner == msg.sender);

        uint256 oldPrice = wnft.price;

        // when change a larger price, there will be a hold fee of margin price
        if (newPrice > oldPrice) {
            (uint256 holdFeeP, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_P);
            feeTo.transfer(holdFeeP);

            (uint256 holdFeeC, ) = getHoldFee(wnft.price, wnft.interval, HOLD_FEE_C);
            payable(LSNFT(nft).getCreator(tokenId)).transfer(holdFeeC);
        }
        wnft.price = newPrice;
    }

    function isOnsale(uint256 tokenId) public view returns (bool) {
        WNFT memory wnft = wnfts[tokenId];
        return wnft.isListed;
    }

    function isExpired(uint256 tokenId) public returns (bool) {
        WNFT memory wnft = wnfts[tokenId];
        if (wnft.isExpired) {
            return true;
        }
        bool expired = block.timestamp > wnft.deadline;
        if (expired) {
            wnft.isPaid = false;
            wnft.isExpired = true;
            emit NFTExpired(tokenId, wnft.owner, wnft.price, wnft.deadline);
        }
        return expired;
    }

    function getWNFT(uint256 tokenId) public view returns (WNFT memory) {
        return wnfts[tokenId];
    }

    function getSignHash(address owner, address nftAddr, uint256 tokenId, uint256 price) public view returns (bytes32) {
        bytes32 digest = keccak256(abi.encode(WNFT_TYPEHASH, owner, nftAddr, tokenId, price, nonces(owner)));
        // bytes32 digest = keccak256(abi.encode(WNFT_TYPEHASH, owner, nftAddr, tokenId, price, 0));
        return EIP712._hashTypedDataV4(digest);
    }

    function recover(bytes32 hash, bytes memory sellerSign) public pure returns (address) {
        return ECDSA.recover(hash, sellerSign);
    }
}