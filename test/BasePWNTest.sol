// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

// solhint-disable-next-line no-global-import
import "forge-std/Test.sol";


abstract contract BasePWNTest is Test {

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
    }

}
