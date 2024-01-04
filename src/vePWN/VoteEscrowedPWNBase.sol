// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol";
import { IERC6372 } from "openzeppelin-contracts/contracts/interfaces/IERC6372.sol";

import { Error } from "../lib/Error.sol";
import { VoteEscrowedPWNStorage } from "./VoteEscrowedPWNStorage.sol";

/// @title VoteEscrowedPWNBase
/// @notice Base contract for the vote-escrowed PWN token.
abstract contract VoteEscrowedPWNBase is VoteEscrowedPWNStorage, IERC20Metadata, IVotes, IERC6372 {

    /*----------------------------------------------------------*|
    |*  # IERC20 METADATA                                       *|
    |*----------------------------------------------------------*/

    /// {IERC20Metadata.name}
    function name() external pure returns (string memory) {
        return "Vote-escrowed PWN";
    }

    /// {IERC20Metadata.symbol}
    function symbol() external pure returns (string memory) {
        return "vePWN";
    }

    /// {IERC20Metadata.decimals}
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// {IERC20Metadata.totalSupply}
    function totalSupply() external view returns (uint256) {
        return totalPowerAt(epochClock.currentEpoch());
    }

    /// {IERC20Metadata.balanceOf}
    function balanceOf(address account) external view returns (uint256) {
        return stakerPowerAt(account, epochClock.currentEpoch());
    }

    /// {IERC20Metadata.transfer}
    function transfer(address /* to */, uint256 /* amount */) external pure returns (bool) {
        revert Error.TransferDisabled();
    }

    /// {IERC20Metadata.transferFrom}
    function transferFrom(address /* from */, address /* to */, uint256 /* amount */) external pure returns (bool) {
        revert Error.TransferFromDisabled();
    }

    /// {IERC20Metadata.allowance}
    function allowance(address /* owner */, address /* spender */) external pure returns (uint256) {
        return 0;
    }

    /// {IERC20Metadata.approve}
    function approve(address /* spender */, uint256 /* amount */) external pure returns (bool) {
        revert Error.ApproveDisabled();
    }


    /*----------------------------------------------------------*|
    |*  # VOTES                                                 *|
    |*----------------------------------------------------------*/

    /// {IVotes.getVotes}
    function getVotes(address account) external view returns (uint256) {
        return stakerPowerAt(account, epochClock.currentEpoch());
    }

    /// {IVotes.getPastVotes}
    function getPastVotes(address account, uint256 epoch) external view returns (uint256) {
        return stakerPowerAt(account, epoch);
    }

    /// {IVotes.getPastTotalSupply}
    function getPastTotalSupply(uint256 epoch) external view returns (uint256) {
        return totalPowerAt(epoch);
    }

    /// {IVotes.delegates}
    function delegates(address /* account */) external pure returns (address) {
        return address(0);
    }

    /// {IVotes.delegate}
    function delegate(address /* delegatee */) external pure {
        revert Error.DelegateDisabled();
    }

    /// {IVotes.delegateBySig}
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

    /// {IERC6372.clock}
    function clock() external view returns (uint48) {
        return epochClock.currentEpoch();
    }

    /// {IERC6372.CLOCK_MODE}
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=pwn-epoch";
    }


    /*----------------------------------------------------------*|
    |*  # POWER FUNCTION PLACEHOLDERS                           *|
    |*----------------------------------------------------------*/

    /// @notice Returns the power of a staker at an epoch.
    /// @param staker The address of the staker.
    /// @param epoch The epoch at which the power is calculated.
    /// @return The power of the staker at the epoch.
    function stakerPowerAt(address staker, uint256 epoch) virtual public view returns (uint256);

    /// @notice Returns the total power at an epoch.
    /// @param epoch The epoch at which the power is calculated.
    /// @return The total power at the epoch.
    function totalPowerAt(uint256 epoch) virtual public view returns (uint256);


    /*----------------------------------------------------------*|
    |*  # SHARED INTERNAL                                       *|
    |*----------------------------------------------------------*/

    /// @dev Return the power based on the amount of PWN tokens staked and the remaining lockup.
    function _power(int104 amount, uint8 remainingLockup) internal pure returns (int104) {
        if (remainingLockup <= EPOCHS_IN_YEAR) return amount;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 2) return amount * 115 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 3) return amount * 130 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 4) return amount * 150 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 5) return amount * 175 / 100;
        else return amount * 350 / 100;
    }

    /// @dev Return the power decrease based on the amount of PWN tokens staked and the remaining lockup.
    function _powerDecrease(int104 amount, uint8 remainingLockup) internal pure returns (int104) {
        if (remainingLockup == 0) return -amount; // Final power loss
        else if (remainingLockup <= EPOCHS_IN_YEAR) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 2) return -amount * 15 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 3) return -amount * 20 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 4) return -amount * 25 / 100;
        else if (remainingLockup <= EPOCHS_IN_YEAR * 5) return -amount * 175 / 100;
        else return 0;
    }

}
