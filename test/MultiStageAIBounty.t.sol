// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/MultiStageAIBounty.sol";

contract MultiStageAIBountyTest is Test {
    MultiStageAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";
    uint256 reward = 1 ether;
    uint256 challengeStake = 0.01 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        bounty = new MultiStageAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, 2 days, challengeStake);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        // Reveal
        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        // Challenge phase
        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.submitChallenge{value: challengeStake}(challengeId, bob, "Bob copied my answer");
        vm.stopPrank();

        // Move after challenge deadline
        vm.warp(block.timestamp + 4 days + 1);

        // Resolve challenges (simplified - no bonus to avoid funding issues)
        vm.startPrank(owner);
        bounty.resolveChallenges(challengeId);
        bounty.judgeAll(challengeId, bytes("LLM input"));
        bounty.finalizeWinner(challengeId, 0);
        vm.stopPrank();

        MultiStageAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.expectRevert("Not reveal phase");
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();
    }

    function testCannotChallengeBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        // Try to challenge before challenge phase starts (still in reveal phase)
        vm.warp(block.timestamp + 1 days + 12 hours);
        vm.startPrank(alice);
        vm.expectRevert("Not challenge phase");
        bounty.submitChallenge{value: challengeStake}(challengeId, bob, "Reason");
        vm.stopPrank();
    }

    function testCannotJudgeWithoutResolvingChallenges() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        // Create a challenge
        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        bounty.submitChallenge{value: challengeStake}(challengeId, bob, "Reason");
        vm.stopPrank();

        vm.warp(block.timestamp + 4 days + 1);
        vm.startPrank(owner);
        vm.expectRevert("Challenges must be resolved first");
        bounty.judgeAll(challengeId, bytes(""));
        vm.stopPrank();
    }

    function testInsufficientChallengeStake() public {
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        vm.expectRevert("Stake too low");
        bounty.submitChallenge{value: challengeStake - 1 wei}(challengeId, bob, "Reason");
        vm.stopPrank();
    }
}
