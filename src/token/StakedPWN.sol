// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

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
        address from, address to, uint256 /* firstTokenId */, uint256 /* batchSize */
    ) override internal {
        // filter mints and burns from require condition
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert Error.TransfersDisabled();
        }
    }

}
