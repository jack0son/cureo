//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "./Ownable.sol";

contract PortalController {
    address internal _owner;

    // Only should be created by a contract
    constructor() {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert("not owner");
        _;
    }

    // Callee needs to be restricted
    function execute(
        address callee,
        uint256 value,
        bytes calldata data
    ) external onlyOwner returns (bool success, bytes memory returnData) {
        if (callee.code.length == 0) revert("not contract");

        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = callee.call{ value: value }(data);
    }

    // NOTE: The gallery should always destroy the `PortalController` in the same runtime context that deploys it.
    function destroy(address etherDestination) external onlyOwner {
        selfdestruct(payable(etherDestination));
    }

    // // solhint-disable-next-line no-empty-blocks
    // receive() external payable {}
}