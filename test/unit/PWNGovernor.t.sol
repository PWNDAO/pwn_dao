// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

import { PWNGovernor } from "src/PWNGovernor.sol";

import { Base_Test } from "../Base.t.sol";

abstract contract PWNGovernor_Test is Base_Test {

    PWNGovernor public governor;

    address public votingToken = makeAddr("votingToken");
    uint48 public currentClock = 42069;

    function setUp() external {
        vm.mockCall(
            votingToken, abi.encodeWithSignature("clock()"), abi.encode(currentClock)
        );

        governor = new PWNGovernor(IVotes(votingToken));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNGovernor_Constructor_Test is PWNGovernor_Test {

    function test_shouldStoreConstructorArgs() external {
        assertEq(governor.name(), "PWNGovernor");
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 7 days);
        assertEq(governor.proposalThreshold(), 50_000e18); // 50k power
        assertEq(governor.quorumNumerator(currentClock), 20); // 20%
    }

}


/*----------------------------------------------------------*|
|*  # SET VOTING PERIOD                                     *|
|*----------------------------------------------------------*/

contract PWNGovernor_SetVotingPeriod_Test is PWNGovernor_Test {

    function testFuzz_shouldFail_whenVotingPeriodMoreThanEpoch(uint256 votingPeriod) external {
        votingPeriod = bound(votingPeriod, governor.MAX_VOTING_PERIOD(), type(uint256).max);

        vm.expectRevert("PWNGovernor: voting period too long");
        vm.prank(address(governor));
        governor.setVotingPeriod(votingPeriod);
    }

}
