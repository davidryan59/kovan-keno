pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
// import "@openzeppelin/contracts/access/Ownable.sol"; 
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

// Keno game with some hard-coded parameters:
// - 80 numbers to choose from
// - player selects between 1 and 10 of these
// - game draws 20 of the 80

// Hashes
// playerRevealHash = hash(playerAddress, salt, choices[10]) - salt should be a random uint256
// playerCommitHash = hash(playerRevealHash) - added to game before the houseHash is known
// houseHash: let the house supply any suitably random data as a uint256 - added to game before the playerRevealHash is known
// Optimal strategy for both house and player is (I think!) to provide a totally random hash/salt

// Randomness
// Generated from playerRevealHash and houseHash.
// The resulting uint256 has 256 bits of data, only 123 bits needed for 20 choices from 1..80


contract KovanKeno {

  enum GameStatus {CREATED, COMMITTED, CANCELLED, FUNDED, PLAYED, CLAIMED}

  // How much does matching k out of n numbers make per $100?
  // Rows are n (1..10), columns are k (0..10)
  // would have preferred doubly nested array, but Solidity didn't seem to like it...
  uint256[110] public payoutsPer100_flat = [
    0, 380, 0, 0, 0, 0, 0, 0, 0, 0, 0, // n = 1 choices, k = 0 to 10 matches (2 to 10 not possible, so zero)
    0, 110, 880, 0, 0, 0, 0, 0, 0, 0, 0, // n = 2
    0, 0, 288, 4000, 0, 0, 0, 0, 0, 0, 0, // n = 3
    0, 0, 130, 700, 12000, 0, 0, 0, 0, 0, 0, // n = 4
    0, 0, 0, 300, 2500, 60000, 0, 0, 0, 0, 0, // n = 5
    0, 0, 0, 168, 800, 8000, 200000, 0, 0, 0, 0, // n = 6
    200, 0, 0, 0, 200, 1800, 28000, 1000000, 0, 0, 0, // n = 7
    300, 0, 0, 0, 200, 800, 5000, 80000, 3000000, 0, 0, // n = 8
    400, 0, 0, 0, 0, 400, 2500, 32000, 500000, 10000000, 0, // n = 9
    600, 0, 0, 0, 0, 200, 1000, 10000, 115000, 2000000, 20000000 // n = 10 choices, payouts for k = 0 to 10 matches (11 data points)
  ]; 

  // For each n, what is the maximum payout per $100 the house must make available?
  uint256[10] public payoutsPer100_max = [
    // idx = n-1 here
    380, 880, 4000, 12000, 60000, 200000, 1000000, 3000000, 10000000, 20000000
  ];

  function getPayoutPer100(uint8 k, uint8 n) public view returns (uint256) {
    // n in range 1 to 10 (number of choices)
    // k in range 0 to 10 (number of matches)
    uint8 idx = k + 11 * (n - 1); // index in flat array above
    return payoutsPer100_flat[idx];
  }

  function getMaxPayoutPer100(uint8 n) public view returns(uint256) {
    // n in range 1 to 10 (number of choices)
    uint8 idx = n - 1; // index in max array above
    return payoutsPer100_max[idx];
  }

  // Store data for individual game
  struct KenoGame {
    GameStatus status; // Status of game
    uint256 currentValue; // keep track of amount in the game

    uint256 blockNumCommitted; // Block number the game was committed
    address playerAddress; // Address of player
    uint256 playerValue; // Amount the player bet
    bytes32 playerCommitHash; // Commit hash of player

    uint8 choiceCount; // between 1 and 10; number of choices (known when committing)
    uint8[10] choices; // numbers between 1 and 80; (only known after revealing)

    uint256 blockNumFunded; // Block number the game was funded
    address houseAddress; // Address of house
    bytes32 houseHash; // random data contribution from house

    uint8[20] results; // 20 distinct numbers between 1 and 80, derived from playerRevealHash and houseHash
    uint8[10] matches; // between 1 and 10 numbers that matched
  }

  // Easily initialise a new game
  function getNewKenoGame() private pure returns (KenoGame memory) {
    return KenoGame({
       status: GameStatus.CREATED,
       currentValue: 0,

       blockNumCommitted: 0,
       playerAddress: address(0),
       playerValue: 0,
       playerCommitHash: 0,

       choiceCount: 0,
       choices: [0,0,0,0,0, 0,0,0,0,0],

       blockNumFunded: 0,
       houseAddress: address(0),
       houseHash: 0,

       results: [0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
       matches: [0,0,0,0,0, 0,0,0,0,0]
    });
  }

  uint256 public nextGameIndex = 0;
  KenoGame[] public games;
  uint256 public totalValueInContract = 0;

  constructor() {
    // is there anything to do on deploy?
  }

  function incrementGameValue(KenoGame memory game, uint256 value) private {
    totalValueInContract += value;
    game.currentValue += value;
  }

  function decrementGameValue(KenoGame memory game, uint256 value) private {
    totalValueInContract -= value;
    game.currentValue -= value;
  }

  // Create a game with a specific number of choices and specific commitHash
  // Construct commitHash using functions getRevealHash then getCommitHash
  // Will need a random salt value, and remember it to playGame later
  function createGame(uint8 choiceCount, bytes32 commitHash) public payable returns (uint256) {
    uint256 blockNum = block.number;
    uint256 value = msg.value;
    address playerAddress = msg.sender;
    // Checks
    require(0 < value, "No money was sent");
    require(0 < choiceCount, "Must make at least 1 choice");
    require(choiceCount <= 10, "Maximum choices is 10");
    // Construct new game and add to contract
    KenoGame memory game = getNewKenoGame();
    game.status = GameStatus.COMMITTED;
    game.blockNumCommitted = blockNum;
    incrementGameValue(game, value);
    game.playerValue += value;
    game.playerAddress = playerAddress;
    game.playerCommitHash = commitHash;
    game.choiceCount = choiceCount;
    // Add new game to contract
    games.push(game);
    uint256 gameIndex = nextGameIndex;
    nextGameIndex += 1;
    // Return index of the new game
    return gameIndex;
  }

  // Get game from memory, throw user-friendly error if out of bounds
  function getGame(uint256 gameIndex) public view returns (KenoGame memory) {
    require (gameIndex < nextGameIndex, "Game does not exist");
    return games[gameIndex];
  }

  // Need to call this at end of each function
  // after updates, before any payments
  function storeUpdatedGame(KenoGame memory game, uint256 index) private {
    games[index] = game;
  }

  // If game does not get funded within specified number of blocks,
  // player can cancel and get full refund
  function cancelGame(uint256 gameIndex) public {
    uint256 blockNum = block.number;
    address playerAddress = msg.sender;
    KenoGame memory game = getGame(gameIndex);
    // Checks
    require(game.playerAddress == playerAddress, "Only player can cancel the game");
    require(game.status == GameStatus.COMMITTED, "Game must be committed but not funded");
    require(5 <= blockNum - game.blockNumCommitted, "Game cannot be cancelled within 5 blocks of committing");
    // Refund player the money
    uint256 refundAmount = game.currentValue;
    game.status = GameStatus.CANCELLED;
    decrementGameValue(game, refundAmount);
    storeUpdatedGame(game, gameIndex);
    (bool sent, ) = playerAddress.call{value: refundAmount}("");
    require(sent, "Failed to refund player");
  }

  // Easily find out game status
  function getGameStatus(uint256 gameIndex) public view returns (GameStatus) {
    KenoGame memory game = getGame(gameIndex);
    return game.status;
  }

  // Easily find out how much funding the house must provide for a specific game
  function getGameFundingNeeded(uint256 gameIndex) public view returns (uint256) {
    KenoGame memory game = getGame(gameIndex);
    uint8 choiceCount = game.choiceCount; // n
    require(1 <= choiceCount && choiceCount <= 10, "Game choice count is not valid");
    uint256 maxPayoutPer100 = getMaxPayoutPer100(choiceCount);
    uint256 fundingNeeded = (game.playerValue * maxPayoutPer100) / 100;
    return fundingNeeded;
  }

  // House should call this to fund a game, within 5 blocks of player committing the game
  // Send a decent chunk of "msg.value" to fund
  // Use getGameFundingNeeded to find out how much
  // Supply a random seed houseHash that player must include to generate randomness
  // (e.g. player does not know houseHash when committing,
  // and house does not know playerRevealHash when funding)
  function fundGame(uint256 gameIndex, bytes32 houseHash) public payable {
    uint256 blockNum = block.number;
    uint256 value = msg.value;
    address houseAddress = msg.sender;
    KenoGame memory game = getGame(gameIndex);
    // Checks
    require(game.status == GameStatus.COMMITTED, "Game must be committed but not funded");
    require(blockNum - game.blockNumCommitted < 5, "Must fund game within 5 blocks of being committed");
    uint256 fundingNeeded = getGameFundingNeeded(gameIndex);
    require(fundingNeeded == value, "Funding amount is wrong");
    // Update game as funded
    game.status = GameStatus.FUNDED;
    game.blockNumFunded = blockNum;
    incrementGameValue(game, value);
    game.houseAddress = houseAddress;
    game.houseHash = houseHash;
    storeUpdatedGame(game, gameIndex);
  }

  // Check that an array of player choices is valid
  function validateAndCountChoices(uint8[10] memory choices) public pure returns (bool, uint8) {
    // Supply an array of choices as strictly ascending numbers between 1 and 80
    // There must be between 1 and 10 choices
    // Unused entries must be at the end, and they must be 0
    // Example valid choices:
    // [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] returns (true, 10)
    // [45, 79, 0, 0, 0, 0, 0, 0, 0, 0] returns (true, 2)
    // Example invalid choices:
    // [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    // [2, 1, 3, 4, 5, 6, 7, 8, 9, 10]
    // [1, 2, 3, 4, 0, 0, 5, 6, 0, 0]
    // Invalid choices all return (false, 0)
    uint8 choiceCount = 0;
    uint8 prevValue = 0;
    // Check the non-zero choices are ascending and in range. Also count them.
    for (uint8 i = 0; i < 10; i++) {
      uint8 thisValue = choices[i];
      if (thisValue == 0) break;
      if (prevValue < thisValue && thisValue <= 80) {
        choiceCount += 1;
        prevValue = thisValue;
      } else {
        // choice is either not greater than previous value, or greater than 80
        return (false, 0);
      }
    }
    // Check the rest of the choice array is zeros
    for (uint8 i = choiceCount; i < 10; i++) {
      if (choices[i] != 0) return (false, 0);
    }
    if (choiceCount == 0) return (false, 0);
    return (true, choiceCount);
  }

  // Helper functions for hashing and randomness
  function getRevealHash(address theAddress, bytes32 randomSalt, uint8[10] memory choices) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(theAddress, randomSalt, choices));
  }
  function getCommitHash(bytes32 revealHash) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(revealHash));
  }
  function getRandomHash(bytes32 playerHash, bytes32 houseHash) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(playerHash, houseHash));
  }
  function getRandomComponent(uint256 initNum, uint8 limit) public pure returns (uint8 modNum, uint256 resNum) {
    modNum = uint8(initNum % limit);
    resNum = (initNum - modNum) / limit;
    return (modNum, resNum);
  }

  // Player uses this to reveal their choices in a specific game (along with the salt)
  // which can be verified using their commitHash
  // Game will either be won or lost depending on a random draw of 20 numbers from 80,
  // according to randomness generated from revealHash and houseHash
  // Player MUST call this within 10 blocks of game being funded,
  // otherwise house can claim all funds in the game!
  function playGame(uint256 gameIndex, bytes32 saltUsed, uint8[10] memory choices) public {
    address playerAddress = msg.sender;
    KenoGame memory game = getGame(gameIndex);
    // General checks
    require(game.playerAddress == playerAddress, "Game must be played by same player who created it");
    require(game.status == GameStatus.FUNDED, "Game must be funded before playing");
    // Check commit hash matches
    bytes32 revealHash = getRevealHash(playerAddress, saltUsed, choices);
    bytes32 commitHash = getCommitHash(revealHash);
    require(commitHash == game.playerCommitHash, "Failed to play game, commit hash mismatch");
    // Check choices are valid
    (bool choicesValid, uint8 choiceCount) = validateAndCountChoices(choices);
    require(choicesValid, "Player choice list is invalid. Player forfeits game.");
    require(game.choiceCount == choiceCount, "Player choice list is the wrong length. Player forfeits game.");
    game.choices = choices;
    // Play the game!
    // Calculate 20 numbers from 80 at random
    uint256 init = uint256(getRandomHash(revealHash, game.houseHash));
    // this initial value contains 256 bits of information
    // to select 20 numbers from 1 to 80, require 122.69 bits of information
    // can therefore use this one 256-bit number to get all the choices
    uint8 idx = 0;
    uint8[80] memory remainingNumbers = [
       1,  2,  3,  4,  5,  6,  7,  8,  9, 10,
      11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
      21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
      31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
      41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
      51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
      61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
      71, 72, 73, 74, 75, 76, 77, 78, 79, 80
    ];
    for (uint8 i = 0; i < 20; i++) {
      (idx, init) = getRandomComponent(init, 80-i); // for i=0, idx will be in range 0 to 79
      game.results[i] = remainingNumbers[idx];
      remainingNumbers[idx] = remainingNumbers[80-i-1]; // quick and lazy shortening of array!
    }
    // Find the matching numbers; store and count them
    uint8 matchCount = 0;
    for (uint8 i = 0; i < game.choiceCount; i++) {
      uint8 num = game.choices[i];
      for (uint8 j = 0; j < 20; j++) {
        if (num == game.results[j]) {
          game.matches[matchCount] = num;
          matchCount += 1;
        }
      }
    }
    // Calculate the player's winnings, and withdraw to player
    game.status = GameStatus.PLAYED;
    uint256 playerWinnings = (game.playerValue * getPayoutPer100(matchCount, choiceCount)) / 100;
    decrementGameValue(game, playerWinnings);
    storeUpdatedGame(game, gameIndex);
    if (0 < playerWinnings) {
      (bool sent, ) = playerAddress.call{value: playerWinnings}("");
      require(sent, "Failed to withdraw player's funds");
    } else {
      // player is a loser, no withdraw for you! ;)
    }
    // The remainder of game funds is due to the house now
    // Do this in a separate claimGameFunds call by the house
  }

  // Function to allow any remaining funds in a game to be withdrawn
  // by firstly the house, and failing that (after a while), anyone
  function claimGameFunds(uint256 gameIndex) public {
    uint256 blockNum = block.number;
    address claimerAddress = msg.sender;
    KenoGame memory game = getGame(gameIndex);
    // Checks
    require(0 < game.currentValue, "Game has no funds left in it");
    bool claimerIsHouse = (claimerAddress == game.houseAddress);
    bool fundedAWhileAgo = (0 < game.blockNumFunded) && (10 < blockNum - game.blockNumFunded);
    bool committedAVeryLongTimeAgo = (0 < game.blockNumCommitted) && (1000 < blockNum - game.blockNumCommitted);
    // Who can claim remaining funds?
    // 1. House can claim immediately after player has played
    // 2. House can claim on delay after funding (e.g. if player fails to play, perhaps knowing they lose)
    // 3. If house fails to claim for a long time, ANYONE can withdraw the funds :)
    require(
      (game.status == GameStatus.PLAYED && claimerIsHouse)
      ||
      (game.status == GameStatus.FUNDED && claimerIsHouse && fundedAWhileAgo)
      ||
      committedAVeryLongTimeAgo
    , "Conditions for claiming game are not met yet");
    // Allow withdrawal to claimer
    uint256 withdrawalAmount = game.currentValue;
    game.status = GameStatus.CLAIMED;
    decrementGameValue(game, withdrawalAmount);
    storeUpdatedGame(game, gameIndex);
    (bool sent, ) = claimerAddress.call{value: withdrawalAmount}("");
    require(sent, "Failed to withdraw funds to claimer");
  }
}
