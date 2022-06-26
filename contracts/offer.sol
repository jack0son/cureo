//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./IERC721";

contract Gallery {
    string private greeting;

    // Prefix command for differntiating between other kinds of listings
    bytes32 internal constant CMD_OFFER = keccak256('offer');

    constructor(uint256 commissionBIPS) {
        _owner = msg.sender;
    }

    function offerAddress(
        bytes32 salt, // entropy - could be signed message from offer accepter
        address calldata holderAddress,
        address calldata tokenAddress,
        uint256 calldata tokenID,
        uint256 calldata price
    ) external view returns (address) {
        return _offerAddress(_create2Salt(salt, holderAddress, tokenAddress, tokenID, price));
    }

    // could inline to reduce gas cost
    function _create2Salt(
        bytes32 salt,
        address calldata holderAddress,
        address calldata tokenAddress,
        uint256 calldata tokenID,
        uint256 calldata price
    ) internal view returns (bytes32)  {
        return keccak256(abi.encode(abi.encode(CMD_OFFER, salt, holderAddress, tokenAddress, tokenID, price)));
    }

    function _execute(
        OfferController offerHandler,
        address callee,
        uint256 nativeValue,
        bytes memory payload
    ) internal returns (bool) {
        (bool success, bytes memory returnData) = offerHandler.execute(callee, nativeValue, payload);
        return success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

    // user and gallery need salt to controll any tokens at offerAddress
    function sell(
        bytes32 salt,
        address holderAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) {
        // could use >= because executor will refund the payment
        require(msg.value == price, "exact payment required");

        OfferController offerController = new OfferController{
        salt: _create2Salt(salt, holderAddress, tokenAddress, tokenID, price)
        }();

        if (!_execute(offerController, tokenAddress, 0, abi.encodeWithSelector(IERC721.selector.transferFrom,
            address(offerController), msg.sender, amount)))
            revert ("refund failed");

        offerController.destroy(msg.sender);
    }

    // holderAddress: original holder to refund to
    function refund(bytes32 salt, address holderAddress, address tokenAddress, uint256 tokenID, uint256 price) {

        // instantiate controller contract to offerAddress address
        OfferController offerController = new OfferController{
        salt: _create2Salt(salt, holderAddress, tokenAddress, tokenID, price)
        }();

        // transfer token from offerController to original holer
        if (!_execute(offerController, tokenAddress, 0, abi.encodeWithSelector(IERC721.selector.transferFrom,
            address(offerController), holderAddress, amount)))
            revert ('refund failed');

        // NOTE: `offerController` must always be destroyed in the same runtime context that it is deployed.
        offerController.destroy(address(this));
    }

    function _offerAddress(bytes32 create2Salt) internal view returns (address) {
        /* Convert a hash which is bytes32 to an address which is 20-byte long
        according to https://docs.soliditylang.org/en/v0.8.1/control-structures.html?highlight=create2#salted-contract-creations-create2 */
        return
        address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            create2Salt,
                            keccak256(abi.encodePacked(type(OfferController).creationCode))
                        )
                    )
                )
            )
        );
    }
}


contract OfferController {
    error NotOwner();
    error NotContract();

    address internal _owner;

    constructor() {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    // Callee needs to be restritced
    function execute(
        address callee,
        uint256 value,
        bytes calldata data
    ) external onlyOwner returns (bool success, bytes memory returnData) {
        if (callee.code.length == 0) revert NotContract();

        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = callee.call{ value: value }(data);
    }

    // NOTE: The gallery should always destroy the `OfferHandler` in the same runtime context that deploys it.
    function destroy(address etherDestination) external onlyOwner {
        selfdestruct(payable(etherDestination));
    }

    // // solhint-disable-next-line no-empty-blocks
    // receive() external payable {}
}
