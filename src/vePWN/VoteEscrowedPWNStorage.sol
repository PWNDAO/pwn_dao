// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { PWNEpochClock } from "../PWNEpochClock.sol";
import { PWNFeeCollector } from "../PWNFeeCollector.sol";
import { StakedPWN } from "../StakedPWN.sol";


contract VoteEscrowedPWNStorage is Ownable2Step, Initializable {

    /*----------------------------------------------------------*|
    |*  # GENERAL PROPERTIES                                    *|
    |*----------------------------------------------------------*/

    uint8 public constant EPOCHS_IN_PERIOD = 13; // ~1 year

    IERC20 public pwnToken;
    StakedPWN public stakedPWN;
    PWNEpochClock public epochClock;
    PWNFeeCollector public feeCollector;


    /*----------------------------------------------------------*|
    |*  # STAKE MANAGEMENT                                      *|
    |*----------------------------------------------------------*/

    bytes32 public constant STAKERS_NAMESPACE = bytes32(uint256(keccak256("vePWN.stakers_namespace")) - 1);

    // stPWN data
    struct Stake {
        uint16 initialEpoch;
        uint104 amount;
        uint8 remainingLockup;
        // uint128 __padding;
    }

    uint256 public lastStakeId;
    mapping (uint256 stakeId => Stake) public stakes;

    // staker power change data
    struct PowerChange { // TODO: get rid of the struct
        int104 power;
        // uint152 __padding;
    }

    struct EpochData {
        uint16 value; // TODO: rename to `epoch`
        uint16 index;
        // uint224 __padding;
    }

    // lastCalculatedStakerEpoch.value < current epoch
    mapping (address staker => EpochData) public lastCalculatedStakerEpoch;
    // `powerChangeEpochs` is sorted in ascending order without duplicates
    mapping (address staker => uint16[]) public powerChangeEpochs;


    /*----------------------------------------------------------*|
    |*  # DAO REVENUE PORTION                                   *|
    |*----------------------------------------------------------*/

    struct PortionCheckpoint {
        uint16 initialEpoch;
        uint16 portion; // % with 2 decimals (1234 = 12.34%)
        // uint224 ___padding;
    }

    // checkpoints are sorted by `initialEpoch` in ascending order without duplicates
    PortionCheckpoint[] public daoRevenuePortion;


    /*----------------------------------------------------------*|
    |*  # POWER                                                 *|
    |*----------------------------------------------------------*/

    // represent `_totalPowerAt` as:
    // - if (`lastCalculatedTotalPowerEpoch` >= epoch) than total power
    // - if (`lastCalculatedTotalPowerEpoch` < epoch) than power change
    mapping (uint256 epoch => int256 power) internal _totalPowerAt;
    uint256 public lastCalculatedTotalPowerEpoch;

}
