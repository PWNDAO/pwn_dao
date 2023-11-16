// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import { PWN } from "../PWN.sol";
import { PWNEpochClock } from "../PWNEpochClock.sol";
import { PWNFeeCollector } from "../PWNFeeCollector.sol";
import { StakedPWN } from "../StakedPWN.sol";

contract VoteEscrowedPWNStorage is Ownable2Step, Initializable {

    /*----------------------------------------------------------*|
    |*  # GENERAL PROPERTIES                                    *|
    |*----------------------------------------------------------*/

    uint8 public constant EPOCHS_IN_PERIOD = 13; // ~1 year

    PWN public pwnToken;
    StakedPWN public stakedPWN;
    PWNEpochClock public epochClock;
    PWNFeeCollector public feeCollector;


    /*----------------------------------------------------------*|
    |*  # STAKE                                                 *|
    |*----------------------------------------------------------*/

    uint256 public lastStakeId;

    // StakedPWN data
    struct Stake {
        uint16 initialEpoch;
        uint8 remainingLockup;
        uint104 amount;
        // uint128 __padding;
    }
    mapping(uint256 stakeId => Stake) public stakes;

    // staker power change data
    struct PowerChange {
        int104 power;
        // uint152 __padding;
    }
    // epochs are sorted in ascending order without duplicates
    mapping(address staker => uint16[]) public powerChangeEpochs;


    /*----------------------------------------------------------*|
    |*  # POWER                                                 *|
    |*----------------------------------------------------------*/

    // represent any stored power as:
    // - if (last calculated epoch >= epoch) than final power
    // - if (last calculated epoch < epoch) than power change

    // 0x4095aace3fa5112cb0c68a7f4a13b25159719f6ef0d2c82c61ab4ee5c36f1caa
    bytes32 public constant STAKER_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.STAKER_POWER")) - 1);
    function _stakerPowerNamespace(address staker) internal pure returns (bytes32) {
        return keccak256(abi.encode(staker, STAKER_POWER_NAMESPACE));
    }

    // 0x920c353e14947c4dbbef6103c601d908b93371995902e76fd01b61e605e633fc
    bytes32 public constant TOTAL_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.TOTAL_POWER")) - 1);
    function _totalPowerNamespace() internal pure returns (bytes32) {
        return TOTAL_POWER_NAMESPACE;
    }

    struct EpochWithPosition {
        uint16 epoch;
        uint16 index;
        // uint224 __padding;
    }
    mapping(address staker => EpochWithPosition) internal _lastCalculatedStakerEpoch;
    function lastCalculatedStakerEpoch(address staker) public view returns (uint256) {
        return uint256(_lastCalculatedStakerEpoch[staker].epoch);
    }

    uint256 public lastCalculatedTotalPowerEpoch;


    /*----------------------------------------------------------*|
    |*  # DAO REVENUE SHARE                                     *|
    |*----------------------------------------------------------*/

    struct RevenueShareCheckpoint {
        uint16 initialEpoch;
        uint16 share; // % with 2 decimals (1234 = 12.34%)
        // uint224 ___padding;
    }
    // checkpoints are sorted by `initialEpoch` in ascending order without duplicates
    RevenueShareCheckpoint[] public daoRevenueShares;

}
