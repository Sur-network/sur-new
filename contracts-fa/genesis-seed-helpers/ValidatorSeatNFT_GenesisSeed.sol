// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../ValidatorSeatNFT.sol";

// ============================================================================
// هشدار: قرارداد کمکی seed کردن GENESIS — موقت، هرگز روی زنجیره‌ی واقعی مستقر نمی‌شود
//
// همتای contracts/ValidatorSeatNFT.sol. از قرارداد واقعی ارث می‌برد (چیدمان storage یکسان) و جایگاه‌های مؤسسین را در
// constructor خودش mint می‌کند، به همان ترتیبی که مؤسسین در ValidatorsRegistry_GenesisSeed seed می‌شوند (ولیدیتور
// نخست اول)، تا شناسه‌های توکن ۱ تا n با هم بخوانند. ابزار genesis: آن را روی یک زنجیره‌ی موقت مستقر کن، storage
// لمس‌شده را استخراج کن (این کار baseURI اولیه را هم می‌گیرد)، و آن را با runtime code ی «قرارداد واقعی» زیر
// SurAddresses.VALIDATOR_SEAT_NFT بنویس.
// ============================================================================
contract ValidatorSeatNFT_GenesisSeed is ValidatorSeatNFT {
    constructor(address[] memory founderOwners) {
        for (uint256 i = 0; i < founderOwners.length; i++) _mintSeat(founderOwners[i]);
    }
}
