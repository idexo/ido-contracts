// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IStakePool.sol";
import "../lib/Operatorable.sol";

contract SpendableVotingByStakeNFTHolder is ReentrancyGuard, Operatorable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address constant ETHEREUM_TOKEN_ADDRESS = address(0);

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
    IStakePool[] private _nftToHold;

    uint8 public proposalIds;
    uint8 private _commentIds;
    uint8 private pVoteInDays;
    uint8 private rVoteDays;

    event FundDeposited(address indexed operator, address indexed tokenAddress, uint256 amount);
    event Swept(address indexed operator, address indexed token, address indexed to, uint256 amount);
    event NewComment(address indexed author, uint8 proposalId, uint8 id, string comment);
    event NewProposal(uint8 proposalId, address indexed author);
    event NewReview(uint8 proposalId, uint8 reviewId);

    constructor(uint8 proposalDurationInDays_, uint8 reviewDurationInDays_, address[] memory nftToHold_) {
        require(proposalDurationInDays_ >= 14, "PROPOSAL_MIN_14_DAYS");
        require(reviewDurationInDays_ >= 7, "REVIEW_MIN_7_DAYS");
        rVoteDays = reviewDurationInDays_;
        pVoteInDays = proposalDurationInDays_;

        for (uint256 n = 0; n < nftToHold_.length; n++) {
            require(_isContract(nftToHold_[n]), "NOT_CONTRACT");
            _nftToHold.push(IStakePool(nftToHold_[n]));
        }

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
    function createProposal(string memory description_, address payeeWallet_, uint256 amount_, address paymentToken_, uint8 fundType_) external {
        require(_isContract(paymentToken_) || paymentToken_ == ETHEREUM_TOKEN_ADDRESS, "NOT_CONTRACT");
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(paymentToken_ == ETHEREUM_TOKEN_ADDRESS || _isContract(paymentToken_), "INVALID_PAYMENT_TOKEN");
        require(fundType_ < 3, "INVALID_FUND_TYPE");
        require(amount_ > 0, "AMOUNT_MUST_BE_GREATER_THAN_ZERO");

        // Change the condition to check the balance based on the payment token
        if (paymentToken_ == ETHEREUM_TOKEN_ADDRESS) {
            require(address(this).balance >= amount_, "INSUFFICIENT_FUNDS");
        } else {
            require(IERC20(paymentToken_).balanceOf(address(this)) >= amount_, "INSUFFICIENT_FUNDS");
        }

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
    function voteProposal(uint8 proposalId_, uint8 optionId_) external endedProposal(proposalId_) nonReentrant returns (bool) {
        Proposal storage vProposal = _proposals[proposalId_];
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(!voted(proposalId_, msg.sender), "ALREADY_VOTED");
        require(optionId_ > 0 && optionId_ <= vProposal.options.length, "INVALID_OPTION");

        uint256 vWeight = _voteWeight(msg.sender);

        for (uint256 opt = 0; opt < vProposal.options.length; opt++) {
            if (vProposal.options[opt].id == optionId_) {
                vProposal.options[opt].votes += vWeight;
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

        if (eProposal.options[0].votes > eProposal.options[1].votes) { // yes > no ... draw = rejected
            eProposal.status = _status[1]; // approved

            // Check if there are sufficient funds based on the payment token
            if (eProposal.paymentToken == ETHEREUM_TOKEN_ADDRESS) {
                require(address(this).balance >= eProposal.amount, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            } else {
                require(IERC20(eProposal.paymentToken).balanceOf(address(this)) >= eProposal.amount, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            }

            // Transfer the funds based on the fundType and payment token
            if (eProposal.fundType.id == 0) {
                _transferFunds(eProposal.paymentToken, eProposal.payeeWallet, eProposal.amount);
                eProposal.status = _status[4]; // completed
            } else if (eProposal.fundType.id == 1) {
                _transferFunds(eProposal.paymentToken, eProposal.payeeWallet, eProposal.amount / 2);
                eProposal.status = _status[3]; // pending
            } else if (eProposal.fundType.id == 2) {
                eProposal.status = _status[3]; // pending
            }
        } else {
            eProposal.status = _status[2]; // rejected
        }
        eProposal.ended = true;
    }


    // Helper function to transfer funds based on the payment token
    function _transferFunds(address paymentToken, address recipient, uint256 amount) private {
        if (paymentToken == ETHEREUM_TOKEN_ADDRESS) {
            (bool success, ) = recipient.call{ value: amount }("");
            require(success, "ETH_TRANSFER_FAILED");
        } else {
            IERC20(paymentToken).safeTransfer(recipient, amount);
        }
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
        require(_proposals[proposalId_].author == msg.sender || owner() == msg.sender, "NOT_OWNER_OR_AUTHOR");
        require(_isHolder(msg.sender), "NOT_NFT_HOLDER");
        require(_proposals[proposalId_].ended == true, "PROPOSAL_VOTE_OPEN");
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

        uint256 vWeight = _voteWeight(msg.sender);

        for (uint256 opt = 0; opt < vReview.options.length; opt++) {
            if (vReview.options[opt].id == optionId_) {
                vReview.options[opt].votes += vWeight;
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

        if (eProposal.fundType.id == 1) {
            // Check if there are sufficient funds based on the payment token
            if (eProposal.paymentToken == ETHEREUM_TOKEN_ADDRESS) {
                require(address(this).balance >= eProposal.amount / 2, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            } else {
                require(IERC20(eProposal.paymentToken).balanceOf(address(this)) >= eProposal.amount / 2, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            }
        } else if (eProposal.fundType.id == 2) {
            // Check if there are sufficient funds based on the payment token
            if (eProposal.paymentToken == ETHEREUM_TOKEN_ADDRESS) {
                require(address(this).balance >= eProposal.amount, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            } else {
                require(IERC20(eProposal.paymentToken).balanceOf(address(this)) >= eProposal.amount, "INSUFFICIENT_FUNDS_CALL_ADMIN");
            }
        }

        if (
            endReview.options[0].votes > endReview.options[1].votes // yes > no ... draw = rejected
        ) {
            if (eProposal.fundType.id == 1) {
                //half_half
                _transferFunds(eProposal.paymentToken, eProposal.payeeWallet, eProposal.amount / 2);
            } else if (eProposal.fundType.id == 2) {
                //post_fund
                _transferFunds(eProposal.paymentToken, eProposal.payeeWallet, eProposal.amount);
            }
            if (eProposal.fundType.id == 1) {
                eProposal.status = _status[4]; // completed
            } else {
                eProposal.status = _status[4]; // completed
            }
        } else {
            eProposal.status = _status[2]; // rejected
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
    function getReview(
        uint8 proposalId_,
        uint8 reviewId_
    ) public view validProposal(proposalId_) validReview(proposalId_, reviewId_) returns (Review memory) {
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
        require(reviewId_ >= 0 && reviewId_ < _reviews[proposalId_].length, "INVALID_REVIEW");
        _;
    }

    /*
     * Modifier check if a proposal id ended.
     */
    modifier endedProposal(uint8 proposalId_) {
        require(block.timestamp < _proposals[proposalIds].endTime, "VOTE_ENDED");
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

    function depositFundsEth() external payable {
        require(msg.value > 0, "ZERO_AMOUNT");
    }


    /*************************|
    |        Internal         |
    |________________________*/

    /**
     * @dev Deposit Funds to the pool.
     * @param account address who deposits to the pool.
     * @param amount deposit amount.
     */
    function _depositFunds(address account, address tokenAddress, uint256 amount) internal virtual {
        require(amount > 0, "ZERO_AMOUNT");

        require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
        require(IERC20(tokenAddress).allowance(msg.sender, address(this)) >= amount, "INSUFFICIENT_ALLOWANCE");
        IERC20(tokenAddress).safeTransferFrom(account, address(this), amount);

        emit FundDeposited(account, tokenAddress, amount);
    }

    /**
     * @dev get vote weight based on stakes held
     *
     * @param voter address.
     */
    function _voteWeight(address voter) public returns (uint256) {
        require(voter != address(0), "Voting#getWeight: ACCOUNT_INVALID");
        uint256 w = 0; // total weight

        for (uint256 i = 0; i < _nftToHold.length; i++) {
            IStakePool sPool = _nftToHold[i];
            uint256[] memory sTokenIds = sPool.getStakeTokenIds(voter);
            for (uint256 j = 0; j < sTokenIds.length; j++) {
                (uint256 amount, , uint256 depositedAt) = sPool.getStakeInfo(sTokenIds[j]);

                w = w.add(amount);
            }
        }
        return w;
    }

    /**
     * @dev check is holder
     *
     * @param voter proposal id.
     */
    function _isHolder(address voter) internal view returns (bool) {
        bool isHold;
        for (uint256 nft = 0; nft < _nftToHold.length; nft++) {
            if (IERC721(_nftToHold[nft]).balanceOf(voter) > 0) {
                isHold = true;
            }
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
