// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiStageAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 challengeDeadline;
        bool judged;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        mapping(address => bool) isParticipant;
        mapping(address => uint256) challengeStakes;
        mapping(address => bool) hasChallenged;
        mapping(address => address) challengeTarget;
        mapping(address => string) challengeReason;
        uint256 challengeCount;
        uint256 challengeStakeAmount;
        bool challengesResolved;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 challengeDeadline;
        bool judged;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        uint256 challengeCount;
        uint256 challengeStakeAmount;
        bool challengesResolved;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event ChallengeSubmitted(uint256 indexed id, address indexed challenger, address indexed target, string reason);
    event ChallengeResolved(uint256 indexed id, address indexed challenger, bool valid);
    event Judged(uint256 indexed id, uint256 answerCount);
    event WinnerFinalized(uint256 indexed id, address indexed winner);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyChallengePhase(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Not challenge phase");
        require(block.timestamp <= challenges[id].challengeDeadline, "Challenge phase ended");
        _;
    }

    modifier onlyAfterChallenge(uint256 id) {
        require(block.timestamp > challenges[id].challengeDeadline, "Challenge phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier notJudged(uint256 id) {
        require(!challenges[id].judged, "Already judged");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        uint256 challengeDuration,
        uint256 challengeStakeAmount
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(challengeDuration > 0, "Challenge duration must be > 0");
        require(challengeStakeAmount > 0, "Challenge stake must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.challengeDeadline = c.revealDeadline + challengeDuration;
        c.challengeStakeAmount = challengeStakeAmount;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);
        c.isParticipant[msg.sender] = true;

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealAnswer(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function submitChallenge(
        uint256 id,
        address target,
        string calldata reason
    ) external payable 
        challengeExists(id)
        onlyChallengePhase(id)
        notJudged(id)
    {
        Challenge storage c = challenges[id];
        require(c.isParticipant[msg.sender], "Not a participant");
        require(c.hasRevealed[msg.sender], "Must have revealed");
        require(c.hasRevealed[target], "Target must have revealed");
        require(target != msg.sender, "Cannot challenge yourself");
        require(!c.hasChallenged[msg.sender], "Already challenged");
        require(msg.value >= c.challengeStakeAmount, "Stake too low");

        c.hasChallenged[msg.sender] = true;
        c.challengeTarget[msg.sender] = target;
        c.challengeReason[msg.sender] = reason;
        c.challengeStakes[msg.sender] = msg.value;
        c.challengeCount++;

        emit ChallengeSubmitted(id, msg.sender, target, reason);
    }

    function resolveChallenges(uint256 id) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterChallenge(id)
        notJudged(id)
    {
        Challenge storage c = challenges[id];
        require(!c.challengesResolved, "Already resolved");
        require(c.challengeCount > 0, "No challenges to resolve");

        // Return stakes to all challengers (simplified)
        for (uint i = 0; i < c.participants.length; i++) {
            address participant = c.participants[i];
            if (c.hasChallenged[participant]) {
                uint256 stake = c.challengeStakes[participant];
                if (stake > 0) {
                    c.challengeStakes[participant] = 0;
                    payable(participant).transfer(stake);
                    emit ChallengeResolved(id, participant, true);
                }
            }
        }

        c.challengesResolved = true;
    }

    function judgeAll(uint256 id, bytes calldata llmInput) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterChallenge(id)
        notJudged(id)
    {
        Challenge storage c = challenges[id];
        require(c.answers.length > 0, "No revealed answers");
        require(c.challengesResolved, "Challenges must be resolved first");

        c.judged = true;
        emit Judged(id, c.answers.length);
    }

    function finalizeWinner(uint256 id, uint256 winnerIndex) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterChallenge(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.judged, "Must judge first");
        require(winnerIndex < c.answers.length, "Invalid winner index");

        c.finalized = true;
        c.winner = c.participants[winnerIndex];

        payable(c.winner).transfer(c.reward);

        emit WinnerFinalized(id, c.winner);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            challengeDeadline: c.challengeDeadline,
            judged: c.judged,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            challengeCount: c.challengeCount,
            challengeStakeAmount: c.challengeStakeAmount,
            challengesResolved: c.challengesResolved
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function hasChallenged(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasChallenged[participant];
    }

    function getChallengeTarget(uint256 id, address participant) external view returns (address) {
        return challenges[id].challengeTarget[participant];
    }

    function getChallengeReason(uint256 id, address participant) external view returns (string memory) {
        return challenges[id].challengeReason[participant];
    }
}
