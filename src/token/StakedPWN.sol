// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import { IStakedPWNSupplyManager } from "src/interfaces/IStakedPWNSupplyManager.sol";
import { Error } from "src/lib/Error.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

/// @title Staked PWN token contract.
/// @notice The token is representation of a stake in the PWN DAO.
/// @dev This contract is Ownable2Step, which means that the ownership transfer
/// must be accepted by the new owner.
/// The token is mintable and burnable by the VoteEscrowedPWN contract.
contract StakedPWN is Ownable2Step, ERC721 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The address of the supply manager contract.
    IStakedPWNSupplyManager public immutable supplyManager;
    /// @notice The address of the epoch clock contract.
    PWNEpochClock public immutable epochClock;

    /// @notice The flag that enables token transfers.
    bool public transfersEnabled;

    /// The list of token ids owned by an address in an epoch.
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

    /// @notice StakedPWN constructor.
    /// @dev The owner must be the PWN DAO.
    /// The supply manager must be the VoteEscrowedPWN contract.
    /// @param _owner The address of the owner.
    /// @param _epochClock The address of the epoch clock contract.
    /// @param _supplyManager The address of the supply manager contract.
    constructor(address _owner, address _epochClock, address _supplyManager) ERC721("Staked PWN", "stPWN") {
        epochClock = PWNEpochClock(_epochClock);
        supplyManager = IStakedPWNSupplyManager(_supplyManager);
        _transferOwnership(_owner);
    }


    /*----------------------------------------------------------*|
    |*  # MINT & BURN                                           *|
    |*----------------------------------------------------------*/

    /// @notice Mints a token.
    /// @dev Only the supply manager can mint tokens.
    /// @param to The address of the token owner.
    /// @param tokenId The token id.
    function mint(address to, uint256 tokenId) external onlySupplyManager {
        _mint(to, tokenId);
    }

    /// @notice Burns a token.
    /// @dev Only the supply manager can burn tokens.
    /// @param tokenId The token id.
    function burn(uint256 tokenId) external onlySupplyManager {
        _burn(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER SWITCH                                       *|
    |*----------------------------------------------------------*/

    /// @notice Enables token transfers.
    /// @dev Only the owner can enable transfers.
    function enableTransfers() external onlyOwner {
        if (transfersEnabled) {
            revert Error.TransfersAlreadyEnabled();
        }
        transfersEnabled = true;
    }


    /*----------------------------------------------------------*|
    |*  # TOKEN OWNERSHIP                                       *|
    |*----------------------------------------------------------*/

    /// @notice Returns the list of token ids owned by an address.
    /// @param owner The address of the token owner.
    function ownedTokensInEpochs(address owner) external view returns (OwnedTokensInEpoch[] memory) {
        return _ownedTokensInEpochs[owner];
    }

    /// @notice Returns the list of token ids owned by an address in an epoch.
    /// @param owner The address of the token owner.
    /// @param epoch The epoch.
    function ownedTokenIdsAt(address owner, uint16 epoch) external view returns (uint256[] memory) {
        OwnedTokensInEpoch[] storage ownedTokenIds = _ownedTokensInEpochs[owner];
        // no owned tokens
        if (ownedTokenIds.length == 0) {
            return new uint256[](0);
        }
        // first owned tokens are in the future
        if (epoch < ownedTokenIds[0].epoch) {
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
    |*  # METADATA                                              *|
    |*----------------------------------------------------------*/

    /// @notice Returns the URI of the token metadata.
    /// @param tokenId The token id.
    /// @return The URI of the token metadata.
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return supplyManager.stakeMetadata(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    /// @notice Hook that is called before any token transfer.
    /// @dev The token transfer is allowed only if the transfers are enabled.
    /// The token ownership is updated in the `_ownedTokensInEpochs` mapping.
    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 /* batchSize */
    ) override internal {
        // filter mints and burns from require condition
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert Error.TransfersDisabled();
        }

        uint16 epoch = epochClock.currentEpoch() + 1;
        // remove token from old owner first to avoid duplicates in case of self transfer
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
