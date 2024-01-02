// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import { Error } from "./lib/Error.sol";
import { PWNEpochClock } from "./PWNEpochClock.sol";

contract StakedPWN is Ownable2Step, ERC721 {

    // # INVARIANTS
    // - number of token ids in the last ownership change epoch is always equal to address balance
    // - no address can have ownership change with epoch > current epoch + 1
    // - mint will add id to the current epoch + 1
    // - burn will remove id from the current epoch + 1

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    address public immutable supplyManager;
    PWNEpochClock public immutable epochClock;

    bool public transfersEnabled;

    struct OwnedTokensInEpoch {
        uint16 epoch;
        // stake ids are incremented by 1
        // if 1000 new ids are added every second, it will take 8878 years to overflow
        uint48[] ids;
    }
    mapping(address => OwnedTokensInEpoch[]) internal _ownedTokensInEpochs;


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
        _mint(to, tokenId);
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

    function ownedTokensInEpochs(address owner) external view returns (OwnedTokensInEpoch[] memory) {
        return _ownedTokensInEpochs[owner];
    }

    function ownedTokenIdsAt(address owner, uint16 epoch) external view returns (uint256[] memory) {
        OwnedTokensInEpoch[] storage ownedTokenIds = _ownedTokensInEpochs[owner];
        if (ownedTokenIds.length == 0) {
            return new uint256[](0);
        }
        if (ownedTokenIds[0].epoch > epoch) {
            return new uint256[](0);
        }

        // find ownership change epoch
        uint256 changeIndex = ownedTokenIds.length - 1;
        while (ownedTokenIds[changeIndex].epoch > epoch) {
            changeIndex--;
        }

        // collect ids as uint256
        uint256 length = ownedTokenIds[changeIndex].ids.length;
        uint256[] memory ids = new uint256[](length);
        for (uint256 i; i < length;) {
            ids[i] = ownedTokenIds[changeIndex].ids[i];
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
        if (from != address(0)) {
            _removeIdFromOwner(from, firstTokenId, epoch);
        }
        if (to != address(0)) {
            _addIdToOwner(to, firstTokenId, epoch);
        }
    }

    function _addIdToOwner(address owner, uint256 tokenId, uint16 epoch) internal {
        OwnedTokensInEpoch[] storage ownedTokenIdsList = _ownedTokensInEpochs[owner];
        OwnedTokensInEpoch storage ownedTokenIds;

        if (ownedTokenIdsList.length == 0) {
            ownedTokenIds = ownedTokenIdsList.push();
            ownedTokenIds.epoch = epoch;
        } else {
            OwnedTokensInEpoch storage lastOwnedTokenIds = ownedTokenIdsList[ownedTokenIdsList.length - 1];
            if (lastOwnedTokenIds.epoch == epoch) {
                ownedTokenIds = lastOwnedTokenIds;
            } else {
                ownedTokenIds = ownedTokenIdsList.push();
                ownedTokenIds.epoch = epoch;
                ownedTokenIds.ids = lastOwnedTokenIds.ids;
            }
        }
        ownedTokenIds.ids.push(uint48(tokenId));
    }

    function _removeIdFromOwner(address owner, uint256 tokenId, uint16 epoch) internal {
        OwnedTokensInEpoch[] storage ownedTokenIdsList = _ownedTokensInEpochs[owner];
        OwnedTokensInEpoch storage lastOwnedTokenIds = ownedTokenIdsList[ownedTokenIdsList.length - 1];

        if (lastOwnedTokenIds.epoch == epoch) {
            _removeIdFromList(lastOwnedTokenIds.ids, tokenId);
        } else {
            OwnedTokensInEpoch storage ownedTokenIds = ownedTokenIdsList.push();
            ownedTokenIds.epoch = epoch;
            ownedTokenIds.ids = lastOwnedTokenIds.ids;
            _removeIdFromList(ownedTokenIds.ids, tokenId);
        }
    }

    function _removeIdFromList(uint48[] storage ids, uint256 tokenId) private {
        uint256 length = ids.length;
        for (uint256 i; i < length;) {
            if (ids[i] == tokenId) {
                ids[i] = ids[length - 1];
                ids.pop();
                return;
            }
            unchecked { ++i; }
        }
    }

}
