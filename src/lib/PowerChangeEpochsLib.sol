// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

library PowerChangeEpochsLib {

    /// @notice Finds an index of the epoch in `stakersPowerChangeEpochs` that is
    /// first greater than or equal to `epoch`.
    /// @dev `stakersPowerChangeEpochs` must be sorted in ascending order without duplicates.
    /// If `epoch` is smaller than the first element of `stakersPowerChangeEpochs`, returns 0.
    /// If `epoch` is greater than the last element of `stakersPowerChangeEpochs`, returns
    /// `stakersPowerChangeEpochs` length.
    /// For array [1, 5, 9, 10] and looking for epoch 7, function will return index 2 (value 9).
    /// @param stakersPowerChangeEpochs The array of epochs.
    /// @param epoch The epoch to search for.
    /// @param low The lower bound of the search (included). Must be in range [0, `stakersPowerChangeEpochs` length -1].
    /// @param high The upper bound of the search (excluded). Must be in range [1, `stakersPowerChangeEpochs` length].
    /// @return The index of the epoch in `stakersPowerChangeEpochs` that is first smaller than or equal to `epoch`.
    function findIndex(
        uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 low, uint256 high
    ) internal view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (epoch > stakersPowerChangeEpochs[mid])
                low = mid + 1;
            else
                high = mid;
        }
        return high;
    }

    function findIndex(
        uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 low
    ) internal view returns (uint256) {
        return findIndex(stakersPowerChangeEpochs, epoch, low, stakersPowerChangeEpochs.length);
    }

    /// @notice Finds an index of the epoch in `stakersPowerChangeEpochs` that is
    /// first smaller than or equal to `epoch`.
    /// @dev `stakersPowerChangeEpochs` must be sorted in ascending order without duplicates.
    /// If `epoch` is smaller than the first element of `stakersPowerChangeEpochs`, returns 0.
    /// For array [1, 5, 9, 10] and looking for epoch 7, function will return index 1 (value 5).
    /// @param stakersPowerChangeEpochs The array of epochs.
    /// @param epoch The epoch to search for.
    /// @param low The lower bound of the search (included). Must be in range [0, `stakersPowerChangeEpochs` length -1].
    /// @param high The upper bound of the search (excluded). Must be in range [1, `stakersPowerChangeEpochs` length].
    /// @return The index of the epoch in `stakersPowerChangeEpochs` that is first smaller than or equal to `epoch`.
    function findNearestIndex(
        uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 low, uint256 high
    ) internal view returns (uint256) {
        uint256 length = stakersPowerChangeEpochs.length;
        if (length == 0)
            return 0;

        if (stakersPowerChangeEpochs[low] > epoch)
            return low;

        if (stakersPowerChangeEpochs[high - 1] <= epoch)
            return high - 1;

        uint256 index = findIndex(stakersPowerChangeEpochs, epoch, low, high);
        if (stakersPowerChangeEpochs[index] == epoch)
            return index;
        else
            return index - 1;
    }

    /// @notice Inserts `epoch` into `stakersPowerChangeEpochs` at `epochIndex`.
    /// @param stakersPowerChangeEpochs The array of epochs.
    /// @param epoch The epoch to insert.
    /// @param epochIndex The index at which to insert `epoch`.
    function insertEpoch(uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 epochIndex) internal {
        stakersPowerChangeEpochs.push();
        for (uint256 i = stakersPowerChangeEpochs.length - 1; i > epochIndex;) {
            stakersPowerChangeEpochs[i] = stakersPowerChangeEpochs[i - 1];

            unchecked { --i; }
        }
        stakersPowerChangeEpochs[epochIndex] = epoch;
    }

    /// @notice Removes the epoch at `epochIndex` from `stakersPowerChangeEpochs`.
    /// @param stakersPowerChangeEpochs The array of epochs.
    /// @param epochIndex The index of the epoch to remove.
    function removeEpoch(uint16[] storage stakersPowerChangeEpochs, uint256 epochIndex) internal {
        uint256 length = stakersPowerChangeEpochs.length;
        for (uint256 i = epochIndex; i < length - 1;) {
            stakersPowerChangeEpochs[i] = stakersPowerChangeEpochs[i + 1];

            unchecked { ++i; }
        }
        stakersPowerChangeEpochs.pop();
    }

}
