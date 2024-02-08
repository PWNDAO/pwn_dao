// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Error } from "src/lib/Error.sol";

import { VoteEscrowedPWNHarness } from "test/harness/VoteEscrowedPWNHarness.sol";
import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

// solhint-disable-next-line no-empty-blocks
abstract contract VoteEscrowedPWN_Base_Test is VoteEscrowedPWN_Test {}


/*----------------------------------------------------------*|
|*  # IERC20                                                *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_IERC20_Test is VoteEscrowedPWN_Base_Test {

    function test_shouldReturnCorrectMetadata() external {
        assertEq(vePWN.name(), "Vote-escrowed PWN");
        assertEq(vePWN.symbol(), "vePWN");
        assertEq(vePWN.decimals(), 18);
    }

    function testFuzz_shouldReturnTotalPower_forTotalSupply(uint256 _totalSupply) external {
        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput({ epoch: currentEpoch }));
        vePWN.workaround_setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.totalSupply();

        assertEq(totalSupply, _totalSupply);
    }

    function testFuzz_shouldReturnStakerPower_forBalanceOf(address holder, uint256 power) external {
        vePWN.workaround_setStakerPowerAtInput(
            VoteEscrowedPWNHarness.StakerPowerAtInput({ staker: holder, epoch: currentEpoch })
        );
        vePWN.workaround_setStakerPowerAtReturn(power);

        uint256 balance = vePWN.balanceOf(holder);

        assertEq(balance, power);
    }

    function test_shouldHaveTransferDisabled() external {
        address from = makeAddr("from");
        address to = makeAddr("to");
        uint256 amount = 420;

        vm.expectRevert(abi.encodeWithSelector(Error.TransferDisabled.selector));
        vePWN.transfer(to, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.TransferFromDisabled.selector));
        vePWN.transferFrom(from, to, amount);

        vm.expectRevert(abi.encodeWithSelector(Error.ApproveDisabled.selector));
        vePWN.approve(to, amount);

        uint256 allowance = vePWN.allowance(from, to);
        assertEq(allowance, 0);
    }

}


/*----------------------------------------------------------*|
|*  # VOTES                                                 *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_Votes_Test is VoteEscrowedPWN_Base_Test {

    function testFuzz_shouldReturnStakerPower_forGetVotes(address voter, uint256 power) external {
        vePWN.workaround_setStakerPowerAtInput(
            VoteEscrowedPWNHarness.StakerPowerAtInput({ staker: voter, epoch: currentEpoch })
        );
        vePWN.workaround_setStakerPowerAtReturn(power);

        uint256 votes = vePWN.getVotes(voter);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnStakerPower_forGetPastVotes(address voter, uint256 power, uint16 epoch) external {
        vePWN.workaround_setStakerPowerAtInput(
            VoteEscrowedPWNHarness.StakerPowerAtInput({ staker: voter, epoch: epoch })
        );
        vePWN.workaround_setStakerPowerAtReturn(power);

        uint256 votes = vePWN.getPastVotes(voter, epoch);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnTotalPower_forGetPastTotalSupply(uint256 _totalSupply, uint16 epoch) external {
        vePWN.workaround_setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput({ epoch: epoch }));
        vePWN.workaround_setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.getPastTotalSupply(epoch);

        assertEq(totalSupply, _totalSupply);
    }

    function test_shouldHaveDisabledDelegation() external {
        address delegatee = makeAddr("delegatee");

        assertEq(vePWN.delegates(delegatee), address(0));

        vm.expectRevert(abi.encodeWithSelector(Error.DelegateDisabled.selector));
        vePWN.delegate(delegatee);

        vm.expectRevert(abi.encodeWithSelector(Error.DelegateBySigDisabled.selector));
        vePWN.delegateBySig(delegatee, 0, 0, 0, 0, 0);
    }

}


/*----------------------------------------------------------*|
|*  # CLOCK - ERC6372                                       *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Base_Clock_Test is VoteEscrowedPWN_Base_Test {

    function test_shouldCallEpochClock() external {
        vm.expectCall(epochClock, abi.encodeWithSignature("currentEpoch()"));

        uint64 clock = vePWN.clock();
        assertEq(clock, currentEpoch);
    }

    function test_shouldReturnCorrectClockMode() external {
        string memory clockMode = vePWN.CLOCK_MODE();

        assertEq(clockMode, "mode=pwn-epoch");
    }

}
