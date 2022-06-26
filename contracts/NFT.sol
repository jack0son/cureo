//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
//import "./Ownable.sol";

contract NFT is ERC721 {
    constructor() ERC721("TEST NFT", "FKE") {
    }

    function mint(address to, uint256 tokenID) public {
        _safeMint(to, tokenID);
    }
}
