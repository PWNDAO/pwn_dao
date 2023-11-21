// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";
import { EpochPowerLib } from "../lib/EpochPowerLib.sol";
import { PowerChangeEpochsLib } from "../lib/PowerChangeEpochsLib.sol";

abstract contract VoteEscrowedPWNStake is VoteEscrowedPWNBase {
    using EpochPowerLib for bytes32;
    using PowerChangeEpochsLib for uint16[];

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event StakeCreated(uint256 indexed stakeId, address indexed staker, uint256 amount, uint256 lockUpEpochs);
    event StakeSplit(
        uint256 indexed stakeId, address indexed staker, uint256 splitAmount, uint256 newStakeId1, uint256 newStakeId2
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
        uint256 additionalEpochs,
        uint256 newStakeId
    );
    event StakeWithdrawn(address indexed staker, uint256 amount);
    event StakeTransferred(
        uint256 indexed stakeId, address indexed fromStaker, address indexed toStaker, uint256 amount
    );


    /*----------------------------------------------------------*|
    |*  # STAKE MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /// @notice Creates a new stake for a caller.
    /// @dev Creates new power changes or update existing ones if overlapping.
    /// @param amount Amount of PWN tokens to stake.
    /// @param lockUpEpochs Number of epochs to lock up the stake for.
    /// @return stakeId Id of the created stake.
    function createStake(uint256 amount, uint256 lockUpEpochs) external returns (uint256 stakeId) {
        require(amount >= 100 && amount <= type(uint88).max, "vePWN: staked amount out of bounds");
        // to prevent rounding errors when computing power
        require(amount % 100 == 0, "vePWN: staked amount must be a multiple of 100");

        // lock up for <1; 5> + {10} years
        require(lockUpEpochs >= EPOCHS_IN_PERIOD, "vePWN: invalid lock up period range");
        require(
            lockUpEpochs <= 5 * EPOCHS_IN_PERIOD || lockUpEpochs == 10 * EPOCHS_IN_PERIOD,
            "vePWN: invalid lock up period range"
        );

        address staker = msg.sender;
        uint16 initialEpoch = _currentEpoch() + 1;
        uint8 remainingLockup = uint8(lockUpEpochs); // safe cast
        int104 int104amount = SafeCast.toInt104(int256(uint256(amount)));

        // store power changes
        _updatePowerChanges({
            staker: staker,
            amount: int104amount,
            powerChangeEpoch: initialEpoch,
            remainingLockup: remainingLockup,
            addition: true
        });

        // create new stake
        stakeId = _createStake(staker, initialEpoch, uint104(amount), remainingLockup);

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
    function splitStake(uint256 stakeId, uint256 splitAmount) external returns (uint256 newStakeId1, uint256 newStakeId2) {
        Stake storage originalStake = stakes[stakeId];
        address staker = msg.sender;
        uint16 originalInitialEpoch = originalStake.initialEpoch;
        uint104 originalAmount = originalStake.amount;
        uint8 originalRemainingLockup = originalStake.remainingLockup;

        require(stakedPWN.ownerOf(stakeId) == staker, "vePWN: caller is not the stake owner");
        require(splitAmount < originalAmount, "vePWN: split amount must be less than stake amount");
        require(splitAmount % 100 == 0, "vePWN: split amount must be a multiple of 100");

        // delete original stake
        _deleteStake(stakeId);

        // create new stakes
        newStakeId1 = _createStake(
            staker, originalInitialEpoch, originalAmount - uint104(splitAmount), originalRemainingLockup
        );
        newStakeId2 = _createStake(staker, originalInitialEpoch, uint104(splitAmount), originalRemainingLockup);

        // emit event
        emit StakeSplit(stakeId, staker, splitAmount, newStakeId1, newStakeId2);
    }

    /// @notice Merges two stakes for a caller.
    /// @dev Burns both stPWN tokens and mints a new one.
    /// @dev Aligns stakes lockups. First stake lockup must be longer than or equal to the second one.
    /// @param stakeId1 Id of the first stake to merge.
    /// @param stakeId2 Id of the second stake to merge.
    /// @return newStakeId Id of the new merged stake.
    function mergeStakes(uint256 stakeId1, uint256 stakeId2) external returns (uint256 newStakeId) {
        Stake storage stake1 = stakes[stakeId1];
        Stake storage stake2 = stakes[stakeId2];
        address staker = msg.sender;
        uint16 finalEpoch1 = stake1.initialEpoch + stake1.remainingLockup;
        uint16 finalEpoch2 = stake2.initialEpoch + stake2.remainingLockup;
        uint16 newInitialEpoch = _currentEpoch() + 1;

        require(stakedPWN.ownerOf(stakeId1) == staker, "vePWN: caller is not the first stake owner");
        require(stakedPWN.ownerOf(stakeId2) == staker, "vePWN: caller is not the second stake owner");
        require(finalEpoch1 >= finalEpoch2, "vePWN: the second stakes lockup is longer than the fist stakes lockup");
        require(finalEpoch1 > newInitialEpoch, "vePWN: both stakes lockups ended");

        // only need to update second stake power changes
        uint8 newRemainingLockup = uint8(finalEpoch1 - newInitialEpoch); // safe cast
        if (finalEpoch1 != finalEpoch2) {
            int104 amount2 = SafeCast.toInt104(int256(uint256(stake2.amount)));
            // clear second stake power changes if necessary
            if (finalEpoch2 > newInitialEpoch) {
                _updatePowerChanges(staker, amount2, newInitialEpoch, uint8(finalEpoch2 - newInitialEpoch), false);
            }
            // store new update power changes
            _updatePowerChanges(staker, amount2, newInitialEpoch, newRemainingLockup, true);
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
    function increaseStake(
        uint256 stakeId, uint256 additionalAmount, uint256 additionalEpochs
    ) external returns (uint256 newStakeId) {
        Stake storage stake = stakes[stakeId];
        address staker = msg.sender;

        require(stakedPWN.ownerOf(stakeId) == staker, "vePWN: caller is not the stake owner");
        require(additionalAmount > 0 || additionalEpochs > 0, "vePWN: nothing to increase");
        require(additionalAmount <= type(uint88).max, "vePWN: staked amount out of bounds");
        // to prevent rounding errors when computing power
        require(additionalAmount % 100 == 0, "vePWN: staked amount must be a multiple of 100");
        require(additionalEpochs <= 10 * EPOCHS_IN_PERIOD, "vePWN: additional epochs out of bounds");

        uint16 newInitialEpoch = _currentEpoch() + 1;
        uint16 oldFinalEpoch = stake.initialEpoch + stake.remainingLockup;
        uint8 newRemainingLockup = SafeCast.toUint8(
            oldFinalEpoch <= newInitialEpoch ? additionalEpochs : oldFinalEpoch + additionalEpochs - newInitialEpoch
        );
        // extended lockup must be in <1; 5> + {10} years
        require(newRemainingLockup >= EPOCHS_IN_PERIOD, "vePWN: invalid lock up period range");
        require(
            newRemainingLockup <= 5 * EPOCHS_IN_PERIOD || newRemainingLockup == 10 * EPOCHS_IN_PERIOD,
            "vePWN: invalid lock up period range"
        );

        uint104 oldAmount = stake.amount;
        uint104 newAmount = oldAmount + uint104(additionalAmount); // safe cast

        // clear old power changes
        if (additionalEpochs > 0 && newRemainingLockup > additionalEpochs) {
            _updatePowerChanges({
                staker: staker,
                amount: SafeCast.toInt104(int256(uint256(oldAmount))),
                powerChangeEpoch: newInitialEpoch,
                remainingLockup: newRemainingLockup - SafeCast.toUint8(additionalEpochs),
                addition: false
            });
        }

        // store new power changes
        _updatePowerChanges({
            staker: staker,
            amount: SafeCast.toInt104(int256(uint256(additionalEpochs > 0 ? newAmount : additionalAmount))),
            powerChangeEpoch: newInitialEpoch,
            remainingLockup: newRemainingLockup,
            addition: true
        });

        // delete original stake
        _deleteStake(stakeId);

        // create new stake
        newStakeId = _createStake(staker, newInitialEpoch, newAmount, newRemainingLockup);

        // transfer additional PWN tokens
        if (additionalAmount > 0)
            pwnToken.transferFrom(staker, address(this), additionalAmount);

        // emit event
        emit StakeIncreased(stakeId, staker, additionalAmount, additionalEpochs, newStakeId);
    }

    /// @notice Withdraws a stake for a caller.
    /// @dev Burns stPWN token and transfers PWN tokens to the caller.
    /// @param stakeId Id of the stake to withdraw.
    function withdrawStake(uint256 stakeId) external {
        Stake storage stake = stakes[stakeId];
        address staker = msg.sender;

        require(stakedPWN.ownerOf(stakeId) == staker, "vePWN: caller is not the stake owner");
        require(
            stake.initialEpoch + stake.remainingLockup <= _currentEpoch(),
            "vePWN: staker cannot withdraw before lockup period"
        );

        // delete data before external call
        uint256 amount = uint256(stake.amount);
        _deleteStake(stakeId);

        // transfer pwn tokens to the staker
        pwnToken.transfer(staker, amount);

        // emit event
        emit StakeWithdrawn(staker, amount);
    }

    /// @notice Transfers a stake for a caller.
    /// @dev Callable only by the `stakedPWN` contract.
    /// @param from Address to transfer the stake from.
    /// @param to Address to transfer the stake to.
    /// @param stakeId Id of the stake to transfer.
    function transferStake(address from, address to, uint256 stakeId) external {
        require(msg.sender == address(stakedPWN), "vePWN: caller is not stakedPWN");

        if (from == address(0) || to == address(0))
            return; // mint or burn, no update needed

        Stake storage stake = stakes[stakeId];
        uint16 newInitialEpoch = _currentEpoch() + 1;

        require(stakedPWN.ownerOf(stakeId) == from, "vePWN: sender is not the stake owner");

        if (newInitialEpoch - stake.initialEpoch >= stake.remainingLockup) {
            emit StakeTransferred(stakeId, from, to, stake.amount);
            return; // lockup period ended, just emit event and return
        }

        uint8 newRemainingLockup = stake.remainingLockup - SafeCast.toUint8(newInitialEpoch - stake.initialEpoch);
        int104 int104amount = SafeCast.toInt104(int256(uint256(stake.amount)));

        // update stake data
        stake.initialEpoch = newInitialEpoch;
        stake.remainingLockup = newRemainingLockup;

        // clear power changes for `from`
        _updatePowerChanges({
            staker: from,
            amount: int104amount,
            powerChangeEpoch: newInitialEpoch,
            remainingLockup: newRemainingLockup,
            addition: false
        });

        // store new power changes for `to`
        _updatePowerChanges({
            staker: to,
            amount: int104amount,
            powerChangeEpoch: newInitialEpoch,
            remainingLockup: newRemainingLockup,
            addition: true
        });

        // emit event
        emit StakeTransferred(stakeId, from, to, stake.amount);
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    /// @dev Store stake data, mint stPWN token and return new stake id
    function _createStake(
        address staker, uint16 initialEpoch, uint104 amount, uint8 remainingLockup
    ) internal returns (uint256 newStakeId) {
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

    function _updatePowerChanges(
        address staker, int104 amount, uint16 powerChangeEpoch, uint8 remainingLockup, bool addition
    ) internal {
        int104 sign = addition ? int104(1) : -1;
        int104 powerChange = _initialPower(amount, remainingLockup);
        uint256 epochIndex = _unsafe_updateEpochPower(staker, powerChangeEpoch, 0, powerChange * sign);
        do {
            (powerChange, powerChangeEpoch, remainingLockup) =
                _nextEpochAndRemainingLockup(amount, powerChangeEpoch, remainingLockup);
            epochIndex = _unsafe_updateEpochPower(staker, powerChangeEpoch, epochIndex, powerChange * sign);
        } while (remainingLockup > 0);
    }


    /// @dev Updates power change for a staker at an epoch and add/remove epoch from `powerChangeEpochs`.
    /// WARNING: `powerChangeEpochs` should be sorted in ascending order without duplicates,
    /// but `lowEpochIndex` can force to insert epoch at a wrong index.
    /// Use `lowEpochIndex` only if you are sure that the epoch cannot be found before the index.
    // solhint-disable-next-line func-name-mixedcase
    function _unsafe_updateEpochPower(
        address staker, uint16 epoch, uint256 lowEpochIndex, int104 power
    ) internal returns (uint256 epochIndex) {
        // update total epoch power
        _totalPowerNamespace().updateEpochPower(epoch, power);

        // update staker epoch power
        bytes32 stakerNamespace = _stakerPowerNamespace(staker);
        stakerNamespace.updateEpochPower(epoch, power);

        uint16[] storage stakersPowerChangeEpochs = powerChangeEpochs[staker];
        // update stakers power changes epochs
        bool epochWithPowerChange = stakerNamespace.getEpochPower(epoch) != 0;
        epochIndex = stakersPowerChangeEpochs.findIndex(epoch, lowEpochIndex);
        bool indexFound = epochIndex < stakersPowerChangeEpochs.length && stakersPowerChangeEpochs[epochIndex] == epoch;

        if (epochWithPowerChange && !indexFound)
            stakersPowerChangeEpochs.insertEpoch(epoch, epochIndex);
        else if (!epochWithPowerChange && indexFound)
            stakersPowerChangeEpochs.removeEpoch(epochIndex);
    }

    /// @dev `remainingLockup` must be > 0
    function _nextEpochAndRemainingLockup(
        int104 amount, uint16 epoch, uint8 remainingLockup
    ) internal pure returns (int104, uint16, uint8) {
        uint8 nextPowerChangeEpochDelta;
        if (remainingLockup > 5 * EPOCHS_IN_PERIOD) {
            nextPowerChangeEpochDelta = remainingLockup - (5 * EPOCHS_IN_PERIOD);
        } else {
            nextPowerChangeEpochDelta = remainingLockup % EPOCHS_IN_PERIOD;
            nextPowerChangeEpochDelta = nextPowerChangeEpochDelta == 0 ? EPOCHS_IN_PERIOD : nextPowerChangeEpochDelta;
        }

        return (
            _decreasePower(amount, remainingLockup - nextPowerChangeEpochDelta),
            epoch + nextPowerChangeEpochDelta,
            remainingLockup - nextPowerChangeEpochDelta
        );
    }

    function _initialPower(int104 amount, uint8 remainingLockup) internal pure returns (int104) {
        if (remainingLockup <= EPOCHS_IN_PERIOD) return amount;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 2) return amount * 115 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 3) return amount * 130 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 4) return amount * 150 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 5) return amount * 175 / 100;
        else return amount * 350 / 100;
    }

    function _decreasePower(int104 amount, uint8 remainingLockup) internal pure returns (int104) {
        if (remainingLockup == 0) return -amount; // Final power loss
        else if (remainingLockup <= EPOCHS_IN_PERIOD) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 2) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 3) return -amount * 20 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 4) return -amount * 25 / 100;
        else if (remainingLockup <= EPOCHS_IN_PERIOD * 5) return -amount * 175 / 100;
        else return 0;
    }

}
