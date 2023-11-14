// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

import { VoteEscrowedPWNHarness } from "../harness/VoteEscrowedPWNHarness.sol";
import { VoteEscrowedPWNTest } from "./VoteEscrowedPWNTest.t.sol";


abstract contract VoteEscrowedPWN_Base_Test is VoteEscrowedPWNTest {

}


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
        vePWN._setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput({ epoch: currentEpoch }));
        vePWN._setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.totalSupply();

        assertEq(totalSupply, _totalSupply);
    }

    function testFuzz_shouldReturnStakerPower_forBalanceOf(address holder, uint256 power) external {
        vePWN._setStakerPowerInput(VoteEscrowedPWNHarness.StakerPowerInput({ staker: holder, epoch: currentEpoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 balance = vePWN.balanceOf(holder);

        assertEq(balance, power);
    }

    function test_shouldHaveDisabledTransfer() external {
        address from = makeAddr("from");
        address to = makeAddr("to");
        uint256 amount = 420;

        vm.expectRevert("vePWN: transfer is disabled");
        vePWN.transfer(to, amount);

        vm.expectRevert("vePWN: transferFrom is disabled");
        vePWN.transferFrom(from, to, amount);

        vm.expectRevert("vePWN: approve is disabled");
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
        vePWN._setStakerPowerInput(VoteEscrowedPWNHarness.StakerPowerInput({ staker: voter, epoch: currentEpoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 votes = vePWN.getVotes(voter);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnStakerPower_forGetPastVotes(address voter, uint256 power, uint256 timepoint, uint16 epoch) external {
        vm.expectCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint));
        vm.mockCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint), abi.encode(epoch));

        vePWN._setStakerPowerInput(VoteEscrowedPWNHarness.StakerPowerInput({ staker: voter, epoch: epoch }));
        vePWN._setStakerPowerReturn(power);

        uint256 votes = vePWN.getPastVotes(voter, timepoint);

        assertEq(votes, power);
    }

    function testFuzz_shouldReturnTotalPower_forGetPastTotalSupply(uint256 _totalSupply, uint256 timepoint, uint16 epoch) external {
        vm.expectCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint));
        vm.mockCall(epochClock, abi.encodeWithSignature("epochFor(uint256)", timepoint), abi.encode(epoch));

        vePWN._setTotalPowerAtInput(VoteEscrowedPWNHarness.TotalPowerAtInput({ epoch: epoch }));
        vePWN._setTotalPowerAtReturn(_totalSupply);

        uint256 totalSupply = vePWN.getPastTotalSupply(timepoint);

        assertEq(totalSupply, _totalSupply);
    }

    function test_shouldHaveDisabledDelegation() external {
        address delegatee = makeAddr("delegatee");

        assertEq(vePWN.delegates(delegatee), address(0));

        vm.expectRevert("vePWN: delegate is disabled");
        vePWN.delegate(delegatee);

        vm.expectRevert("vePWN: delegateBySig is disabled");
        vePWN.delegateBySig(delegatee, 0, 0, 0, 0, 0);
    }

}
