// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { EpochPowerLib } from "src/lib/EpochPowerLib.sol";

import { BitMaskLib } from "../utils/BitMaskLib.sol";
import { Base_Test } from "../Base.t.sol";

contract EpochPowerLib_Test is Base_Test {
    using BitMaskLib for bytes32;

    function _mockEpochPowerWord(bytes32 namespace, uint256 epoch, int104 power1, int104 power2) private {
        bytes32 slot = bytes32(uint256(namespace) + epoch / 2);
        bytes memory rawEpochPowerData = abi.encodePacked(uint48(0), power2, power1);
        vm.store(address(this), slot, abi.decode(rawEpochPowerData, (bytes32)));
    }


    function testFuzz_shouldReturnCorrectPower(bytes32 namespace, uint256 epoch, int104 _power) external {
        namespace = bytes32(bound(uint256(namespace), 1, type(uint256).max / 2));
        epoch = bound(epoch, 1, type(uint256).max / 2);

        if (epoch % 2 == 0)
            _mockEpochPowerWord(namespace, epoch, _power, 0);
        else
            _mockEpochPowerWord(namespace, epoch, 0, _power);

        int104 power = EpochPowerLib.getEpochPower(namespace, epoch);

        assertEq(power, _power);
    }

    function testFuzz_shouldUpdateCorrectPower(
        bytes32 namespace, uint256 epoch, int104 oldPower, int104 _power
    ) external {
        namespace = bytes32(bound(uint256(namespace), 1, type(uint256).max / 2));
        epoch = bound(epoch, 1, type(uint256).max / 2);
        if ((oldPower > 0 && _power > 0) || (oldPower < 0 && _power < 0))
            _power = -(_power >> 1); // bite shift to prevent overflow/underflow

        if (epoch % 2 == 0)
            _mockEpochPowerWord(namespace, epoch, oldPower, 0);
        else
            _mockEpochPowerWord(namespace, epoch, 0, oldPower);

        EpochPowerLib.updateEpochPower(namespace, epoch, _power);

        bytes32 slot = bytes32(uint256(namespace) + epoch / 2);
        bytes32 powerValue = vm.load(address(this), slot);
        assertEq(int104(powerValue.maskUint104(epoch % 2 == 0 ? 0 : 104)), oldPower + _power);
    }

}
