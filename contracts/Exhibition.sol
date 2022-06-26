//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "./IERC721.sol";
import "./Ownable.sol";

contract CureoExhibition is Ownable {

    // TODO
    // 1. listing period
    // 2. commission
    // 3. events
    // 4. cleanup

    // Prefix command for differentiating between future kinds of listings
    bytes32 internal constant CMD_FIXED_LISTING = keccak256('fixed-listing');

    uint256 private commissionPercent;
    uint256 startTime;
    uint256 salePeriod;
    bool started;

    constructor(uint256 commissionPercentage_, uint256 salePeriod_) {
        require(commissionPercent <= 100, "invalid commission");
        require(salePeriod <= 604800, "4 weeks maximum sale period");

        commissionPercent = commissionPercentage_;
        salePeriod = salePeriod_;
        started = false;
    }

    function start() external onlyOwner {
        startTime = block.timestamp;
        started = true;
    }

    function listingAddress(
        bytes32 salt, // entropy generated by curator that creates the listing
        address sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) external view returns (address) {
        return _listingAddress(_create2Salt(salt, sellerAddress, tokenAddress, tokenID, price));
    }

    // could inline to reduce gas cost
    function _create2Salt(
        bytes32 salt,
        address sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) internal pure returns (bytes32)  {
        return keccak256(abi.encode(CMD_FIXED_LISTING, salt, sellerAddress, tokenAddress, tokenID, price));
    }

    // _execute allows the Exhibition contract to call arbitrary contract code at the listingAddress.
    function _execute(
        ListingController listingController,
        address callee,
        uint256 nativeValue,
        bytes memory payload
    ) internal returns (bool) {
        (bool success, bytes memory returnData) = listingController.execute(callee, nativeValue, payload);
        return success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));
    }

    // user and gallery need salt to control any tokens at listingAddress
    function buy(
        bytes32 salt,
        address payable sellerAddress,
        address tokenAddress,
        uint256 tokenID,
        uint256 price
    ) external payable {
        // can use >= because controller contract will refund the payment
        require(started, "exhibition not started");
        require(block.timestamp < startTime + salePeriod, "exhibition over");
        require(msg.value >= price, "insufficient payment");

        ListingController listingController = new ListingController{
        salt: _create2Salt(salt, sellerAddress, tokenAddress, tokenID, price)
        }();

        // buy parameters must match listing parameters used to create listing address for execution
        // on the ListingController to succeed
        if (!_execute(listingController, tokenAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector,
            address(listingController),   // from
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
        listingController.destroy(msg.sender);
    }

    // sellerAddress: original seller to refund to
    // todo: rename to reclaim
    function refund(bytes32 salt, address sellerAddress, address tokenAddress, uint256 tokenID, uint256 price)
    external {
        require(!started || block.timestamp > startTime + salePeriod, "exhibition in progress");

        // instantiate controller contract to listingAddress address
        ListingController listingController = new ListingController{
        salt: _create2Salt(salt, sellerAddress, tokenAddress, tokenID, price)
        }();

        // transfer token from listingController to seller
        if (!_execute(listingController, tokenAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector,
            address(listingController),   // from
            sellerAddress,              // to
            tokenID
            ))) revert ("refund failed");


        // NOTE: `listingController` must always be destroyed in the same runtime context that it is deployed.
        listingController.destroy(address(this));
    }

    function _listingAddress(bytes32 listingSalt) internal view returns (address) {
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
                            listingSalt,
                            keccak256(abi.encodePacked(type(ListingController).creationCode)) // only listing code
                        )
                    )
                )
            )
        );
    }
}

// Allow exhibition contract to act as listing address
contract ListingController {
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

    // NOTE: The gallery should always destroy the `ListingController` in the same runtime context that deploys it.
    function destroy(address etherDestination) external onlyOwner {
        selfdestruct(payable(etherDestination));
    }

    // // solhint-disable-next-line no-empty-blocks
    // receive() external payable {}
}
