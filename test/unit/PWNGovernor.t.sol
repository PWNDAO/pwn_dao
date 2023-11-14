// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

import { PWNGovernor } from "../../src/PWNGovernor.sol";


abstract contract PWNGovernorTest is Test {

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

contract PWNGovernor_Constructor_Test is PWNGovernorTest {

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

contract PWNGovernor_SetVotingPeriod_Test is PWNGovernorTest {

    function testFuzz_shouldFail_whenVotingPeriodMoreThanEpoch(uint256 votingPeriod) external {
        votingPeriod = bound(votingPeriod, governor.MAX_VOTING_PERIOD(), type(uint256).max);

        vm.expectRevert("PWNGovernor: voting period too long");
        vm.prank(address(governor));
        governor.setVotingPeriod(votingPeriod);
    }

}
