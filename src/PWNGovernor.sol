// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import { Governor, IGovernor } from "openzeppelin-contracts/contracts/governance/Governor.sol";
import { GovernorSettings } from "openzeppelin-contracts/contracts/governance/extensions/GovernorSettings.sol";
import { GovernorCountingSimple }
    from "openzeppelin-contracts/contracts/governance/extensions/GovernorCountingSimple.sol";
import { GovernorVotes } from "openzeppelin-contracts/contracts/governance/extensions/GovernorVotes.sol";
import { GovernorVotesQuorumFraction }
    from "openzeppelin-contracts/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import { IVotes } from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

contract PWNGovernor is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {

    // # INVARIANTS
    // - voting duration <= 1 epoch

    uint256 public constant MAX_VOTING_PERIOD = 2_419_200; // 1 epoch

    constructor(IVotes _token)
        Governor("PWNGovernor")
        GovernorSettings(1 days, 7 days, 50_000e18)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(20) // 20%
    {}

    // The following functions are overrides required by Solidity.

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 timepoint)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }


    function _setVotingPeriod(uint256 newVotingPeriod) internal override virtual {
        require(newVotingPeriod < MAX_VOTING_PERIOD, "PWNGovernor: voting period too long");
        super._setVotingPeriod(newVotingPeriod);
    }

}
