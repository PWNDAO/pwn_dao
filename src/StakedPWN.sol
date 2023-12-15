// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import { IStakedPWNSupplyManager } from "./interfaces/IStakedPWNSupplyManager.sol";
import { Error } from "./lib/Error.sol";

contract StakedPWN is Ownable2Step, ERC721 {

    // # INVARIANTS
    // - `IStakedPWNSupplyManager.transferStake` is called everytime `stPWN` token is transferred

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    IStakedPWNSupplyManager public immutable supplyManager;

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

    constructor(address _owner, address _supplyManager) ERC721("Staked PWN", "stPWN") {
        supplyManager = IStakedPWNSupplyManager(_supplyManager);
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
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 /* batchSize */
    ) override internal {
        // filter mints and burns from require condition
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert Error.TransfersDisabled();
        }
        supplyManager.transferStake(from, to, firstTokenId);
    }

}
