// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { IGovernor } from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { PWNEpochClock } from "./PWNEpochClock.sol";
import { PWNGovernor } from "./PWNGovernor.sol";

contract PWN is Ownable2Step, ERC20 {

    // # INVARIANTS
    // - owner can mint max INITIAL_TOTAL_SUPPLY regardless of burned amount
    // - after reaching the IMMUTABLE_PERIOD, token can be inflated by MAX_INFLATION_RATE
    // - voting reward per proposal can be assigned only once
    // - voting reward can be claimed only once per proposal per voter

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    uint256 public constant INITIAL_TOTAL_SUPPLY = 100_000_000e18;
    uint256 public constant MAX_INFLATION_RATE = 20; // max inflation rate (2 decimals) after immutable period
    uint256 public constant INFLATION_DENOMINATOR = 10000; // 2 decimals
    uint256 public constant IMMUTABLE_PERIOD = 65; // ~5 years in epochs

    // solhint-disable-next-line immutable-vars-naming, var-name-mixedcase
    uint256 public immutable INITIAL_EPOCH;
    PWNEpochClock public immutable epochClock;

    PWNGovernor public governor;
    /// Amount of tokens already minted by the owner
    uint256 public ownerMintedAmount;

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
        require(ownerMintedAmount + amount <= INITIAL_TOTAL_SUPPLY, "PWN: initial supply reached");

        unchecked { ownerMintedAmount += amount; }

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
        require(address(governor) != address(0), "PWN: governor not set");
        require(governor.state(proposalId) == IGovernor.ProposalState.Succeeded, "PWN: proposal not succeeded");
        require(governor.hasVoted(proposalId, voter), "PWN: caller has not voted");
        require(votingRewards[proposalId] > 0, "PWN: no reward");
        require(!votingRewardsClaimed[proposalId][voter], "PWN: reward already claimed");
        votingRewardsClaimed[proposalId][voter] = true;

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        uint256 totalVotes = againstVotes + forVotes + abstainVotes;
        uint256 callerVotes = governor.getVotes(voter, governor.proposalSnapshot(proposalId));
        uint256 reward = Math.mulDiv(votingRewards[proposalId], callerVotes, totalVotes);

        _mint(voter, reward);

        emit VotingRewardClaimed(proposalId, voter, reward);
    }


    /*----------------------------------------------------------*|
    |*  # GOVERNOR SETTER                                       *|
    |*----------------------------------------------------------*/

    function setGovernor(address payable _governor) external onlyOwner {
        require(_governor != address(0), "PWN: governor zero address");
        governor = PWNGovernor(_governor);
    }

}
