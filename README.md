# PWN DAO

**PWN DAO** is a decentralized autonomous organization designed to manage and enhance the PWN Protocol, a platform for peer-to-peer lending with unique governance features. This repository contains the core smart contracts and governance mechanisms for PWN DAO.

## Overview

PWN DAO operates under a dual governance structure:

- **Community Governance**: All token holders who stake $PWN tokens can participate in governance. Proposals require a quorum of 20% of staked tokens and must achieve a 60% approval rate to pass.
- **Steward Governance**: Stewards, appointed by the community, can make decisions using a multi-signature mechanism. Their proposals are automatically implemented unless vetoed by at least 10% of the total voting power.

## Deployed Addresses on Ethereum

The following are the contract addresses for PWN DAO on the Ethereum mainnet:

| Contract Name                     | Address |
| -                                 | - |
| **PWN DAO**	                    | `0x1B8383D2726E7e18189205337424a2631A2102F4` |
| **PWN token**                     | `0x420690e3C226398De46b2c467AD4547870391Ba3` |
| **vePWN**	                        | `0x683b463672e3F11eE36dc64Ae8970241F5fb6726` |
| **stPWN**	                        | `0x1Eba7F1E2DdDC008D3CD6E88b5F3C8A52BDC1C14` |
| **Community gov plugin**          | `0x1cd32eC9160aFC5B2EaD9A522244580F29a2959b` |
| **Stewards gov plugin**	        | `0x05E50fE39C5E4d6caab8648BA327d0a0e9E923bb` |
| **Stewards execute allowlist**    | `0xa7abafd48372560f35D599a36D729B0dce143856` |
| **PWNEpochClock**	                | `0x65EA4fdc09900f1f1E1aa911a90f4eFEF1BACfCb` |

## Governance Model

### Community Governance

- **Staking**: $PWN token holders must stake their tokens to gain governance power. The voting power is determined by the amount and remaining lockup period of the stake, with multipliers up to 3.5x for a 10-year commitment.
- **Proposals**: Any token holder with at least 1 voting power can submit a proposal. Proposals require a 20% quorum and 60% approval to pass.
- **Voting**: Stakers can vote on proposals, with rewards given to active participants.

### Steward Governance

- **Stewards**: Community-appointed individuals who can submit optimistic proposals that can be vetoed by the community. They act as operational leaders of the DAO.
- **Veto Power**: Token holders can veto steward decisions if they collectively hold at least 10% of the voting power.

## Voter Incentives

PWN DAO incentivizes participation by rewarding voters who support successful proposals with newly minted $PWN tokens. Non-participation may lead to inflationary penalties or reduced voting rewards.

## Tokens and Treasury

- **$PWN Token (PWN)**: The native governance token of the DAO.
- **StakedPWN (stPWN)**: An NFT representing staked $PWN tokens, non-transferable unless governance enables transferability.
- **VoteEscrowedPWN (vePWN)**: A non-transferable token representing the voting power of staked $PWN.

PWN DAO's treasury is funded by protocol fees, initially set at 0%, with the ability to adjust fees over time. Funds are managed through governance decisions for protocol upgrades, ecosystem development, or community rewards.

## Infrastructure

PWN DAO utilizes the Aragon OSx framework for decentralized governance and is initially deployed on Ethereum, with plans for multi-chain governance supported by a bridge timelock mechanism.

## Contact

For any questions, suggestions, or to get in touch with the PWN DAO team, please visit our [website](https://pwn.xyz) or reach out through our community channels.
