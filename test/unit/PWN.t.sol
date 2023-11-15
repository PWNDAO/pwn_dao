// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { PWN } from "../../src/PWN.sol";

import { BasePWNTest } from "../BasePWNTest.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";


abstract contract PWNTest is BasePWNTest {

    bytes32 public constant TOTAL_SUPPLY_SLOT = bytes32(uint256(4));
    bytes32 public constant OWNER_MINTED_AMOUNT_SLOT = bytes32(uint256(8));
    bytes32 public constant REWARDS_SLOT = bytes32(uint256(9));

    PWN public pwnToken;

    address public owner = makeAddr("owner");
    address public clock = makeAddr("clock");
    address public governor = makeAddr("governor");
    uint256 public initialEpochTimestamp = 1;

    function setUp() virtual public {
        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(initialEpochTimestamp)
        );

        pwnToken = new PWN(owner, clock, payable(governor));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTANTS                                             *|
|*----------------------------------------------------------*/

contract PWN_Constants_Test is PWNTest {

    function test_constants() external {
        assertEq(pwnToken.name(), "PWN DAO");
        assertEq(pwnToken.symbol(), "PWN");
        assertEq(pwnToken.decimals(), 18);
        assertEq(pwnToken.INITIAL_TOTAL_SUPPLY(), 100_000_000e18);
        assertEq(pwnToken.MAX_INFLATION_RATE(), 20);
        assertEq(pwnToken.IMMUTABLE_PERIOD(), 65);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWN_Constructor_Test is PWNTest {

    function testFuzz_shouldSetInitialParams(
        address _owner, address _clock, address _governor, uint256 _initialEpochTimestamp
    ) external checkAddress(_clock) {
        // `0x2e23...470b` will be an address of the PWN token in this test
        // foundry sometimes provide this address as a clock address
        vm.assume(_clock != 0x2e234DAe75C793f67A35089C9d99245E1C58470b);

        vm.mockCall(
            _clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(_initialEpochTimestamp)
        );

        pwnToken = new PWN(_owner, _clock, payable(_governor));

        assertEq(pwnToken.owner(), _owner);
        assertEq(address(pwnToken.epochClock()), _clock);
        assertEq(address(pwnToken.governor()), _governor);
        assertEq(pwnToken.initialEpochTimestamp(), _initialEpochTimestamp);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract PWN_Mint_Test is PWNTest {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.mint(100 ether);
    }

    function testFuzz_shouldFail_whenInitialSupplyReached(uint256 ownerMintedAmount, uint256 amount) external {
        ownerMintedAmount = bound(ownerMintedAmount, 0, pwnToken.INITIAL_TOTAL_SUPPLY());
        amount = bound(
            amount, pwnToken.INITIAL_TOTAL_SUPPLY() - ownerMintedAmount + 1, type(uint256).max - ownerMintedAmount
        );

        vm.store(
            address(pwnToken), OWNER_MINTED_AMOUNT_SLOT, bytes32(ownerMintedAmount)
        );

        vm.expectRevert("PWN: initial supply reached");
        vm.prank(owner);
        pwnToken.mint(amount);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract PWN_Burn_Test is PWNTest {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        deal(address(pwnToken), caller, 100 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.burn(100 ether);
    }

    function test_shouldBurnCallersTokens() external {
        deal(address(pwnToken), owner, 100 ether);

        vm.prank(owner);
        pwnToken.burn(10 ether);

        assertEq(pwnToken.balanceOf(owner), 90 ether);
    }

    function test_shouldNotDecreseOwnerMintedAmount() external {
        uint256 ownerMintedAmount = 100 ether;
        deal(address(pwnToken), owner, 100 ether);
        vm.store(
            address(pwnToken), OWNER_MINTED_AMOUNT_SLOT, bytes32(ownerMintedAmount)
        );

        vm.prank(owner);
        pwnToken.burn(10 ether);

        bytes32 ownerMintedAmountValue = vm.load(address(pwnToken), OWNER_MINTED_AMOUNT_SLOT);
        assertEq(uint256(ownerMintedAmountValue), ownerMintedAmount);
    }

}


/*----------------------------------------------------------*|
|*  # ASSIGN VOTING REWARDS                                 *|
|*----------------------------------------------------------*/

contract PWN_AssignVotingReward_Test is PWNTest {
    using SlotComputingLib for bytes32;

    uint256 public proposalId = 69;
    uint256 public reward = 101 ether;

    event VotingRewardAssigned(uint256 indexed proposalId, uint256 reward);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(pwnToken.IMMUTABLE_PERIOD() + 1)
        );
        vm.store(
            address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(uint256(100_000_000 ether))
        );
    }

    function _maxReward() private view returns (uint256) {
        return pwnToken.totalSupply() * pwnToken.MAX_INFLATION_RATE() / 1000;
    }


    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.assignVotingReward(proposalId, reward);
    }

    function testFuzz_shouldFail_whenImmutablePeriodNotReached(uint256 currentEpoch) external {
        currentEpoch = bound(currentEpoch, initialEpochTimestamp, pwnToken.IMMUTABLE_PERIOD());

        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(currentEpoch)
        );

        vm.expectRevert("PWN: immutable period not reached");
        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);
    }

    function testFuzz_shouldFail_whenRewardTooHigh(uint256 _reward) external {
        reward = bound(_reward, _maxReward() + 1, type(uint256).max);

        vm.expectRevert("PWN: reward too high");
        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);
    }

    function test_shouldFail_whenZeroReward() external {
        vm.expectRevert("PWN: reward cannot be zero");
        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, 0);
    }

    function test_shouldFail_whenRewardAlreadyAssigned() external {
        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);

        vm.expectRevert("PWN: reward already assigned");
        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);
    }

    function testFuzz_shouldStoreAssignedReward(uint256 _proposalId, uint256 _reward) external {
        proposalId = _proposalId;
        reward = bound(_reward, 1, _maxReward());

        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);

        bytes32 rewardValue = vm.load(
            address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId)
        );
        assertEq(uint256(rewardValue), reward);
    }

    function testFuzz_shouldNotMintNewTokens(uint256 _proposalId, uint256 _reward) external {
        proposalId = _proposalId;
        reward = bound(_reward, 1, _maxReward());

        uint256 originalTotalSupply = pwnToken.totalSupply();

        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);

        assertEq(originalTotalSupply, pwnToken.totalSupply());
    }

    function testFuzz_shouldEmit_VotingRewardAssigned(uint256 _proposalId, uint256 _reward) external {
        proposalId = _proposalId;
        reward = bound(_reward, 1, _maxReward());

        vm.expectEmit();
        emit VotingRewardAssigned(proposalId, reward);

        vm.prank(owner);
        pwnToken.assignVotingReward(proposalId, reward);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM VOTING REWARDS                                  *|
|*----------------------------------------------------------*/

contract PWN_ClaimVotingReward_Test is PWNTest {
    using SlotComputingLib for bytes32;

    address public voter = makeAddr("voter");
    uint256 public proposalId = 69;
    uint256 public reward = 100 ether;
    uint256 public timepoint = 17e8;

    event VotingRewardClaimed(uint256 indexed proposalId, address indexed voter, uint256 reward);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            governor,
            abi.encodeWithSignature("state(uint256)"),
            abi.encode(4)
        );
        vm.mockCall(
            governor,
            abi.encodeWithSignature("hasVoted(uint256,address)"),
            abi.encode(true)
        );
        vm.mockCall(
            governor,
            abi.encodeWithSignature("proposalVotes(uint256)"),
            abi.encode(10, 11, 9)
        );
        vm.mockCall(
            governor,
            abi.encodeWithSignature("proposalSnapshot(uint256)"),
            abi.encode(timepoint)
        );
        vm.mockCall(
            governor,
            abi.encodeWithSignature("getVotes(address,uint256)"),
            abi.encode(3)
        );
        vm.store(
            address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId), bytes32(reward)
        );
        vm.store(
            address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(uint256(100_000_000 ether))
        );
    }


    function testFuzz_shouldFail_whenProposalStateNotSucceeded(uint256 proposalState) external {
        proposalState = bound(proposalState, 0, 7);
        vm.assume(proposalState != 4);

        vm.mockCall(
            governor,
            abi.encodeWithSignature("state(uint256)"),
            abi.encode(proposalState)
        );

        vm.expectRevert("PWN: proposal not succeeded");
        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

    function testFuzz_shouldFail_whenCallerNotVoted(address caller) external {
        vm.mockCall(
            governor,
            abi.encodeWithSignature("hasVoted(uint256,address)"),
            abi.encode(false)
        );

        vm.expectRevert("PWN: caller has not voted");
        vm.prank(caller);
        pwnToken.claimVotingReward(proposalId);
    }

    function test_shouldFail_whenNoRewardAssigned() external {
        vm.store(
            address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId), bytes32(0)
        );

        vm.expectRevert("PWN: no reward");
        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

    function test_shouldUseProposalSnapshotAsTimepoint() external {
        vm.expectCall(
            governor,
            abi.encodeWithSignature("proposalSnapshot(uint256)", proposalId)
        );
        vm.expectCall(
            governor,
            abi.encodeWithSignature("getVotes(address,uint256)", voter, timepoint)
        );

        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

    function testFuzz_shouldMintRewardToCaller(uint256 votersPower) external {
        votersPower = bound(votersPower, 1, 30e18);
        vm.mockCall(
            governor,
            abi.encodeWithSignature("proposalVotes(uint256)"),
            abi.encode(10e18, 11e18, 9e18) // total power = 30e18
        );
        vm.mockCall(
            governor,
            abi.encodeWithSignature("getVotes(address,uint256)"),
            abi.encode(votersPower)
        );

        uint256 originalTotalSupply = pwnToken.totalSupply();
        uint256 originalBalance = pwnToken.balanceOf(voter);

        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);

        uint256 voterReward = reward * votersPower / 30e18;
        assertEq(originalTotalSupply + voterReward, pwnToken.totalSupply());
        assertEq(originalBalance + voterReward, pwnToken.balanceOf(voter));
    }

    function test_shouldEmit_VotingRewardClaimed() external {
        vm.expectEmit();
        emit VotingRewardClaimed(proposalId, voter, 10 ether);

        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

}
