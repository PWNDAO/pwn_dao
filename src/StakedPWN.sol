// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import { Error } from "./lib/Error.sol";
import { PWNEpochClock } from "./PWNEpochClock.sol";

contract StakedPWN is Ownable2Step, ERC721 {

    // # INVARIANTS
    // - TODO:

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    address public immutable supplyManager;
    PWNEpochClock public immutable epochClock;

    bool public transfersEnabled;

    struct OwnershipChange {
        uint16 epoch;
        // ids are incremented by 1
        // if 1000 new ids are added every second, it will take 8878 years to overflow
        uint48[] ids;
    }
    mapping(address => OwnershipChange[]) internal _ownershipChanges;


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlySupplyManager() {
        if (msg.sender != address(supplyManager)) {
            revert Error.CallerNotSupplyManager();
        }
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _owner, address _epochClock, address _supplyManager) ERC721("Staked PWN", "stPWN") {
        epochClock = PWNEpochClock(_epochClock);
        supplyManager = _supplyManager;
        _transferOwnership(_owner);
    }


    /*----------------------------------------------------------*|
    |*  # MINT & BURN                                           *|
    |*----------------------------------------------------------*/

    function mint(address to, uint256 tokenId) external onlySupplyManager {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlySupplyManager {
        _burn(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER SWITCH                                       *|
    |*----------------------------------------------------------*/

    function enableTransfers() external onlyOwner {
        if (transfersEnabled) {
            revert Error.TransfersAlreadyEnabled();
        }
        transfersEnabled = true;
    }


    /*----------------------------------------------------------*|
    |*  # TOKEN OWNERSHIP                                       *|
    |*----------------------------------------------------------*/

    function ownershipChanges(address owner) external view returns (OwnershipChange[] memory) {
        return _ownershipChanges[owner];
    }

    function ownedTokenIdsAt(address owner, uint16 epoch) external view returns (uint256[] memory) {
        OwnershipChange[] storage changes = _ownershipChanges[owner];
        if (changes.length == 0) {
            return new uint256[](0);
        }
        if (changes[0].epoch > epoch) {
            return new uint256[](0);
        }

        // find ownership change epoch
        uint256 changeIndex = changes.length - 1;
        while (changes[changeIndex].epoch > epoch) {
            changeIndex--;
        }

        // collect ids as uint256
        uint256 length = changes[changeIndex].ids.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length;) {
            ids[i] = changes[changeIndex].ids[i];
            unchecked { ++i; }
        }

        return ids;
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 /* batchSize */
    ) override internal {
        // filter mints and burns from require condition
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert Error.TransfersDisabled();
        }

        uint16 epoch = epochClock.currentEpoch() + 1;
        if (to != address(0)) {
            _addIdToList(to, firstTokenId, epoch);
        }
        if (from != address(0)) {
            _removeIdFromList(from, firstTokenId, epoch);
        }
    }

    function _addIdToList(address owner, uint256 tokenId, uint16 epoch) internal {
        OwnershipChange[] storage changes = _ownershipChanges[owner];
        if (changes.length == 0) {
            OwnershipChange storage change = changes.push();
            change.epoch = epoch;
            change.ids.push(uint48(tokenId));
            return;
        }

        OwnershipChange storage lastChange = changes[changes.length - 1];
        if (lastChange.epoch == epoch) {
            lastChange.ids.push(uint48(tokenId));
        } else {
            OwnershipChange storage change = changes.push();
            change.epoch = epoch;
            change.ids = lastChange.ids;
            change.ids.push(uint48(tokenId));
        }
    }

    function _removeIdFromList(address owner, uint256 tokenId, uint16 epoch) private {
        OwnershipChange[] storage changes = _ownershipChanges[owner];
        OwnershipChange storage lastChange = changes[changes.length - 1];
        uint256 idIndex = _findIdInList(lastChange.ids, tokenId);

        if (lastChange.epoch == epoch) {
            lastChange.ids[idIndex] = lastChange.ids[lastChange.ids.length - 1];
            lastChange.ids.pop();
        } else {
            OwnershipChange storage change = changes.push();
            change.epoch = epoch;
            for (uint256 i; i < lastChange.ids.length;) {
                if (i == idIndex) {
                    unchecked { ++i; }
                    continue;
                }
                change.ids.push(lastChange.ids[i]);
                unchecked { ++i; }
            }
        }
    }

    function _findIdInList(uint48[] storage ids, uint256 tokenId) internal view returns (uint256 index) {
        uint256 length = ids.length;
        for (uint256 i; i < length;) {
            if (ids[i] == tokenId) {
                return i;
            }
            unchecked { ++i; }
        }
    }

}
