pragma solidity ^0.4.23;

/**
 * @title Safe math
 */
contract SafeMath {
  function safeMul(uint256 _a, uint256 _b) internal pure returns (uint256) {
    if (_a == 0) {
      return 0;
    }

    uint256 c = _a * _b;
    require(c / _a == _b, "safeMul error");

    return c;
  }

  function safeDiv(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b > 0, "safeDiv error");
    uint256 c = _a / _b;

    return c;
  }

  function safeSub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b <= _a, "safeSub error");
    uint256 c = _a - _b;

    return c;
  }

  function safeAdd(uint256 _a, uint256 _b) internal pure returns (uint256) {
    uint256 c = _a + _b;
    require(c >= _a, "safeAdd error");

    return c;
  }
}

/**
 * @title Contract to bet Ether for a number and win randomly when the number of bets is met.
 * @author phanlancer
 */
contract Lottery is SafeMath {
  address spawner; // who spawn the lottery contract. It's different from the lotteryOwner

  // Structure of prize tier for winners
  struct PrizeTier {
    // winning number - your lucky
    uint winNumber;
    // number of winners for the prize tier
    uint8 numberOfWinners;
    // amount of the winnings per user per tier
    uint amountOfWinning;
  }

  // Lottery parameters
  address public lotteryOwner; // address to fund the raised money to, who wanna raise the funds
  uint public lotteryAmount = 1 ether; // Default 1 ether. The total amount of the lottery
  uint public ticketCost = 200 finney; // Default 0.2 ether. The cost of the ticket
  uint8 public numberOfPrizeTiers = 2; // Default 2 tiers. Number of prize tiers
  PrizeTier[] public prizeTiers; // Prize tiers

  // Lottery limitation
  uint private constant MIN_TICKET_COST = 10 finney; // Minimum ticket cost is 0.01 ether
  uint private constant MAX_LOTTERY_AMOUNT = 1000 ether; // Maximum amount of ether which this lottery can raise
  uint private constant MAX_NUMBER_PRIZE_TIERS = 100; // Maximum number of prize tiers

  // Lottery variables
  uint public totalBet; // The total amount of Ether raised for this current lottery
  uint public numberOfBets; // The total number of tickets bought by players
  uint public numberOfTickets; // = lotteryAmount / ticketCost

  mapping(uint => address[]) numberBetPlayers; // Each number has an array of players. Associate each number with a bunch of players
  mapping(address => uint) playerBetsNumber; // The number that each player has bet for

  // event DrawWinner(uint _winNumber, uint8 _numberOfWinners, uint _amountOfWinning, uint8 _prizeTier);
  // event WithdrawToWinner(address _winner, uint _winNumber, uint _amountOfWinning);
  // event WithdrawToOwner(uint _withdrawal);

  /**
    * @dev Throws if called by any account other than the spawner.
    */
  modifier onlySpawner() {
    require(msg.sender == spawner, "should be spawner");
    _;
  }

  modifier isFilledPrizeTiers() {
    require(prizeTiers.length == numberOfPrizeTiers, "contract needs required prize tiers");
    _;
  }
  
  // Modifier to only allow the execution of functions when the bets are completed
  modifier onEndGame() {
    if(totalBet >= lotteryAmount) _;
  }

  /**
   * @notice Constructor that's used to configure the minimum bet per game and the max amount of bets
   * @param _lotteryAmount The total amount of the lottery
   * @param _ticketCost The cost of the ticket
   * @param _numberOfPrizeTiers Number of prize tiers
   */
  constructor(address _lotteryOwner, uint _lotteryAmount, uint _ticketCost, uint8 _numberOfPrizeTiers) public {
    spawner = msg.sender;

    require(_lotteryOwner != address(0), "should be valid address");
    
    if(_lotteryAmount > 0 && _lotteryAmount <= MAX_LOTTERY_AMOUNT) lotteryAmount = _lotteryAmount;
    if(_ticketCost > MIN_TICKET_COST && _ticketCost <= _lotteryAmount) ticketCost = _ticketCost;
    if(_numberOfPrizeTiers >= 1 && _numberOfPrizeTiers <= MAX_NUMBER_PRIZE_TIERS) numberOfPrizeTiers = _numberOfPrizeTiers;

    // calculate number of tickets to be issued
    numberOfTickets = (lotteryAmount + ticketCost - 1) / ticketCost;
  }

  /**
   * @notice After contructor is called fillPrizeTiers should be called to fill prize tiers
   * @param _arrayNumberOfWinners array of number of winners per tier
   * @param _arrayAmountOfWinning array of amount of winnings per player per tier
   */
  function fillPrizeTiers(uint8[] _arrayNumberOfWinners, uint[] _arrayAmountOfWinning) external onlySpawner {
    require(prizeTiers.length != numberOfPrizeTiers, "prize tiers are already set");
    require(_arrayNumberOfWinners.length == numberOfPrizeTiers, "should be same as numberOfPrizeTiers");
    require(_arrayAmountOfWinning.length == numberOfPrizeTiers, "should be same as numberOfPrizeTiers");

    for(uint8 i = 0; i < numberOfPrizeTiers; i++) {
      prizeTiers[i].numberOfWinners = _arrayNumberOfWinners[i];
      prizeTiers[i].amountOfWinning = _arrayAmountOfWinning[i];
    }
  }

  /**
   * @notice Get number of winners per tier
   * @param _tier The index of the prize tier
   * @return uint8
   */
  function numberOfWinnersPerTier(uint8 _tier) public view returns(uint8) {
    return prizeTiers[_tier].numberOfWinners;
  }

  /**
   * @notice Get amount of winning per player per tier
   * @param _tier The index of the prize tier
   * @return uint
   */
  function amountOfWinningPerTier(uint8 _tier) public view returns(uint) {
    return prizeTiers[_tier].amountOfWinning;
  }

  /**
   * @notice Check if a player exists in the current game
   * @param _player The address of the player to check
   * @return bool Returns true is it exists or false if it doesn't
   */
  function checkPlayerExists(address _player) public view returns(bool) {
    if(playerBetsNumber[_player] > 0)
      return true;
    else
      return false;
  }

  /**
   * @notice To bet for a number by sending Ether
   * @param _numberToBet The number that the player wants to bet for. Must be between 1 and numberOfTickets both inclusive
   */
  function buyTicket(uint _numberToBet) external payable{

    // Check that the max amount of bets hasn't been met yet
    assert(totalBet < lotteryAmount);

    // Check that the player doesn't exists
    assert(checkPlayerExists(msg.sender) == false);

    // Check that the number to bet is within the range
    assert(_numberToBet >= 1 && _numberToBet <= numberOfTickets);

    // Check if ticket cost is correct
    assert(ticketCost == msg.value);

    // Set the number bet for that player
    playerBetsNumber[msg.sender] = _numberToBet;

    // The player msg.sender has bet for that number
    numberBetPlayers[_numberToBet].push(msg.sender);

    numberOfBets += 1;
    totalBet = safeAdd(totalBet, ticketCost);

    if(totalBet >= lotteryAmount) generateNumberWinner();
  }

  /**
   * @notice Generates a random number between 1 and numberOfTickets both inclusive.
   */
  function generateNumberWinner() private onEndGame isFilledPrizeTiers {
    // cumulativeHash will be used to generate random numbers
    bytes32 cumulativeHash = keccak256(abi.encodePacked(block.difficulty, block.timestamp));

    for(uint8 i = numberOfPrizeTiers - 1; i >= 0; i--) {
      // update hash for random
      cumulativeHash = keccak256(abi.encodePacked(blockhash(block.number - i), cumulativeHash));

      // generate random number and save it in PrizeTier struct. the random number will be in a range of 1 to numberOfTickets
      prizeTiers[i].winNumber = uint(cumulativeHash) % numberOfTickets + 1;
    }

    distributePrizes();
  }

  /**
   * @notice Sends the corresponding Ether to each winner then deletes all the
   * players for the next game and resets the `totalBet` and `numberOfBets`
   */
  function distributePrizes() private onEndGame isFilledPrizeTiers {
    // Loop through all the winners to send the corresponding prize for each one
    for(uint8 i = 0; i < numberOfPrizeTiers; i++) {
      for(uint j = 0; j < numberBetPlayers[prizeTiers[i].winNumber].length; j++) {
        numberBetPlayers[prizeTiers[i].winNumber][j].transfer(prizeTiers[i].amountOfWinning);
        totalBet = safeSub(totalBet, prizeTiers[i].amountOfWinning);
      }
    }

    // raised funds are sent to the lottery owner
    lotteryOwner.transfer(totalBet);
    
    // after distribute prizes kill the contract
    selfdestruct(spawner);
  }

  /**
   * @notice kill this contract whenever you want
   */
  function kill() public onlySpawner {
    selfdestruct(spawner);
  }
}
