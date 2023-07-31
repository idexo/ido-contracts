// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract VestingAlt is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public immutable cliff;
    uint256 public immutable duration;
    uint256 public immutable claimsPeriod;

    uint256 public totalAmount;
    uint256 public claimedAmount;
    uint256 public lastClaimTime;

    // ERC20 token address.
    IERC20 public immutable token;

    bool public initialDeposited;

    event InitialDeposited(address indexed operator, uint256 amount);
    event Claimed(uint256 amount);

    constructor(
        IERC20 erc20_,
        address beneficiary_,
        uint256 startTime_,
        uint256 cliff_,
        uint256 duration_,
        uint256 claimsPeriod_
    ) {
        token = erc20_;
        beneficiary = beneficiary_;
        startTime = startTime_;
        cliff = cliff_;
        duration = duration_;
        claimsPeriod = claimsPeriod_;
    }

    /**************************|
    |          Vesting         |
    |_________________________*/

    /**
     * @dev Deposit the initial funds to the vesting contract.
     * Before using this function the depositor needs to do an allowance from the depositor to the vesting contract.
     * @param amount uint256 deposit amount.
     */
    function depositInitial(uint256 amount) public virtual {
        require(!initialDeposited, "ALREADY_INITIAL_DEPOSITED");
        require(amount > 0, "AMOUNT_INVALID");
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalAmount = amount;
        initialDeposited = true;

        emit InitialDeposited(msg.sender, amount);
    }

    /**
     * @dev Claim.
     * @param amount uint256 claim amount.
     */
    function claim(uint256 amount) public nonReentrant {
        require(msg.sender == beneficiary, "CALLER_NO_BENEFICIARY");
        require(block.timestamp >= startTime.add(cliff * 1 days), "CLIFF_PERIOD");
        require(block.timestamp.sub(lastClaimTime) >= claimsPeriod * 1 days, "WITHIN_CLAIM_PERIOD_FROM_LAST_CLAIM");
        require(amount > 0, "AMOUNT_INVALID");
        require(amount <= getAvailableClaimAmount(), "AVAILABLE_CLAIM_AMOUNT_EXCEEDED");

        claimedAmount = claimedAmount.add(amount);
        lastClaimTime = block.timestamp;
        token.safeTransfer(beneficiary, amount);

        emit Claimed(amount);
    }

    /**
     * @dev Get vested amount.
     */
    function getVestedAmount() public view returns (uint256) {
        if (block.timestamp < startTime.add(cliff * 1 days)) {
            return 0;
        } else if (block.timestamp >= startTime.add(cliff * 1 days).add(duration * 1 days)) {
            return totalAmount;
        } else {
            return totalAmount.mul(block.timestamp.sub(startTime.add(cliff * 1 days))).div(duration * 1 days);
        }
    }

    /**
     * @dev Get available claim amount.
     * Equals to total vested amount - claimed amount.
     */
    function getAvailableClaimAmount() public view returns (uint256) {
        if (block.timestamp.sub(lastClaimTime) >= claimsPeriod * 1 days) {
            return getVestedAmount().sub(claimedAmount);
        } else {
            return 0;
        }
    }
}