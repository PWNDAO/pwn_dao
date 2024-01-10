// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Initializable } from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import { PWN } from "../PWN.sol";
import { PWNEpochClock } from "../PWNEpochClock.sol";
import { StakedPWN } from "../StakedPWN.sol";

/// @title VoteEscrowedPWNStorage.
/// @notice Storage contract holding all state variables used by VoteEscrowedPWN.
/// @dev This contract is Ownable2Step, which means that the ownership transfer
/// must be accepted by the new owner.
/// The contract is Initializable, which means that it has an initializer
/// function that must be called exactly once.
contract VoteEscrowedPWNStorage is Ownable2Step, Initializable {

    /*----------------------------------------------------------*|
    |*  # GENERAL PROPERTIES                                    *|
    |*----------------------------------------------------------*/

    /// @notice The number of epochs in a year.
    uint8 public constant EPOCHS_IN_YEAR = 13;

    /// @notice The address of the PWN token contract.
    PWN public pwnToken;
    /// @notice The address of the staked PWN token contract.
    StakedPWN public stakedPWN;
    /// @notice The address of the epoch clock contract.
    PWNEpochClock public epochClock;


    /*----------------------------------------------------------*|
    |*  # STAKE                                                 *|
    |*----------------------------------------------------------*/

    /// @notice The last stake id.
    uint256 public lastStakeId;

    struct Stake {
        // The first epoch from which the stake is locked.
        // max uint16 (65535) > epoch number for the next 5.4k years
        uint16 initialEpoch;
        // The number of epochs the stake is locked for.
        // max uint8 (255) > max epoch lock up number 130
        uint8 remainingLockup;
        // Amount of PWN tokens staked.
        // max uint104 (2e31) > max stake ≈ 7e28
        // - total initial supply with decimals (1e26)
        // - max multiplier with decimals (350)
        // - 350 max voting reward claims (2)
        uint104 amount;
        // uint128 __padding;
    }
    /// @notice The stake for a stake id.
    mapping(uint256 stakeId => Stake) public stakes;


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    /// @notice The namespace for the total power.
    /// @dev The namespace is used to store the total power per epoch.
    /// For more information about how the total power is stored, see `EpochPowerLib`.
    /// Represent any stored power as:
    /// - if (`lastCalculatedTotalPowerEpoch` < epoch) than power change
    /// - if (`lastCalculatedTotalPowerEpoch` >= epoch) than final power
    // 0x920c353e14947c4dbbef6103c601d908b93371995902e76fd01b61e605e633fe
    bytes32 public constant TOTAL_POWER_NAMESPACE = bytes32(uint256(keccak256("vePWN.TOTAL_POWER")) + 1);

    /// @notice The last epoch in which the total power was calculated.
    uint256 public lastCalculatedTotalPowerEpoch;

}
