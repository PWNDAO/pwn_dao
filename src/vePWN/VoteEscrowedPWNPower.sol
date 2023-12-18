// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { Error } from "../lib/Error.sol";
import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";
import { EpochPowerLib } from "../lib/EpochPowerLib.sol";
import { PowerChangeEpochsLib } from "../lib/PowerChangeEpochsLib.sol";

contract VoteEscrowedPWNPower is VoteEscrowedPWNBase {
    using EpochPowerLib for bytes32;
    using PowerChangeEpochsLib for uint16[];

    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event StakerPowerCalculated(address indexed staker, uint256 indexed epoch);
    event TotalPowerCalculated(uint256 indexed epoch);


    /*----------------------------------------------------------*|
    |*  # STAKER POWER                                          *|
    |*----------------------------------------------------------*/

    /// @notice Returns staker power for given epoch.
    /// @param staker Staker address.
    /// @param epoch Epoch number.
    /// @return Staker power.
    function stakerPowerAt(address staker, uint256 epoch) override virtual public view returns (uint256) {
        uint16 _epoch = SafeCast.toUint16(epoch);

        // nobody can have any power before epoch 1
        if (_epoch == 0) {
            return 0;
        }

        // for no power changes return 0
        uint16[] storage stakerPowerChangeEpochs = _powerChangeEpochs[staker];
        if (stakerPowerChangeEpochs.length == 0) {
            return 0;
        }

        // for epoch before first power change return 0
        if (_epoch < stakerPowerChangeEpochs[0]) {
            return 0;
        }

        bytes32 stakerNamespace = _stakerPowerNamespace(staker);
        uint256 lcIndex = _lastCalculatedStakerEpochIndex[staker];
        uint16 lcEpoch = stakerPowerChangeEpochs[lcIndex];
        if (lcEpoch == _epoch) {
            return SafeCast.toUint256(int256(stakerNamespace.getEpochPower(lcEpoch)));

        } else if (lcEpoch > _epoch) {
            uint256 index = stakerPowerChangeEpochs.findNearestIndex(_epoch, 0, lcIndex);
            return SafeCast.toUint256(int256(stakerNamespace.getEpochPower(stakerPowerChangeEpochs[index])));

        } else {
            uint256 index = stakerPowerChangeEpochs.findNearestIndex(_epoch, lcIndex, stakerPowerChangeEpochs.length);
            int104 power;
            for (uint256 i = lcIndex; i <= index;) {
                power += stakerNamespace.getEpochPower(stakerPowerChangeEpochs[i]);
                unchecked { ++i; }
            }
            return SafeCast.toUint256(int256(power));
        }
    }

    function calculatePower() external {
        calculateStakerPower(msg.sender);
    }

    function calculateStakerPower(address staker) public {
        calculateStakerPowerUpTo(staker, epochClock.currentEpoch() - 1);
    }

    /// @notice Calculates and store staker power up to given epoch.
    /// @param staker Staker address.
    /// @param epoch Epoch number.
    function calculateStakerPowerUpTo(address staker, uint256 epoch) public {
        uint16[] storage stakerPowerChangeEpochs = _powerChangeEpochs[staker];

        if (stakerPowerChangeEpochs.length == 0) {
            revert Error.NoPowerChanges();
        }
        // epoch is on purpose smaller than current epoch to allow quick access to current epoch - 1
        // for voting purposes where `lastCalculatedEpoch` is up to date
        if (epoch >= epochClock.currentEpoch()) {
            revert Error.EpochStillRunning();
        }

        uint256 lcIndex = _lastCalculatedStakerEpochIndex[staker];
        uint256 lcEpoch = stakerPowerChangeEpochs[lcIndex];
        if (lcEpoch >= epoch) {
            revert Error.PowerAlreadyCalculated(lcEpoch);
        }

        // calculate stakers power
        bytes32 stakerNamespace = _stakerPowerNamespace(staker);
        for (uint256 i = lcIndex + 1; i < stakerPowerChangeEpochs.length;) {
            uint256 nextEpoch = stakerPowerChangeEpochs[i];
            if (nextEpoch > epoch) {
                break;
            }

            stakerNamespace.updateEpochPower({
                epoch: nextEpoch,
                power: stakerNamespace.getEpochPower(lcEpoch)
            });

            // check invariant
            if (stakerNamespace.getEpochPower(nextEpoch) < 0) {
                revert Error.InvariantFail_NegativeCalculatedPower();
            }

            lcEpoch = nextEpoch;
            lcIndex = i;

            unchecked { ++i; }
        }

        _lastCalculatedStakerEpochIndex[staker] = lcIndex;

        emit StakerPowerCalculated(staker, lcEpoch);
    }


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    function totalPowerAt(uint256 epoch) override virtual public view returns (uint256) {
        if (lastCalculatedTotalPowerEpoch >= epoch) {
            return SafeCast.toUint256(int256(_totalPowerNamespace().getEpochPower(epoch)));
        }

        // sum the rest of epochs
        int104 totalPower;
        for (uint256 i = lastCalculatedTotalPowerEpoch; i <= epoch;) {
            totalPower += _totalPowerNamespace().getEpochPower(i);
            unchecked { ++i; }
        }

        return SafeCast.toUint256(int256(totalPower));
    }

    function calculateTotalPower() external {
        calculateTotalPowerUpTo(epochClock.currentEpoch() - 1);
    }

    function calculateTotalPowerUpTo(uint256 epoch) public {
        if (epoch >= epochClock.currentEpoch()) {
            revert Error.EpochStillRunning();
        }
        if (lastCalculatedTotalPowerEpoch >= epoch) {
            revert Error.PowerAlreadyCalculated(lastCalculatedTotalPowerEpoch);
        }

        bytes32 totalPowerNamespace = _totalPowerNamespace();
        for (uint256 i = lastCalculatedTotalPowerEpoch; i < epoch;) {
            totalPowerNamespace.updateEpochPower({
                epoch: i + 1,
                power: totalPowerNamespace.getEpochPower(i)
            });

            // check invariant
            if (totalPowerNamespace.getEpochPower(i + 1) < 0) {
                revert Error.InvariantFail_NegativeCalculatedPower();
            }

            unchecked { ++i; }
        }

        lastCalculatedTotalPowerEpoch = epoch;

        emit TotalPowerCalculated(epoch);
    }

}
