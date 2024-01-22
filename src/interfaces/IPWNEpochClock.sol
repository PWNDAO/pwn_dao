// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IPWNEpochClock {

    /// @notice Returns the current epoch number.
    /// @return The current epoch number.
    function currentEpoch() external view returns (uint16);

}
