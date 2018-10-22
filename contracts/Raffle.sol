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
contract Raffle is SafeMath {
  address spawner; // (RafflePanda company) who spawn the Raffle contract. It's different from the Raffle Owner

  // Structure of prize tier for winners
  struct PrizeTier {
    // winning number - your lucky
    uint[] winNumbers;
    // number of winners for the prize tier
    uint8 numberOfWinners;
    // amount of the winnings per user per tier
    uint amountOfWinning;
  }

  // Raffle parameters
  address public raffleOwner; // address to fund the raised money to, who wanna raise the funds
  uint public raffleAmount = 1 ether; // Default 1 ether. The total amount of the raffle
  uint public ticketCost = 20 finney; // Default 0.02 ether. The cost of the ticket
  uint8 public numberOfPrizeTiers = 2; // Default 2 tiers. Number of prize tiers
  PrizeTier[] public prizeTiers; // Prize tiers
  uint public feePercentage;

  // Raffle limitation
  uint private constant MIN_TICKET_COST = 10 finney; // Minimum ticket cost is 0.01 ether
  uint private constant MAX_RAFFLE_AMOUNT = 1000 ether; // Maximum amount of ether which this raffle can raise
  uint private constant MAX_NUMBER_PRIZE_TIERS = 100; // Maximum number of prize tiers

  // Raffle variables
  uint public currentTicket = 0;
  uint public totalBet = 0; // The total amount of Ether raised for this current raffle
  uint public numberOfTickets; // = raffleAmount / ticketCost

  // For Random generation
  uint private latestBlockNumber;
  bytes32 private cumulativeHash;

  mapping(uint => address) numberBetPlayers; // Each number has a player.

  // event when buy a ticket
  event BuyTicket(uint _numberToBet, address _holder, uint _count);
  // event when draw winners per tier
  event DrawWinners(uint _winNumber, uint _amountOfWinning, uint8 _prizeTier);
  // event when transfer prize to a winner
  event WithdrawToWinner(address _winner, uint _winNumber, uint _amountOfWinning, uint8 _prizeTier);
  // event when withdraw raised funds to the raffle owner
  event WithdrawToOwner(uint _total);
  // distribute prize to winners
  event WithdrawFeeToSpawner(uint _fee);

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
    if(totalBet >= raffleAmount) _;
  }

  /**
   * @notice Constructor that's used to configure the minimum bet per game and the max amount of bets
   * @param _raffleAmount The total amount of the raffle
   * @param _ticketCost The cost of the ticket
   * @param _numberOfPrizeTiers Number of prize tiers
   */
  constructor(address _raffleOwner, uint _feePercentage, uint _raffleAmount, uint _ticketCost, uint8 _numberOfPrizeTiers) public {
    spawner = msg.sender;

    require(_raffleOwner != address(0), "should be valid address");
    require(_feePercentage < 100, "fee should be less than 100 %");

    if(_raffleAmount > 0 && _raffleAmount <= MAX_RAFFLE_AMOUNT) raffleAmount = _raffleAmount;
    if(_ticketCost > MIN_TICKET_COST && _ticketCost <= _raffleAmount) ticketCost = _ticketCost;
    if(_numberOfPrizeTiers >= 1 && _numberOfPrizeTiers <= MAX_NUMBER_PRIZE_TIERS) numberOfPrizeTiers = _numberOfPrizeTiers;

    latestBlockNumber = block.number;
    cumulativeHash = bytes32(0);

    feePercentage = _feePercentage;
    raffleOwner = _raffleOwner;
    numberOfTickets = (raffleAmount + ticketCost - 1) / ticketCost;
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
      prizeTiers.push(PrizeTier({
        winNumbers: new uint[](_arrayNumberOfWinners[i]),
        numberOfWinners: _arrayNumberOfWinners[i],
        amountOfWinning: _arrayAmountOfWinning[i]
      }));
    }
  }

  /**
   * @notice Buy bulk tickets at once
   * @param _count Count of bulk tickets
   */
  function buyBulkTickets(uint _count) external payable {
    // Check that the max amount of bets hasn't been met yet
    require(currentTicket < numberOfTickets, "raffle amount is reached");
    // Check if ticket cost is correct
    require(msg.value == ticketCost * _count, "ticket cost is not correct");
    
    uint i = 0;
    for (i = 0; i < _count; i++) {
      currentTicket ++;
      // The player msg.sender has bet for this number 'currentTicket'
      numberBetPlayers[currentTicket] = msg.sender;
      // calculate total bet for this raffle
      totalBet = safeAdd(totalBet, ticketCost);
      
      if (currentTicket >= numberOfTickets) {
        break;
      }
      
      cumulativeHash = keccak256(abi.encodePacked(blockhash(latestBlockNumber), block.difficulty, cumulativeHash));
      latestBlockNumber = block.number;
    }
    
    if (currentTicket >= numberOfTickets) {
      drawWinners();
    }
    
    emit BuyTicket(currentTicket, msg.sender, i);
  }

  /**
   @notice check if random number is duplicated
   */
  function checkDupRandom(uint rand) private view returns(bool) {
    uint8 i;
    uint8 j;
    for(i = 0; i < numberOfPrizeTiers; i--) {
      for(j = 0; j < prizeTiers[i].numberOfWinners; j++) {
        // doing for in the same sequence as drawwinners, so if it meets first empty value, it's okay to return false
        if(prizeTiers[i].winNumbers[j] == uint(0)) return false;

        if(prizeTiers[i].winNumbers[j] == rand) return true;
      }
    }
    return false;
  }

  /**
   * @notice Generates a random number between 1 and numberOfTickets both inclusive.
   */
  function drawWinners() private onEndGame isFilledPrizeTiers {
    // cumulativeHash will be used to generate random numbers
    bytes32 baseHash = keccak256(abi.encodePacked(blockhash(latestBlockNumber), block.difficulty, cumulativeHash));
    uint randomNumber = uint(baseHash) % numberOfTickets + 1;

    uint8 i;
    uint8 j;
    for(i = 0; i < numberOfPrizeTiers; i++) {
      for(j = 0; j < prizeTiers[i].numberOfWinners; j++) {
        // make sure the win number is not duplicated for different tiers
        while(checkDupRandom(randomNumber)) {
          // update hash for random
          baseHash = keccak256(abi.encodePacked(blockhash(latestBlockNumber), baseHash));
          // generate random number and save it in PrizeTier struct. the random number will be in a range of 1 to numberOfTickets
          randomNumber = uint(baseHash) % numberOfTickets + 1;
        }
        prizeTiers[i].winNumbers[j] = randomNumber;
        // emit event when draw winners per tier
        emit DrawWinners(prizeTiers[i].winNumbers[j], prizeTiers[i].amountOfWinning, i + 1);
      }
    }

    distributePrizes();
  }

  /**
   * @notice Sends the corresponding Ether to each winner then deletes all the
   * players for the next game and resets the `totalBet` and `currentTicket`
   */
  function distributePrizes() private onEndGame isFilledPrizeTiers {
    // pay fee to RafflePanda company
    if(feePercentage > 0) {
      uint fee;
      fee = safeDiv(safeMul(totalBet, feePercentage), 100);
      feePercentage = 0;
      spawner.transfer(fee);
      totalBet = safeSub(totalBet, fee);

      // event log when withdraw fees to the contract spawner
      emit WithdrawFeeToSpawner(fee);
    }

    // Loop through all the winners to send the corresponding prize for each one
    uint8 i;
    uint8 j;
    for(i = 0; i < numberOfPrizeTiers; i++) {
      for(j = 0; j < prizeTiers[i].numberOfWinners; j++) {
        // withdraw prize to winner's address
        numberBetPlayers[prizeTiers[i].winNumbers[j]].transfer(prizeTiers[i].amountOfWinning);
        totalBet = safeSub(totalBet, prizeTiers[i].amountOfWinning);
        // event log when withdraw the prize to a winner
        emit WithdrawToWinner(numberBetPlayers[prizeTiers[i].winNumbers[j]], prizeTiers[i].winNumbers[j], prizeTiers[i].amountOfWinning, i + 1);
      }
    }

    // raised funds are sent to the raffle owner(fundraiser)
    raffleOwner.transfer(totalBet);
    emit WithdrawToOwner(totalBet);
    totalBet = 0;
    currentTicket = 0;

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
