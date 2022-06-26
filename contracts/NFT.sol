//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./Ownable.sol";

abstract contract NFT is ERC721, Ownable {
    constructor() {
    }

    function mint(address to, uint256 tokenID) external onlyOwner {
        _safeMint(to, tokenID);
    }
}
