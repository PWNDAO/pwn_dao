// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

library BitMaskLib {

    function _rightShift(bytes32 from, uint256 rightOffset, uint256 typeSize) private pure returns (uint256) {
        require(rightOffset <= 256 - typeSize, "Invalid mask offset");
        return uint256(from >> rightOffset);
    }


    function maskUint8(bytes32 from, uint256 rightOffset) internal pure returns (uint8) {
        return uint8(_rightShift(from, rightOffset, 8));
    }

    function maskUint16(bytes32 from, uint256 rightOffset) internal pure returns (uint16) {
        return uint16(_rightShift(from, rightOffset, 16));
    }

    function maskUint104(bytes32 from, uint256 rightOffset) internal pure returns (uint104) {
        return uint104(_rightShift(from, rightOffset, 104));
    }

    function maskUint240(bytes32 from, uint256 rightOffset) internal pure returns (uint240) {
        return uint240(_rightShift(from, rightOffset, 240));
    }

}
