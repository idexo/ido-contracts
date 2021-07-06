// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStakePool.sol";

contract Voting is Ownable, AccessControl {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    Counters.Counter public pollIds;
    IStakePool[] public stakePools;

    /* EVENTS  */
    event VoteCasted(address indexed voter, uint256 pollID, bool vote, uint256 weight);
	event PollCreated(address indexed creator, uint256 pollID, string description, uint256 votingTimeInDays);
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
	}

    /* VOTER */
    struct Voter {
        bool voted;
        bool vote;
        uint256 weight;
    }

    mapping(uint256 => Poll) public polls;
    mapping(uint256 => mapping(address => Voter)) public voters;

    constructor(
        address[] memory _stakePools
    )
    {
        for (uint256 i = 0; i < _stakePools.length; i++) {
            require(_stakePools[i] != address(0), "Voting#constructor: STAKE_POOL_ADDRESS_INVALID");
            stakePools.push(IStakePool(_stakePools[i]));
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
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Voting#onlyAdmin: CALLER_NO_ADMIN_ROLE");
        _;
    }

    /**
     * @dev Restricted to members of the operator role.
     */
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Voting#onlyOperator: CALLER_NO_OPERATOR_ROLE");
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
        require(!hasRole(OPERATOR_ROLE, account), "Voting#addOperator: ALREADY_OERATOR_ROLE");
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
        require(hasRole(OPERATOR_ROLE, account), "Voting#removeOperator: NO_OPERATOR_ROLE");
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

    /***********************|
    |          Poll         |
    |______________________*/

    /* GETTERS */

    /**
     * @dev Return poll info except for yesVotes and noVotes.
     *
     * @param _pollId poll id
     */
    function getPollInfo(
        uint256 _pollId
    )
        public
        view
        validPoll(_pollId)
        returns (string memory, uint256, uint256, uint256, PollStatus, address, address[] memory)
    {
        Poll memory poll = polls[_pollId];
        return (poll.description, poll.startTime, poll.endTime, poll.minimumStakeTimeInDays, poll.status, poll.creator, poll.voters);
    }

    /**
     * @dev Return poll yesVotes and noVotes.
     *
     * @param _pollId poll id
     */
    function getPollVotes(
        uint256 _pollId
    )
        public
        view
        onlyOperator
        validPoll(_pollId)
        returns (uint256, uint256)
    {
        Poll memory poll = polls[_pollId];
        return (poll.yesVotes, poll.noVotes);
    }

    /*
	 * Modifier that checks for a valid poll ID.
	 */
	modifier validPoll(
        uint256 _pollId
    )
	{
		require(_pollId > 0 && _pollId <= pollIds.current(), "Voting#validPoll: POLL_ID_INVALID");
		_;
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
        uint256 _durationTimeInDays,
        uint256 _minimumStakeTimeInDays
    )
        external
        onlyOperator
        returns (uint256)
    {
        require(bytes(_description).length > 0, "Voting#createPoll: DESCRIPTION_INVALID");
        require(_durationTimeInDays > 0, "Voting#createPoll: DURATION_TIME_INVALID");

        pollIds.increment();
        Poll storage poll = polls[pollIds.current()];
        poll.startTime = block.timestamp;
        poll.endTime = block.timestamp.add(_durationTimeInDays.mul(1 days));
        poll.minimumStakeTimeInDays = _minimumStakeTimeInDays;
        poll.description = _description;
        poll.creator = _msgSender();

        emit PollCreated(_msgSender(), pollIds.current(), _description, _durationTimeInDays);
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
        Poll storage poll = polls[_pollId];
        require(block.timestamp >= poll.endTime, "Voting#endPoll: VOTING_PERIOD_NOT_EXPIRED");
        require(poll.status == PollStatus.IN_PROGRESS, "Voting#endPoll: POLL_ALREADY_ENDED");
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
        return voters[_pollId][_account].voted;
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
        Poll storage poll = polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "Voting#castVote: POLL_ALREADY_ENDED");
        require(block.timestamp < poll.endTime, "Voting#castVote: VOTING_PERIOD_EXPIRED");
        require(!checkIfVoted(_pollId, _msgSender()), "Voting#castVote: USER_ALREADY_VOTED");

        uint256 w = getWeight(_pollId, _msgSender());
        if (_vote) {
            poll.yesVotes = poll.yesVotes.add(w);
        } else {
            poll.noVotes = poll.noVotes.add(w);
        }

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
        require(_account != address(0), "Voting#getWeight: ACCOUNT_INVALID");
        uint256 w = 0; // total weight
        Poll memory poll = polls[_pollId];
        require(poll.status == PollStatus.IN_PROGRESS, "Voting#getWeight: POLL_ALREADY_ENDED");

        for (uint256 i = 0; i < stakePools.length; i++) {
            IStakePool sPool = stakePools[i];
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
