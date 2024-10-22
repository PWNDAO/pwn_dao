// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { EpochPowerLib } from "src/lib/EpochPowerLib.sol";
import { Error } from "src/lib/Error.sol";
import { VoteEscrowedPWNBase, StakesInEpoch } from "./VoteEscrowedPWNBase.sol";

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
    /// @param beneficiary The beneficiary address.
    /// @param amount The amount of PWN tokens staked.
    /// @param lockUpEpochs The number of epochs the stake is locked up for.
    event StakeCreated(
        uint256 indexed stakeId,
        address indexed staker,
        address indexed beneficiary,
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

    /// @notice Emitted whenever stake power is transferred between beneficiaries.
    /// @dev When a stake is created, the `originalBeneficiary` is address(0).
    /// When a stake is deleted, the `newBeneficiary` is address(0).
    /// @param stakeId The id of the stake.
    /// @param originalBeneficiary The original stake power beneficiary.
    /// @param newBeneficiary The new stake power beneficiary.
    event StakePowerDelegated(
        uint256 indexed stakeId,
        address indexed originalBeneficiary,
        address indexed newBeneficiary
    );


    /*----------------------------------------------------------*|
    |*  # STAKE MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    /// @notice Creates a new stake for a caller.
    /// @param amount Amount of PWN tokens to stake. Needs to be divisible by 100.
    /// @param lockUpEpochs Number of epochs to lock up the stake for. Needs to be in <13;65> + {130} epochs.
    /// @return Id of the created stake.
    function createStake(uint256 amount, uint256 lockUpEpochs) external returns (uint256) {
        return createStakeOnBehalfOf(msg.sender, msg.sender, amount, lockUpEpochs);
    }

    /// @notice Creates a new stake on behalf of a staker.
    /// @param staker Address that will be the owner of the StakedPWN token.
    /// @param beneficiary Address that will be the beneficiary of the stake power.
    /// @param amount Amount of PWN tokens to stake. Needs to be divisible by 100.
    /// @param lockUpEpochs Number of epochs to lock up the stake for. Needs to be in <13;65> + {130} epochs.
    /// @return stakeId Id of the created stake.
    function createStakeOnBehalfOf(address staker, address beneficiary, uint256 amount, uint256 lockUpEpochs)
        public
        returns (uint256 stakeId)
    {
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

        uint16 initialEpoch = epochClock.currentEpoch() + 1;

        // store power changes
        _updateTotalPower(uint104(amount), initialEpoch, uint8(lockUpEpochs), true);

        // create new stake
        stakeId = _createStake({
            owner: staker,
            beneficiary: beneficiary,
            initialEpoch: initialEpoch,
            amount: uint104(amount),
            lockUpEpochs: uint8(lockUpEpochs)
        });

        // transfer pwn token
        pwnToken.transferFrom(msg.sender, address(this), amount);

        // emit event
        emit StakeCreated(stakeId, staker, beneficiary, amount, lockUpEpochs);
    }

    /// @notice Splits a stake for a caller.
    /// @dev Burns an original stPWN token and mints two new ones.
    /// The beneficiary of the new stake is the stake owner.
    /// @param stakeId Id of the stake to split.
    /// @param stakeBeneficiary Address that is the current beneficiary of the stake.
    /// @param splitAmount Amount of PWN tokens to split into a first new stake.
    /// @return newStakeId1 Id of the first new stake.
    /// @return newStakeId2 Id of the second new stake.
    function splitStake(uint256 stakeId, address stakeBeneficiary, uint256 splitAmount)
        external
        returns (uint256 newStakeId1, uint256 newStakeId2)
    {
        address staker = msg.sender;
        Stake storage originalStake = _stakes[stakeId];
        uint16 originalInitialEpoch = originalStake.initialEpoch;
        uint104 originalAmount = originalStake.amount;
        uint8 originalLockUpEpochs = originalStake.lockUpEpochs;

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
        _deleteStake({ owner: staker, beneficiary: stakeBeneficiary, stakeId: stakeId });

        // create new stakes
        newStakeId1 = _createStake({
            owner: staker,
            beneficiary: staker,
            initialEpoch: originalInitialEpoch,
            amount: originalAmount - uint104(splitAmount),
            lockUpEpochs: originalLockUpEpochs
        });
        newStakeId2 = _createStake({
            owner: staker,
            beneficiary: staker,
            initialEpoch: originalInitialEpoch,
            amount: uint104(splitAmount),
            lockUpEpochs: originalLockUpEpochs
        });

        // emit event
        emit StakeSplit(stakeId, staker, originalAmount - uint104(splitAmount), splitAmount, newStakeId1, newStakeId2);
    }

    /// @notice Merges two stakes for a caller.
    /// @dev Burns both stPWN tokens and mints a new one.
    /// Aligns stakes lockups. First stake lockup must be longer than or equal to the second one.
    /// The beneficiary of the new stake is the stake owner.
    /// @param stakeId1 Id of the first stake to merge.
    /// @param stakeBeneficiary1 Address that is the current beneficiary of the first stake.
    /// @param stakeId2 Id of the second stake to merge.
    /// @param stakeBeneficiary2 Address that is the current beneficiary of the second stake.
    /// @return newStakeId Id of the new merged stake.
    function mergeStakes(uint256 stakeId1, address stakeBeneficiary1, uint256 stakeId2, address stakeBeneficiary2)
        external
        returns (uint256 newStakeId)
    {
        address staker = msg.sender;
        Stake storage stake1 = _stakes[stakeId1];
        Stake storage stake2 = _stakes[stakeId2];
        uint16 finalEpoch1 = stake1.initialEpoch + stake1.lockUpEpochs;
        uint16 finalEpoch2 = stake2.initialEpoch + stake2.lockUpEpochs;
        uint16 newInitialEpoch = epochClock.currentEpoch() + 1;

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
        _deleteStake({ owner: staker, beneficiary: stakeBeneficiary1, stakeId: stakeId1 });
        _deleteStake({ owner: staker, beneficiary: stakeBeneficiary2, stakeId: stakeId2 });

        // create new stake
        uint104 newAmount = stake1.amount + stake2.amount;
        newStakeId = _createStake({
            owner: staker,
            beneficiary: staker,
            initialEpoch: newInitialEpoch,
            amount: newAmount,
            lockUpEpochs: newLockUpEpochs
        });

        // emit event
        emit StakeMerged(stakeId1, stakeId2, staker, newAmount, newLockUpEpochs, newStakeId);
    }

    /// @notice Increases a stake for a caller.
    /// @dev Creates new stake and burns old stPWN token.
    /// If the stakes lockup ended, `additionalEpochs` will be added from the next epoch.
    /// The sum of `lockUpEpochs` and `additionalEpochs` must be in <13;65> + {130}.
    /// Expecting PWN token approval for the contract if `additionalAmount` > 0.
    /// The beneficiary of the new stake is the stake owner.
    /// @param stakeId Id of the stake to increase.
    /// @param stakeBeneficiary Address that is the current beneficiary of the stake.
    /// @param additionalAmount Amount of PWN tokens to increase the stake by.
    /// @param additionalEpochs Number of epochs to add to exisitng stake lockup.
    /// @return newStakeId Id of the new stake.
    function increaseStake(uint256 stakeId, address stakeBeneficiary, uint256 additionalAmount, uint256 additionalEpochs)
        external
        returns (uint256 newStakeId)
    {
        address staker = msg.sender;
        Stake storage stake = _stakes[stakeId];

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
        _deleteStake({ owner: staker, beneficiary: stakeBeneficiary, stakeId: stakeId });

        // create new stake
        newStakeId = _createStake({
            owner: staker,
            beneficiary: staker,
            initialEpoch: newInitialEpoch,
            amount: newAmount,
            lockUpEpochs: newLockUpEpochs
        });

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
    /// @param stakeBeneficiary Address that is the current beneficiary of the stake.
    function withdrawStake(uint256 stakeId, address stakeBeneficiary) external {
        address staker = msg.sender;
        Stake storage stake = _stakes[stakeId];

        // stake must be unlocked
        if (stake.initialEpoch + stake.lockUpEpochs > epochClock.currentEpoch()) {
            revert Error.WithrawalBeforeLockUpEnd();
        }

        // delete stake
        _deleteStake({ owner: staker, beneficiary: stakeBeneficiary, stakeId: stakeId });

        // transfer pwn tokens to the staker
        pwnToken.transfer(staker, stake.amount);

        // emit event
        emit StakeWithdrawn(stakeId, staker, stake.amount);
    }

    /// @notice Delegate a stake power to another address.
    /// @dev Caller must be the stake owner.
    /// @param stakeId Id of the stake to claim power for.
    /// @param currentBeneficiary The address which is the current stake power beneficiary.
    /// @param newBeneficiary The address which will be the new stake power beneficiary.
    function delegateStakePower(uint256 stakeId, address currentBeneficiary, address newBeneficiary) external {
        address staker = msg.sender;

        // power already delegated to the new beneficiary
        if (currentBeneficiary == newBeneficiary) {
            revert Error.SameBeneficiary();
        }

        // staker must be stake owner
        _checkIsStakeOwner(staker, stakeId);

        // remove token from current beneficiary first to avoid duplicates
        _removeStakeFromBeneficiary(stakeId, currentBeneficiary);
        _addStakeToBeneficiary(stakeId, newBeneficiary);

        // emit event
        emit StakePowerDelegated(stakeId, currentBeneficiary, newBeneficiary);
    }


    /*----------------------------------------------------------*|
    |*  # GETTERS                                               *|
    |*----------------------------------------------------------*/

    /// @notice Stake data structure.
    /// @param stakeId The id of the stake.
    /// @param owner The address of the stake owner. It is also the owner of the stPWN token.
    /// @param initialEpoch The epoch from which the stake starts.
    /// @param lockUpEpochs The number of epochs the stake is locked up for.
    /// @param remainingEpochs The number of epochs remaining until the stake is unlocked.
    /// @param currentMultiplier The current power multiplier for the stake.
    /// @param amount The amount of PWN tokens staked.
    struct StakeData {
        uint256 stakeId;
        address owner;
        uint16 initialEpoch;
        uint8 lockUpEpochs;
        uint8 remainingEpochs;
        uint8 currentMultiplier;
        uint104 amount;
    }

    /// @notice Returns the stake data for a given stake id.
    /// @param stakeId Id of the stake.
    /// @return stakeData The stake data.
    function getStake(uint256 stakeId) public view returns (StakeData memory stakeData) {
        Stake storage stake = _stakes[stakeId];
        uint16 currentEpoch = epochClock.currentEpoch();

        stakeData.stakeId = stakeId;
        stakeData.owner = stakedPWN.ownerOf(stakeId);
        stakeData.initialEpoch = stake.initialEpoch;
        stakeData.lockUpEpochs = stake.lockUpEpochs;
        stakeData.remainingEpochs = (stakeData.initialEpoch + stakeData.lockUpEpochs >= currentEpoch)
            ? uint8(stakeData.initialEpoch + stakeData.lockUpEpochs - currentEpoch) : 0;
        stakeData.currentMultiplier = (stakeData.initialEpoch <= currentEpoch && stakeData.remainingEpochs > 0)
            ? uint8(uint104(_power(100, stakeData.remainingEpochs))) : 0;
        stakeData.amount = stake.amount;
    }

    /// @notice Returns the stake data for a given list of stake ids.
    /// @param stakeIds List of stake ids.
    /// @return stakeData Array of stake data.
    function getStakes(uint256[] calldata stakeIds) external view returns (StakeData[] memory stakeData) {
        stakeData = new StakeData[](stakeIds.length);
        for (uint256 i; i < stakeIds.length; ++i) {
            stakeData[i] = getStake(stakeIds[i]);
        }
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    /// @dev Store stake data, mint stPWN token and return new stake id
    function _createStake(address owner, address beneficiary, uint16 initialEpoch, uint104 amount, uint8 lockUpEpochs)
        internal
        returns (uint256 newStakeId)
    {
        newStakeId = ++lastStakeId;
        Stake storage stake = _stakes[newStakeId];
        stake.initialEpoch = initialEpoch;
        stake.amount = amount;
        stake.lockUpEpochs = lockUpEpochs;

        stakedPWN.mint(owner, newStakeId);
        _addStakeToBeneficiary(newStakeId, beneficiary);
        emit StakePowerDelegated(newStakeId, address(0), beneficiary);
    }

    /// @dev Burn stPWN token, but keepts the stake data for historical power calculations.
    ///      Staker must be the stake owner and beneficiary.
    function _deleteStake(address owner, address beneficiary, uint256 stakeId) internal {
        _checkIsStakeOwner(owner, stakeId);
        _removeStakeFromBeneficiary(stakeId, beneficiary);
        stakedPWN.burn(stakeId);
        emit StakePowerDelegated(stakeId, beneficiary, address(0));
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

    function _checkIsStakeOwner(address staker, uint256 stakeId) internal view {
        if (stakedPWN.ownerOf(stakeId) != staker) {
            revert Error.NotStakeOwner();
        }
    }

    function _checkIsStakeBeneficiary(address staker, uint256 stakeId) internal view {
        StakesInEpoch[] storage stakesInEpochs = beneficiaryOfStakes[staker];
        if (stakesInEpochs.length == 0) {
            revert Error.NotStakeBeneficiary();
        }

        StakesInEpoch storage currentStakes = stakesInEpochs[stakesInEpochs.length - 1];
        uint256 index = _findIdInList(currentStakes.ids, stakeId);
        if (index == currentStakes.ids.length) {
            revert Error.NotStakeBeneficiary();
        }
    }

    function _addStakeToBeneficiary(uint256 stakeId, address beneficiary) internal {
        uint16 epoch = epochClock.currentEpoch() + 1;
        StakesInEpoch[] storage stakesInEpochs = beneficiaryOfStakes[beneficiary];
        StakesInEpoch storage stakesInNextEpoch;

        if (stakesInEpochs.length == 0) {
            stakesInNextEpoch = stakesInEpochs.push();
            stakesInNextEpoch.epoch = epoch;
        } else {
            StakesInEpoch storage stakesInLatestEpoch = stakesInEpochs[stakesInEpochs.length - 1];
            if (stakesInLatestEpoch.epoch == epoch) {
                stakesInNextEpoch = stakesInLatestEpoch;
            } else {
                stakesInNextEpoch = stakesInEpochs.push();
                stakesInNextEpoch.epoch = epoch;
                stakesInNextEpoch.ids = stakesInLatestEpoch.ids;
            }
        }
        stakesInNextEpoch.ids.push(SafeCast.toUint48(stakeId));
    }

    /// @dev Would revert if the stake is not found.
    function _removeStakeFromBeneficiary(uint256 stakeId, address beneficiary) internal {
        uint16 epoch = epochClock.currentEpoch() + 1;
        StakesInEpoch[] storage stakesInEpochs = beneficiaryOfStakes[beneficiary];

        if (stakesInEpochs.length == 0) {
            revert Error.StakeNotFound(stakeId);
        }

        StakesInEpoch storage stakesInLatestEpoch = stakesInEpochs[stakesInEpochs.length - 1];

        if (stakesInLatestEpoch.epoch == epoch) {
            _removeIdFromList(stakesInLatestEpoch.ids, stakeId);
        } else {
            StakesInEpoch storage stakesInNextEpoch = stakesInEpochs.push();
            stakesInNextEpoch.epoch = epoch;
            stakesInNextEpoch.ids = stakesInLatestEpoch.ids;
            _removeIdFromList(stakesInNextEpoch.ids, stakeId);
        }
    }

    function _removeIdFromList(uint48[] storage ids, uint256 tokenId) private {
        uint256 length = ids.length;
        uint256 index = _findIdInList(ids, tokenId);

        if (index == length) {
            revert Error.StakeNotFound(tokenId);
        }

        ids[index] = ids[length - 1];
        ids.pop();
    }

    function _findIdInList(uint48[] storage ids, uint256 id) private view returns (uint256) {
        uint256 length = ids.length;
        for (uint256 i; i < length;) {
            if (ids[i] == id) {
                return i;
            }
            unchecked { ++i; }
        }
        return length;
    }

}
