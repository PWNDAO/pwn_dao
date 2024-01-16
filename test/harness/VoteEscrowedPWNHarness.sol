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

    function exposed_power(int104 amount, uint8 lockUpEpochs) external pure returns (int104) {
        return _power(amount, lockUpEpochs);
    }

    function exposed_powerDecrease(int104 amount, uint8 remainingLockup) external pure returns (int104) {
        return _powerDecrease(amount, remainingLockup);
    }

    function exposed_makeName(uint256 stakeId) external pure returns (string memory) {
        return _makeName(stakeId);
    }

    function exposed_makeExternalUrl(uint256 stakeId) external view returns (string memory) {
        return _makeExternalUrl(stakeId);
    }

    function exposed_makeApiUriWith(uint256 stakeId, string memory path) external view returns (string memory) {
        return _makeApiUriWith(stakeId, path);
    }

    function exposed_makeDescription() external pure returns (string memory) {
        return _makeDescription();
    }

    function exposed_computeAttributes(uint256 stakeId) external view returns (MetadataAttributes memory) {
        return _computeAttributes(stakeId);
    }

    function exposed_makeMultiplier(uint8 lockUpEpochs) external pure returns (string memory) {
        return _makeMultiplier(lockUpEpochs);
    }

    function exposed_makeStakedAmount(StakedAmount memory stakedAmount) external pure returns (string memory) {
        return _makeStakedAmount(stakedAmount);
    }

    function exposed_makePowerChanges(PowerChange[] memory powerChanges) external pure returns (string memory) {
        return _makePowerChanges(powerChanges);
    }

    // workaround

    function workaround_getTotalEpochPower(uint256 epoch) external view returns (int104) {
        return TOTAL_POWER_NAMESPACE.getEpochPower(epoch);
    }

    function workaround_storeTotalEpochPower(uint256 epoch, int104 power) external {
        TOTAL_POWER_NAMESPACE.updateEpochPower(epoch, power);
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
