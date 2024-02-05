// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;
// solhint-disable quotes
// solhint-disable max-line-length

import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";

import { VoteEscrowedPWN } from "src/VoteEscrowedPWN.sol";

import { VoteEscrowedPWN_Test } from "./VoteEscrowedPWNTest.t.sol";

contract VoteEscrowedPWN_StakeMetadata_Test is VoteEscrowedPWN_Test {
    uint256 public stakeId = 1;
    uint104 public amount = 100e18;
    uint16 public initialEpoch = uint16(currentEpoch - 20);
    uint8 public lockUpEpochs = 130;

    function setUp() public override {
        super.setUp();

        vm.mockCall(epochClock, abi.encodeWithSignature("INITIAL_EPOCH_TIMESTAMP()"), abi.encode(0));
        vm.mockCall(epochClock, abi.encodeWithSignature("SECONDS_IN_EPOCH()"), abi.encode(uint256(2_419_200)));

        vm.warp(currentEpoch * 2_419_200);

        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, amount);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE FIELDS                                           *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_StakeMetadata_MakeFields_Test is VoteEscrowedPWN_StakeMetadata_Test {
    using Strings for address;
    using Strings for uint256;

    function test_makeName() external {
        assertEq(keccak256(bytes(vePWN.exposed_makeName(0))), keccak256(bytes('"PWN DAO Stake #0"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeName(1))), keccak256(bytes('"PWN DAO Stake #1"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeName(15))), keccak256(bytes('"PWN DAO Stake #15"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeName(953))), keccak256(bytes('"PWN DAO Stake #953"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeName(31223))), keccak256(bytes('"PWN DAO Stake #31223"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeName(3010102))), keccak256(bytes('"PWN DAO Stake #3010102"')));
    }

    function test_makeApiUriWith() external {
        assertEq(
            keccak256(bytes(vePWN.exposed_makeApiUriWith(1, "hello"))),
            keccak256(bytes('"https://api-dao.pwn.xyz/stpwn/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/1/hello"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeApiUriWith(101, "its me"))),
            keccak256(bytes('"https://api-dao.pwn.xyz/stpwn/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/101/its me"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeApiUriWith(987, "babe?"))),
            keccak256(bytes('"https://api-dao.pwn.xyz/stpwn/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/987/babe?"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeApiUriWith(101_332_103, "where"))),
            keccak256(bytes('"https://api-dao.pwn.xyz/stpwn/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/101332103/where"'))
        );
    }

    function test_makeExternalUrl() external {
        assertEq(
            keccak256(bytes(vePWN.exposed_makeExternalUrl(1))),
            keccak256(bytes('"https://app.pwn.xyz/#/asset/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/1"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeExternalUrl(1939020))),
            keccak256(bytes('"https://app.pwn.xyz/#/asset/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/1939020"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeExternalUrl(87619233123))),
            keccak256(bytes('"https://app.pwn.xyz/#/asset/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/87619233123"'))
        );
        assertEq(
            keccak256(bytes(vePWN.exposed_makeExternalUrl(30302221))),
            keccak256(bytes('"https://app.pwn.xyz/#/asset/31337/0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f/30302221"'))
        );
    }

    function test_makeDescription() external {
        assertEq(
            keccak256(bytes(vePWN.exposed_makeDescription())),
            keccak256(bytes('"This NFT is a representation of a PWN DAO stake. Stake ownership grants its owner power in the PWN DAO. The power is determined by the amount of PWN tokens staked and the remaining lockup period. The power decreases over time until the lockup is over."'))
        );
    }

    function test_makeMultiplier() external {
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(0))), keccak256(bytes('"1.0x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(13))), keccak256(bytes('"1.0x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(14))), keccak256(bytes('"1.15x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(26))), keccak256(bytes('"1.15x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(27))), keccak256(bytes('"1.3x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(39))), keccak256(bytes('"1.3x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(40))), keccak256(bytes('"1.5x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(52))), keccak256(bytes('"1.5x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(53))), keccak256(bytes('"1.75x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(65))), keccak256(bytes('"1.75x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(66))), keccak256(bytes('"3.5x"')));
        assertEq(keccak256(bytes(vePWN.exposed_makeMultiplier(130))), keccak256(bytes('"3.5x"')));
    }

    function testFuzz_makeStakedAmount(uint256 amount, uint256 decimals, address addr) external {
        VoteEscrowedPWN.StakedAmount memory stakedAmount;
        stakedAmount.amount = amount;
        stakedAmount.decimals = decimals;
        stakedAmount.pwnTokenAddress = addr;
        string memory expected = string.concat(
            '{"amount":', amount.toString(),
            ',"decimals":', decimals.toString(),
            ',"pwn_token_address":"', addr.toHexString(), '"}'
        );

        assertEq(
            keccak256(bytes(vePWN.exposed_makeStakedAmount(stakedAmount))),
            keccak256(bytes(expected))
        );
    }

    function test_makePowerChanges() external {
        VoteEscrowedPWN.PowerChange[] memory powerChanges = new VoteEscrowedPWN.PowerChange[](3);
        powerChanges[0].timestamp = 102;
        powerChanges[0].power = 100;
        powerChanges[0].multiplier = '"1.0x"';
        powerChanges[1].timestamp = 4004002020;
        powerChanges[1].power = 200;
        powerChanges[1].multiplier = '"1.15x"';
        powerChanges[2].timestamp = 30115;
        powerChanges[2].power = 300;
        powerChanges[2].multiplier = '"1.3x"';
        string memory expected = string.concat(
            '[{"start_date":102,"power":100,"multiplier":"1.0x"},',
            '{"start_date":4004002020,"power":200,"multiplier":"1.15x"},',
            '{"start_date":30115,"power":300,"multiplier":"1.3x"}]'
        );

        assertEq(
            keccak256(bytes(vePWN.exposed_makePowerChanges(powerChanges))),
            keccak256(bytes(expected))
        );
    }

}


/*----------------------------------------------------------*|
|*  # COMPUTE ATTRIBUTES                                    *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_StakeMetadata_ComputeAttributes_Test is VoteEscrowedPWN_StakeMetadata_Test {
    using Strings for address;
    using Strings for uint256;

    function testFuzz_shouldComputeOwner(address _owner) external checkAddress(_owner) {
        vm.mockCall(stakedPWN, abi.encodeWithSignature("ownerOf(uint256)", stakeId), abi.encode(_owner));

        VoteEscrowedPWN.MetadataAttributes memory attributes = vePWN.exposed_computeAttributes(stakeId);

        assertEq(attributes.stakeOwner, _owner);
    }

    function testFuzz_shouldComputeStakedAmount(uint256 _amount) external {
        _amount = _boundAmount(_amount);
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, uint104(_amount));

        VoteEscrowedPWN.MetadataAttributes memory attributes = vePWN.exposed_computeAttributes(stakeId);

        assertEq(attributes.stakedAmountFormatted, _amount / 1e18);
        assertEq(attributes.stakedAmount.amount, _amount);
        assertEq(attributes.stakedAmount.decimals, 18);
        assertEq(attributes.stakedAmount.pwnTokenAddress, pwnToken);
    }

    function testFuzz_shouldComputeLockUpDuration(uint256 _lockUpEpochs) external {
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, amount);

        VoteEscrowedPWN.MetadataAttributes memory attributes = vePWN.exposed_computeAttributes(stakeId);

        assertEq(attributes.lockUpDuration, uint256(lockUpEpochs) * 28);
    }

    function testFuzz_shouldComputePowerChangesAndFieldsDerivedFromIt(
        uint256 _initialEpoch, uint256 _lockUpEpochs, uint256 _amount
    ) external {
        initialEpoch = uint16(bound(_initialEpoch, 1, currentEpoch + 1));
        lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        amount = uint104(_boundAmount(_amount));
        _mockStake(staker, stakeId, initialEpoch, lockUpEpochs, amount);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(initialEpoch, lockUpEpochs, amount);

        VoteEscrowedPWN.MetadataAttributes memory attributes = vePWN.exposed_computeAttributes(stakeId);

        string[] memory multipliers = new string[](7);
        multipliers[0] = '"0x"';
        multipliers[1] = '"1.0x"';
        multipliers[2] = '"1.15x"';
        multipliers[3] = '"1.3x"';
        multipliers[4] = '"1.5x"';
        multipliers[5] = '"1.75x"';
        multipliers[6] = '"3.5x"';

        // check power changes
        assertEq(powerChanges.length, attributes.powerChanges.length);
        int104 power;
        for (uint256 i; i < powerChanges.length; ++i) {
            power += powerChanges[i].powerChange;
            assertEq(attributes.powerChanges[i].timestamp, uint256(powerChanges[i].epoch - 1) * 2_419_200);
            assertEq(attributes.powerChanges[i].power, uint256(int256(power)));
            assertEq(attributes.powerChanges[i].multiplier, multipliers[powerChanges.length - 1 - i]);
        }
        // check timestamps
        assertEq(attributes.initialTimestamp, attributes.powerChanges[0].timestamp);
        assertEq(attributes.unlockTimestamp, attributes.powerChanges[attributes.powerChanges.length - 1].timestamp);
        // check time-dependent fields
        uint256 currentPowerChangeIndex;
        for (uint256 i; i < attributes.powerChanges.length; ++i) {
            if (attributes.powerChanges[i].timestamp <= block.timestamp) {
                currentPowerChangeIndex = i;
            }
        }
        if (block.timestamp < attributes.powerChanges[0].timestamp) {
            assertEq(attributes.currentPower, 0);
            assertEq(attributes.multiplier, '"0x"');
        } else {
            assertEq(attributes.currentPower, attributes.powerChanges[currentPowerChangeIndex].power);
            assertEq(attributes.multiplier, attributes.powerChanges[currentPowerChangeIndex].multiplier);
        }
    }

}
