// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { TransparentUpgradeableProxy }
    from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IVotingContract } from "src/interfaces/IVotingContract.sol";
import { PWN } from "src/PWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";
import { StakedPWN } from "src/StakedPWN.sol";
import { VoteEscrowedPWN } from "src/VoteEscrowedPWN.sol";

import { Base_Test } from "../Base.t.sol";

interface IAragonDAOLike {
    struct Action {
        address to;
        uint256 value;
        bytes data;
    }

    // solhint-disable-next-line foundry-test-functions
    function execute(
        bytes32 callId,
        Action[] memory actions,
        uint256 allowFailureMap
    ) external returns (bytes[] memory, uint256);
}

contract PWN_ForkTest is Base_Test {

    PWN public pwnToken;
    PWNEpochClock public epochClock;
    StakedPWN public stPWN;
    VoteEscrowedPWN public vePWN;

    address public dao = vm.envAddress("DAO");
    address public governancePlugin = vm.envAddress("GOVERNANCE_PLUGIN");

    address public voter = makeAddr("voter");
    address public votingContract = makeAddr("votingContract");

    function setUp() external {
        vm.createSelectFork("ethereum");

        // deploy contracts
        epochClock = new PWNEpochClock(block.timestamp);
        pwnToken = new PWN(dao);
        VoteEscrowedPWN vePWNImpl = new VoteEscrowedPWN();
        vePWN = VoteEscrowedPWN(address(
            new TransparentUpgradeableProxy(address(vePWNImpl), makeAddr("protocolTimelock"), "")
        ));
        stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock), dao);

        vm.startPrank(dao);
        pwnToken.mint(pwnToken.MINTABLE_TOTAL_SUPPLY());
        pwnToken.transfer(voter, 100e18);
        vm.stopPrank();

        // label addresses for debugging
        vm.label(address(pwnToken), "PWN Token");
        vm.label(address(epochClock), "PWN Epoch Clock");
        vm.label(address(stPWN), "Staked PWN");
        vm.label(address(vePWN), "Vote Escrowed PWN");
        vm.label(voter, "Voter");
        vm.label(dao, "DAO");
    }


    function testFork_shouldAssignProposalRewardAndClaimProposalReward() external {
        uint256 proposalId = 3;
        IAragonDAOLike _dao = IAragonDAOLike(dao);

        vm.startPrank(voter);
        pwnToken.approve(address(vePWN), 100e18);
        vePWN.createStake(100e18, 130); // 350 power
        vm.stopPrank();

        // get over immutable period => epoch 28
        vm.warp(block.timestamp + epochClock.SECONDS_IN_EPOCH() * 27);

        IVotingContract.ProposalParameters memory proposalParameters = IVotingContract.ProposalParameters({
            votingMode: IVotingContract.VotingMode.Standard,
            supportThreshold: 0,
            startDate: 0,
            endDate: 0,
            snapshotEpoch: 27,
            minVotingPower: 0
        });
        // not important for assigning reward
        IVotingContract.Tally memory proposalTally = IVotingContract.Tally({
            abstain: 0,
            yes: 350e18,
            no: 0
        });
        // not important for assigning reward
        IVotingContract.Action[] memory proposalActions = new IVotingContract.Action[](0);

        // mock voting contract
        // todo: use deployed voting contract
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getProposal(uint256)", proposalId),
            abi.encode(false, true, proposalParameters, proposalTally, proposalActions, 0)
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVotingToken()"),
            abi.encode(address(vePWN))
        );
        vm.mockCall(
            votingContract,
            abi.encodeWithSignature("getVoteOption(uint256,address)", proposalId, voter),
            abi.encode(IVotingContract.VoteOption.Yes)
        );

        IAragonDAOLike.Action[] memory actions = new IAragonDAOLike.Action[](2);
        actions[0] = IAragonDAOLike.Action({ // set voting reward to 1%
            to: address(pwnToken),
            value: 0,
            data: abi.encodeWithSelector(pwnToken.setVotingReward.selector, votingContract, 100) // 1%
        });
        actions[1] = IAragonDAOLike.Action({ // assign proposal reward
            to: address(pwnToken),
            value: 0,
            data: abi.encodeWithSelector(pwnToken.assignProposalReward.selector, votingContract, proposalId)
        });

        // execute the proposal
        vm.prank(governancePlugin);
        _dao.execute({
            callId: bytes32(proposalId),
            actions: actions,
            allowFailureMap: 0
        });

        uint256 originalBalance = pwnToken.balanceOf(voter);
        // claim proposal reward
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);

        assertEq(pwnToken.balanceOf(voter), originalBalance + 1_000_000e18);
    }

}
