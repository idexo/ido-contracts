// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../staking/StakePoolDAOTimeLimited.sol";

contract SPVDAO is StakePoolDAOTimeLimited {
    using SafeERC20 for IERC20;
    string public poolDescription;

    struct Proposal {
        string description;
        Option[] options;
        address payeeWallet;
        uint256 amount;
        address paymentToken;
        FundType fundType;
        uint256 endTime;
        Status status;
        address author;
        bool ended;
    }

    struct Review {
        uint8 id;
        string description;
        Option[] options;
        uint256 endTime;
        bool ended;
    }

    struct Comment {
        uint8 id;
        uint8 proposalId;
        string commentURI;
        address author;
    }

    struct Option {
        uint8 id;
        string name;
        uint256 votes;
    }

    struct Status {
        uint8 id;
        string status;
    }

    struct FundType {
        uint8 id;
        string fundType;
    }

    mapping(uint8 => mapping(address => bool)) private _votedProp;
    mapping(uint8 => mapping(address => bool)) private _votedRev;
    mapping(uint8 => Proposal) private _proposals;
    mapping(uint8 => Review[]) private _reviews;
    mapping(uint8 => Comment[]) public _comments;

    Status[] private _status;
    FundType[] private _fundType;
    address private _nftToHold;

    uint8 public proposalIds;
    uint8 private _commentIds;
    uint8 private pVoteInDays;
    uint8 private rVoteDays;

    event FundDeposited(address indexed operator, address indexed tokenAddress, uint256 amount);
    event Swept(address indexed operator, address indexed token, address indexed to, uint256 amount);
    event NewComment(address indexed author, uint8 proposalId, uint8 id, string comment);
    event NewProposal(uint8 proposalId, address indexed author);
    event NewReview(uint8 proposalId, uint8 reviewId);

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        string memory stakeTokenBASEUri_,
        uint256 timeLimitInDays_,
        uint256 minPoolStakeAmount_,
        IERC20 depositToken_,
        uint8 proposalDurationInDays_,
        uint8 reviewDurationInDays_,
        string memory poolDescription_
    ) StakePoolDAOTimeLimited(stakeTokenName_, stakeTokenSymbol_, stakeTokenBASEUri_, timeLimitInDays_, minPoolStakeAmount_, depositToken_) {
        _nftToHold = address(this);
        require(proposalDurationInDays_ >= 7, "PROPOSAL_MIN_7_DAYS");
        require(reviewDurationInDays_ >= 7, "REVIEW_MIN_7_DAYS");
        rVoteDays = reviewDurationInDays_;
        pVoteInDays = proposalDurationInDays_;
        poolDescription = poolDescription_;

        string[5] memory sts = ["proposed", "approved", "rejected", "pending", "completed"];
        for (uint8 i = 0; i < sts.length; i++) {
            _status.push(Status(i + 1, sts[i]));
        }
        string[3] memory ft = ["prefund", "half_half", "postfund"];
        for (uint8 i = 0; i < ft.length; i++) {
            _fundType.push(FundType(i + 1, ft[i]));
        }
    }

    /*************************|
    |        Proposal         |
    |________________________*/

    /**
     * @dev create a new proposal
     *
     * @param description_ description.
     * @param payeeWallet_ address of payee.
     * @param amount_ amount.
     * @param paymentToken_ token for payment.
     * @param fundType_ uint8 fund type
     */
    function createProposal(
        string memory description_,
        address payeeWallet_,
        uint256 amount_,
        address paymentToken_,
        uint8 fundType_
    ) external {
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(IERC721(paymentToken_).balanceOf(address(this)) >= amount_, "INSUFFICIENT_FUNDS");

        proposalIds++;
        Proposal storage prop = _proposals[proposalIds];
        prop.description = description_;
        prop.payeeWallet = payeeWallet_;
        prop.amount = amount_;
        prop.paymentToken = paymentToken_;
        prop.endTime = block.timestamp + pVoteInDays * 1 days;
        prop.author = msg.sender;
        prop.status = _status[0];

        _putOptions(proposalIds);
        _putFundType(proposalIds, fundType_);

        emit NewProposal(proposalIds, msg.sender);
    }

    /**
     * @dev get a proposal
     *
     * @param proposalId_ proposal id.
     */
    function getProposal(uint8 proposalId_) external view returns (Proposal memory) {
        require(proposalId_ > 0 && proposalId_ <= proposalIds, "INVALID_PROPOSALID");

        return _proposals[proposalId_];
    }

    /**
     * @dev vote a proposal
     *
     * @param proposalId_ proposal id.
     * @param optionId_ option id.
     */
    function voteProposal(uint8 proposalId_, uint8 optionId_) external nonReentrant returns (bool) {
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(!voted(proposalId_, msg.sender), "ALREADY_VOTED");
        require(block.timestamp < _proposals[proposalId_].endTime, "VOTE_ENDED");
        require(optionId_ > 0 && optionId_ <= _proposals[proposalId_].options.length, "INVALID_OPTION");

        for (uint256 opt = 0; opt < _proposals[proposalId_].options.length; opt++) {
            if (_proposals[proposalId_].options[opt].id == optionId_) {
                _proposals[proposalId_].options[opt].votes += IERC721(_nftToHold).balanceOf(msg.sender);
            }
        }
        _votedProp[proposalId_][msg.sender] = true;

        return true;
    }

    /**
     * @dev end a proposal vote after endTime
     *
     * @param proposalId_ proposal id.
     */
    function endProposalVote(uint8 proposalId_) public nonReentrant {
        Proposal storage eProposal = _proposals[proposalId_];
        require(!eProposal.ended, "ALREADY_ENDED");
        require(block.timestamp > eProposal.endTime, "OPEN_FOR_VOTE");
        if (
            eProposal.options[0].votes > eProposal.options[1].votes // yes > no ... draw = rejected
        ) {
            eProposal.status = _status[1]; // approved
            require(IERC20(eProposal.paymentToken).balanceOf(address(this)) >= eProposal.amount, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            if (eProposal.fundType.id == 1) {
                IERC20(eProposal.paymentToken).safeTransfer(eProposal.payeeWallet, eProposal.amount);
            } else if (eProposal.fundType.id == 2) {
                // half_half
                IERC20(eProposal.paymentToken).safeTransfer(eProposal.payeeWallet, eProposal.amount / 2);
            }
        } else {
            eProposal.status = _status[2]; // rejected
        }
        eProposal.ended = true;
    }

    /*************************|
    |          Review         |
    |________________________*/

    /**
     * @dev create a new review
     *
     * @param proposalId_ proposal id.
     * @param description_ description.
     */
    function createReview(uint8 proposalId_, string memory description_) external validProposal(proposalId_) {
        require(_proposals[proposalId_].author == msg.sender, "NOT_OWNER_OR_AUTHOR");
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(_proposals[proposalId_].ended = true, "PROPOSAL_VOTE_OPEN");
        require(_proposals[proposalId_].status.id != 3, "REJECTED_PROPOSAL");

        _reviews[proposalId_].push();
        uint256 len = _reviews[proposalId_].length;
        Review storage nReview = _reviews[proposalId_][len - 1];
        nReview.id = uint8(len);
        nReview.description = description_;
        nReview.endTime = block.timestamp + rVoteDays * 1 days;

        string[2] memory options = ["yes", "no"];
        for (uint256 opt = 0; opt < options.length; opt++) {
            nReview.options.push(Option({ id: uint8(opt + 1), name: options[opt], votes: 0 }));
        }

        emit NewReview(proposalId_, uint8(len));
    }

    /**
     * @dev vote a review
     *
     * @param proposalId_ proposal id.
     * @param reviewId_ review id.
     * @param optionId_ option id.
     */
    function voteReview(
        uint8 proposalId_,
        uint8 reviewId_,
        uint8 optionId_
    ) external validProposal(proposalId_) validReview(proposalId_, reviewId_) returns (bool) {
        Review storage vReview = _reviews[proposalId_][reviewId_];
        require(block.timestamp < vReview.endTime, "VOTE_ENDED");
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(voted(proposalId_, msg.sender), "NOT_PROPOSAL_VOTER");
        require(!_votedRev[proposalId_][msg.sender], "ALREADY_VOTED");
        require(optionId_ > 0 && optionId_ <= vReview.options.length, "INVALID_OPTION");

        for (uint256 opt = 0; opt < vReview.options.length; opt++) {
            if (vReview.options[opt].id == optionId_) {
                vReview.options[opt].votes += IERC721(_nftToHold).balanceOf(msg.sender);
            }
        }
        _votedRev[proposalId_][msg.sender] = true;

        return true;
    }

    /**
     * @dev end a review vote
     *
     * @param proposalId_ proposal id.
     * @param reviewId_ review id.
     */
    function endReviewVote(uint8 proposalId_, uint8 reviewId_) public validProposal(proposalId_) validReview(proposalId_, reviewId_) nonReentrant {
        Proposal storage eProposal = _proposals[proposalId_];
        Review storage endReview = _reviews[proposalId_][reviewId_];
        require(block.timestamp > endReview.endTime, "REVIEW_OPEN_FOR_VOTE");
        require(!endReview.ended, "ALREADY_ENDED");
        if (eProposal.fundType.id == 2) {
            require(IERC20(eProposal.paymentToken).balanceOf(address(this)) >= eProposal.amount / 2, "INSUFFICIENT_FUNDS_CALL_ADMIN");
        }

        if (
            endReview.options[0].votes > endReview.options[1].votes // yes > no ... draw = rejected
        ) {
            if (eProposal.fundType.id == 2) {
                //half_half
                IERC20(eProposal.paymentToken).safeTransfer(eProposal.payeeWallet, eProposal.amount / 2);
            }
            if (eProposal.fundType.id == 2) {
                eProposal.status = _status[4]; // pending
            } else {
                eProposal.status = _status[5]; // completed
            }
        } else {
            eProposal.status = _status[4]; // pending
        }
        endReview.ended = true;
    }

    /**
     * @dev get number of reviews for a proposal
     *
     * @param proposalId_ proposal id.
     */
    function getReviewIds(uint8 proposalId_) public view returns (uint256) {
        return _reviews[proposalId_].length;
    }

    /**
     * @dev get a review
     *
     * @param proposalId_ proposal id.
     * @param reviewId_ review id.
     */
    function getReview(uint8 proposalId_, uint8 reviewId_)
        public
        view
        validProposal(proposalId_)
        validReview(proposalId_, reviewId_)
        returns (Review memory)
    {
        return _reviews[proposalId_][reviewId_];
    }

    /*************************|
    |        Comments         |
    |________________________*/

    /**
     * @dev create a comment
     *
     * @param proposalId_ proposal id.
     * @param commentURI_ proposal id.
     */
    function createComment(uint8 proposalId_, string memory commentURI_) external {
        require(voted(proposalId_, msg.sender), "NOT_PROPOSAL_VOTER");
        _commentIds++;
        _comments[proposalId_].push(Comment({ proposalId: proposalId_, id: _commentIds, commentURI: commentURI_, author: msg.sender }));

        emit NewComment(msg.sender, proposalId_, _commentIds, commentURI_);
    }

    /**
     * @dev get comments
     *
     * @param proposalId_ proposal id.
     */
    function getComments(uint8 proposalId_) external view returns (Comment[] memory comments) {
        return _comments[proposalId_];
    }

    /*************************|
    |           Utils         |
    |________________________*/

    /**
     * @dev Check if `account_` already voted for `proposalId`.
     *
     * @param proposalId_ proposal id.
     * @param account_ account.
     */
    function voted(uint8 proposalId_, address account_) public view validProposal(proposalId_) returns (bool) {
        return _votedProp[proposalId_][account_];
    }

    /***********************|
    |       Modifiers       |
    |______________________*/

    /*
     * Modifier checks valid proposalId.
     */
    modifier validProposal(uint8 proposalId_) {
        require(proposalId_ > 0 && proposalId_ <= proposalIds, "INVALID_PROPOSAL");
        _;
    }

    /*
     * Modifier check valid reviewId.
     */
    modifier validReview(uint8 proposalId_, uint8 reviewId_) {
        require(reviewId_ < _reviews[proposalId_].length, "INVALID_REVIEW");
        _;
    }

    /*
     * Modifier check if a proposal id ended.
     */
    modifier endedProposal(uint8 proposalId_) {
        require(block.timestamp > _proposals[proposalIds].endTime, "VOTE_ENDED");
        _;
    }

    /*************************|
    |     Deposit Funds       |
    |________________________*/

    /**
     * @dev Deposit Funds to the contract.
     * Requirements:
     *
     * - `amount` must not be zero
     * @param amount deposit amount.
     * @param tokenAddress Funds token address
     */
    function depositFunds(address tokenAddress, uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        _depositFunds(msg.sender, tokenAddress, amount);
    }

    /*************************|
    |        Internal         |
    |________________________*/

    /**
     * @dev Deposit Funds to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositFunds(
        address account,
        address tokenAddress,
        uint256 amount
    ) internal virtual {
        require(amount > 0, "ZERO_AMOUNT");
        require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
        require(IERC20(tokenAddress).allowance(msg.sender, address(this)) >= amount, "INSUFFICIENT_ALLOWANCE");
        IERC20(tokenAddress).safeTransferFrom(account, address(this), amount);

        emit FundDeposited(account, tokenAddress, amount);
    }

    /**
     * @dev check is holder
     *
     * @param voter proposal id.
     */
    function _isHolder(address voter) internal view returns (bool) {
        bool isHold;

        if (IERC721(_nftToHold).balanceOf(voter) > 0) {
            isHold = true;
        }

        return isHold;
    }

    /**
     * @dev Check if `_account` is contract
     */
    function _isContract(address _account) internal view returns (bool) {
        uint256 size;

        assembly {
            size := extcodesize(_account)
        }
        return size > 0;
    }

    /**
     * @dev put options
     *
     * @param proposalId_ proposal id.
     */
    function _putOptions(uint8 proposalId_) internal {
        string[2] memory options = ["yes", "no"];
        Proposal storage prop = _proposals[proposalId_];
        for (uint256 opt = 0; opt < options.length; opt++) {
            prop.options.push(Option({ id: uint8(opt + 1), name: options[opt], votes: 0 }));
        }
    }

    /**
     * @dev put fund types
     *
     * @param proposalId_ proposal id.
     * @param fundType_ proposal id.
     */
    function _putFundType(uint8 proposalId_, uint8 fundType_) internal {
        Proposal storage prop = _proposals[proposalId_];
        for (uint256 idx = 0; idx < _fundType.length; idx++) {
            if (_fundType[idx].id == fundType_) {
                prop.fundType = _fundType[idx];
            }
        }
    }
}
