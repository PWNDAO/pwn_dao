// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { Error } from "../lib/Error.sol";
import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";
import { EpochPowerLib } from "../lib/EpochPowerLib.sol";

abstract contract VoteEscrowedPWNStake is VoteEscrowedPWNBase {
    using EpochPowerLib for bytes32;

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event StakeCreated(uint256 indexed stakeId, address indexed staker, uint256 amount, uint256 lockUpEpochs);
    event StakeSplit(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 amount1,
        uint256 amount2,
        uint256 newStakeId1,
        uint256 newStakeId2
    );
    event StakeMerged(
        uint256 indexed stakeId1,
        uint256 indexed stakeId2,
        address indexed staker,
        uint256 amount,
        uint256 remainingLockup,
        uint256 newStakeId
    );
    event StakeIncreased(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 additionalAmount,
        uint256 newAmount,
        uint256 additionalEpochs,
        uint256 newEpochs,
        uint256 newStakeId
    );
    event StakeWithdrawn(uint256 indexed stakeId, address indexed staker, uint256 amount);


    /*----------------------------------------------------------*|
    |*  # STAKE MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /// @notice Creates a new stake for a caller.
    /// @dev Creates new power changes or update existing ones if overlapping.
    /// @param amount Amount of PWN tokens to stake.
    /// @param lockUpEpochs Number of epochs to lock up the stake for.
    /// @return stakeId Id of the created stake.
    function createStake(uint256 amount, uint256 lockUpEpochs) external returns (uint256 stakeId) {
        // max stake of total initial supply (100M) with decimals 1e26 < max uint88 (3e26)
        if (amount < 100 || amount > type(uint88).max) {
            revert Error.InvalidAmount();
        }
        // amount must be a multiple of 100 to prevent rounding errors when computing power
        if (amount % 100 > 0) {
            revert Error.InvalidAmount();
        }
        // lock up for <1; 5> + {10} years
        if (lockUpEpochs < EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }
        if (lockUpEpochs > 5 * EPOCHS_IN_YEAR && lockUpEpochs != 10 * EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }

        address staker = msg.sender;
        uint16 initialEpoch = epochClock.currentEpoch() + 1;

        // store power changes
        _updateTotalPower(uint104(amount), initialEpoch, uint8(lockUpEpochs), true);

        // create new stake
        stakeId = _createStake(staker, initialEpoch, uint104(amount), uint8(lockUpEpochs));

        // transfer pwn token
        pwnToken.transferFrom(staker, address(this), amount);

        // emit event
        emit StakeCreated(stakeId, staker, amount, lockUpEpochs);
    }

    /// @notice Splits a stake for a caller.
    /// @dev Burns an original stake token and mints two new stPWN tokens. Doesn't update any power changes.
    /// @param stakeId Id of the stake to split.
    /// @param splitAmount Amount of PWN tokens to split into a new stake.
    /// @return newStakeId1 Id of the first new stake.
    /// @return newStakeId2 Id of the second new stake.
    function splitStake(uint256 stakeId, uint256 splitAmount)
        external
        returns (uint256 newStakeId1, uint256 newStakeId2)
    {
        address staker = msg.sender;
        Stake storage originalStake = stakes[stakeId];
        uint16 originalInitialEpoch = originalStake.initialEpoch;
        uint104 originalAmount = originalStake.amount;
        uint8 originalRemainingLockup = originalStake.remainingLockup;

        // original stake must be owned by the caller
        if (stakedPWN.ownerOf(stakeId) != staker) {
            revert Error.NotStakeOwner();
        }
        // split amount must be greater than 0
        if (splitAmount == 0) {
            revert Error.InvalidAmount();
        }
        // split amount must be less than stake amount
        if (splitAmount >= originalAmount) {
            revert Error.InvalidAmount();
        }
        // split amount must be a multiple of 100 to prevent rounding errors when computing power
        if (splitAmount % 100 > 0) {
            revert Error.InvalidAmount();
        }

        // delete original stake
        _deleteStake(stakeId);

        // create new stakes
        newStakeId1 = _createStake(
            staker, originalInitialEpoch, originalAmount - uint104(splitAmount), originalRemainingLockup
        );
        newStakeId2 = _createStake(staker, originalInitialEpoch, uint104(splitAmount), originalRemainingLockup);

        // emit event
        emit StakeSplit(stakeId, staker, originalAmount - uint104(splitAmount), splitAmount, newStakeId1, newStakeId2);
    }

    /// @notice Merges two stakes for a caller.
    /// @dev Burns both stPWN tokens and mints a new one.
    /// @dev Aligns stakes lockups. First stake lockup must be longer than or equal to the second one.
    /// @param stakeId1 Id of the first stake to merge.
    /// @param stakeId2 Id of the second stake to merge.
    /// @return newStakeId Id of the new merged stake.
    function mergeStakes(uint256 stakeId1, uint256 stakeId2) external returns (uint256 newStakeId) {
        address staker = msg.sender;
        Stake storage stake1 = stakes[stakeId1];
        Stake storage stake2 = stakes[stakeId2];
        uint16 finalEpoch1 = stake1.initialEpoch + stake1.remainingLockup;
        uint16 finalEpoch2 = stake2.initialEpoch + stake2.remainingLockup;
        uint16 newInitialEpoch = epochClock.currentEpoch() + 1;

        // both stakes must be owned by the caller
        if (stakedPWN.ownerOf(stakeId1) != staker) {
            revert Error.NotStakeOwner();
        }
        if (stakedPWN.ownerOf(stakeId2) != staker) {
            revert Error.NotStakeOwner();
        }
        // the first stake lockup end must be greater than or equal to the second stake lockup end
        // both stake lockup ends must be greater than the current epoch
        if (finalEpoch1 < finalEpoch2 || finalEpoch1 <= newInitialEpoch) {
            revert Error.LockUpPeriodMismatch();
        }

        uint8 newRemainingLockup = uint8(finalEpoch1 - newInitialEpoch); // safe cast
        // only need to update second stake power changes if has different final epoch
        if (finalEpoch1 != finalEpoch2) {
            uint104 amount2 = stake2.amount;
            // clear second stake power changes if necessary
            if (finalEpoch2 > newInitialEpoch) {
                _updateTotalPower(amount2, newInitialEpoch, uint8(finalEpoch2 - newInitialEpoch), false);
            }
            // store new update power changes
            _updateTotalPower(amount2, newInitialEpoch, newRemainingLockup, true);
        }

        uint104 newAmount = stake1.amount + stake2.amount; // need to store before deleting stakes data
        // delete old stakes
        _deleteStake(stakeId1);
        _deleteStake(stakeId2);

        // create new stake
        newStakeId = _createStake(staker, newInitialEpoch, newAmount, newRemainingLockup);

        // emit event
        emit StakeMerged(stakeId1, stakeId2, staker, newAmount, newRemainingLockup, newStakeId);
    }

    /// @notice Increases a stake for a caller.
    /// @dev Creates new stake and burns old stPWN token.
    /// @dev If stakes lockup ended, `additionalEpochs` will be added from the next epoch.
    /// @dev The sum of current `remainingLockup` and `additionalEpochs` must be in <13;65> + {130}
    /// @dev Expecting pwn token approval for the contract if `additionalAmount` > 0.
    /// @param stakeId Id of the stake to increase.
    /// @param additionalAmount Amount of PWN tokens to increase the stake by.
    /// @param additionalEpochs Number of epochs to add to exisitng stake lockup.
    /// @return newStakeId Id of the new stake.
    function increaseStake(uint256 stakeId, uint256 additionalAmount, uint256 additionalEpochs)
        external
        returns (uint256 newStakeId)
    {
        address staker = msg.sender;
        Stake storage stake = stakes[stakeId];

        // stake must be owned by the caller
        if (stakedPWN.ownerOf(stakeId) != staker) {
            revert Error.NotStakeOwner();
        }
        // additional amount or additional epochs must be greater than 0
        if (additionalAmount == 0 && additionalEpochs == 0) {
            revert Error.NothingToIncrease();
        }
        if (additionalAmount > type(uint88).max) {
            revert Error.InvalidAmount();
        }
        // to prevent rounding errors when computing power
        if (additionalAmount % 100 > 0) {
            revert Error.InvalidAmount();
        }
        if (additionalEpochs > 10 * EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }

        uint16 newInitialEpoch = epochClock.currentEpoch() + 1;
        uint16 oldFinalEpoch = stake.initialEpoch + stake.remainingLockup;
        uint8 newRemainingLockup = SafeCast.toUint8(
            oldFinalEpoch <= newInitialEpoch ? additionalEpochs : oldFinalEpoch + additionalEpochs - newInitialEpoch
        );
        // extended lockup must be in <1; 5> + {10} years
        if (newRemainingLockup < EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }
        if (newRemainingLockup > 5 * EPOCHS_IN_YEAR && newRemainingLockup != 10 * EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }

        uint104 oldAmount = stake.amount;
        uint104 newAmount = oldAmount + uint104(additionalAmount); // safe cast

        { // avoid stack too deep
            bool additionOnly = additionalEpochs == 0;

            // clear old power changes if adding epochs
            if (!additionOnly && newRemainingLockup > additionalEpochs) {
                _updateTotalPower(oldAmount, newInitialEpoch, newRemainingLockup - uint8(additionalEpochs), false);
            }

            // store new power changes
            uint104 amount = additionOnly ? uint104(additionalAmount) : newAmount;
            _updateTotalPower(amount, newInitialEpoch, newRemainingLockup, true);
        }

        // delete original stake
        _deleteStake(stakeId);

        // create new stake
        newStakeId = _createStake(staker, newInitialEpoch, newAmount, newRemainingLockup);

        // transfer additional PWN tokens
        if (additionalAmount > 0) {
            pwnToken.transferFrom(staker, address(this), additionalAmount);
        }

        // emit event
        emit StakeIncreased(
            stakeId, staker, additionalAmount, newAmount, additionalEpochs, newRemainingLockup, newStakeId
        );
    }

    /// @notice Withdraws a stake for a caller.
    /// @dev Burns stPWN token and transfers PWN tokens to the caller.
    /// @param stakeId Id of the stake to withdraw.
    function withdrawStake(uint256 stakeId) external {
        address staker = msg.sender;
        Stake storage stake = stakes[stakeId];

        // stake must be owned by the caller
        if (stakedPWN.ownerOf(stakeId) != staker) {
            revert Error.NotStakeOwner();
        }
        // stake must be unlocked
        if (stake.initialEpoch + stake.remainingLockup > epochClock.currentEpoch()) {
            revert Error.WithrawalBeforeLockUpEnd();
        }

        // delete data before external call
        uint256 amount = uint256(stake.amount);
        _deleteStake(stakeId);

        // transfer pwn tokens to the staker
        pwnToken.transfer(staker, amount);

        // emit event
        emit StakeWithdrawn(stakeId, staker, amount);
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    /// @dev Store stake data, mint stPWN token and return new stake id
    function _createStake(address staker, uint16 initialEpoch, uint104 amount, uint8 remainingLockup)
        internal
        returns (uint256 newStakeId)
    {
        newStakeId = ++lastStakeId;
        Stake storage stake = stakes[newStakeId];
        stake.initialEpoch = initialEpoch;
        stake.amount = amount;
        stake.remainingLockup = remainingLockup;

        stakedPWN.mint(staker, newStakeId);
    }

    /// @dev Deletes a stake and burns stPWN token.
    function _deleteStake(uint256 stakeId) internal {
        delete stakes[stakeId];
        stakedPWN.burn(stakeId);
    }

    function _updateTotalPower(uint104 amount, uint16 initialEpoch, uint8 lockUpEpochs, bool addition) internal {
        int104 _amount = SafeCast.toInt104(int256(uint256(amount))) * (addition ? int104(1) : -1);
        uint8 remainingLockup = lockUpEpochs;
        // store initial power
        _totalPowerNamespace().updateEpochPower({
            epoch: initialEpoch,
            power: _power(_amount, remainingLockup)
        });
        // store gradual power decrease
        while (remainingLockup > 0) {
            remainingLockup -= _epochsToNextPowerChange(remainingLockup);
            _totalPowerNamespace().updateEpochPower({
                epoch: initialEpoch + lockUpEpochs - remainingLockup,
                power: _powerDecrease(_amount, remainingLockup)
            });
        }
    }

    function _epochsToNextPowerChange(uint8 remainingLockup) internal pure returns (uint8) {
        if (remainingLockup > 5 * EPOCHS_IN_YEAR) {
            return remainingLockup - (5 * EPOCHS_IN_YEAR);
        } else {
            uint8 nextPowerChangeEpochDelta = remainingLockup % EPOCHS_IN_YEAR;
            return nextPowerChangeEpochDelta == 0 ? EPOCHS_IN_YEAR : nextPowerChangeEpochDelta;
        }
    }

    function _powerDecrease(int104 amount, uint8 remainingLockup) internal pure returns (int104) {
        if (remainingLockup == 0) return -amount; // Final power loss
        else if (remainingLockup <= EPOCHS_IN_YEAR) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 2) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 3) return -amount * 20 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 4) return -amount * 25 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 5) return -amount * 175 / 100;
        else return 0;
    }

}
