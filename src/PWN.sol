// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNEpochClock } from "./PWNEpochClock.sol";

interface ITokenVoting {
    enum VoteOption {
        None, Abstain, Yes, No
    }

    enum VotingMode {
        Standard, EarlyExecution, VoteReplacement
    }

    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotEpoch;
        uint256 minVotingPower;
    }

    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    struct Action {
        address to;
        uint256 value;
        bytes data;
    }

    function getVotingToken() external view returns (IVotes);
    function getVoteOption(uint256 proposalId, address voter) external view returns (VoteOption);
    function getProposal(uint256 proposalId) external view returns (
        bool open,
        bool executed,
        ProposalParameters memory parameters,
        Tally memory tally,
        Action[] memory actions,
        uint256 allowFailureMap
    );
}

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
    PWNEpochClock public immutable epochClock;

    ITokenVoting public tokenVoting;
    /// Amount of tokens already minted by the owner
    uint256 public mintedSupply;

    mapping(uint256 proposalId => uint256 reward) public votingRewards;
    mapping(uint256 proposalId => mapping(address voter => bool claimed)) public votingRewardsClaimed;


    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    event VotingRewardAssigned(uint256 indexed proposalId, uint256 reward);
    event VotingRewardClaimed(uint256 indexed proposalId, address indexed voter, uint256 reward);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _owner, address _epochClock) ERC20("PWN DAO", "PWN") {
        _transferOwnership(_owner);
        epochClock = PWNEpochClock(_epochClock);
        INITIAL_EPOCH = epochClock.currentEpoch();
    }


    /*----------------------------------------------------------*|
    |*  # MANAGE SUPPLY                                         *|
    |*----------------------------------------------------------*/

    function mint(uint256 amount) external onlyOwner {
        require(mintedSupply + amount <= MINTABLE_TOTAL_SUPPLY, "PWN: mintable supply reached");
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
    function assignVotingReward(uint256 proposalId, uint256 reward) external onlyOwner {
        require(epochClock.currentEpoch() - INITIAL_EPOCH >= IMMUTABLE_PERIOD, "PWN: immutable period not reached");
        require(
            reward <= Math.mulDiv(totalSupply(), MAX_INFLATION_RATE, INFLATION_DENOMINATOR),
            "PWN: reward too high"
        );
        require(reward > 0, "PWN: reward cannot be zero");
        require(votingRewards[proposalId] == 0, "PWN: reward already assigned");

        votingRewards[proposalId] = reward;

        emit VotingRewardAssigned(proposalId, reward);
    }

    function claimVotingReward(uint256 proposalId) external {
        address voter = msg.sender;
        require(address(tokenVoting) != address(0), "PWN: token voting not set");
        (
            , bool executed,
            ITokenVoting.ProposalParameters memory proposalParameters,
            ITokenVoting.Tally memory tally,,
        ) = tokenVoting.getProposal(proposalId);
        require(executed, "PWN: proposal not executed");
        require(
            tokenVoting.getVoteOption(proposalId, voter) != ITokenVoting.VoteOption.None,
            "PWN: caller has not voted"
        );
        require(votingRewards[proposalId] > 0, "PWN: no reward");
        require(!votingRewardsClaimed[proposalId][voter], "PWN: reward already claimed");
        votingRewardsClaimed[proposalId][voter] = true;

        // voter is rewarded proportionally to the amount of votes he had at the snapshot block
        // it doesn't matter if he voted yes, no or abstained
        uint256 callerVotes = tokenVoting.getVotingToken().getPastVotes(voter, proposalParameters.snapshotEpoch);
        uint256 totalVotes = tally.abstain + tally.yes + tally.no;
        uint256 reward = Math.mulDiv(votingRewards[proposalId], callerVotes, totalVotes);

        _mint(voter, reward);

        emit VotingRewardClaimed(proposalId, voter, reward);
    }


    /*----------------------------------------------------------*|
    |*  # TOKEN VOTING SETTER                                   *|
    |*----------------------------------------------------------*/

    function setTokenVotingContract(ITokenVoting _tokenVoting) external onlyOwner {
        require(address(_tokenVoting) != address(0), "PWN: token voting zero address");
        tokenVoting = _tokenVoting;
    }

}
