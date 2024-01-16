// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { Error } from "../lib/Error.sol";
import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";
import { EpochPowerLib } from "../lib/EpochPowerLib.sol";

/// @title VoteEscrowedPWNStake
/// @notice Contract for the vote-escrowed PWN token implementing stake functions.
abstract contract VoteEscrowedPWNStake is VoteEscrowedPWNBase {
    using EpochPowerLib for bytes32;

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when a stake is created.
    /// @param stakeId The id of the created stake.
    /// @param staker The staker address.
    /// @param amount The amount of PWN tokens staked.
    /// @param lockUpEpochs The number of epochs the stake is locked up for.
    event StakeCreated(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 amount,
        uint256 lockUpEpochs
    );

    /// @notice Emitted when a stake is split.
    /// @param stakeId The id of the original stake.
    /// @param staker The staker address.
    /// @param amount1 The amount of PWN tokens in the first new stake.
    /// @param amount2 The amount of PWN tokens in the second new stake.
    /// @param newStakeId1 The id of the first new stake.
    /// @param newStakeId2 The id of the second new stake.
    event StakeSplit(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 amount1,
        uint256 amount2,
        uint256 newStakeId1,
        uint256 newStakeId2
    );

    /// @notice Emitted when two stakes are merged.
    /// @param stakeId1 The id of the first stake to merge.
    /// @param stakeId2 The id of the second stake to merge.
    /// @param staker The staker address.
    /// @param amount The amount of PWN tokens in the new stake.
    /// @param lockUpEpochs The number of epochs the stake is locked up for.
    /// @param newStakeId The id of the new stake.
    event StakeMerged(
        uint256 indexed stakeId1,
        uint256 indexed stakeId2,
        address indexed staker,
        uint256 amount,
        uint256 lockUpEpochs,
        uint256 newStakeId
    );

    /// @notice Emitted when a stake is increased.
    /// @param stakeId The id of the original stake.
    /// @param staker The staker address.
    /// @param additionalAmount The amount of PWN tokens added to the stake.
    /// @param newAmount The amount of PWN tokens in the new stake.
    /// @param additionalEpochs The number of epochs added to the stake lockup.
    /// @param newEpochs The number of epochs the stake is locked up for.
    /// @param newStakeId The id of the new stake.
    event StakeIncreased(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 additionalAmount,
        uint256 newAmount,
        uint256 additionalEpochs,
        uint256 newEpochs,
        uint256 newStakeId
    );

    /// @notice Emitted when a stake is withdrawn.
    /// @param stakeId The id of the stake.
    /// @param staker The staker address.
    /// @param amount The amount of PWN tokens withdrawn.
    event StakeWithdrawn(
        uint256 indexed stakeId,
        address indexed staker,
        uint256 amount
    );


    /*----------------------------------------------------------*|
    |*  # STAKE MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /// @notice Creates a new stake for a caller.
    /// @dev Mints stPWN token and transfers PWN tokens to the contract.
    /// @param amount Amount of PWN tokens to stake. Needs to be divisible by 100.
    /// @param lockUpEpochs Number of epochs to lock up the stake for. Needs to be in <13;65> + {130} epochs.
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
    /// @dev Burns an original stPWN token and mints two new ones.
    /// @param stakeId Id of the stake to split.
    /// @param splitAmount Amount of PWN tokens to split into a first new stake.
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
        uint8 originalLockUpEpochs = originalStake.lockUpEpochs;

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
            staker, originalInitialEpoch, originalAmount - uint104(splitAmount), originalLockUpEpochs
        );
        newStakeId2 = _createStake(staker, originalInitialEpoch, uint104(splitAmount), originalLockUpEpochs);

        // emit event
        emit StakeSplit(stakeId, staker, originalAmount - uint104(splitAmount), splitAmount, newStakeId1, newStakeId2);
    }

    /// @notice Merges two stakes for a caller.
    /// @dev Burns both stPWN tokens and mints a new one.
    /// Aligns stakes lockups. First stake lockup must be longer than or equal to the second one.
    /// @param stakeId1 Id of the first stake to merge.
    /// @param stakeId2 Id of the second stake to merge.
    /// @return newStakeId Id of the new merged stake.
    function mergeStakes(uint256 stakeId1, uint256 stakeId2) external returns (uint256 newStakeId) {
        address staker = msg.sender;
        Stake storage stake1 = stakes[stakeId1];
        Stake storage stake2 = stakes[stakeId2];
        uint16 finalEpoch1 = stake1.initialEpoch + stake1.lockUpEpochs;
        uint16 finalEpoch2 = stake2.initialEpoch + stake2.lockUpEpochs;
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

        uint8 newLockUpEpochs = uint8(finalEpoch1 - newInitialEpoch); // safe cast
        // only need to update second stake power changes if has different final epoch
        if (finalEpoch1 != finalEpoch2) {
            uint104 amount2 = stake2.amount;
            // clear second stake power changes if necessary
            if (finalEpoch2 > newInitialEpoch) {
                _updateTotalPower(amount2, newInitialEpoch, uint8(finalEpoch2 - newInitialEpoch), false);
            }
            // store new update power changes
            _updateTotalPower(amount2, newInitialEpoch, newLockUpEpochs, true);
        }

        // delete old stakes
        _deleteStake(stakeId1);
        _deleteStake(stakeId2);

        // create new stake
        uint104 newAmount = stake1.amount + stake2.amount;
        newStakeId = _createStake(staker, newInitialEpoch, newAmount, newLockUpEpochs);

        // emit event
        emit StakeMerged(stakeId1, stakeId2, staker, newAmount, newLockUpEpochs, newStakeId);
    }

    /// @notice Increases a stake for a caller.
    /// @dev Creates new stake and burns old stPWN token.
    /// If the stakes lockup ended, `additionalEpochs` will be added from the next epoch.
    /// The sum of `lockUpEpochs` and `additionalEpochs` must be in <13;65> + {130}.
    /// Expecting PWN token approval for the contract if `additionalAmount` > 0.
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
        uint16 oldFinalEpoch = stake.initialEpoch + stake.lockUpEpochs;
        uint8 newLockUpEpochs = SafeCast.toUint8(
            oldFinalEpoch <= newInitialEpoch ? additionalEpochs : oldFinalEpoch + additionalEpochs - newInitialEpoch
        );
        // extended lockup must be in <1; 5> + {10} years
        if (newLockUpEpochs < EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }
        if (newLockUpEpochs > 5 * EPOCHS_IN_YEAR && newLockUpEpochs != 10 * EPOCHS_IN_YEAR) {
            revert Error.InvalidLockUpPeriod();
        }

        uint104 oldAmount = stake.amount;
        uint104 newAmount = oldAmount + uint104(additionalAmount); // safe cast

        { // avoid stack too deep
            bool amountAdditionOnly = additionalEpochs == 0;

            // clear old power changes if adding epochs
            if (!amountAdditionOnly && newLockUpEpochs > additionalEpochs) {
                _updateTotalPower(oldAmount, newInitialEpoch, newLockUpEpochs - uint8(additionalEpochs), false);
            }

            // store new power changes
            uint104 amount = amountAdditionOnly ? uint104(additionalAmount) : newAmount;
            _updateTotalPower(amount, newInitialEpoch, newLockUpEpochs, true);
        }

        // delete original stake
        _deleteStake(stakeId);

        // create new stake
        newStakeId = _createStake(staker, newInitialEpoch, newAmount, newLockUpEpochs);

        // transfer additional PWN tokens
        if (additionalAmount > 0) {
            pwnToken.transferFrom(staker, address(this), additionalAmount);
        }

        // emit event
        emit StakeIncreased(
            stakeId, staker, additionalAmount, newAmount, additionalEpochs, newLockUpEpochs, newStakeId
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
        if (stake.initialEpoch + stake.lockUpEpochs > epochClock.currentEpoch()) {
            revert Error.WithrawalBeforeLockUpEnd();
        }

        // delete stake
        _deleteStake(stakeId);

        // transfer pwn tokens to the staker
        pwnToken.transfer(staker, stake.amount);

        // emit event
        emit StakeWithdrawn(stakeId, staker, stake.amount);
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    /// @dev Store stake data, mint stPWN token and return new stake id
    function _createStake(address staker, uint16 initialEpoch, uint104 amount, uint8 lockUpEpochs)
        internal
        returns (uint256 newStakeId)
    {
        newStakeId = ++lastStakeId;
        Stake storage stake = stakes[newStakeId];
        stake.initialEpoch = initialEpoch;
        stake.amount = amount;
        stake.lockUpEpochs = lockUpEpochs;

        stakedPWN.mint(staker, newStakeId);
    }

    /// @dev Burn stPWN token, but keepts the stake data for historical power calculations
    function _deleteStake(uint256 stakeId) internal {
        stakedPWN.burn(stakeId);
    }

    /// @dev Update total power changes for a given amount and lockup
    function _updateTotalPower(uint104 amount, uint16 initialEpoch, uint8 lockUpEpochs, bool addition) internal {
        int104 _amount = SafeCast.toInt104(int256(uint256(amount))) * (addition ? int104(1) : -1);
        uint8 remainingLockup = lockUpEpochs;
        // store initial power
        TOTAL_POWER_NAMESPACE.updateEpochPower({
            epoch: initialEpoch,
            power: _power(_amount, remainingLockup)
        });
        // store gradual power decrease
        while (remainingLockup > 0) {
            remainingLockup -= _epochsToNextPowerChange(remainingLockup);
            TOTAL_POWER_NAMESPACE.updateEpochPower({
                epoch: initialEpoch + lockUpEpochs - remainingLockup,
                power: _powerDecrease(_amount, remainingLockup)
            });
        }
    }

}
