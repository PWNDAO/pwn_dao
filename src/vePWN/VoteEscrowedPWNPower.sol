// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

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
    /// @dev If staker power for given epoch is not calculated, it will be calculated.
    /// @param staker Staker address.
    /// @param epoch Epoch number.
    /// @return Staker power.
    function stakerPower(address staker, uint256 epoch) override virtual public view returns (uint256) {
        uint16 _epoch = SafeCast.toUint16(epoch);

        // for epoch zero return 0
        if (_epoch == 0)
            return 0;

        // for no power changes return 0
        uint16[] storage _powerChangeEpochs = powerChangeEpochs[staker];
        if (_powerChangeEpochs.length == 0)
            return 0;

        // for epoch before first power change return 0
        if (_epoch < _powerChangeEpochs[0])
            return 0;

        bytes32 stakerNamespace = _stakerPowerNamespace(staker);
        EpochWithPosition storage lastCalculatedEpoch = lastCalculatedStakerEpoch[staker];
        uint16 lcEpoch = lastCalculatedEpoch.epoch;
        uint16 lcIndex = lastCalculatedEpoch.index;
        if (lcEpoch == _epoch) {
            return uint256(int256(stakerNamespace.getEpochPower(_powerChangeEpochs[lcIndex])));

        } else if (lcEpoch > _epoch) {
            uint256 index = _powerChangeEpochs.findNearestIndex(_epoch, 0, lcIndex);
            return uint256(int256(stakerNamespace.getEpochPower(_powerChangeEpochs[index])));

        } else {
            uint256 index = _powerChangeEpochs.findNearestIndex(_epoch, lcIndex, _powerChangeEpochs.length);
            int104 power;
            for (uint256 i = lcIndex; i <= index;) {
                power += stakerNamespace.getEpochPower(_powerChangeEpochs[i]);
                unchecked { ++i; }
            }

            return uint256(uint104(power));
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
        uint16[] storage _powerChangeEpochs = powerChangeEpochs[staker];

        require(_powerChangeEpochs.length > 0, "vePWN: staker has no power changes");
        // epoch is on purpose smaller than current epoch to allow quick access to current epoch - 1
        // for voting purposes where `lastCalculatedEpoch` is up to date
        require(epoch < epochClock.currentEpoch(), "vePWN: epoch hasn't ended yet");

        EpochWithPosition storage lastCalculatedEpoch = lastCalculatedStakerEpoch[staker];
        // set last calculated epoch as first epoch if necessary
        if (lastCalculatedEpoch.epoch == 0)
            lastCalculatedEpoch.epoch = _powerChangeEpochs[0];

        uint256 lcEpoch = lastCalculatedEpoch.epoch;
        uint256 lcIndex = lastCalculatedEpoch.index;
        require(lcEpoch < epoch, "vePWN: staker power already calculated");

        // calculate stakers power
        for (uint256 i = lcIndex + 1; i < _powerChangeEpochs.length;) {
            uint256 nextEpoch = _powerChangeEpochs[i];
            if (nextEpoch > epoch)
                break;

            bytes32 stakerNamespace = _stakerPowerNamespace(staker);
            stakerNamespace.updateEpochPower({
                epoch: nextEpoch,
                power: stakerNamespace.getEpochPower(lcEpoch)
            });

            // check invariant
            require(stakerNamespace.getEpochPower(nextEpoch) >= 0, "vePWN: staker power cannot be negative");

            lcEpoch = nextEpoch;
            lcIndex = i;

            unchecked { ++i; }
        }

        lastCalculatedEpoch.epoch = SafeCast.toUint16(lcEpoch);
        lastCalculatedEpoch.index = SafeCast.toUint16(lcIndex);

        emit StakerPowerCalculated(staker, lcEpoch);
    }


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    function totalPowerAt(uint256 epoch) override virtual public view returns (uint256) {
        if (lastCalculatedTotalPowerEpoch >= epoch)
            return SafeCast.toUint256(int256(_totalPowerNamespace().getEpochPower(epoch)));

        // sum the rest of epochs
        int104 totalPower;
        for (uint256 i = lastCalculatedTotalPowerEpoch; i <= epoch;) {
            totalPower += _totalPowerNamespace().getEpochPower(i);
            unchecked { ++i; }
        }

        return SafeCast.toUint256(int256(totalPower));
    }

    function calculateTotalPower() external {
        calculateTotalPowerUpTo(epochClock.currentEpoch());
    }

    function calculateTotalPowerUpTo(uint256 epoch) public {
        require(epoch < _currentEpoch(), "vePWN: epoch hasn't ended yet");
        require(lastCalculatedTotalPowerEpoch < epoch, "vePWN: total power already calculated");

        for (uint256 i = lastCalculatedTotalPowerEpoch; i < epoch;) {
            _totalPowerNamespace().updateEpochPower({
                epoch: i + 1,
                power: _totalPowerNamespace().getEpochPower(i)
            });

            // check invariant
            require(_totalPowerNamespace().getEpochPower(i + 1) >= 0, "vePWN: total power cannot be negative");

            unchecked { ++i; }
        }

        lastCalculatedTotalPowerEpoch = epoch;

        emit TotalPowerCalculated(epoch);
    }

}
