pragma solidity ^0.5.2;

/**
 * @title Token interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
interface IToken {
  function transfer(address to, uint256 value) external returns (bool);
  function burnUnsoldTokens() external returns (bool);
}

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {
  /**
   * @dev Multiplies two unsigned integers, reverts on overflow.
   */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b);

    return c;
  }

  /**
   * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
   */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0);
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  /**
   * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
   */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a);
    uint256 c = a - b;

    return c;
  }

  /**
   * @dev Adds two unsigned integers, reverts on overflow.
   */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a);

    return c;
  }

  /**
   * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
   * reverts when dividing by zero.
   */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}

/**
 * @title SafeTransfer
 * @dev Wrappers around ERC20 operations that throw on failure.
 * To use this library you can add a `using SafeTransfer for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeTransfer {
  using SafeMath for uint256;

  function safeTransfer(IToken token, address to, uint256 value) internal {
    require(token.transfer(to, value));
  }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address private _owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  constructor () internal {
    _owner = msg.sender;
    emit OwnershipTransferred(address(0), _owner);
  }

  /**
   * @return the address of the owner.
   */
  function owner() public view returns (address) {
    return _owner;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(isOwner());
    _;
  }

  /**
   * @return true if `msg.sender` is the owner of the contract.
   */
  function isOwner() public view returns (bool) {
    return msg.sender == _owner;
  }

  /**
   * @dev Allows the current owner to relinquish control of the contract.
   * @notice Renouncing to ownership will leave the contract without an owner.
   * It will not be possible to call the functions with the `onlyOwner`
   * modifier anymore.
   */
  function renounceOwnership() public onlyOwner {
    emit OwnershipTransferred(_owner, address(0));
    _owner = address(0);
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    _transferOwnership(newOwner);
  }

  /**
   * @dev Transfers control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function _transferOwnership(address newOwner) internal {
    require(newOwner != address(0));
    emit OwnershipTransferred(_owner, newOwner);
    _owner = newOwner;
  }
}

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conform
 * the base architecture for crowdsales. They are *not* intended to be modified / overridden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropriate to concatenate
 * behavior.
 */
contract Crowdsale is Ownable {
  using SafeMath for uint256;
  using SafeTransfer for IToken;

  // The token being sold
  IToken private _token;

  mapping (address => bool) private _whitelist;

  enum Stages {Inactive, PrivateSale, PreSale, MainSale, SaleIsOver}

  Stages currentStage;

  struct StageDetails {
    uint256 price; // EUR per 1000 tokens
    uint256 hardCap; // in tokens
    uint256 sold; // in tokens
    uint8 discount; // in %
    uint256 startDate; // Unix timestamp, UTC
    uint256 endDate; // Unix timestamp, UTC
    string name; // stage name
  }

  mapping (uint8 => StageDetails) stage;

  bool saleOver = false;

  /**
   * Event for token purchase logging
   * @param purchaser who paid for the tokens
   * @param beneficiary who got the tokens
   * @param value weis paid for purchase
   * @param amount amount of tokens purchased
   */
  event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

  /**
   * @param newOwner Address of the contract owner
   * @param token Address of the token being sold
   */
  constructor (address newOwner, IToken token) public {
    require(newOwner != address(0));
    require(address(token) != address(0));
    _token = token;

    stage[uint8(Stages.Inactive)] = StageDetails(0, 0, 0, 0, 0, 0, 'Inactive');
    stage[uint8(Stages.SaleIsOver)] = StageDetails(0, 0, 0, 0, 0, 0, 'Sale Is Over');
    /**
     * Private sale, price 0.065 EUR per token, Hard Cap 700 000 000 tokens,
     * start 01/08/2019 00:00:00, end 31/12/2019 23:59:59
     */
    stage[uint8(Stages.PrivateSale)] = StageDetails(65, 7e26, 0, 35, 1564617600, 1577836799, 'Private-sale');
    /**
     * Pre sale, price 0.085 EUR per token, Hard Cap 350 000 000 tokens,
     * start 01/01/2020 00:00:00, end 31/03/2020 23:59:59
     */
    stage[uint8(Stages.PreSale)] = StageDetails(85, 35e25, 0, 15, 1577836800, 1585699199, 'Pre-sale');
    /**
     * Main sale, price 0.1 EUR per token, Hard Cap 350 000 000 tokens,
     * start 01/04/2020 00:00:00, end 30/06/2020 23:59:59
     */
    stage[uint8(Stages.MainSale)] = StageDetails(100, 35e25, 0, 0, 1585699200, 1593561599, 'Main sale');
    transferOwnership(newOwner);
  }

  /**
   * @dev fallback function ***DO NOT OVERRIDE***
   * Note that other contracts will transfer fund with a base gas stipend
   * of 2300, which is not enough to call buyTokens. Consider calling
   * buyTokens directly when purchasing tokens from a contract.
   */
  function () external payable {
    revert();
  }

  /**
   * @return the token being sold.
   */
  function token() public view returns (IToken) {
    return _token;
  }

  /**
   * @return current stage index.
   */
  function currentStageIndex() public view returns (uint8) {
    if (now < stage[uint8(Stages.PrivateSale)].startDate) return uint8(0);
    if (now < stage[uint8(Stages.PreSale)].startDate) return uint8(1);
    if (now < stage[uint8(Stages.MainSale)].startDate) return uint8(2);
    if (now <= stage[uint8(Stages.MainSale)].endDate) return uint8(3);
    return uint8(4);
  }

  /**
   * @return current stage price in EUR per 1000 tokens.
   */
  function currentStagePrice() public view returns (uint256) {
    uint8 stageIndex = currentStageIndex();
    return stage[stageIndex].price;
  }

  /**
   * @return current stage tokens Hard Cap.
   */
  function currentStageHardCap() public view returns (uint256) {
    uint8 stageIndex = currentStageIndex();
    return stage[stageIndex].hardCap;
  }

  /**
   * @return current stage sold tokens.
   */
  function currentStageSoldTokens() public view returns (uint256) {
    uint8 stageIndex = currentStageIndex();
    return stage[stageIndex].sold;
  }

  /**
   * @return current stage discount.
   */
  function currentStageDiscount() public view returns (uint8) {
    uint8 stageIndex = currentStageIndex();
    return stage[stageIndex].discount;
  }

  /**
   * @return current stage name.
   */
  function currentStageName() public view returns (string memory) {
    uint8 stageIndex = currentStageIndex();
    return stage[stageIndex].name;
  }

  /**
   * @return sale status.
   */
  function saleActive() public view returns (bool) {
    uint8 stageIndex = currentStageIndex();
    return (stageIndex >=1 && stageIndex <= 3);
  }

  /**
   * @param recipient - beneficiary address
   * @param tokenAmount - token amount
   */
  function sendTokens(address recipient, uint256 tokenAmount) public onlyOwner returns(bool) {
    require(!saleOver);
    uint8 stageIndex = currentStageIndex();
    require(stageIndex >=1 && stageIndex <= 3);
    require(recipient != address(0));
    require(tokenAmount > 0);

    require(tokenAmount.add(stage[stageIndex].sold) <= stage[stageIndex].hardCap);
    stage[stageIndex].sold = tokenAmount.add(stage[stageIndex].sold);

    _deliverTokens(recipient, tokenAmount);
    return true;
  }

  /**
   * @dev burns unsold tokens
   */
  function terminateSale() public onlyOwner returns(bool) {
    require(!saleOver);
    uint8 stageIndex = currentStageIndex();
    require(stageIndex > 3);
    require(_token.burnUnsoldTokens());
    saleOver = true;
    return true;
  }

  /**
   * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
   * @param recipient Address where tokens will be sent
   * @param tokenAmount Number of tokens to be sent
   */
  function _deliverTokens(
    address recipient,
    uint256 tokenAmount
  )
    internal
  {
    _token.safeTransfer(recipient, tokenAmount);
  }

  /**
   * @dev get date parameter
   */
  function getPrivateSaleStartDate () public view returns (uint256) {
    return stage[uint8(Stages.PrivateSale)].startDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setPrivateSaleStartDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.PrivateSale)].startDate > now, 'Private sale start date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate < stage[uint8(Stages.PrivateSale)].endDate, 'New date should be less than Private sale end date');
    stage[uint8(Stages.PrivateSale)].startDate = newDate;
    return true;
  }

  /**
   * @dev get date parameter
   */
  function getPrivateSaleEndDate () public view returns (uint256) {
    return stage[uint8(Stages.PrivateSale)].endDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setPrivateSaleEndDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.PrivateSale)].endDate > now, 'Private sale end date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate > stage[uint8(Stages.PrivateSale)].startDate, 'New date should be greater than Private sale start date');
    require (newDate < stage[uint8(Stages.PreSale)].startDate, 'New date should be less than Pre sale start date');
    stage[uint8(Stages.PrivateSale)].endDate = newDate;
    return true;
  }

  /**
   * @dev get date parameter
   */
  function getPreSaleStartDate () public view returns (uint256) {
    return stage[uint8(Stages.PreSale)].startDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setPreSaleStartDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.PreSale)].startDate > now, 'Pre sale start date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate > stage[uint8(Stages.PrivateSale)].endDate, 'New date should be greater than Private sale end date');
    require (newDate < stage[uint8(Stages.PreSale)].endDate, 'New date should be less than Pre sale end date');
    stage[uint8(Stages.PreSale)].startDate = newDate;
    return true;
  }

  /**
   * @dev get date parameter
   */
  function getPreSaleEndDate () public view returns (uint256) {
    return stage[uint8(Stages.PreSale)].endDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setPreSaleEndDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.PreSale)].endDate > now, 'Pre sale end date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate > stage[uint8(Stages.PreSale)].startDate, 'New date should be greater than Pre sale start date');
    require (newDate < stage[uint8(Stages.MainSale)].startDate, 'New date should be less than Main sale start date');
    stage[uint8(Stages.PreSale)].endDate = newDate;
    return true;
  }

  /**
   * @dev get date parameter
   */
  function getMainSaleStartDate () public view returns (uint256) {
    return stage[uint8(Stages.MainSale)].startDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setMainSaleStartDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.MainSale)].startDate > now, 'Main sale start date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate > stage[uint8(Stages.PreSale)].endDate, 'New date should be greater than Pre sale end date');
    require (newDate < stage[uint8(Stages.MainSale)].endDate, 'New date should be less than Main sale end date');
    stage[uint8(Stages.MainSale)].startDate = newDate;
    return true;
  }

  /**
   * @dev get date parameter
   */
  function getMainSaleEndDate () public view returns (uint256) {
    return stage[uint8(Stages.MainSale)].endDate;
  }

  /**
   * @dev change date parameter
   * @param newDate - new date
   */
  function setMainSaleEndDate (uint256 newDate) public onlyOwner returns (bool) {
    require (stage[uint8(Stages.MainSale)].endDate > now, 'Main sale end date can not be changed');
    require (newDate > now, 'New date should be in future');
    require (newDate > stage[uint8(Stages.MainSale)].startDate, 'New date should be greater than Main sale start date');
    stage[uint8(Stages.MainSale)].endDate = newDate;
    return true;
  }
}