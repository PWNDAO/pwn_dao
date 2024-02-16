// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title Interface of the PWN Epoch Clock contract.
/// @notice The contract is used to get the current epoch number.
interface IPWNEpochClock {

    /// @notice Returns the current epoch number.
    /// @return The current epoch number.
    function currentEpoch() external view returns (uint16);

}
