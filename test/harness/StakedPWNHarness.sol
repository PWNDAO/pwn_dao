// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { StakedPWN } from "src/token/StakedPWN.sol";

// solhint-disable foundry-test-functions
contract StakedPWNHarness is StakedPWN {

    // exposed

    function exposed_addIdToList(address owner, uint256 tokenId, uint16 epoch) external {
        _addIdToOwner(owner, tokenId, epoch);
    }


    constructor(address _owner, address _epochClock, address _supplyManager)
        StakedPWN(_owner, _epochClock, _supplyManager)
    {}

}
