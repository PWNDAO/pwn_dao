// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { PWN } from "./PWN.sol";
import { PWNEpochClock } from "./PWNEpochClock.sol";
import { StakedPWN } from "./StakedPWN.sol";
import { VoteEscrowedPWNBase } from "./vePWN/VoteEscrowedPWNBase.sol";
import { VoteEscrowedPWNStake } from "./vePWN/VoteEscrowedPWNStake.sol";
import { VoteEscrowedPWNPower } from "./vePWN/VoteEscrowedPWNPower.sol";

contract VoteEscrowedPWN is VoteEscrowedPWNStake, VoteEscrowedPWNPower {

    // # INVARIANTS
    // - stakes for past & current epochs are immutable
    // - sum of all stakers power == total power
    // - sum of all address power changes == 0
    // - total power for epoch is up-to-date only if `lastCalculatedTotalPowerEpoch` >= epoch
    // - calculated total power cannot be negative
    // - any `initialEpoch` cannot be equal to 0 & greater than current epoch + 1
    // - stakes `remainingLockup` is always > 0
    // - every stake has exactly one `stPWN` token

    // max stake ≈ 7e28 < max int104 (1e31)
    //  - total initial supply with decimals (1e26)
    //  - max multiplier with decimals (350)
    //  - 350 max inflation claims (2)
    // epoch number for the next 5.4k years < max uint16 (65535)
    // max epoch lock up number 130 < max uint8 (255)

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    // solhint-disable-next-line no-empty-blocks
    constructor() {
        // Is used as a proxy. Use initializer to setup initial properties.
    }

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

    function stakerPowerAt(address staker, uint256 epoch)
        public
        view
        virtual
        override(VoteEscrowedPWNBase, VoteEscrowedPWNPower)
        returns (uint256)
    {
        return super.stakerPowerAt(staker, epoch);
    }

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
