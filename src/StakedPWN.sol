// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

interface IVoteEscrowedPWN {
    function transferStake(address from, address to, uint256 stakeId) external;
}

contract StakedPWN is Ownable2Step, ERC721 {

    // # INVARIANTS
    // - `VoteEscrowedPWN.transferStake` is called everytime `stPWN` token is transferred
    // - every `VoteEscrowedPWN` stake has exactly one `stPWN` token

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    IVoteEscrowedPWN public immutable voteEscrowedPWN;

    bool public transfersEnabled;


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyVoteEscrowedPWNContract() {
        require(msg.sender == address(voteEscrowedPWN), "StakedPWN: caller is not vote escrowed pwn contract");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _owner, address _vePWN) ERC721("Staked PWN", "stPWN") {
        voteEscrowedPWN = IVoteEscrowedPWN(_vePWN);
        _transferOwnership(_owner);
    }


    /*----------------------------------------------------------*|
    |*  # MINT & BURN                                           *|
    |*----------------------------------------------------------*/

    function mint(address to, uint256 tokenId) external onlyVoteEscrowedPWNContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyVoteEscrowedPWNContract {
        _burn(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER SWITCH                                       *|
    |*----------------------------------------------------------*/

    function enableTransfers() external onlyOwner {
        require(!transfersEnabled, "StakedPWN: transfers are already enabled");
        transfersEnabled = true;
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    function _beforeTokenTransfer(
        address from, address to, uint256 firstTokenId, uint256 /* batchSize */
    ) override internal {
        // filter mints and burns from require condition
        if (from != address(0) && to != address(0)) {
            require(transfersEnabled, "StakedPWN: transfers are disabled");
        }
        voteEscrowedPWN.transferStake(from, to, firstTokenId);
    }

}
