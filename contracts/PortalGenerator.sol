//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "./IERC721.sol";
import "./Ownable.sol";
import "./PortalController.sol";

contract PortalGenerator is Ownable {

    // TODO
    // 1. listing period
    // 2. commission
    // 3. events
    // 4. cleanup

    // Prefix command for differentiating between future kinds of listings
    bytes32 internal constant CMD_FIXED_LISTING = keccak256('fixed-listing');

    // NOT SURE WHETHER TO MAKE THIS A VIRTUAL FUNCTION?
    // function generateAddress(
    //     bytes32 salt, // entropy generated by curator that creates the portal
    //     bytes memory data
    // ) external view virtual returns (address) {
    //     return _portalAddress(_create2Salt(salt, data));
    // }

    // could inline to reduce gas cost
    function _create2Salt(
        bytes32 salt,
        bytes memory data
    ) internal pure returns (bytes32)  {
        return keccak256(abi.encode(CMD_FIXED_LISTING, salt, data));
    }

    function _portalAddress(bytes32 portalSalt) internal view returns (address) {
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
                            portalSalt,
                            keccak256(abi.encodePacked(type(PortalController).creationCode)) // only portal code
                        )
                    )
                )
            )
        );
    }

    // _execute allows the Exhibition contract to call arbitrary contract code at the portalAddress.
    function _execute(
        PortalController portalController,
        address callee,
        uint256 nativeValue,
        bytes memory payload
    ) internal returns (bool) {
        (bool success, bytes memory returnData) = portalController.execute(callee, nativeValue, payload);
        return success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

    // should I make these some kind of inheritable function?
    // // user and gallery need salt to control any tokens at portalAddress
    // function buy(
    //     bytes32 salt,
    //     address payable sellerAddress,
    //     address tokenAddress,
    //     uint256 tokenID,
    //     uint256 price
    // ) external payable {
    //     // can use >= because controller contract will refund the payment
    //     require(started, "exhibition not started");
    //     require(block.timestamp < startTime + salePeriod, "exhibition over");
    //     // are they only able to pay using ETH? Should I try adding ERC20 functionality too?
    //     require(msg.value >= price, "insufficient payment");

    //     // build calldata object for IERC721.transferFrom()
    //     bytes memory data = abi.encode(sellerAddress, tokenAddress, tokenID, price);

    //     ListingController listingController = new ListingController{
    //     salt: _create2Salt(salt, data)
    //     }();

    //     // buy parameters must match listing parameters used to create listing address for execution
    //     // on the ListingController to succeed
    //     if (
    //         !_execute(
    //             listingController, 
    //             tokenAddress, 
    //             0, 
    //             abi.encodeWithSelector(
    //                 IERC721.transferFrom.selector,
    //                 address(listingController),   // from
    //                 msg.sender,                 // to
    //                 tokenID
    //             )
    //         )
    //     ) revert ("transferFrom failed");

    //     // todo: use safe math to handle overflow
    //     uint256 commission = price * commissionPercent / 100;

    //     (bool paidCurator,) = owner.call{value: commission}("");
    //     if(!paidCurator) revert("failed to pay curator");

    //     (bool paidSeller,) = sellerAddress.call{value: price - commission}("");
    //     if(!paidSeller) revert("failed to pay seller");

    //     // don't pay contract storage costs
    //     listingController.destroy(msg.sender);
    // }

    // // sellerAddress: original seller to refund to
    // // todo: rename to reclaim
    // function refund(bytes32 salt, address sellerAddress, address tokenAddress, uint256 tokenID, uint256 price)
    // external {
    //     require(!started || block.timestamp > startTime + salePeriod, "exhibition in progress");

    //     bytes memory data = abi.encode(sellerAddress, tokenAddress, tokenID, price);

    //     // instantiate controller contract to listingAddress address
    //     ListingController listingController = new ListingController{
    //     salt: _create2Salt(salt, data)
    //     }();

    //     // transfer token from listingController to seller
    //     if (!_execute(listingController, tokenAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector,
    //         address(listingController),   // from
    //         sellerAddress,              // to
    //         tokenID
    //         ))) revert ("refund failed");


    //     // NOTE: `listingController` must always be destroyed in the same runtime context that it is deployed.
    //     listingController.destroy(address(this));
    // }
}