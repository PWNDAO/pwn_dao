// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { EpochPowerLib } from "../../src/lib/EpochPowerLib.sol";
import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

// solhint-disable foundry-test-functions
contract VoteEscrowedPWNHarness is VoteEscrowedPWN {
    using EpochPowerLib for bytes32;

    // exposed

    function exposed_nextEpochAndRemainingLockup(
        int104 amount, uint16 epoch, uint8 remainingLockup
    ) external pure returns (int104, uint16, uint8) {
        return _nextEpochAndRemainingLockup(amount, epoch, remainingLockup);
    }

    function exposed_updateEpochPower(
        address staker, uint16 epoch, uint256 lowEpochIndex, int104 power
    ) external returns (uint256 epochIndex) {
        return _unsafe_updateEpochPower(staker, epoch, lowEpochIndex, power);
    }

    function exposed_initialPower(int104 amount, uint8 epochs) external pure returns (int104) {
        return _initialPower(amount, epochs);
    }

    function exposed_decreasePower(int104 amount, uint8 epoch) external pure returns (int104) {
        return _decreasePower(amount, epoch);
    }

    // workaround

    function workaround_getStakerEpochPower(address staker, uint256 epoch) external view returns (int104) {
        return _stakerPowerNamespace(staker).getEpochPower(epoch);
    }

    function workaround_storeStakerEpochPower(address staker, uint256 epoch, int104 power) external {
        _stakerPowerNamespace(staker).updateEpochPower(epoch, power);
    }

    function workaround_getTotalEpochPower(uint256 epoch) external view returns (int104) {
        return _totalPowerNamespace().getEpochPower(epoch);
    }

    function workaround_storeTotalEpochPower(uint256 epoch, int104 power) external {
        _totalPowerNamespace().updateEpochPower(epoch, power);
    }

    function workaround_stakerPowerChangeEpochsLength(address staker) external view returns (uint256) {
        return powerChangeEpochs[staker].length;
    }

    function workaround_pushDaoRevenuePortionCheckpoint(uint16 initialEpoch, uint16 portion) external {
        daoRevenuePortion.push(PortionCheckpoint(initialEpoch, portion));
    }

    function workaround_getDaoRevenuePortionCheckpointAt(
        uint256 index
    ) external view returns (PortionCheckpoint memory) {
        return daoRevenuePortion[index];
    }

    function workaround_clearDaoRevenuePortionCheckpoints() external {
        delete daoRevenuePortion;
    }

    function workaround_getDaoRevenuePortionCheckpointsLength() external view returns (uint256) {
        return daoRevenuePortion.length;
    }


    struct StakerPowerInput {
        address staker;
        uint256 epoch;
    }
    StakerPowerInput public expectedStakerPowerInput;
    uint256 public stakerPowerReturn;
    bool public mockStakerPower = true;
    function stakerPower(address staker, uint256 epoch) virtual public view override returns (uint256) {
        if (mockStakerPower) {
            require(expectedStakerPowerInput.staker == staker, "vePWNHarness:stakerPower:staker");
            require(expectedStakerPowerInput.epoch == epoch, "vePWNHarness:stakerPower:epoch");
            return stakerPowerReturn;
        } else {
            return super.stakerPower(staker, epoch);
        }
    }

    struct TotalPowerAtInput {
        uint256 epoch;
    }
    TotalPowerAtInput public expectedTotalPowerAtInput;
    uint256 public totalPowerAtReturn;
    bool public mockTotalPowerAt = true;
    function totalPowerAt(uint256 epoch) virtual public view override returns (uint256) {
        if (mockTotalPowerAt) {
            require(expectedTotalPowerAtInput.epoch == epoch, "vePWNHarness:totalPowerAt:epoch");
            return totalPowerAtReturn;
        } else {
            return super.totalPowerAt(epoch);
        }
    }


    // setters

    function workaround_setMockStakerPower(bool value) external {
        mockStakerPower = value;
    }

    function workaround_setStakerPowerInput(StakerPowerInput memory input) external {
        expectedStakerPowerInput = input;
    }

    function workaround_setStakerPowerReturn(uint256 value) external {
        stakerPowerReturn = value;
    }

    function workaround_setMockTotalPowerAt(bool value) external {
        mockTotalPowerAt = value;
    }

    function workaround_setTotalPowerAtInput(TotalPowerAtInput memory input) external {
        expectedTotalPowerAtInput = input;
    }

    function workaround_setTotalPowerAtReturn(uint256 value) external {
        totalPowerAtReturn = value;
    }

}
