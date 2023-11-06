// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";


library PowerChangeEpochsLib {

    // `stakersPowerChangeEpochs` must be sorted in ascending order without duplicates
    function findIndex(uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 low) internal view returns (uint256) {
        uint256 high = stakersPowerChangeEpochs.length;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (epoch > stakersPowerChangeEpochs[mid]) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    function insertEpoch(uint16[] storage stakersPowerChangeEpochs, uint16 epoch, uint256 epochIndex) internal {
        stakersPowerChangeEpochs.push();
        for (uint256 i = stakersPowerChangeEpochs.length - 1; i > epochIndex;) {
            stakersPowerChangeEpochs[i] = stakersPowerChangeEpochs[i - 1];

            unchecked { --i; }
        }
        stakersPowerChangeEpochs[epochIndex] = epoch;
    }

    function removeEpoch(uint16[] storage stakersPowerChangeEpochs, uint256 epochIndex) internal {
        uint256 length = stakersPowerChangeEpochs.length;
        for (uint256 i = epochIndex; i < length - 1;) {
            stakersPowerChangeEpochs[i] = stakersPowerChangeEpochs[i + 1];

            unchecked { ++i; }
        }
        stakersPowerChangeEpochs.pop();
    }

}
