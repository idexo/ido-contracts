// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStakePool.sol";

/**
 If total votes of poll reach threshold `_pollMinimumVotes`, poll endures `_pollDurationInDays`.
 If not, poll expires within `_pollMaximumDurationInDays`.
 */

contract Voting1 is Ownable, AccessControl {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    Counters.Counter private _pollIds;
    IStakePool[] private _stakePools;

    /* Minimum votes threshold for poll to endure `_pollDurationInDays` */
    uint256 private _pollMinimumVotes;
    /* Maximum duration threshold in days that poll which did not reach `_pollMinimumVotes` expires */
    uint256 private _pollMaximumDurationInDays;
    /* Normal duration threshold for poll that reached `_pollMinimumVotes` */
    uint256 private _pollDurationInDays;

    /* EVENTS */
    event VoteCasted(address indexed voter, uint256 pollID, bool vote, uint256 weight);
	event PollCreated(address indexed creator, uint256 pollID, string description);
	event PollStatusUpdated(uint256 pollID, PollStatus status);

    /* Determine the current state of a poll */
	enum PollStatus {
        IN_PROGRESS,
        PASSED,
        REJECTED
    }

    /* POLL */
    struct Poll {
		uint256 yesVotes;
		uint256 noVotes;
		uint256 startTime;
		uint256 endTime;
        uint256 minimumStakeTimeInDays;
		string description;
		PollStatus status;
		address creator;
		address[] voters;
        bool reachedMinimumVotes;
	}

    /* VOTER */
    struct Voter {
        bool voted;
        bool vote;
        uint256 weight;
    }

    mapping(uint256 => Poll) private _polls;
    mapping(uint256 => mapping(address => Voter)) private _voters;

    constructor(
        address[] memory stakePools_,
        uint256 pollMinimumVotes_,
        uint256 pollMaximumDurationInDays_,
        uint256 pollDurationInDays_
    )
    {
        require(pollMinimumVotes_ > 0, "Voting1#constructor: POLL_MINIMUM_VOTES_INVALID");
        require(pollMaximumDurationInDays_ > 0, "Voting1#constructor: POLL_MAXIMUM_DURATION_INVALID");
        require(pollDurationInDays_ > 0, "Voting1#constructor: POLL_DURATION_INVALID");

        for (uint256 i = 0; i < stakePools_.length; i++) {
            require(stakePools_[i] != address(0), "Voting1#constructor: STAKE_POOL_ADDRESS_INVALID");
            _stakePools.push(IStakePool(stakePools_[i]));
        }

        _pollMinimumVotes = pollMinimumVotes_;
        _pollMaximumDurationInDays = pollMaximumDurationInDays_;
        _pollDurationInDays = pollDurationInDays_;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    function getPollMinimumVotes()
        public
        view
        returns (uint256)
    {
        return _pollMinimumVotes;
    }

    function setPollMinimumVotes(
        uint256 pollMinimumVotes_
    )
        public
        onlyOperator
    {
        require(pollMinimumVotes_ > 0, "Voting1#setPollMinimumVotes: POLL_MINIMUM_VOTES_INVALID");
        _pollMinimumVotes = pollMinimumVotes_;
    }

    function getPollMaximumDurationInDays()
        public
        view
        returns (uint256)
    {
        return _pollMaximumDurationInDays;
    }

    function setPollMaximumDurationInDays(
        uint256 pollMaximumDurationInDays_
    )
        public
        onlyOperator
    {
        require(pollMaximumDurationInDays_ > 0, "Voting1#setPollMaximumDurationInDays: POLL_MAXIMUM_DURATION_INVALID");
        _pollMaximumDurationInDays = pollMaximumDurationInDays_;
    }

    function getPollDurationInDays()
        public
        view
        returns (uint256)
    {
        return _pollDurationInDays;
    }

    function setPollDurationInDays(
        uint256 pollDurationInDays_
    )
        public
        onlyOperator
    {
        require(pollDurationInDays_ > 0, "Voting1#setPollDurationInDays: POLL_DURATION_INVALID");
        _pollDurationInDays = pollDurationInDays_;
    }

    /***********************|
    |          Role         |
    |______________________*/

    /**
     * @dev Restricted to members of the admin role.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Voting1#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Voting1#onlyOperator: CALLER_NO_OPERATOR_ROLE");
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
        require(!hasRole(OPERATOR_ROLE, account), "Voting1#addOperator: ALREADY_OERATOR_ROLE");
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
        require(hasRole(OPERATOR_ROLE, account), "Voting1#removeOperator: NO_OPERATOR_ROLE");
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
        require(_sPool != address(0), "Voting1#addStakePool: STAKE_POOL_ADDRESS_INVALID");
        for (uint256 i = 0; i < _stakePools.length; i++) {
            require(address(_stakePools[i]) != _sPool, "Voting1#addStakePool: STAKE_POOL_ADDRESS_ALREADY_FOUND");
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
        require(_sPool != address(0), "Voting1#removeStakePool: STAKE_POOL_ADDRESS_INVALID");
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
        require(isDeleted, "Voting1#removeStakePool: STAKE_POOL_ADDRESS_NOT_FOUND");
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
		require(_pollId > 0 && _pollId <= _pollIds.current(), "Voting1#validPoll: POLL_ID_INVALID");
		_;
	}

    /* GETTERS */

    /**
     * @dev Return poll info.
     * Except for yesVotes and noVotes.
     *
     * @param _pollId poll id
     */
    function getPoll(
        uint256 _pollId
    )
        public
        view
        validPoll(_pollId)
        returns (string memory, uint256, uint256, uint256, PollStatus, address, address[] memory, bool)
    {
        Poll memory poll = _polls[_pollId];
        return (poll.description, poll.startTime, poll.endTime, poll.minimumStakeTimeInDays, poll.status, poll.creator, poll.voters, poll.reachedMinimumVotes);
    }

    /**
     * @dev Return poll all info.
     * Only accessible by operators.
     *
     * @param _pollId poll id
     */
    function getPollForOperator(
        uint256 _pollId
    )
        public
        view
        onlyOperator
        validPoll(_pollId)
        returns (string memory, uint256, uint256, uint256, PollStatus, address, address[] memory, bool, uint256, uint256)
    {
        Poll memory poll = _polls[_pollId];
        return (poll.description, poll.startTime, poll.endTime, poll.minimumStakeTimeInDays, poll.status, poll.creator, poll.voters, poll.reachedMinimumVotes, poll.yesVotes, poll.noVotes);
    }

    /**
     * @dev Return `_voter` info for `_pollId` poll.
     * Except for yes/no result.
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
        returns (bool, bool, uint256)
    {
        return (_voters[_pollId][_voter].voted, _voters[_pollId][_voter].vote, _voters[_pollId][_voter].weight);
    }

    /**
	 * @dev Create a new poll.
     *
     * @param _description poll description.
     * @param _minimumStakeTimeInDays minimum stake duration time for poll voters.
	 */
    function createPoll(
        string memory _description,
        uint256 _minimumStakeTimeInDays
    )
        external
        onlyOperator
        returns (uint256)
    {
        require(bytes(_description).length > 0, "Voting1#createPoll: DESCRIPTION_INVALID");

        _pollIds.increment();
        Poll storage poll = _polls[_pollIds.current()];
        poll.startTime = block.timestamp;
        poll.endTime = block.timestamp.add(_pollMaximumDurationInDays.mul(1 days));
        poll.minimumStakeTimeInDays = _minimumStakeTimeInDays;
        poll.description = _description;
        poll.creator = _msgSender();

        emit PollCreated(_msgSender(), _pollIds.current(), _description);
        return _pollIds.current();
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
        Poll storage poll = _polls[_pollId];
        require(block.timestamp >= poll.endTime, "Voting1#endPoll: POLL_PERIOD_NOT_EXPIRED");
        require(poll.status == PollStatus.IN_PROGRESS, "Voting1#endPoll: POLL_ALREADY_ENDED");
        if (poll.yesVotes > poll.noVotes) {
            poll.status = PollStatus.PASSED;
        } else {
            poll.status = PollStatus.REJECTED;
        }

        emit PollStatusUpdated(_pollId, poll.status);
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
     * @param _vote bool.
	 */
    function castVote(
        uint256 _pollId,
        bool _vote
    )
        external
        validPoll(_pollId)
    {
        Poll storage poll = _polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "Voting1#castVote: POLL_ALREADY_ENDED");
        require(block.timestamp < poll.endTime, "Voting1#castVote: POLL_PERIOD_EXPIRED");
        require(!checkIfVoted(_pollId, _msgSender()), "Voting1#castVote: USER_ALREADY_VOTED");

        uint256 w = getWeight(_pollId, _msgSender());
        if (!poll.reachedMinimumVotes && poll.yesVotes.add(poll.noVotes).add(w) > _pollMinimumVotes) {
            poll.reachedMinimumVotes = true;
            poll.endTime = poll.startTime.add(_pollDurationInDays.mul(1 days));
        }
        if (_vote) {
            poll.yesVotes = poll.yesVotes.add(w);
        } else {
            poll.noVotes = poll.noVotes.add(w);
        }
        poll.voters.push(_msgSender());

        Voter storage voter = _voters[_pollId][_msgSender()];
        voter.voted = true;
        voter.vote = _vote;
        voter.weight = w;

        emit VoteCasted(_msgSender(), _pollId, _vote, w);
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
        require(_account != address(0), "Voting1#getWeight: ACCOUNT_INVALID");
        uint256 w = 0; // total weight
        Poll memory poll = _polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "Voting1#getWeight: POLL_ALREADY_ENDED");
        require(_stakePools.length > 0, "Voting1#getWeight: STAKE_POOL_EMPTY");

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
