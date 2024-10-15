// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IPWNTokenGovernance } from "src/governance/token/IPWNTokenGovernance.sol";
import { IRewardToken } from "src/interfaces/IRewardToken.sol";
import { Error } from "src/lib/Error.sol";

/// @title PWN token contract.
/// @notice The token is the main governance token of the PWN DAO and is used
/// as a reward for voting in proposals.
/// @dev This contract is Ownable2Step, which means that the ownership transfer
/// must be accepted by the new owner.
/// The token is mintable and burnable by the owner.
contract PWN is Ownable2Step, ERC20, IRewardToken {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The total supply of the token that can be minted by the owner.
    uint256 public constant MINTABLE_TOTAL_SUPPLY = 100_000_000e18; // 100M PWN tokens
    /// @notice The maximum voting reward nominator that can be set to a voting contract.
    uint256 public constant MAX_VOTING_REWARD = 100; // 1%
    /// @notice The denominator of the voting reward.
    uint256 public constant VOTING_REWARD_DENOMINATOR = 10000;

    /// @notice The flag that enables token transfers.
    bool public transfersEnabled;

    /// @notice The list of addresses that are allowed to transfer tokens even before the transfers are enabled.
    mapping (address addr => bool allowed) public transferAllowlist;

    /// @notice Amount of tokens already minted by the owner.
    uint256 public mintedSupply;

    /// @notice Percentage of the total supply that can be assigned as a reward for voting in the voting contract.
    /// @dev The reward cannot be set to more than `MAX_VOTING_REWARD` of the total supply.
    /// The reward is divided by `VOTING_REWARD_DENOMINATOR` to get the actual percentage.
    mapping(address votingContract => uint256 reward) public votingRewards;

    /// The reward for voting in a proposal.
    struct ProposalReward {
        uint256 reward;
        mapping(address voter => bool claimed) claimed;
    }
    /// @notice Assigned reward for voting in a proposal.
    /// @dev The voters reward is proportional to the amount of votes the voter had in the snapshot epoch.
    mapping(address votingContract => mapping(uint256 proposalId => ProposalReward reward)) public proposalRewards;


    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when the owner sets the reward for voting in a voting contract.
    /// @param votingContract The voting contract address.
    /// @param votingReward The voting reward nominator.
    event VotingRewardSet(address indexed votingContract, uint256 votingReward);

    /// @notice Emitted when the owner assigns a reward to a governance proposal.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    /// @param reward The reward amount.
    event ProposalRewardAssigned(
        address indexed votingContract,
        uint256 indexed proposalId,
        uint256 reward
    );

    /// @notice Emitted when a voter claims his reward for voting in a proposal.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    /// @param voter The voter address.
    /// @param voterReward The voters reward amount.
    event ProposalRewardClaimed(
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
    |*  # ALLOWANCE                                             *|
    |*----------------------------------------------------------*/

    /// @inheritdoc ERC20
    function increaseAllowance(address /* spender */, uint256 /* addedValue */) public override pure returns (bool) {
        revert Error.IncreaseAllowanceNotSupported();
    }

    /// @inheritdoc ERC20
    function decreaseAllowance(address /* spender */, uint256 /* addedValue */) public override pure returns (bool) {
        revert Error.DecreaseAllowanceNotSupported();
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
    /// It doesn't increase the number of tokens that can be minted by the owner.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER SWITCH                                       *|
    |*----------------------------------------------------------*/

    /// @notice Enables token transfers.
    /// @dev Only the owner can enable transfers.
    function enableTransfers() external onlyOwner {
        if (transfersEnabled) {
            revert Error.TransfersAlreadyEnabled();
        }
        transfersEnabled = true;
    }

    /// @notice Enable or disable token transfers for a specific address.
    /// @dev Only the owner can call this function.
    function setTransferAllowlist(address addr, bool isAllowed) external onlyOwner {
        transferAllowlist[addr] = isAllowed;
    }


    /*----------------------------------------------------------*|
    |*  # VOTING REWARDS                                        *|
    |*----------------------------------------------------------*/

    /// @notice Sets the reward for voting in a proposal of a voting contract.
    /// @dev The reward can be set only by the owner and cannot exceed `MAX_VOTING_REWARD`.
    /// The reward is calculated from the current total supply at the moment of assigning the reward.
    /// @param votingContract The voting contract address.
    /// The contract must call `assignProposalReward` on proposal creation with the new proposal id.
    /// @param votingReward The voting reward nominator. Passing 0 disables the reward.
    function setVotingReward(address votingContract, uint256 votingReward) external onlyOwner {
        if (votingContract == address(0)) {
            revert Error.ZeroVotingContract();
        }
        if (votingReward > MAX_VOTING_REWARD) {
            revert Error.InvalidVotingReward();
        }
        votingRewards[votingContract] = votingReward;

        emit VotingRewardSet(votingContract, votingReward);
    }

    /// @inheritdoc IRewardToken
    function assignProposalReward(uint256 proposalId) external {
        address votingContract = msg.sender;

        // check that the voting contract has a reward set
        uint256 votingReward = votingRewards[votingContract];
        if (votingReward > 0) {
            // check that the proposal reward has not been assigned yet
            ProposalReward storage proposalReward = proposalRewards[votingContract][proposalId];
            if (proposalReward.reward == 0) {
                // assign the reward
                uint256 reward = Math.mulDiv(totalSupply(), votingReward, VOTING_REWARD_DENOMINATOR);
                proposalReward.reward = reward;

                emit ProposalRewardAssigned(votingContract, proposalId, reward);
            }
        }
    }

    /// @notice Claims the reward for voting in a proposal.
    /// @dev The reward can be claimed only if the caller has voted.
    /// It doesn't matter if the caller voted yes, no or abstained.
    /// @param votingContract The voting contract address.
    /// @param proposalId The proposal id.
    function claimProposalReward(address votingContract, uint256 proposalId) external {
        if (votingContract == address(0)) {
            revert Error.ZeroVotingContract();
        }

        // check that the reward has been assigned
        ProposalReward storage proposalReward = proposalRewards[votingContract][proposalId];
        uint256 assignedReward = proposalReward.reward;
        if (assignedReward == 0) {
            revert Error.ProposalRewardNotAssigned();
        }

        IPWNTokenGovernance _votingContract = IPWNTokenGovernance(votingContract);
        ( // get proposal data
            , bool executed,
            IPWNTokenGovernance.ProposalParameters memory proposalParameters,
            IPWNTokenGovernance.Tally memory tally,,
        ) = _votingContract.getProposal(proposalId);

        // check that the proposal has been executed
        if (!executed) {
            revert Error.ProposalNotExecuted();
        }

        // check that the caller has voted
        address voter = msg.sender;
        if (_votingContract.getVoteOption(proposalId, voter) == IPWNTokenGovernance.VoteOption.None) {
            revert Error.CallerHasNotVoted();
        }

        // check that the reward has not been claimed yet
        if (proposalReward.claimed[voter]) {
            revert Error.ProposalRewardAlreadyClaimed();
        }

        // store that the reward has been claimed
        proposalReward.claimed[voter] = true;

        // voter is rewarded proportionally to the amount of votes he had in the snapshot epoch
        // it doesn't matter if he voted yes, no or abstained
        uint256 voterVotes = _votingContract.getVotingToken().getPastVotes(voter, proposalParameters.snapshotEpoch);
        uint256 totalVotes = tally.abstain + tally.yes + tally.no;
        uint256 voterReward = Math.mulDiv(assignedReward, voterVotes, totalVotes);

        // mint the reward to the voter
        _mint(voter, voterReward);

        emit ProposalRewardClaimed(votingContract, proposalId, voter, voterReward);
    }


    /*----------------------------------------------------------*|
    |*  # TRANSFER CALLBACK                                     *|
    |*----------------------------------------------------------*/

    /// @notice Hook that is called before any token transfer.
    /// @dev The token transfer is allowed only if the transfers are enabled or caller is whitelisted.
    function _beforeTokenTransfer(
        address from, address to, uint256 /* amount */
    ) override internal view {
        // Note: filter mints and burns from require condition
        if (!transfersEnabled && !transferAllowlist[_msgSender()] && from != address(0) && to != address(0)) {
            revert Error.TransfersDisabled();
        }
    }

}
