// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

library SlotComputingLib {

    // mappings

    function withMappingKey(bytes32 slot, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    function withMappingKey(bytes32 slot, address key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    function withMappingKey(bytes32 slot, uint256 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    // arrays

    function withArrayIndex(bytes32 slot, uint256 index) internal pure returns (bytes32) {
        return bytes32(uint256(slot) + index);
    }

}
