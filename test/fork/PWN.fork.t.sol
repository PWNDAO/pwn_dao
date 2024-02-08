// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { TransparentUpgradeableProxy }
    from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IPWNTokenGovernance, IDAO } from "src/governance/token/IPWNTokenGovernance.sol";
import { PWN } from "src/token/PWN.sol";
import { StakedPWN } from "src/token/StakedPWN.sol";
import { VoteEscrowedPWN } from "src/token/VoteEscrowedPWN.sol";
import { PWNEpochClock } from "src/PWNEpochClock.sol";

import { Base_Test } from "../Base.t.sol";

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
            new TransparentUpgradeableProxy({
                _logic: address(vePWNImpl),
                admin_: dao,
                _data: ""
            })
        ));
        stPWN = new StakedPWN(dao, address(epochClock), address(vePWN));

        vePWN.initialize(address(pwnToken), address(stPWN), address(epochClock));

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
        IDAO _dao = IDAO(dao);

        vm.startPrank(voter);
        pwnToken.approve(address(vePWN), 100e18);
        vePWN.createStake(100e18, 130); // 350 power
        vm.stopPrank();

        // get over immutable period => epoch 28
        vm.warp(block.timestamp + epochClock.SECONDS_IN_EPOCH() * 27);

        IPWNTokenGovernance.ProposalParameters memory proposalParameters = IPWNTokenGovernance.ProposalParameters({
            votingMode: IPWNTokenGovernance.VotingMode.Standard,
            supportThreshold: 0,
            startDate: 0,
            endDate: 0,
            snapshotEpoch: 27,
            minVotingPower: 0
        });
        // not important for assigning reward
        IPWNTokenGovernance.Tally memory proposalTally = IPWNTokenGovernance.Tally({
            abstain: 0,
            yes: 350e18,
            no: 0
        });
        // not important for assigning reward
        IDAO.Action[] memory proposalActions = new IDAO.Action[](0);

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
            abi.encode(IPWNTokenGovernance.VoteOption.Yes)
        );

        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0] = IDAO.Action({ // set voting reward to 1%
            to: address(pwnToken),
            value: 0,
            data: abi.encodeWithSelector(pwnToken.setVotingReward.selector, votingContract, 100) // 1%
        });
        actions[1] = IDAO.Action({ // assign proposal reward
            to: address(pwnToken),
            value: 0,
            data: abi.encodeWithSelector(pwnToken.assignProposalReward.selector, votingContract, proposalId)
        });

        // execute the proposal
        vm.prank(governancePlugin);
        _dao.execute({
            _callId: bytes32(proposalId),
            _actions: actions,
            _allowFailureMap: 0
        });

        uint256 originalBalance = pwnToken.balanceOf(voter);
        // claim proposal reward
        vm.prank(voter);
        pwnToken.claimProposalReward(votingContract, proposalId);

        assertEq(pwnToken.balanceOf(voter), originalBalance + 1_000_000e18);
    }

}
