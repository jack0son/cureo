// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IOwnable {
    error NotOwner();
    error InvalidOwner();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;
}

abstract contract Ownable is IOwnable {
    address public override owner;

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotOwner();

        _;
    }

    function transferOwnership(address newOwner) override external virtual onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
