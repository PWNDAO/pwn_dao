// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IVotingContract } from "./interfaces/IVotingContract.sol";
import { Error } from "./lib/Error.sol";

/// @title PWN token contract.
/// @notice The token is the main governance token of the PWN DAO and is used
/// as a reward for voting in proposals.
/// @dev This contract is Ownable2Step, which means that the ownership transfer
/// must be accepted by the new owner.
/// The token is mintable and burnable by the owner.
contract PWN is Ownable2Step, ERC20 {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The total supply of the token that can be minted by the owner.
    uint256 public constant MINTABLE_TOTAL_SUPPLY = 100_000_000e18; // 100M PWN tokens
    /// @notice The numerator of the voting reward that is assigned to a proposal.
    /// @dev The voting reward is calculated from the current total supply.
    uint256 public constant VOTING_REWARD = 20; // 0.2%
    /// @notice The denominator of the voting reward.
    uint256 public constant VOTING_REWARD_DENOMINATOR = 10000;
    /// @notice The immutable period (in epochs) after which voting rewards can be set.
    uint256 public constant IMMUTABLE_PERIOD = 26; // ~2 years

    /// @notice Amount of tokens already minted by the owner.
    uint256 public mintedSupply;

    /// The reward for voting in a proposal.
    struct VotingReward {
        uint256 reward;
        mapping(address voter => bool claimed) claimed;
    }
    /// @notice The reward for voting in a proposal.
    /// @dev The voters reward is proportional to the amount of votes the voter had in the snapshot epoch.
    mapping(address votingContract => mapping(uint256 proposalId => VotingReward reward)) public votingRewards;

    /// @notice The validity of a voting contract.
    /// @dev The validity of a voting contract is used to check if the contract can be used to assign rewards.
    mapping(address votingContract => bool isValid) public validVotingContracts;


    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when the owner assigns a reward to a voting proposal.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    /// @param reward The reward amount.
    event VotingRewardAssigned(
        address indexed votingContract,
        uint256 indexed proposalId,
        uint256 reward
    );

    /// @notice Emitted when a voter claims his reward for voting in a proposal.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    /// @param voter The voter address.
    /// @param voterReward The voters reward amount.
    event VotingRewardClaimed(
        address indexed votingContract,
        uint256 indexed proposalId,
        address indexed voter,
        uint256 voterReward
    );


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    /// @notice PWN token constructor.
    /// @dev The owner must be the PWN DAO.
    /// @param _owner The owner address.
    constructor(address _owner) ERC20("PWN DAO", "PWN") {
        _transferOwnership(_owner);
    }


    /*----------------------------------------------------------*|
    |*  # MANAGE SUPPLY                                         *|
    |*----------------------------------------------------------*/

    /// @notice Mints new tokens.
    /// @dev The owner can mint tokens only until the `MINTABLE_TOTAL_SUPPLY` is reached.
    /// Newly minted tokens are automatically assigned to the caller.
    /// @param amount The amount of tokens to mint.
    function mint(uint256 amount) external onlyOwner {
        if (mintedSupply + amount > MINTABLE_TOTAL_SUPPLY) {
            revert Error.MintableSupplyExceeded();
        }
        unchecked {
            mintedSupply += amount;
        }
        _mint(msg.sender, amount);
    }

    /// @notice Burns tokens.
    /// It doens't increase the number of tokens that can be minted by the owner.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }


    /*----------------------------------------------------------*|
    |*  # VOTING REWARDS                                        *|
    |*----------------------------------------------------------*/

    /// @notice Sets the validity of a voting contract.
    /// @dev The validity of a voting contract is used to check if the contract can be used to assign rewards.
    /// @param votingContract The voting contract address.
    /// @param isValid The validity of the voting contract.
    function setVotingContract(address votingContract, bool isValid) external onlyOwner {
        if (votingContract == address(0)) {
            revert Error.ZeroVotingContract();
        }
        validVotingContracts[votingContract] = isValid;
    }

    /// @notice Assigns a reward to a voting proposal.
    /// @dev The reward can be assigned only by the owner after the immutable period for an executed proposal.
    /// The reward is calculated as 0.2% of the current total supply.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    function assignVotingReward(address votingContract, uint256 proposalId) external onlyOwner {
        if (votingContract == address(0)) {
            revert Error.ZeroVotingContract();
        }
        if (!validVotingContracts[votingContract]) {
            revert Error.InvalidVotingContract();
        }
        // check that the reward has not been assigned yet
        VotingReward storage votingReward = votingRewards[votingContract][proposalId];
        if (votingReward.reward != 0) {
            revert Error.RewardAlreadyAssigned(votingReward.reward);
        }
        ( // get proposal data
            , bool executed, IVotingContract.ProposalParameters memory proposalParameters,,,
        ) = IVotingContract(votingContract).getProposal(proposalId);
        // check that the proposal has been executed
        if (!executed) {
            revert Error.ProposalNotExecuted();
        }
        // check that the proposal is not in the immutable period
        if (proposalParameters.snapshotEpoch <= IMMUTABLE_PERIOD) { // expecting the first epoch to be number 1
            revert Error.ProposalSnapshotInImmutablePeriod();
        }

        // assign the reward
        uint256 reward = Math.mulDiv(totalSupply(), VOTING_REWARD, VOTING_REWARD_DENOMINATOR);
        votingReward.reward = reward;

        emit VotingRewardAssigned(votingContract, proposalId, reward);
    }

    /// @notice Claims the reward for voting in a proposal.
    /// @dev The reward can be claimed only if the proposal has been executed and the caller has voted.
    /// It doesn't matter if the caller voted yes, no or abstained.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    function claimVotingReward(address votingContract, uint256 proposalId) external {
        if (votingContract == address(0)) {
            revert Error.ZeroVotingContract();
        }
        // check that the reward has been assigned
        VotingReward storage votingReward = votingRewards[votingContract][proposalId];
        uint256 assignedReward = votingReward.reward;
        if (assignedReward == 0) {
            revert Error.RewardNotAssigned();
        }
        ( // get proposal data
            ,, IVotingContract.ProposalParameters memory proposalParameters, IVotingContract.Tally memory tally,,
        ) = IVotingContract(votingContract).getProposal(proposalId);
        // check that the caller has voted
        address voter = msg.sender;
        if (IVotingContract(votingContract).getVoteOption(proposalId, voter) == IVotingContract.VoteOption.None) {
            revert Error.CallerHasNotVoted();
        }
        // check that the reward has not been claimed yet
        if (votingReward.claimed[voter]) {
            revert Error.RewardAlreadyClaimed();
        }
        // store that the reward has been claimed
        votingReward.claimed[voter] = true;

        // voter is rewarded proportionally to the amount of votes he had in the snapshot epoch
        // it doesn't matter if he voted yes, no or abstained
        uint256 voterVotes = IVotingContract(votingContract).getVotingToken()
            .getPastVotes(voter, proposalParameters.snapshotEpoch);
        uint256 totalVotes = tally.abstain + tally.yes + tally.no;
        uint256 voterReward = Math.mulDiv(assignedReward, voterVotes, totalVotes);

        // mint the reward to the voter
        _mint(voter, voterReward);

        emit VotingRewardClaimed(votingContract, proposalId, voter, voterReward);
    }

}
