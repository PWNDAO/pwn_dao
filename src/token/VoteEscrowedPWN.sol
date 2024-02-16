// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { VoteEscrowedPWNBase } from "src/token/vePWN/VoteEscrowedPWNBase.sol";
import { VoteEscrowedPWNStake } from "src/token/vePWN/VoteEscrowedPWNStake.sol";
import { VoteEscrowedPWNStakeMetadata } from "src/token/vePWN/VoteEscrowedPWNStakeMetadata.sol";
import { VoteEscrowedPWNPower } from "src/token/vePWN/VoteEscrowedPWNPower.sol";
import { PWN } from "src/token/PWN.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

/// @title VoteEscrowedPWN
/// @notice VoteEscrowedPWN is a contract for voting with PWN tokens.
/// @dev VoteEscrowedPWN is a contract for gaining voting power with PWN tokens.
contract VoteEscrowedPWN is VoteEscrowedPWNStake, VoteEscrowedPWNStakeMetadata, VoteEscrowedPWNPower {

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor() {
        // Is used as a proxy. Use initializer to setup initial properties.
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @dev Can be called only once.
    /// @param _pwnToken The address of the PWN token.
    /// @param _stakedPWN The address of the staked PWN contract.
    /// @param _epochClock The address of the epoch clock contract.
    function initialize(
        address _pwnToken,
        address _stakedPWN,
        address _epochClock
    ) external initializer {
        pwnToken = PWN(_pwnToken);
        stakedPWN = StakedPWN(_stakedPWN);
        epochClock = PWNEpochClock(_epochClock);
    }

    // The following functions are overrides required by Solidity.

    /// @inheritdoc VoteEscrowedPWNBase
    function stakerPowerAt(address staker, uint256 epoch)
        public
        view
        virtual
        override(VoteEscrowedPWNBase, VoteEscrowedPWNPower)
        returns (uint256)
    {
        return super.stakerPowerAt(staker, epoch);
    }

    /// @inheritdoc VoteEscrowedPWNBase
    function totalPowerAt(uint256 epoch)
        public
        view
        virtual
        override(VoteEscrowedPWNBase, VoteEscrowedPWNPower)
        returns (uint256)
    {
        return super.totalPowerAt(epoch);
    }

}
