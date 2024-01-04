// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { PWN } from "./PWN.sol";
import { PWNEpochClock } from "./PWNEpochClock.sol";
import { StakedPWN } from "./StakedPWN.sol";
import { VoteEscrowedPWNBase } from "./vePWN/VoteEscrowedPWNBase.sol";
import { VoteEscrowedPWNStake } from "./vePWN/VoteEscrowedPWNStake.sol";
import { VoteEscrowedPWNPower } from "./vePWN/VoteEscrowedPWNPower.sol";

/// @title VoteEscrowedPWN
/// @notice VoteEscrowedPWN is a contract for voting with PWN tokens.
/// @dev VoteEscrowedPWN is a contract for gaining voting power with PWN tokens.
contract VoteEscrowedPWN is VoteEscrowedPWNStake, VoteEscrowedPWNPower {

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    // solhint-disable-next-line no-empty-blocks
    constructor() {
        // Is used as a proxy. Use initializer to setup initial properties.
    }

    /// @notice Initializes the contract.
    /// @dev Can be called only once.
    /// @param _pwnToken The address of the PWN token.
    /// @param _stakedPWN The address of the staked PWN contract.
    /// @param _epochClock The address of the epoch clock contract.
    /// @param _owner The address of the owner. Should be PWN DAO.
    function initialize(
        address _pwnToken,
        address _stakedPWN,
        address _epochClock,
        address _owner
    ) external initializer {
        pwnToken = PWN(_pwnToken);
        stakedPWN = StakedPWN(_stakedPWN);
        epochClock = PWNEpochClock(_epochClock);
        _transferOwnership(_owner);
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
