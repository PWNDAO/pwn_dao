// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

/// @title Interface for StakedPWN supply manager.
/// @notice This contract is used to manage the supply of StakedPWN tokens and their metadata.
interface IStakedPWNSupplyManager {

    /// @notice Returns the metadata associated with a stake.
    /// @param stakeId The ID of the stake.
    /// @return The metadata associated with the stake.
    function stakeMetadata(uint256 stakeId) external view returns (string memory);

}
