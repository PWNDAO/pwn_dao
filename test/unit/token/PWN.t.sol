// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IPWNTokenGovernance, IDAO } from "src/governance/token/IPWNTokenGovernance.sol";
import { Error } from "src/lib/Error.sol";
import { SlotComputingLib } from "src/lib/SlotComputingLib.sol";
import { PWN } from "src/token/PWN.sol";

import { Base_Test } from "test/Base.t.sol";

abstract contract PWN_Test is Base_Test {
    using SlotComputingLib for bytes32;

    bytes32 public constant TOTAL_SUPPLY_SLOT = bytes32(uint256(4));
    bytes32 public constant TRANSFER_ENABLED_SLOT = bytes32(uint256(7));
    bytes32 public constant TRANSFER_ALLOWLIST_SLOT = bytes32(uint256(8));
    bytes32 public constant OWNER_MINTED_AMOUNT_SLOT = bytes32(uint256(9));
    bytes32 public constant VOTING_REWARDS_SLOT = bytes32(uint256(10));
    bytes32 public constant PROPOSAL_REWARDS_SLOT = bytes32(uint256(11));

    PWN public pwnToken;

    address public owner = makeAddr("owner");
    address public votingContract = makeAddr("votingContract");
    address public votingToken = makeAddr("votingToken");
    address public voter = makeAddr("voter");
    uint256 public proposalId = 69;
    uint64 public snapshotEpoch = 420;
    uint256 public pastVotes = 100;
    uint256 public votingReward = 20;

    IPWNTokenGovernance.ProposalParameters public proposalParameters = IPWNTokenGovernance.ProposalParameters({
        supportThreshold: 0,
        startDate: 0,
        endDate: 0,
        snapshotEpoch: snapshotEpoch,
        minVotingPower: 0
    });
    IPWNTokenGovernance.Tally public tally = IPWNTokenGovernance.Tally({
        abstain: 100,
        yes: 200,
        no: 0
    });
    IDAO.Action[] public actions;

    function setUp() virtual public {
        vm.mockCall(
            votingContract,
            abi.encodeCall(IPWNTokenGovernance.getVotingToken, ()),
            abi.encode(votingToken)
        );
        vm.mockCall(
            votingContract,
            abi.encodeCall(IPWNTokenGovernance.getVoteOption, (proposalId, voter)),
            abi.encode(IPWNTokenGovernance.VoteOption.Yes)
        );
        vm.mockCall(
            votingContract,
            abi.encodeCall(IPWNTokenGovernance.getProposal, (proposalId)),
            abi.encode(false, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(pastVotes)
        );

        pwnToken = new PWN(owner);

        vm.prank(owner);
        pwnToken.enableTransfers();

        vm.store(address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(uint256(100_000_000 ether)));
        vm.store(address(pwnToken), VOTING_REWARDS_SLOT.withMappingKey(votingContract), bytes32(votingReward));
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
        assertEq(pwnToken.MAX_VOTING_REWARD(), 100);
        assertEq(pwnToken.VOTING_REWARD_DENOMINATOR(), 10000);
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWN_Constructor_Test is PWN_Test {

    function testFuzz_shouldSetInitialParams(address _owner) external {
        pwnToken = new PWN(_owner);

        assertEq(pwnToken.owner(), _owner);
    }

}


/*----------------------------------------------------------*|
|*  # ALLOWANCE                                             *|
|*----------------------------------------------------------*/

contract PWN_Allowance_Test is PWN_Test {

    address spender = makeAddr("spender");

    function test_shouldFailToCall_increaseAllowance() external {
        vm.expectRevert(abi.encodeWithSelector(Error.IncreaseAllowanceNotSupported.selector));
        pwnToken.increaseAllowance(spender, 1);
    }

    function test_shouldFailToCall_decreaseAllowance() external {
        vm.expectRevert(abi.encodeWithSelector(Error.DecreaseAllowanceNotSupported.selector));
        pwnToken.decreaseAllowance(spender, 1);
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
|*  # ENABLE TRANSFER                                       *|
|*----------------------------------------------------------*/

contract PWN_EnableTransfers_Test is PWN_Test {

    function setUp() override public virtual {
        super.setUp();

        // Reset transfer enabled flag
        vm.store(address(pwnToken), TRANSFER_ENABLED_SLOT, bytes32(0));
    }


    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.enableTransfers();
    }

    function test_shouldFail_whenTransferAlreadyEnabled() external {
        vm.store(address(pwnToken), TRANSFER_ENABLED_SLOT, bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersAlreadyEnabled.selector));
        vm.prank(owner);
        pwnToken.enableTransfers();
    }

    function test_shouldStorageTransferEnabledFlag() external {
        vm.prank(owner);
        pwnToken.enableTransfers();

        assertTrue(pwnToken.transfersEnabled());
    }

}


/*----------------------------------------------------------*|
|*  # SET TRANSFER ALLOWLIST                                *|
|*----------------------------------------------------------*/

contract PWN_SetTransferAllowlist_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.setTransferAllowlist(makeAddr("allowedAddr"), true);
    }

    function testFuzz_shouldSetTransferAllowlist(address allowedAddr, bool isAllowed) external {
        vm.prank(owner);
        pwnToken.setTransferAllowlist(allowedAddr, isAllowed);

        bytes32 isAllowedValue = vm.load(address(pwnToken), TRANSFER_ALLOWLIST_SLOT.withMappingKey(allowedAddr));
        assertEq(isAllowed, uint256(isAllowedValue) == 1 ? true : false);
    }

}


/*----------------------------------------------------------*|
|*  # SET VOTING REWARD                                     *|
|*----------------------------------------------------------*/

contract PWN_SetVotingReward_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    event VotingRewardSet(address indexed votingContract, uint256 votingReward);


    function testFuzz_shouldFail_whenCallerNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        pwnToken.setVotingReward(votingContract, votingReward);
    }

    function test_shouldFail_whenVotingContractZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroVotingContract.selector));
        vm.prank(owner);
        pwnToken.setVotingReward(address(0), votingReward);
    }

    function test_shouldFail_whenVotingRewardBiggerThanMax(uint256 _votingReward) external {
        votingReward = bound(_votingReward, pwnToken.MAX_VOTING_REWARD() + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Error.InvalidVotingReward.selector));
        vm.prank(owner);
        pwnToken.setVotingReward(votingContract, votingReward);
    }

    function testFuzz_shouldStoreVotingReward(address _votingContract, uint256 _votingReward)
        external
        checkAddress(_votingContract)
    {
        votingReward = bound(_votingReward, 0, pwnToken.MAX_VOTING_REWARD());

        vm.prank(owner);
        pwnToken.setVotingReward(_votingContract, votingReward);

        bytes32 votingRewardValue = vm.load(address(pwnToken), VOTING_REWARDS_SLOT.withMappingKey(_votingContract));
        assertEq(uint256(votingRewardValue), votingReward);
    }

    function testFuzz_shouldEmit_VotingRewardSet(address _votingContract, uint256 _votingReward)
        external
        checkAddress(_votingContract)
    {
        votingReward = bound(_votingReward, 0, pwnToken.MAX_VOTING_REWARD());

        vm.expectEmit();
        emit VotingRewardSet(_votingContract, votingReward);

        vm.prank(owner);
        pwnToken.setVotingReward(_votingContract, votingReward);
    }

}


/*----------------------------------------------------------*|
|*  # ASSIGN PROPOSAL REWARD                                *|
|*----------------------------------------------------------*/

contract PWN_AssignProposalReward_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    event ProposalRewardAssigned(
        address indexed votingContract,
        uint256 indexed proposalId,
        uint256 reward
    );

    function _proposalReward(uint256 votingReward) private view returns (uint256) {
        return pwnToken.totalSupply() * votingReward / pwnToken.VOTING_REWARD_DENOMINATOR();
    }


    function testFuzz_shouldNotStoreAssignedReward_whenVotingRewardNotSetForCaller(address caller) external {
        vm.assume(caller != votingContract);

        vm.prank(caller);
        pwnToken.assignProposalReward(proposalId);

        bytes32 rewardValue = vm.load(
            address(pwnToken), PROPOSAL_REWARDS_SLOT.withMappingKey(caller).withMappingKey(proposalId)
        );
        assertEq(uint256(rewardValue), 0);
    }

    function testFuzz_shouldNotUpdateAssignedReward_whenProposalRewardAlreadySet(uint256 currentReward) external {
        currentReward = bound(currentReward, 1, type(uint256).max);
        bytes32 slot = PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId);
        vm.store(address(pwnToken), slot, bytes32(currentReward));

        vm.prank(votingContract);
        pwnToken.assignProposalReward(proposalId);

        bytes32 rewardValue = vm.load(address(pwnToken), slot);
        assertEq(uint256(rewardValue), currentReward);
    }

    function testFuzz_shouldStoreAssignedReward(uint256 totalSupply, uint256 _votingReward) external {
        totalSupply = bound(totalSupply, 100, type(uint104).max);
        vm.store(address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(totalSupply));
        votingReward = bound(_votingReward, 1, pwnToken.MAX_VOTING_REWARD());
        vm.store(address(pwnToken), VOTING_REWARDS_SLOT.withMappingKey(votingContract), bytes32(votingReward));

        vm.prank(votingContract);
        pwnToken.assignProposalReward(proposalId);

        bytes32 rewardValue = vm.load(
            address(pwnToken), PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId)
        );
        assertEq(uint256(rewardValue), _proposalReward(votingReward));
    }

    function test_shouldNotMintNewTokens() external {
        uint256 originalTotalSupply = pwnToken.totalSupply();

        vm.prank(votingContract);
        pwnToken.assignProposalReward(proposalId);

        assertEq(originalTotalSupply, pwnToken.totalSupply());
    }

    function testFuzz_shouldEmit_ProposalRewardAssigned(uint256 totalSupply, uint256 _votingReward) external {
        totalSupply = bound(totalSupply, 100, type(uint104).max);
        votingReward = bound(_votingReward, 1, pwnToken.MAX_VOTING_REWARD());
        vm.store(address(pwnToken), TOTAL_SUPPLY_SLOT, bytes32(totalSupply));
        vm.store(address(pwnToken), VOTING_REWARDS_SLOT.withMappingKey(votingContract), bytes32(votingReward));

        vm.expectEmit();
        emit ProposalRewardAssigned(votingContract, proposalId, _proposalReward(votingReward));

        vm.prank(votingContract);
        pwnToken.assignProposalReward(proposalId);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM PROPOSAL REWARD BATCH                           *|
|*----------------------------------------------------------*/

contract PWN_ClaimProposalRewardBatch_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    event ProposalRewardClaimed(
        address indexed votingContract,
        uint256 indexed proposalId,
        address indexed voter,
        uint256 voterReward
    );

    uint256 public reward = 100 ether;
    uint256[] public proposalIds;

    function setUp() override public {
        super.setUp();

        proposalIds = new uint256[](3);
        proposalIds[0] = 1;
        proposalIds[1] = 2;
        proposalIds[2] = 3;

        for (uint256 i; i < proposalIds.length; ++i) {
            vm.store(
                address(pwnToken),
                PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalIds[i]),
                bytes32(reward)
            );
        }

        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)"),
            abi.encode(false, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)"),
            abi.encode(IPWNTokenGovernance.VoteOption.Yes)
        );
    }


    function test_shouldFail_whenZeroVotingContract() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroVotingContract.selector));
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(address(0), proposalIds);
    }

    function test_shouldFail_whenNoRewardAssigned() external {
        proposalIds[2] = 5; // set non-existing proposal id

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalRewardNotAssigned.selector, 5));
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

    function test_shouldFail_whenProposalNotExecuted() external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalIds[2]),
            abi.encode(true, false /* executed */, proposalParameters, tally, actions, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalNotExecuted.selector, proposalIds[2]));
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

    function test_shouldFail_whenCallerHasNotVoted() external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)", proposalIds[2], voter),
            abi.encode(IPWNTokenGovernance.VoteOption.None)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.CallerHasNotVoted.selector));
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

    function test_shouldFail_whenVoterAlreadyClaimedReward() external {
        bytes32 claimedSlot = PROPOSAL_REWARDS_SLOT
            .withMappingKey(votingContract)
            .withMappingKey(proposalIds[2])
            .withArrayIndex(1)
            .withMappingKey(voter);
        vm.store(address(pwnToken), claimedSlot, bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalRewardAlreadyClaimed.selector, proposalIds[2]));
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

    function test_shouldStoreThatVoterClaimedReward() external {
        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);

        for (uint256 i; i < proposalIds.length; ++i) {
            bytes32 claimedSlot = PROPOSAL_REWARDS_SLOT
                .withMappingKey(votingContract)
                .withMappingKey(proposalIds[i])
                .withArrayIndex(1)
                .withMappingKey(voter);
            bytes32 rewardClaimedValue = vm.load(address(pwnToken), claimedSlot);
            assertEq(uint256(rewardClaimedValue), 1);
        }
    }

    function test_shouldUseProposalSnapshotAsPastVotesTimepoint() external {
        vm.expectCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch)
        );

        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

    function test_shouldMintRewardToCaller() external {
        uint256 totalPower = tally.no + tally.yes + tally.abstain;
        uint256 originalTotalSupply = pwnToken.totalSupply();
        uint256 originalBalance = pwnToken.balanceOf(voter);

        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);

        uint256 voterReward = Math.mulDiv(reward, pastVotes, totalPower) * proposalIds.length;
        assertEq(originalTotalSupply + voterReward, pwnToken.totalSupply());
        assertEq(originalBalance + voterReward, pwnToken.balanceOf(voter));
    }

    function test_shouldEmit_VotingRewardClaimed() external {
        uint256 totalPower = tally.no + tally.yes + tally.abstain;
        uint256 voterReward = Math.mulDiv(reward, pastVotes, totalPower);

        for (uint256 i; i < proposalIds.length; ++i) {
            vm.expectEmit();
            emit ProposalRewardClaimed(votingContract, proposalIds[i], voter, voterReward);
        }

        vm.prank(voter);
        pwnToken.claimProposalRewardBatch(votingContract, proposalIds);
    }

}


/*----------------------------------------------------------*|
|*  # CLAIM PROPOSAL REWARD                                 *|
|*----------------------------------------------------------*/

contract PWN_ClaimProposalReward_Test is PWN_Test {
    using SlotComputingLib for bytes32;

    event ProposalRewardClaimed(
        address indexed votingContract,
        uint256 indexed proposalId,
        address indexed voter,
        uint256 voterReward
    );

    uint256 public reward = 100 ether;

    function setUp() override public {
        super.setUp();

        vm.store(
            address(pwnToken),
            PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );
    }


    function test_shouldFail_whenZeroVotingContract() external {
        vm.expectRevert(abi.encodeWithSelector(Error.ZeroVotingContract.selector));
        vm.prank(voter);
        pwnToken.claimProposalReward(address(0), proposalId);
    }

    function test_shouldFail_whenNoRewardAssigned() external {
        vm.store(
            address(pwnToken),
            PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(uint256(0))
        );

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalRewardNotAssigned.selector, proposalId));
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);
    }

    function test_shouldFail_whenProposalNotExecuted() external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(true, false /* executed */, proposalParameters, tally, actions, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalNotExecuted.selector, proposalId));
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);
    }

    function testFuzz_shouldFail_whenCallerHasNotVoted(address caller) external {
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)", proposalId, caller),
            abi.encode(IPWNTokenGovernance.VoteOption.None)
        );

        vm.expectRevert(abi.encodeWithSelector(Error.CallerHasNotVoted.selector));
        vm.prank(caller);
        pwnToken.claimProposalReward(votingContract, proposalId);
    }

    function test_shouldFail_whenVoterAlreadyClaimedReward() external {
        bytes32 claimedSlot = PROPOSAL_REWARDS_SLOT
            .withMappingKey(votingContract)
            .withMappingKey(proposalId)
            .withArrayIndex(1)
            .withMappingKey(voter);
        vm.store(address(pwnToken), claimedSlot, bytes32(uint256(1)));

        vm.expectRevert(abi.encodeWithSelector(Error.ProposalRewardAlreadyClaimed.selector, proposalId));
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);
    }

    function test_shouldStoreThatVoterClaimedReward() external {
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);

        bytes32 claimedSlot = PROPOSAL_REWARDS_SLOT
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
        pwnToken.claimProposalReward(votingContract, proposalId);
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
            abi.encode(false, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(votersPower)
        );
        vm.store(
            address(pwnToken),
            PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );

        uint256 originalTotalSupply = pwnToken.totalSupply();
        uint256 originalBalance = pwnToken.balanceOf(voter);

        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);

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
            PROPOSAL_REWARDS_SLOT.withMappingKey(votingContract).withMappingKey(proposalId),
            bytes32(reward)
        );
        tally.no = 0;
        tally.yes = totalPower;
        tally.abstain = 0;
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(false, true, proposalParameters, tally, actions, 0)
        );
        vm.mockCall(
            votingToken,
            abi.encodeWithSignature("getPastVotes(address,uint256)", voter, snapshotEpoch),
            abi.encode(votersPower)
        );
        uint256 voterReward = Math.mulDiv(reward, votersPower, totalPower);

        vm.expectEmit();
        emit ProposalRewardClaimed(votingContract, proposalId, voter, voterReward);

        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);
    }

}


/*----------------------------------------------------------*|
|*  # TRANSFER CALLBACK                                     *|
|*----------------------------------------------------------*/

contract PWN_TransferCallback_Test is PWN_Test {

    function setUp() override public {
        super.setUp();

        vm.startPrank(owner);
        pwnToken.mint(1 ether);
        pwnToken.setTransferAllowlist(owner, true);
        vm.stopPrank();

        // Reset transfer enabled flag
        vm.store(address(pwnToken), TRANSFER_ENABLED_SLOT, bytes32(0));
    }


    function test_shouldAllowMint() external {
        vm.prank(owner);
        pwnToken.mint(1 ether);
    }

    function test_shouldAllowBurn() external {
        vm.prank(owner);
        pwnToken.burn(1 ether);
    }

    function testFuzz_shouldAllowTransfer_whenTransfersEnabled(address caller) external {
        vm.assume(caller != owner && caller != address(0));

        vm.startPrank(owner);
        pwnToken.enableTransfers();
        pwnToken.transfer(caller, 1 ether);
        vm.stopPrank();

        vm.prank(caller);
        pwnToken.transfer(owner, 1 ether);
    }

    function testFuzz_shouldAllowTransfer_whenTransfersDisabled_whenAddrInAllowlist_whenCallerOwner(address caller) external {
        vm.assume(caller != owner && caller != address(0));

        vm.startPrank(owner);
        pwnToken.setTransferAllowlist(caller, true);
        pwnToken.transfer(caller, 1 ether);
        vm.stopPrank();

        vm.prank(caller);
        pwnToken.transfer(owner, 1 ether);
    }

    function testFuzz_shouldAllowTransfer_whenTransfersDisabled_whenAddrInAllowlist_whenCallerOperator(address caller) external {
        vm.assume(caller != owner && caller != address(0));
        address from = makeAddr("from");

        vm.startPrank(owner);
        pwnToken.setTransferAllowlist(caller, true);
        pwnToken.transfer(from, 1 ether);
        vm.stopPrank();

        vm.prank(from);
        pwnToken.approve(caller, 1 ether);

        vm.prank(caller);
        pwnToken.transferFrom(from, owner, 1 ether);
    }

    function testFuzz_shouldBlockTransfer_whenTransfersDisabled_whenAddrNotInAllowlist(address caller) external {
        vm.assume(caller != owner && caller != address(0));

        vm.prank(owner);
        pwnToken.transfer(caller, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Error.TransfersDisabled.selector));
        vm.prank(caller);
        pwnToken.transfer(owner, 1 ether);
    }

}
