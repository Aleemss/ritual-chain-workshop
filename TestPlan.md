# Test Plan – MultiStageAIBounty

- Happy path: 3 participants commit → reveal → challenge → resolve → judge → finalize
- Cannot reveal before deadline (reverts)
- Cannot challenge before deadline (reverts)
- Cannot judge without resolving challenges (reverts)
- Insufficient challenge stake (reverts)
