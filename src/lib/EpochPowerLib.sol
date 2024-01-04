// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

/// @notice Utility library for storing epoch power in a bytes32 word.
/// @dev The library is used to store and access epoch power in a bytes32 word.
library EpochPowerLib {

    /// @notice A container for the epoch power.
    /// @param power1 The power of the first epoch.
    /// @param power2 The power of the second epoch.
    struct EpochPowerWord {
        int104 power1;
        int104 power2;
        // uint48 __padding;
    }

    /// @notice Gets the epoch power for a given namespace and epoch.
    /// @dev The epoch power is stored in pairs of epochs in a bytes32 word to save storage.
    /// @param namespace The namespace to get the epoch power for.
    /// @param epoch The epoch to get the epoch power for.
    /// @return The epoch power.
    function getEpochPower(bytes32 namespace, uint256 epoch) internal view returns (int104) {
        EpochPowerWord storage ep = _getEpochPowerWord(namespace, epoch);
        return epoch % 2 == 0 ? ep.power1 : ep.power2;
    }

    /// @notice Updates the epoch power for a given namespace and epoch.
    /// @dev The epoch power will be added to the existing epoch power.
    /// @param namespace The namespace to update the epoch power for.
    /// @param epoch The epoch to update the epoch power for.
    /// @param power The epoch power to add to the existing epoch power.
    function updateEpochPower(bytes32 namespace, uint256 epoch, int104 power) internal {
        EpochPowerWord storage ep = _getEpochPowerWord(namespace, epoch);
        if (epoch % 2 == 0) {
            ep.power1 += power;
        } else {
            ep.power2 += power;
        }
    }


    function _getEpochPowerWord(bytes32 namespace, uint256 epoch) private pure returns (EpochPowerWord storage ep) {
        bytes32 slot = bytes32(uint256(namespace) + epoch / 2);
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            ep.slot := slot
        }
    }

}
