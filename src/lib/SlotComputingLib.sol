// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

/// @notice Utility library for computing storage slots.
/// @dev The library is used to compute storage slots for mappings and arrays.
library SlotComputingLib {

    /*----------------------------------------------------------*|
    |*  # MAPPING                                               *|
    |*----------------------------------------------------------*/

    /// @notice Computes the storage slot for a mapping with a bytes32 type key.
    /// @dev The storage slot is computed as `keccak256(abi.encode(key, slot))`.
    /// @param slot The storage slot to compute the mapping slot for.
    /// @param key Bytes32 key to compute the mapping slot for.
    /// @return The storage slot for the mapping with the given key.
    function withMappingKey(bytes32 slot, bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    /// @notice Computes the storage slot for a mapping with a address type key.
    /// @dev The storage slot is computed as `keccak256(abi.encode(key, slot))`.
    /// @param slot The storage slot to compute the mapping slot for.
    /// @param key Address key to compute the mapping slot for.
    /// @return The storage slot for the mapping with the given key.
    function withMappingKey(bytes32 slot, address key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    /// @notice Computes the storage slot for a mapping with a uint256 type key.
    /// @dev The storage slot is computed as `keccak256(abi.encode(key, slot))`.
    /// @param slot The storage slot to compute the mapping slot for.
    /// @param key Uint256 key to compute the mapping slot for.
    /// @return The storage slot for the mapping with the given key.
    function withMappingKey(bytes32 slot, uint256 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, slot));
    }

    /*----------------------------------------------------------*|
    |*  # ARRAY                                                 *|
    |*----------------------------------------------------------*/

    /// @notice Computes the storage slot for an array with a given index.
    /// @dev The storage slot is computed as `slot + index`.
    /// `slot` should be a `keccak256` of the array slot where its length is stored.
    /// @param slot The storage slot to compute the array slot for.
    /// It should be a `keccak256` of the array slot where its length is stored.
    /// @param index The index to compute the array slot for.
    /// @return The storage slot for the array with the given index.
    function withArrayIndex(bytes32 slot, uint256 index) internal pure returns (bytes32) {
        return bytes32(uint256(slot) + index);
    }

}
