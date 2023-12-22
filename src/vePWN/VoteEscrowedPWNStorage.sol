// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import { PWN } from "../PWN.sol";
import { PWNEpochClock } from "../PWNEpochClock.sol";
import { StakedPWN } from "../StakedPWN.sol";

contract VoteEscrowedPWNStorage is Ownable2Step, Initializable {

    /*----------------------------------------------------------*|
    |*  # GENERAL PROPERTIES                                    *|
    |*----------------------------------------------------------*/

    uint8 public constant EPOCHS_IN_YEAR = 13;

    PWN public pwnToken;
    StakedPWN public stakedPWN;
    PWNEpochClock public epochClock;


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


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    // represent any stored power as:
    // - if (last calculated epoch >= epoch) than final power
    // - if (last calculated epoch < epoch) than power change

    // 0x920c353e14947c4dbbef6103c601d908b93371995902e76fd01b61e605e633fc
    bytes32 public constant TOTAL_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.TOTAL_POWER")) - 1);
    function _totalPowerNamespace() internal pure returns (bytes32) {
        return TOTAL_POWER_NAMESPACE;
    }

    uint256 public lastCalculatedTotalPowerEpoch;

}
