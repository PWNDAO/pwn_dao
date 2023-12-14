// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { Error } from "src/lib/Error.sol";
import { PWN, IVotingContract } from "src/PWN.sol";

import { Base_Test } from "../Base.t.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";

abstract contract PWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant TOTAL_SUPPLY_SLOT = bytes32(uint256(4));
    bytes32 public constant OWNER_MINTED_AMOUNT_SLOT = bytes32(uint256(7));
    bytes32 public constant REWARDS_SLOT = bytes32(uint256(8));

    PWN public pwnToken;

    address public owner = makeAddr("owner");
    address public clock = makeAddr("clock");
    address public votingContract = makeAddr("votingContract");
    address public votingToken = makeAddr("votingToken");
    address public voter = makeAddr("voter");
    uint256 public proposalId = 69;
    uint256 public reward = 100 ether;
    uint64 public snapshotEpoch = 420;
    uint256 public pastVotes = 100;

    IVotingContract.ProposalParameters public proposalParameters = IVotingContract.ProposalParameters({
        votingMode: IVotingContract.VotingMode.Standard,
        supportThreshold: 0,
        startDate: 0,
        endDate: 0,
        snapshotEpoch: snapshotEpoch,
        minVotingPower: 0
    });
    IVotingContract.Tally public tally = IVotingContract.Tally({
        abstain: 100,
        yes: 200,
        no: 0
    });
    IVotingContract.Action[] public actions;

    function setUp() virtual public {
        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(1)
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVotingToken()"),
            abi.encode(votingToken)
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)", proposalId, voter),
            abi.encode(IVotingContract.VoteOption.Yes)
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(pastVotes)
        );

        pwnToken = new PWN(owner, clock);

        vm.store(address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(uint256(100_000_000 ether)));
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
        assertEq(pwnToken.MINTABLE_TOTAL_SUPPLY(), 100_000_000e18);
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
        ownerMintedAmount = bound(ownerMintedAmount, 0, pwnToken.MINTABLE_TOTAL_SUPPLY());
        amount = bound(
            amount, pwnToken.MINTABLE_TOTAL_SUPPLY() - ownerMintedAmount + 1, type(uint256).max - ownerMintedAmount
        );
        vm.store(address(pwnToken), OWNER_MINTED_AMOUNT_SLOT, bytes32(ownerMintedAmount));

        vm.expectRevert(abi.encodeWithSelector(Error.MintableSupplyExceeded.selector));
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

    event VotingRewardAssigned(address indexed votingContract, uint256 indexed proposalId, uint256 reward);

    function setUp() override public {
        super.setUp();

        vm.mockCall(
            clock,
            abi.encodeWithSignature("currentEpoch()"),
            abi.encode(pwnToken.IMMUTABLE_PERIOD() + 1)
        );
    }

    function _maxReward() private view returns (uint256) {
        return pwnToken.totalSupply() * pwnToken.MAX_INFLATION_RATE() / pwnToken.INFLATION_DENOMINATOR();
    }


    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);
    }

    function test_shouldFail_whenZeroVotingContract() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroVotingContract.selector));
        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(address(0)), proposalId, reward);
    }

    function testFuzz_shouldFail_whenImmutablePeriodNotReached(uint256 snapshotEpoch) external {
        snapshotEpoch = bound(
            snapshotEpoch, pwnToken.INITIAL_EPOCH(), pwnToken.IMMUTABLE_PERIOD() + pwnToken.INITIAL_EPOCH() - 1
        );
        proposalParameters.snapshotEpoch = uint64(snapshotEpoch);
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, false, proposalParameters, tally, actions, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.InImmutablePeriod.selector));
        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);
    }

    function testFuzz_shouldFail_whenRewardTooHigh(uint256 _reward) external {
        reward = bound(_reward, _maxReward() + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Error.RewardTooHigh.selector, _maxReward()));
        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);
    }

    function test_shouldFail_whenZeroReward() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroReward.selector));
        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, 0);
    }

    function test_shouldFail_whenRewardAlreadyAssigned() external {
        vm.store(
            address(pwnToken),
            REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.RewardAlreadyAssigned.selector, reward));
        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);
    }

    function testFuzz_shouldStoreAssignedReward(uint256 _reward) external {
        reward = bound(_reward, 1, _maxReward());

        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);

        bytes32 rewardValue = vm.load(
            address(pwnToken), REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId)
        );
        assertEq(uint256(rewardValue), reward);
    }

    function testFuzz_shouldNotMintNewTokens(uint256 _reward) external {
        reward = bound(_reward, 1, _maxReward());

        uint256 originalTotalSupply = pwnToken.totalSupply();

        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);

        assertEq(originalTotalSupply, pwnToken.totalSupply());
    }

    function testFuzz_shouldEmit_VotingRewardAssigned(uint256 _reward) external {
        reward = bound(_reward, 1, _maxReward());

        vm.expectEmit();
        emit VotingRewardAssigned(votingContract, proposalId, reward);

        vm.prank(owner);
        pwnToken.assignVotingReward(IVotingContract(votingContract), proposalId, reward);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM VOTING REWARDS                                  *|
|*----------------------------------------------------------*/

contract PWN_ClaimVotingReward_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    event VotingRewardClaimed(address indexed votingContract, uint256 indexed proposalId, address indexed voter, uint256 reward);

    function setUp() override public {
        super.setUp();

        vm.store(
            address(pwnToken),
            REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );
    }

    function test_shouldFail_whenZeroVotingContract() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroVotingContract.selector));
        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(address(0)), proposalId);
    }

    function test_shouldFail_whenProposalNotExecuted() external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, false /* executed */, proposalParameters, tally, actions, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalNotExecuted.selector));
        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

    function testFuzz_shouldFail_whenCallerHasNotVoted(address caller) external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)", proposalId, caller),
            abi.encode(IVotingContract.VoteOption.None)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.CallerHasNotVoted.selector));
        vm.prank(caller);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

    function test_shouldFail_whenNoRewardAssigned() external {
        vm.store(
            address(pwnToken),
            REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(0)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.ZeroReward.selector));
        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

    function test_shouldFail_whenVoterAlreadyClaimedReward() external {
        bytes32 claimedSlot = REWARDS_SLOT
            .withMappingKey(votingContract)
            .withMappingKey(proposalId)
            .withArrayIndex(1)
            .withMappingKey(voter);
        vm.store(address(pwnToken), claimedSlot, bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Error.RewardAlreadyClaimed.selector));
        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

    function test_shouldStoreThatVoterClaimedReward() external {
        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);

        bytes32 claimedSlot = REWARDS_SLOT
            .withMappingKey(votingContract)
            .withMappingKey(proposalId)
            .withArrayIndex(1)
            .withMappingKey(voter);
        bytes32 rewardClaimedValue = vm.load(address(pwnToken), claimedSlot);
        assertEq(uint256(rewardClaimedValue), 1);
    }

    function test_shouldUseProposalSnapshotAsPastVotesTimepoint() external {
        vm.expectCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch)
        );

        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

    function testFuzz_shouldMintRewardToCaller(
        uint256 _reward, uint256 noVotes, uint256 yesVotes, uint256 abstainVotes, uint256 votersPower
    ) external {
        reward = bound(_reward, 1, 100 ether);
        tally.no = bound(noVotes, 1, type(uint256).max / 3);
        tally.yes = bound(yesVotes, 1, type(uint256).max / 3);
        tally.abstain = bound(abstainVotes, 1, type(uint256).max / 3);
        uint256 totalPower = tally.no + tally.yes + tally.abstain;
        votersPower = bound(votersPower, 1, totalPower);
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(votersPower)
        );
        vm.store(
            address(pwnToken),
            REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );

        uint256 originalTotalSupply = pwnToken.totalSupply();
        uint256 originalBalance = pwnToken.balanceOf(voter);

        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);

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
        vm.store(
            address(pwnToken),
            REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );
        tally.no = 0;
        tally.yes = totalPower;
        tally.abstain = 0;
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(votersPower)
        );
        uint256 voterReward = Math.mulDiv(reward, votersPower, totalPower);

        vm.expectEmit();
        emit VotingRewardClaimed(votingContract, proposalId, voter, voterReward);

        vm.prank(voter);
        pwnToken.claimVotingReward(IVotingContract(votingContract), proposalId);
    }

}
