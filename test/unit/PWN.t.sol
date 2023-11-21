// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWN } from "src/PWN.sol";

import { Base_Test } from "../Base.t.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";

abstract contract PWN_Test is Base_Test {

    bytes32 public constant TOTAL_SUPPLY_SLOT = bytes32(uint256(4));
    bytes32 public constant GOVERNOR_SLOT = bytes32(uint256(7));
    bytes32 public constant OWNER_MINTED_AMOUNT_SLOT = bytes32(uint256(8));
    bytes32 public constant REWARDS_SLOT = bytes32(uint256(9));
    bytes32 public constant REWARDS_CLAIMED_SLOT = bytes32(uint256(10));

    PWN public pwnToken;

    address public owner = makeAddr("owner");
    address public clock = makeAddr("clock");
    address public governor = makeAddr("governor");

    function setUp() virtual public {
        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(1)
        );

        pwnToken = new PWN(owner, clock);
        vm.prank(owner);
        pwnToken.setGovernor(payable(governor));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTANTS                                             *|
|*----------------------------------------------------------*/

contract PWN_Constants_Test is PWN_Test {

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

contract PWN_Constructor_Test is PWN_Test {

    function testFuzz_shouldSetInitialParams(
        address _owner, address _clock, uint256 initialEpoch
    ) external checkAddress(_clock) {
        // `0x2e23...470b` will be an address of the PWN token in this test
        // foundry sometimes provide this address as a clock address
        vm.assume(_clock != 0x2e234DAe75C793f67A35089C9d99245E1C58470b);
        vm.mockCall(_clock, abi.encodeWithSignature("currentEpoch()"), abi.encode(initialEpoch));

        pwnToken = new PWN(_owner, _clock);

        assertEq(pwnToken.owner(), _owner);
        assertEq(address(pwnToken.epochClock()), _clock);
        assertEq(pwnToken.INITIAL_EPOCH(), initialEpoch);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract PWN_Mint_Test is PWN_Test {

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
        vm.store(address(pwnToken), OWNER_MINTED_AMOUNT_SLOT, bytes32(ownerMintedAmount));

        vm.expectRevert("PWN: initial supply reached");
        vm.prank(owner);
        pwnToken.mint(amount);
    }

}


/*----------------------------------------------------------*|
|*  # BURN                                                  *|
|*----------------------------------------------------------*/

contract PWN_Burn_Test is PWN_Test {

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);
        deal(address(pwnToken), caller, 100 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.burn(100 ether);
    }

    function testFuzz_shouldBurnCallersTokens(uint256 originalAmount, uint256 burnAmount) external {
        originalAmount = bound(originalAmount, 1, type(uint256).max);
        burnAmount = bound(burnAmount, 0, originalAmount);
        deal(address(pwnToken), owner, originalAmount);

        vm.prank(owner);
        pwnToken.burn(burnAmount);

        assertEq(pwnToken.balanceOf(owner), originalAmount - burnAmount);
    }

    function testFuzz_shouldNotDecreseOwnerMintedAmount(uint256 originalAmount, uint256 burnAmount) external {
        originalAmount = bound(originalAmount, 1, type(uint256).max);
        burnAmount = bound(burnAmount, 0, originalAmount);
        deal(address(pwnToken), owner, originalAmount);
        uint256 ownerMintedAmount = originalAmount;
        vm.store(address(pwnToken), OWNER_MINTED_AMOUNT_SLOT, bytes32(ownerMintedAmount));

        vm.prank(owner);
        pwnToken.burn(burnAmount);

        bytes32 ownerMintedAmountValue = vm.load(address(pwnToken), OWNER_MINTED_AMOUNT_SLOT);
        assertEq(uint256(ownerMintedAmountValue), ownerMintedAmount);
    }

}


/*----------------------------------------------------------*|
|*  # ASSIGN VOTING REWARDS                                 *|
|*----------------------------------------------------------*/

contract PWN_AssignVotingReward_Test is PWN_Test {
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
        return pwnToken.totalSupply() * pwnToken.MAX_INFLATION_RATE() / pwnToken.INFLATION_DENOMINATOR();
    }


    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.assignVotingReward(proposalId, reward);
    }

    function testFuzz_shouldFail_whenImmutablePeriodNotReached(uint256 currentEpoch) external {
        currentEpoch = bound(
            currentEpoch, pwnToken.INITIAL_EPOCH(), pwnToken.IMMUTABLE_PERIOD() + pwnToken.INITIAL_EPOCH() - 1
        );

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

        bytes32 rewardValue = vm.load(address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId));
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

contract PWN_ClaimVotingReward_Test is PWN_Test {
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


    function test_shouldFail_whenGovernorNotSet() external {
        vm.store(address(pwnToken), GOVERNOR_SLOT, bytes32(uint256(0)));

        vm.expectRevert("PWN: governor not set");
        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
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

    function testFuzz_shouldFail_whenCallerHasNotVoted(address caller) external {
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
        vm.store(address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId), bytes32(0));

        vm.expectRevert("PWN: no reward");
        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

    function test_shouldFail_whenVoterAlreadyClaimedReward() external {
        vm.store(
            address(pwnToken),
            REWARDS_CLAIMED_SLOT.withMappingKey(proposalId).withMappingKey(voter),
            bytes32(uint256(1))
        );

        vm.expectRevert("PWN: reward already claimed");
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

    function test_shouldStoreThatVoterClaimedReward() external {
        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);

        bytes32 rewardClaimedValue = vm.load(
            address(pwnToken), REWARDS_CLAIMED_SLOT.withMappingKey(proposalId).withMappingKey(voter)
        );
        assertEq(uint256(rewardClaimedValue), 1);
    }

    function testFuzz_shouldMintRewardToCaller(
        uint256 _reward, uint256 againsVotes, uint256 forVotes, uint256 abstainVotes, uint256 votersPower
    ) external {
        reward = bound(_reward, 1, 100 ether);
        againsVotes = bound(againsVotes, 1, type(uint256).max / 3);
        forVotes = bound(forVotes, 1, type(uint256).max / 3);
        abstainVotes = bound(abstainVotes, 1, type(uint256).max / 3);
        uint256 totalPower = againsVotes + forVotes + abstainVotes;
        votersPower = bound(votersPower, 1, totalPower);
        vm.mockCall(
            governor,
            abi.encodeWithSignature("proposalVotes(uint256)"),
            abi.encode(againsVotes, forVotes, abstainVotes)
        );
        vm.mockCall(governor, abi.encodeWithSignature("getVotes(address,uint256)"), abi.encode(votersPower));
        vm.store(address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId), bytes32(reward));

        uint256 originalTotalSupply = pwnToken.totalSupply();
        uint256 originalBalance = pwnToken.balanceOf(voter);

        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);

        uint256 voterReward = Math.mulDiv(reward, votersPower, totalPower);
        assertEq(originalTotalSupply + voterReward, pwnToken.totalSupply());
        assertEq(originalBalance + voterReward, pwnToken.balanceOf(voter));
    }

    function testFuzz_shouldEmit_VotingRewardClaimed(
        uint256 _reward, uint256 totalPower, uint256 votersPower
    ) external {
        reward = bound(_reward, 1, 100 ether);
        totalPower = bound(totalPower, 1, type(uint256).max);
        votersPower = bound(votersPower, 1, totalPower);
        vm.store(address(pwnToken), REWARDS_SLOT.withMappingKey(proposalId), bytes32(reward));
        vm.mockCall(governor, abi.encodeWithSignature("proposalVotes(uint256)"), abi.encode(0, totalPower, 0));
        vm.mockCall(governor, abi.encodeWithSignature("getVotes(address,uint256)"), abi.encode(votersPower));
        uint256 voterReward = Math.mulDiv(reward, votersPower, totalPower);

        vm.expectEmit();
        emit VotingRewardClaimed(proposalId, voter, voterReward);

        vm.prank(voter);
        pwnToken.claimVotingReward(proposalId);
    }

}


/*----------------------------------------------------------*|
|*  # SET GOVERNOR                                          *|
|*----------------------------------------------------------*/

contract PWN_SetGovernor_Test is PWN_Test {

    function test_shouldFail_whenZeroAddress() external {
        vm.expectRevert("PWN: governor zero address");
        vm.prank(owner);
        pwnToken.setGovernor(payable(0));
    }

    function testFuzz_shouldStoreNewGovernor(address _governor) external checkAddress(_governor) {
        vm.prank(owner);
        pwnToken.setGovernor(payable(_governor));

        bytes32 governorValue = vm.load(address(pwnToken), GOVERNOR_SLOT);
        assertEq(address(uint160(uint256(governorValue))), _governor);
    }

}
