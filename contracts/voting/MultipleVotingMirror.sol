// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IStakeMirrorNFT.sol";

/**
 * Voting contract that offers multiple options to voters.
 */

contract MultipleVotingMirror is Ownable, AccessControl {
  /* POLL */
  struct Poll {
    uint256 startTime; // poll start timestamp
    uint256 endTime; // poll end timestamp
    uint8 minimumStakeTimeInDays; // number of days that implies how long stakers should remain staked in stake pool to vote
    uint8 winningOptionId; // poll result, starts from 1
    string description; // poll description
    string[] options; // poll option string, first option string is default empty ('')
    address creator; // poll creator address
    address[] voters; // poll voter address array
  }

  /* VOTER */
  struct Voter {
    uint8 optionId; // vote option index, `0` implies he/she did not cast vote
    uint256 weight; // voter's voting weight (derived from stake pool)
  }

  // poll id => poll info
  mapping(uint256 => Poll) private _polls;
  // poll id => voter address => voter info
  mapping(uint256 => mapping(address => Voter)) private _voters;
  // poll id => option id => vote cast number
  mapping(uint256 => mapping(uint8 => uint256)) private _votes;
  // stake pool address => status
  mapping(address => bool) public isStakePool;

  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  uint256 public pollIds;
  IStakeMirrorNFT[] public stakePools;

  /* EVENTS  */
  event VoteCasted(address indexed voter, uint256 pollID, uint8 optionId, uint256 weight);
  event PollCreated(address indexed creator, uint256 pollID);

  constructor(address[] memory stakePools_) {
    for (uint256 i = 0; i < stakePools_.length; i++) {
      if (stakePools_[i] != address(0)) {
        stakePools.push(IStakeMirrorNFT(stakePools_[i]));
        isStakePool[stakePools_[i]] = true;
      }
    }

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(OPERATOR_ROLE, msg.sender);
  }

  /***********************|
  |          Role         |
  |______________________*/

  /**
    * @dev Restricted to members of the admin role.
    */
  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "CALLER_NO_ADMIN_ROLE");
    _;
  }

  /**
    * @dev Restricted to members of the operator role.
    */
  modifier onlyOperator() {
    require(hasRole(OPERATOR_ROLE, msg.sender), "CALLER_NO_OPERATOR_ROLE");
    _;
  }

  /**
    * @dev Add an account to the operator role.
    * @param account address
    */
  function addOperator(address account) public onlyAdmin {
    grantRole(OPERATOR_ROLE, account);
  }

  /**
    * @dev Remove an account from the operator role.
    * @param account address
    */
  function removeOperator(address account) public onlyAdmin {
    revokeRole(OPERATOR_ROLE, account);
  }

  /**
    * @dev Check if an account is operator.
    * @param account address
    */
  function checkOperator(address account) public view returns (bool) {
    return hasRole(OPERATOR_ROLE, account);
  }

  /*****************************|
  |          Stake Pool         |
  |____________________________*/

  /**
    * @dev Add a new stake pool.
    * @param _sPool new stake pool address.
    */
  function addStakePool(address _sPool) external onlyOperator {
    require(_sPool != address(0), "STAKE_POOL_ADDRESS_INVALID");
    require(_isContract(_sPool), "STAKE_POOL_NOT_CONTRACT");
    require(!isStakePool[_sPool], "STAKE_POOL_ADDRESS_ALREADY_FOUND");
    stakePools.push(IStakeMirrorNFT(_sPool));
    isStakePool[_sPool] = true;
  }

  /**
    * @dev Remove from stake pool addresses.
    * @param _sPool stake pool address.
    */
  function removeStakePool(address _sPool) external onlyOperator {
    require(isStakePool[_sPool], "STAKE_POOL_ADDRESS_NOT_FOUND");
    uint256 len = stakePools.length;

    for (uint256 i = 0; i < len; i++) {
      if (address(stakePools[i]) == _sPool) {
        if (i != len - 1) {
          stakePools[i] = stakePools[len - 1];
        }
        stakePools.pop();
        break;
      }
    }

    isStakePool[_sPool] = false;
  }

  /***********************|
  |          Poll         |
  |______________________*/

  /*
    * Modifier that checks for a valid poll ID.
    */
  modifier validPoll(uint256 _pollId) {
    require(_pollId > 0 && _pollId <= pollIds, "POLL_ID_INVALID");
    _;
  }

  /* GETTERS */

  /**
    * @dev Return poll general info.
    * Except for voting result.
    *
    * @param _pollId poll id
    * @return description string, option string array, poll startTime, endTime, minimumStakeTimeInDays, creator address, voter address array
    */
  function getPollInfo(uint256 _pollId) public view validPoll(_pollId)
    returns (
      string memory,
      string[] memory,
      uint256,
      uint256,
      uint8,
      address,
      address[] memory
    )
  {
    Poll memory poll = _polls[_pollId];
    return (
      poll.description,
      poll.options,
      poll.startTime,
      poll.endTime,
      poll.minimumStakeTimeInDays,
      poll.creator,
      poll.voters
    );
  }

  /**
    * @dev Return poll voting info.
    * Operators can call any time.
    * After ended, any user can call.
    * @param _pollId poll id
    * @return poll votes detail (first element is default 0), poll winning option id (0 implies no votes happened)
    */
  function getPollVotingInfo(uint256 _pollId) public view validPoll(_pollId) returns (uint256[] memory, uint8) {
    Poll memory poll = _polls[_pollId];
    require(block.timestamp >= poll.endTime || checkOperator(msg.sender), "POLL_NOT_ENDED__CALLER_NO_OPERATOR");
    uint256[] memory votes = new uint256[](poll.options.length);

    for (uint8 i = 0; i < votes.length; i++) {
      votes[i] = _votes[_pollId][i];
    }

    return (votes, poll.winningOptionId);
  }

  /**
    * @dev Return `_voter` info for `_pollId` poll.
    * Operators can call any time.
    * After ended, any user can call.
    *
    * @param _pollId poll id
    * @param _voter address of voter
    * @return voting option id (`0` implies he/she did not cast vote), voting weight
    */
  function getVoterInfo(
    uint256 _pollId,
    address _voter
  ) public view validPoll(_pollId) returns (uint8, uint256) {
    require(block.timestamp >= _polls[_pollId].endTime || checkOperator(msg.sender), "POLL_NOT_ENDED__CALLER_NO_OPERATOR");
    Voter memory voter = _voters[_pollId][_voter];
    return (voter.optionId, voter.weight);
  }

  /**
    * @dev Create a new poll.
    */
  function createPoll(
    string memory _description,
    string[] memory _options,
    uint256 _startTime,
    uint256 _endTime,
    uint8 _minimumStakeTimeInDays
  ) public onlyOperator returns (uint256) {
    require(bytes(_description).length > 0, "DESCRIPTION_INVALID");
    require(_options.length > 1, "OPTIONS_INVALID" );
    require(_startTime >= block.timestamp, "START_TIME_INVALID");
    require(_endTime > _startTime, "END_TIME_INVALID");

    uint256 newPollId = pollIds + 1;
    pollIds = newPollId;
    Poll storage poll = _polls[newPollId];
    poll.startTime = _startTime;
    poll.endTime = _endTime;
    poll.minimumStakeTimeInDays = _minimumStakeTimeInDays;
    poll.description = _description;
    poll.options.push("");

    for (uint8 i = 0; i < _options.length; i++) {
      poll.options.push(_options[i]);
    }

    poll.creator = msg.sender;
    emit PollCreated(msg.sender, newPollId);

    return newPollId;
  }

  /**
   * @dev Update poll `startTime` and `endTime`
   *
   * Poll must not be ended
   * If poll started, it is not allowed to set `startTime`
   */
  function updatePollTime(
    uint256 _pollId,
    uint256 _startTime,
    uint256 _endTime
  ) public onlyOperator validPoll(_pollId) {
    Poll storage poll = _polls[_pollId];
    uint256 startTime = poll.startTime;
    bool started = startTime < block.timestamp;
    bool ended = poll.endTime < block.timestamp;
    require(!ended, "POLL_ENDED");

    if (_startTime >= block.timestamp && !started) {
      poll.startTime = _startTime;
      startTime = _startTime;
    }

    if (_endTime >= block.timestamp) {
      poll.endTime = _endTime;
    }
  }

  /**
    * @dev Check if `_account` already voted for `_pollId`.
    *
    * @param _pollId poll id.
    * @param _account user.
    */
  function checkIfVoted(
    uint256 _pollId,
    address _account
  ) public view validPoll(_pollId) returns (bool) {
    return _voters[_pollId][_account].optionId != 0;
  }

  /***********************|
  |          Vote         |
  |______________________*/

  /**
    * @dev User vote `_optionId` for `_pollId`.
    *
    * @param _pollId poll id.
    * @param _optionId voting option id.
    */
  function castVote(
    uint256 _pollId,
    uint8 _optionId
  ) external validPoll(_pollId) {
    require( _optionId > 0, "INVALID_VOTE_OPTION_ID");
    Poll storage poll = _polls[_pollId];
    require(block.timestamp < poll.endTime, "POLL_ENDED");
    require(!checkIfVoted(_pollId, msg.sender), "USER_VOTED");

    uint256 w = _getWeight(_pollId, msg.sender);
    uint256 optionVote = _votes[_pollId][_optionId] + w;
    _votes[_pollId][_optionId] = optionVote;

    // decide winning option id
    if (optionVote > _votes[_pollId][poll.winningOptionId]) {
      poll.winningOptionId = _optionId;
    }

    Voter storage voter = _voters[_pollId][msg.sender];
    voter.optionId = _optionId;
    voter.weight = w;

    emit VoteCasted(msg.sender, _pollId, _optionId, w);
}

  /*****************************|
  |          StakeToken         |
  |____________________________*/

  /**
    * @dev Get `_account` weight for `_pollId`.
    *
    * @param _pollId poll id.
    * @param _account.
    */
  function _getWeight(
    uint256 _pollId,
    address _account
  ) private validPoll(_pollId) returns (uint256) {
    require(_account != address(0), "ACCOUNT_INVALID");
    uint256 w; // total weight
    bool oldEnough = true;
    Poll memory poll = _polls[_pollId];
    require(block.timestamp < poll.endTime, "POLL_ENDED");

    for (uint256 i = 0; i < stakePools.length; i++) {
      IStakeMirrorNFT sPool = stakePools[i];
      uint256[] memory sTokenIds = sPool.getStakeTokenIds(_account);

      for (uint256 j = 0; j < sTokenIds.length; j++) {
        (uint256 amount, , uint256 depositedAt) = sPool.getStakeInfo(sTokenIds[j]);
        if (depositedAt +  poll.minimumStakeTimeInDays * 1 days < poll.startTime) {
          w += amount;
        } else {
          oldEnough = false;
        }
      }
    }
    require(w > 0, oldEnough ? "NO_VALID_VOTING_NFTS_PRESENT" : "STAKE_NOT_OLD_ENOUGH");
    return w;
  }

  /**
    * @dev Check if `_account` is contract
    */
  function _isContract(address _account) private view returns (bool) {
    uint size;

    assembly {
      size := extcodesize(_account)
    }

    return size > 0;
  }
}
