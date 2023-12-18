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

    uint8 public constant EPOCHS_IN_PERIOD = 13; // ~1 year

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
    |*  # STAKER POWER                                          *|
    |*----------------------------------------------------------*/

    // represent any stored power as:
    // - if (last calculated epoch >= epoch) than final power
    // - if (last calculated epoch < epoch) than power change

    // 0x4095aace3fa5112cb0c68a7f4a13b25159719f6ef0d2c82c61ab4ee5c36f1caa
    bytes32 public constant STAKER_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.STAKER_POWER")) - 1);
    function _stakerPowerNamespace(address staker) internal pure returns (bytes32) {
        return keccak256(abi.encode(staker, STAKER_POWER_NAMESPACE));
    }

    // epochs are sorted in ascending order without duplicates
    mapping(address staker => uint16[]) internal _powerChangeEpochs;
    function powerChangeEpochs(address staker) public view returns (uint16[] memory) {
        return _powerChangeEpochs[staker];
    }

    mapping(address staker => uint256) internal _lastCalculatedStakerEpochIndex;
    function lastCalculatedStakerPowerEpoch(address staker) public view returns (uint256) {
        if (_powerChangeEpochs[staker].length == 0) {
            return 0;
        }
        uint256 lcEpochIndex = _lastCalculatedStakerEpochIndex[staker];
        return _powerChangeEpochs[staker][lcEpochIndex];
    }


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    // 0x920c353e14947c4dbbef6103c601d908b93371995902e76fd01b61e605e633fc
    bytes32 public constant TOTAL_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.TOTAL_POWER")) - 1);
    function _totalPowerNamespace() internal pure returns (bytes32) {
        return TOTAL_POWER_NAMESPACE;
    }

    uint256 public lastCalculatedTotalPowerEpoch;

}
