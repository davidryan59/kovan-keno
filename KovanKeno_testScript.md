## Format of script:
### Player / House
- functionName(inputs)
- functionName(actual inputs used for testing)
- result: output that you will get


### Player:
- validateAndCountChoices([enter up to 10 choices, use trailing 0s to make array length 10])
- validateAndCountChoices([2,3,5,7,0, 0,0,0,0,0])
- result: [true, 4]

- getRevealHash(own address, random salt, [10 choices])
- getRevealHash(
    0xABCD1234ABCD1234ABCD1234ABCD1234ABCD1234, (edited)
    0x0000000000000000000000000000000000000000000000000000000000000000, (IN A REAL GAME, USE A PROPER SALT HERE!)
    [2,3,5,7,0, 0,0,0,0,0]
  )
- result: 0x6e189acd1dd1076ad18fb45ad97be412abf59bf1c6a2348765efd236ea95ae11

- getCommitHash(reveal hash)
- getCommitHash(0x6e189acd1dd1076ad18fb45ad97be412abf59bf1c6a2348765efd236ea95ae11)
- result: 0x97b8b31e910c4eac89e31a148f20a1b3aa068b1139b61890807b3ae0ada42c38

- createGame(choice count, commit hash, value)
- createGame(
    4,
    0x97b8b31e910c4eac89e31a148f20a1b3aa068b1139b61890807b3ae0ada42c38,
    1 ETH
  )
- result: Game created at game index 0

- getGameStatus(0) = 1

- if you try cancelGame(0) after 5 blocks then getGameStatus(0) = 2, you get refunded, you cannot use this game further


### House

- getGameFundingNeeded(game index)
- getGameFundingNeeded(0)
- result: 120 ETH

- fundGame(game index, house hash, value)
- fundGame(
    0,
    0x0000000000000000000000000000000000000000000000000000000000000000, (IN A REAL GAME, USE A PROPER HASH HERE!)
    120 ETH value
  )
- result: game is funded

- getGameStatus(0) = 3


### Player
- playGame(game index, salt used, choices)
- playGame(
    0,
    0x0000000000000000000000000000000000000000000000000000000000000000,
    [2,3,5,7,0, 0,0,0,0,0]  
  )
- result: Player wins 1.3 ETH! Matches are [3, 7], can see this from inspecting game object 0

- getGameStatus(0) = 4

House
- claimGameFunds(game index)
- claimGameFunds(0)
- result: 119.7 ETH returned to house

- getGameStatus(0) = 5
