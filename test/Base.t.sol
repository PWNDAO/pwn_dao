// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

// solhint-disable-next-line no-global-import
import "forge-std/Test.sol";

abstract contract Base_Test is Test {

    modifier checkAddress(address addr) {
        _checkAddress(addr, false);
        _;
    }

    modifier checkAddressAllowZero(address addr) {
        _checkAddress(addr, true);
        _;
    }

    // # HELPERS

    function _checkAddress(address addr, bool allowZero) internal virtual {
        if (!allowZero) vm.assume(addr != address(0));
        assumeAddressIsNot(addr, AddressType.Precompile, AddressType.ForgeAddress);
        vm.assume(addr != 0x2e234DAe75C793f67A35089C9d99245E1C58470b);
    }

}
