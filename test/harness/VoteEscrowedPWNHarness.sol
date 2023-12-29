// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { EpochPowerLib } from "src/lib/EpochPowerLib.sol";
import { VoteEscrowedPWN } from "src/VoteEscrowedPWN.sol";

// solhint-disable foundry-test-functions
contract VoteEscrowedPWNHarness is VoteEscrowedPWN {
    using EpochPowerLib for bytes32;

    // exposed

    function exposed_epochsToNextPowerChange(uint8 remainingLockup) external pure returns (uint8) {
        return _epochsToNextPowerChange(remainingLockup);
    }

    function exposed_power(int104 amount, uint8 remainingLockup) external pure returns (int104) {
        return _power(amount, remainingLockup);
    }

    function exposed_powerDecrease(int104 amount, uint8 remainingLockup) external pure returns (int104) {
        return _powerDecrease(amount, remainingLockup);
    }

    // workaround

    function workaround_getTotalEpochPower(uint256 epoch) external view returns (int104) {
        return _totalPowerNamespace().getEpochPower(epoch);
    }

    function workaround_storeTotalEpochPower(uint256 epoch, int104 power) external {
        _totalPowerNamespace().updateEpochPower(epoch, power);
    }


    struct StakerPowerAtInput {
        address staker;
        uint256 epoch;
    }
    StakerPowerAtInput public expectedStakerPowerAtInput;
    uint256 public stakerPowerAtReturn;
    bool public mockStakerPowerAt = true;
    function stakerPowerAt(address staker, uint256 epoch) virtual public view override returns (uint256) {
        if (mockStakerPowerAt) {
            require(expectedStakerPowerAtInput.staker == staker, "vePWNHarness:stakerPowerAt:staker");
            require(expectedStakerPowerAtInput.epoch == epoch, "vePWNHarness:stakerPowerAt:epoch");
            return stakerPowerAtReturn;
        } else {
            return super.stakerPowerAt(staker, epoch);
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

    function workaround_setMockStakerPowerAt(bool value) external {
        mockStakerPowerAt = value;
    }

    function workaround_setStakerPowerAtInput(StakerPowerAtInput memory input) external {
        expectedStakerPowerAtInput = input;
    }

    function workaround_setStakerPowerAtReturn(uint256 value) external {
        stakerPowerAtReturn = value;
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
