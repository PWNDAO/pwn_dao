// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";


interface IVoteEscrowedPWN {
    function transferStake(address from, address to, uint256 stakeId) external;
}

contract StakedPWN is ERC721 {

    // # INVARIANTS
    // - `transferStake` has to be called on `VoteEscrowedPWN` contract anytime token is transferred
    // - only `VoteEscrowedPWN` contract can mint & burn tokens

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    IVoteEscrowedPWN public immutable stakingContract; // rename (make it mutable?)


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), "StakedPWN: caller is not staking contract");
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _stakingContract) ERC721("Staked PWN", "stPWN") {
        stakingContract = IVoteEscrowedPWN(_stakingContract);
    }


    /*----------------------------------------------------------*|
    |*  # MINT & BURN                                           *|
    |*----------------------------------------------------------*/

    function mint(address to, uint256 tokenId) external onlyStakingContract {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyStakingContract {
        _burn(tokenId);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 /* batchSize */) override internal {
        stakingContract.transferStake(from, to, firstTokenId);
    }

}
