// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract NFT is ERC1155, Ownable {

    address public NFTMintOwnership;
    mapping(uint256 => string) private _uris;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    constructor() ERC1155("URL"){
    }

    function chnageOwnership(address newOwner) external onlyOwner{
        NFTMintOwnership = newOwner;
    }

    function uri(uint256 tokenId) override public view returns (string memory) {
        return _uris[tokenId];
    }

    function getCurTokenId() public view returns (uint256) {
        return _tokenIds.current();
    }

    function mint(uint256 amount, string memory _metadata)
        public
        returns(uint256)
    {
        require(NFTMintOwnership == msg.sender, "Other than contract trying to mint");
        uint256 newItemId = _tokenIds.current();
        _uris[newItemId] = _metadata;
        _mint(msg.sender, newItemId, amount, "");
        _tokenIds.increment();
        return newItemId;
    }

    function sendtoReciepient(address recepient, uint256 id) //We probably don't need this; can directly call safe transferfrom
        public
    {
    safeTransferFrom (msg.sender, recepient, id, 1, "");// doubt, do we need to send _metadata?
    }
}