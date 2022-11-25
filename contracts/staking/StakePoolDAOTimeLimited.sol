// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./StakePoolDAOSPV.sol";

contract StakePoolDAOTimeLimited is StakePoolDAOSPV {
    using SafeERC20 for IERC20;

    // Minimum pool stake amount
    uint256 public minPoolStakeAmount;
    // Days to close pool from minPoolStakeAmount is reached
    uint256 public timeLimitInDays;
    // Time Limit after min pool stake amount reached
    uint256 public timeLimit;

    constructor(
        string memory stakeTokenName_,
        string memory stakeTokenSymbol_,
        string memory stakeTokenBASEUri_,
        uint256 timeLimitInDays_,
        uint256 minPoolStakeAmount_,
        IERC20 depositToken_
    ) StakePoolDAOSPV(stakeTokenName_, stakeTokenSymbol_, stakeTokenBASEUri_, depositToken_) {
        timeLimitInDays = timeLimitInDays_;
        minPoolStakeAmount = minPoolStakeAmount_;
    }

    /**
     * @dev Deposit stake to the pool.
     * @param account address of recipient.
     * @param amount deposit amount.
     */
    function _deposit(address account, uint256 amount) internal virtual override {
        StakePoolDAOSPV._deposit(account, amount);
        if (timeLimit > 0) {
            require(block.timestamp < timeLimit, "StakePool#_deposit: DEPOSIT_TIME_CLOSED");
        }
        if (timeLimit == 0 && depositToken.balanceOf(address(this)) >= minPoolStakeAmount) {
            timeLimit = block.timestamp + (timeLimitInDays * 1 days);
        }
    }

    /**
     * @dev If amount is less than amount of the stake, cut off amount.
     * If amount is equal to amount of the stake, burn the stake.
     *
     * Requirements:
     *
     * - `account` must be owner of `stakeId`
     * @param account address whose stake is being withdrawn.
     * @param stakeId id of stake that is being withdrawn.
     * @param withdrawAmount withdraw amount.
     */
    function _withdraw(
        address account,
        uint256 stakeId,
        uint256 withdrawAmount
    ) internal virtual override {
        StakePoolDAOSPV._withdraw(account, stakeId, withdrawAmount);
        if (timeLimit > 0 && block.timestamp < timeLimit && depositToken.balanceOf(address(this)) < minPoolStakeAmount) {
            timeLimit = 0;
        }
    }
}
