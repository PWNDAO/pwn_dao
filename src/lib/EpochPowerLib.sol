// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;


library EpochPowerLib {

    struct EpochPowerWord {
        int104 power1; // TODO: update to int128
        int104 power2; // TODO: update to int128
    }


    function getEpochPower(bytes32 namespace, uint256 epoch) internal view returns (int104) {
        EpochPowerWord storage ep = _getEpochPowerWord(namespace, epoch);
        return epoch % 2 == 0 ? ep.power1 : ep.power2;
    }

    function updateEpochPower(bytes32 namespace, uint256 epoch, int104 power) internal {
        EpochPowerWord storage ep = _getEpochPowerWord(namespace, epoch);
        if (epoch % 2 == 0)
            ep.power1 += power;
        else
            ep.power2 += power;
    }


    function _getEpochPowerWord(bytes32 namespace, uint256 epoch) private pure returns (EpochPowerWord storage ep) {
        bytes32 slot = bytes32(uint256(namespace) + epoch / 2);
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") { ep.slot := slot }
    }

}
