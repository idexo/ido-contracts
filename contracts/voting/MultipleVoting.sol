// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IStakePool.sol";

/**
 * Voting contract that offers multiple options to voters.
 */

contract MultipleVoting is Ownable, AccessControl {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    Counters.Counter public pollIds;
    IStakePool[] private _stakePools;

    /* EVENTS  */
    event VoteCasted(address indexed voter, uint256 pollID, uint256 vote, uint256 weight);
	event PollCreated(address indexed creator, uint256 pollID, uint256 votingTimeInDays);
	event PollEnded(uint256 pollID, uint256 winningOptionID);

    /* Determine the current state of a poll */
	enum PollStatus {
        IN_PROGRESS,
        ENDED
    }

    /* POLL */
    struct Poll {
		uint256 startTime; // poll start timestamp
		uint256 endTime; // poll end timestamp
        uint256 minimumStakeTimeInDays; // number of days that implies how long stakers should remain staked in StakePools to be able to vote
		string description; // poll description
        string[] options; // poll option string
		PollStatus status; // poll status (IN_PROGRESS, ENDED)
		address creator; // poll creator address
		address[] voters; // poll voter address array
	}

    /* VOTER */
    struct Voter {
        bool voted; // true implies voter already voted
        uint256 vote; // vote option index
        uint256 weight; // voter's voting weight (derived from StakePool)
    }

    // poll id => poll info
    mapping(uint256 => Poll) private _polls;
    // poll id => voter address => voting info
    mapping(uint256 => mapping(address => Voter)) private _voters;
    // poll id => option id => vote cast number
    mapping(uint256 => mapping(uint256 => uint256)) private _votes;

    constructor(
        address[] memory stakePools_
    )
    {
        for (uint256 i = 0; i < stakePools_.length; i++) {
            require(stakePools_[i] != address(0), "MultipleVoting#constructor: STAKE_POOL_ADDRESS_INVALID");
            _stakePools.push(IStakePool(stakePools_[i]));
        }

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "MultipleVoting#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "MultipleVoting#onlyOperator: CALLER_NO_OPERATOR_ROLE");
        _;
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(
        address account
    )
        public
        onlyAdmin
    {
        require(!hasRole(OPERATOR_ROLE, account), "MultipleVoting#addOperator: ALREADY_OERATOR_ROLE");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(
        address account
    )
        public
        onlyAdmin
    {
        require(hasRole(OPERATOR_ROLE, account), "MultipleVoting#removeOperator: NO_OPERATOR_ROLE");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(
        address account
    )
        public
        view
        returns (bool)
    {
        return hasRole(OPERATOR_ROLE, account);
    }

    /*****************************|
    |          Stake Pool         |
    |____________________________*/

    /**
     * @dev Add a new stake pool.
     * @param _sPool new stake pool address.
     */
    function addStakePool(
        address _sPool
    )
        external
        onlyOperator
    {
        require(_sPool != address(0), "MultipleVoting#addStakePool: STAKE_POOL_ADDRESS_INVALID");
        for (uint256 i = 0; i < _stakePools.length; i++) {
            require(address(_stakePools[i]) != _sPool, "MultipleVoting#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND");
        }
        _stakePools.push(IStakePool(_sPool));
    }

    /**
     * @dev Remove from stake pool addresses.
     * @param _sPool stake pool address.
     */
    function removeStakePool(
        address _sPool
    )
        external
        onlyOperator
    {
        bool isDeleted;
        require(_sPool != address(0), "MultipleVoting#removeStakePool: STAKE_POOL_ADDRESS_INVALID");
        for (uint256 i = 0; i < _stakePools.length; i++) {
            if (address(_stakePools[i]) == _sPool) {
                if (i != _stakePools.length - 1) {
                    _stakePools[i] = _stakePools[_stakePools.length - 1];
                }
                _stakePools.pop();
                isDeleted = true;
                break;
            }
        }
        require(isDeleted, "MultipleVoting#removeStakePool: STAKE_POOL_ADDRESS_NOT_FOUND");
    }

    /**
     * @dev Return array of stake pool address.
     */
    function getStakePools()
        external
        view
        returns (address[] memory)
    {
        address[] memory sPoolAddrs = new address[](_stakePools.length);
        for (uint256 i = 0; i < _stakePools.length; i++) {
            sPoolAddrs[i] = address(_stakePools[i]);
        }
        return sPoolAddrs;
    }

    /***********************|
    |          Poll         |
    |______________________*/

    /*
	 * Modifier that checks for a valid poll ID.
	 */
	modifier validPoll(
        uint256 _pollId
    )
	{
		require(_pollId > 0 && _pollId <= pollIds.current(), "MultipleVoting#validPoll: POLL_ID_INVALID");
		_;
	}

    /* GETTERS */

    /**
     * @dev Return poll info.
     * Except for voting result.
     *
     * @param _pollId poll id
     * @return description string, option string array, poll startTime, endTime, minimumStakeTimeInDays, status(IN_PROGRESS, ENDED), creator address, voter address array
     */
    function getPoll(
        uint256 _pollId
    )
        public
        view
        validPoll(_pollId)
        returns (string memory, string[] memory, uint256, uint256, uint256, PollStatus, address, address[] memory)
    {
        Poll memory poll = _polls[_pollId];
        return (poll.description, poll.options, poll.startTime, poll.endTime, poll.minimumStakeTimeInDays, poll.status, poll.creator, poll.voters);
    }

    /**
     * @dev Return poll all info including voting result.
     * Only accessible by operators.
     *
     * @param _pollId poll id
     * @return description string, option string array, poll startTime, endTime, minimumStakeTimeInDays, status(IN_PROGRESS, ENDED), creator address, voter address array, voting option result
     */
    function getPollForOperator(
        uint256 _pollId
    )
        public
        view
        onlyOperator
        validPoll(_pollId)
        returns (string memory, string[] memory, uint256, uint256, uint256, PollStatus, address, address[] memory, uint256[] memory)
    {
        Poll memory poll = _polls[_pollId];
        uint256[] memory votes = new uint256[](poll.options.length);
        for (uint256 i = 0; i < votes.length; i++) {
            votes[i] = _votes[_pollId][i];
        }
        return (poll.description, poll.options, poll.startTime, poll.endTime, poll.minimumStakeTimeInDays, poll.status, poll.creator, poll.voters, votes);
    }

    /**
     * @dev Return `_voter` info for `_pollId` poll.
     * Except for voting option.
     *
     * @param _pollId poll id
     * @param _voter address of voter
     */
    function getVoter(
        uint256 _pollId,
        address _voter
    )
        public
        view
        validPoll(_pollId)
        returns (bool, uint256)
    {
        return (_voters[_pollId][_voter].voted, _voters[_pollId][_voter].weight);
    }

    /**
     * @dev Return `_voter` all info for `_pollId` poll.
     * Only accessible by operators.
     *
     * @param _pollId poll id
     * @param _voter address of voter
     */
    function getVoterForOperator(
        uint256 _pollId,
        address _voter
    )
        public
        view
        onlyOperator
        validPoll(_pollId)
        returns (bool, uint256, uint256)
    {
        return (_voters[_pollId][_voter].voted, _voters[_pollId][_voter].vote, _voters[_pollId][_voter].weight);
    }

    /**
	 * @dev Create a new poll.
     *
     * @param _description poll description.
     * @param _durationTimeInDays poll duration time.
     * @param _minimumStakeTimeInDays minimum stake duration time for poll voters.
	 */
    function createPoll(
        string memory _description,
        string[] memory _options,
        uint256 _durationTimeInDays,
        uint256 _minimumStakeTimeInDays
    )
        external
        onlyOperator
        returns (uint256)
    {
        require(bytes(_description).length > 0, "MultipleVoting#createPoll: DESCRIPTION_INVALID");
        require(_options.length > 1, "MultipleVoting#createPoll: OPTIONS_INVALID");
        require(_durationTimeInDays > 0, "MultipleVoting#createPoll: DURATION_TIME_INVALID");

        pollIds.increment();
        Poll storage poll = _polls[pollIds.current()];
        poll.startTime = block.timestamp;
        poll.endTime = block.timestamp.add(_durationTimeInDays.mul(1 days));
        poll.minimumStakeTimeInDays = _minimumStakeTimeInDays;
        poll.description = _description;
        poll.options = _options;
        poll.creator = _msgSender();

        emit PollCreated(_msgSender(), pollIds.current(),_durationTimeInDays);
        return pollIds.current();
    }

    /**
	 * @dev End `_pollId` poll.
     *
     * @param _pollId poll id.
	 */
    function endPoll(
        uint256 _pollId
    )
        external
        onlyOperator
        validPoll(_pollId)
    {
        uint256 winningOptionId;
        uint256 maxVotes;
        Poll storage poll = _polls[_pollId];
        require(block.timestamp >= poll.endTime, "MultipleVoting#endPoll: VOTING_PERIOD_NOT_EXPIRED");
        require(poll.status == PollStatus.IN_PROGRESS, "MultipleVoting#endPoll: POLL_ALREADY_ENDED");
        poll.status = PollStatus.ENDED;
        // decide winning option
        for (uint256 i = 0; i < poll.options.length; i++) {
            if (maxVotes < _votes[_pollId][i]) {
                maxVotes = _votes[_pollId][i];
                winningOptionId = i;
            }
        }

        emit PollEnded(_pollId, winningOptionId);
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
    )
        public
        view
        validPoll(_pollId)
        returns (bool)
    {
        return _voters[_pollId][_account].voted;
    }

    /***********************|
    |          Vote         |
    |______________________*/

    /**
	 * @dev User vote `_vote` for `_pollId`.
     *
     * @param _pollId poll id.
     * @param _optionId voting option id.
	 */
    function castVote(
        uint256 _pollId,
        uint256 _optionId
    )
        external
        validPoll(_pollId)
    {
        Poll storage poll = _polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "MultipleVoting#castVote: POLL_ALREADY_ENDED");
        require(block.timestamp < poll.endTime, "MultipleVoting#castVote: VOTING_PERIOD_EXPIRED");
        require(!checkIfVoted(_pollId, _msgSender()), "MultipleVoting#castVote: USER_ALREADY_VOTED");

        uint256 w = getWeight(_pollId, _msgSender());
        _votes[_pollId][_optionId]++;

        Voter storage voter = _voters[_pollId][_msgSender()];
        voter.voted = true;
        voter.vote = _optionId;
        voter.weight = w;

        emit VoteCasted(_msgSender(), _pollId, _optionId, w);
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
    function getWeight(
        uint256 _pollId,
        address _account
    )
        public
        validPoll(_pollId)
        returns (uint256)
    {
        require(_account != address(0), "MultipleVoting#getWeight: ACCOUNT_INVALID");
        uint256 w = 0; // total weight
        Poll memory poll = _polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "MultipleVoting#getWeight: POLL_ALREADY_ENDED");

        for (uint256 i = 0; i < _stakePools.length; i++) {
            IStakePool sPool = _stakePools[i];
            uint256[] memory sTokenIds = sPool.getTokenId(_account);
            for (uint256 j = 0; j < sTokenIds.length; j++) {
                (uint256 amount, uint256 multiplier, uint256 depositedAt) = sPool.getStake(sTokenIds[j]);
                if (depositedAt < poll.startTime.sub(poll.minimumStakeTimeInDays.mul(1 days))) {
                    w = w.add(amount.mul(multiplier).div(100));
                }
            }
        }
        return w;
    }
}
