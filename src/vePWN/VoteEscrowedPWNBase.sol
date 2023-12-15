// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IERC20Metadata } from "openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol";
import { IERC6372 } from "openzeppelin-contracts/contracts/interfaces/IERC6372.sol";

import { Error } from "../lib/Error.sol";
import { VoteEscrowedPWNStorage } from "./VoteEscrowedPWNStorage.sol";

abstract contract VoteEscrowedPWNBase is VoteEscrowedPWNStorage, IERC20Metadata, IERC6372 {

    /*----------------------------------------------------------*|
    |*  # IERC20 METADATA                                       *|
    |*----------------------------------------------------------*/

    function name() external pure returns (string memory) {
        return "Vote-escrowed PWN";
    }

    function symbol() external pure returns (string memory) {
        return "vePWN";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return totalPowerAt(epochClock.currentEpoch());
    }

    function balanceOf(address account) external view returns (uint256) {
        return stakerPower(account, epochClock.currentEpoch());
    }

    function transfer(address /* to */, uint256 /* amount */) external pure returns (bool) {
        revert Error.TransferDisabled();
    }

    function transferFrom(address /* from */, address /* to */, uint256 /* amount */) external pure returns (bool) {
        revert Error.TransferFromDisabled();
    }

    function allowance(address /* owner */, address /* spender */) external pure returns (uint256) {
        return 0;
    }

    function approve(address /* spender */, uint256 /* amount */) external pure returns (bool) {
        revert Error.ApproveDisabled();
    }


    /*----------------------------------------------------------*|
    |*  # VOTES                                                 *|
    |*----------------------------------------------------------*/

    function getVotes(address account) external view returns (uint256) {
        return stakerPower(account, epochClock.currentEpoch());
    }

    function getPastVotes(address account, uint256 epoch) external view returns (uint256) {
        return stakerPower(account, epoch);
    }

    function getPastTotalSupply(uint256 epoch) external view returns (uint256) {
        return totalPowerAt(epoch);
    }

    function delegates(address /* account */) external pure returns (address) {
        return address(0);
    }

    function delegate(address /* delegatee */) external pure {
        revert Error.DelegateDisabled();
    }

    function delegateBySig(
        address /* delegatee */,
        uint256 /* nonce */,
        uint256 /* expiry */,
        uint8 /* v */,
        bytes32 /* r */,
        bytes32 /* s */
    ) external pure {
        revert Error.DelegateBySigDisabled();
    }


    /*----------------------------------------------------------*|
    |*  # CLOCK - ERC6372                                       *|
    |*----------------------------------------------------------*/

    function clock() external view returns (uint48) {
        return epochClock.currentEpoch();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=pwn-epoch";
    }


    /*----------------------------------------------------------*|
    |*  # POWER FUNCTION PLACEHOLDERS                           *|
    |*----------------------------------------------------------*/

    function stakerPower(address, uint256) virtual public view returns (uint256);

    function totalPowerAt(uint256) virtual public view returns (uint256);

}
