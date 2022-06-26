//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "./IERC721.sol";
import "./Ownable.sol";

contract CureoExhibition is Ownable {

    // TODO
    // 1. offer period
    // 2. commission
    // 3. events
    // 4. cleanup

    // Prefix command for differentiating between future kinds of listings
    bytes32 internal constant CMD_FIXED_OFFER = keccak256('fixed-offer');

    uint256 private commissionPercent;

    constructor(uint256 commissionPercentage_) {
        require(commissionPercent <= 100, 'invalid commission');
        commissionPercent = commissionPercentage_;
    }

    function offerAddress(
        bytes32 salt, // entropy generated by curator that creates the offer
        address sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) external view returns (address) {
        return _offerAddress(_create2Salt(salt, sellerAddress, tokenAddress, tokenID, price));
    }

    // could inline to reduce gas cost
    function _create2Salt(
        bytes32 salt,
        address sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) internal view returns (bytes32)  {
        return keccak256(abi.encode(CMD_FIXED_OFFER, salt, sellerAddress, tokenAddress, tokenID, price));
    }

    // _execute allows the Exhibition contract to call arbitrary contract code at the offerAddress.
    function _execute(
        OfferController offerController,
        address callee,
        uint256 nativeValue,
        bytes memory payload
    ) internal returns (bool) {
        (bool success, bytes memory returnData) = offerController.execute(callee, nativeValue, payload);
        return success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

    // user and gallery need salt to control any tokens at offerAddress
    function buy(
        bytes32 salt,
        address payable sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) external payable {
        // can use >= because controller contract will refund the payment
        require(msg.value >= price, "insufficient payment");

        OfferController offerController = new OfferController{
        salt: _create2Salt(salt, sellerAddress, tokenAddress, tokenID, price)
        }();

        // buy parameters must match offer parameters used to create offer address for execution
        // on the OfferController to succeed
        if (!_execute(offerController, tokenAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector,
            address(offerController),   // from
            msg.sender,                 // to
            tokenID
            ))) revert ("transferFrom failed");

        // todo: use safe math to handle overflow
        uint256 commission = price * commissionPercent / 100;

        (bool paidCurator,) = owner.call{value: commission}("");
        if(!paidCurator) revert("failed to pay curator");

        (bool paidSeller,) = sellerAddress.call{value: price - commission}("");
        if(!paidSeller) revert("failed to pay seller");

        // don't pay contract storage costs
        offerController.destroy(msg.sender);
    }

    // sellerAddress: original seller to refund to
    // todo: rename to reclaim
    function refund(bytes32 salt, address sellerAddress, address tokenAddress, uint256 tokenID, uint256 price)
    external {

        // instantiate controller contract to offerAddress address
        OfferController offerController = new OfferController{
        salt: _create2Salt(salt, sellerAddress, tokenAddress, tokenID, price)
        }();

        // transfer token from offerController to seller
        if (!_execute(offerController, tokenAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector,
            address(offerController),   // from
            sellerAddress,              // to
            tokenID
            ))) revert ("refund failed");


        // NOTE: `offerController` must always be destroyed in the same runtime context that it is deployed.
        offerController.destroy(address(this));
    }

    function _offerAddress(bytes32 offerSalt) internal view returns (address) {
        /* Convert a hash which is bytes32 to an address which is 20-byte long
        according to https://docs.soliditylang.org/en/v0.8.1/control-structures.html?highlight=create2#salted-contract-creations-create2 */
        return
        address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this), // creator
                            offerSalt,
                            keccak256(abi.encodePacked(type(OfferController).creationCode)) // only offer code
                        )
                    )
                )
            )
        );
    }
}

// Allow exhibition contract to act as offer address
contract OfferController {
    address internal _owner;

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

    // NOTE: The gallery should always destroy the `OfferController` in the same runtime context that deploys it.
    function destroy(address etherDestination) external onlyOwner {
        selfdestruct(payable(etherDestination));
    }

    // // solhint-disable-next-line no-empty-blocks
    // receive() external payable {}
}
