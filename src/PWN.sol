// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IVotingContract } from "./interfaces/IVotingContract.sol";
import { Error } from "./lib/Error.sol";
import { PWNEpochClock } from "./PWNEpochClock.sol";

contract PWN is Ownable2Step, ERC20 {

    // # INVARIANTS
    // - owner can mint max MINTABLE_TOTAL_SUPPLY regardless of burned amount
    // - after reaching the IMMUTABLE_PERIOD, token can be inflated by MAX_INFLATION_RATE
    // - voting reward per proposal can be assigned only once
    // - voting reward can be claimed only once per proposal per voter

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public constant MINTABLE_TOTAL_SUPPLY = 100_000_000e18;
    uint256 public constant MAX_INFLATION_RATE = 20; // max inflation rate (2 decimals) after immutable period
    uint256 public constant INFLATION_DENOMINATOR = 10000; // 2 decimals
    uint256 public constant IMMUTABLE_PERIOD = 65; // ~5 years in epochs

    // solhint-disable-next-line immutable-vars-naming, var-name-mixedcase
    uint256 public immutable INITIAL_EPOCH;

    /// Amount of tokens already minted by the owner
    uint256 public mintedSupply;

    struct VotingReward {
        uint256 reward;
        mapping(address voter => bool claimed) claimed;
    }
    mapping(address votingContract => mapping(uint256 proposalId => VotingReward reward)) public votingRewards;


    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event VotingRewardAssigned(address indexed votingContract, uint256 indexed proposalId, uint256 reward);
    event VotingRewardClaimed(
        address indexed votingContract, uint256 indexed proposalId, address indexed voter, uint256 reward
    );


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _owner, address _epochClock) ERC20("PWN DAO", "PWN") {
        _transferOwnership(_owner);
        INITIAL_EPOCH = PWNEpochClock(_epochClock).currentEpoch();
    }


    /*----------------------------------------------------------*|
    |*  # MANAGE SUPPLY                                         *|
    |*----------------------------------------------------------*/

    function mint(uint256 amount) external onlyOwner {
        if (mintedSupply + amount > MINTABLE_TOTAL_SUPPLY) {
            revert Error.MintableSupplyExceeded();
        }
        unchecked {
            mintedSupply += amount;
        }
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }


    /*----------------------------------------------------------*|
    |*  # VOTING REWARDS                                        *|
    |*----------------------------------------------------------*/

    // can be assigned only once
    function assignVotingReward(
        IVotingContract votingContract, uint256 proposalId, uint256 reward
    ) external onlyOwner {
        if (address(votingContract) == address(0)) {
            revert Error.ZeroVotingContract();
        }

        (
            ,, IVotingContract.ProposalParameters memory proposalParameters,,,
        ) = votingContract.getProposal(proposalId);

        if (proposalParameters.snapshotEpoch - INITIAL_EPOCH < IMMUTABLE_PERIOD) {
            revert Error.InImmutablePeriod();
        }
        uint256 maxReward = Math.mulDiv(totalSupply(), MAX_INFLATION_RATE, INFLATION_DENOMINATOR);
        if (reward > maxReward) {
            revert Error.RewardTooHigh(maxReward);
        }
        if (reward == 0) {
            revert Error.ZeroReward();
        }
        VotingReward storage currentReward = votingRewards[address(votingContract)][proposalId];
        if (currentReward.reward > 0) {
            revert Error.RewardAlreadyAssigned(currentReward.reward);
        }

        currentReward.reward = reward;

        emit VotingRewardAssigned(address(votingContract), proposalId, reward);
    }

    function claimVotingReward(IVotingContract votingContract, uint256 proposalId) external {
        address voter = msg.sender;
        if (address(votingContract) == address(0)) {
            revert Error.ZeroVotingContract();
        }
        (
            , bool executed,
            IVotingContract.ProposalParameters memory proposalParameters,
            IVotingContract.Tally memory tally,,
        ) = votingContract.getProposal(proposalId);
        if (!executed) {
            revert Error.ProposalNotExecuted();
        }
        if (votingContract.getVoteOption(proposalId, voter) == IVotingContract.VoteOption.None) {
            revert Error.CallerHasNotVoted();
        }
        VotingReward storage currentReward = votingRewards[address(votingContract)][proposalId];
        if (currentReward.reward == 0) {
            revert Error.ZeroReward();
        }
        if (currentReward.claimed[voter]) {
            revert Error.RewardAlreadyClaimed();
        }
        currentReward.claimed[voter] = true;

        // voter is rewarded proportionally to the amount of votes he had at the snapshot
        // it doesn't matter if he voted yes, no or abstained
        uint256 callerVotes = votingContract.getVotingToken().getPastVotes(voter, proposalParameters.snapshotEpoch);
        uint256 totalVotes = tally.abstain + tally.yes + tally.no;
        uint256 reward = Math.mulDiv(currentReward.reward, callerVotes, totalVotes);

        _mint(voter, reward);

        emit VotingRewardClaimed(address(votingContract), proposalId, voter, reward);
    }

}
