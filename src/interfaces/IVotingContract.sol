// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

interface IVotingContract {
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
